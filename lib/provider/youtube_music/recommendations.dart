import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:openmusic/models/database/database.dart';
import 'package:openmusic/models/metadata/metadata.dart';
import 'package:openmusic/provider/database/database.dart';
import 'package:openmusic/provider/metadata_plugin/core/auth.dart';
import 'package:openmusic/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:openmusic/provider/youtube_music/youtube_music.dart';
import 'package:openmusic/services/kv_store/kv_store.dart';
import 'package:openmusic/services/logger/logger.dart';
import 'package:openmusic/services/metadata/metadata.dart';
import 'package:openmusic/services/youtube_music/song_matching.dart';
import 'package:openmusic/services/youtube_music/youtube_music.dart';

/// Recommendations for the home page, sourced from YouTube Music and resolved
/// back into objects of the active metadata plugin.
class YoutubeMusicRecommendations {
  /// Songs to play, already resolved through the metadata plugin.
  final List<SpotubeFullTrackObject> tracks;

  /// Artists worth exploring, likewise resolved through the plugin.
  final List<SpotubeFullArtistObject> artists;

  /// The track the recommendations were built around, for "because you
  /// listened to …" copy.
  final String? seedTrackName;

  const YoutubeMusicRecommendations({
    this.tracks = const [],
    this.artists = const [],
    this.seedTrackName,
  });

  bool get isEmpty => tracks.isEmpty && artists.isEmpty;

  Map<String, dynamic> toJson() => {
        "tracks": tracks.map((track) => track.toJson()).toList(),
        "artists": artists.map((artist) => artist.toJson()).toList(),
        "seedTrackName": seedTrackName,
      };

  factory YoutubeMusicRecommendations.fromJson(Map<String, dynamic> json) {
    return YoutubeMusicRecommendations(
      tracks: (json["tracks"] as List? ?? [])
          .map(
            (raw) => SpotubeTrackObject.fromJson(
              (raw as Map).cast<String, dynamic>(),
            ),
          )
          .whereType<SpotubeFullTrackObject>()
          .toList(),
      artists: (json["artists"] as List? ?? [])
          .map(
            (raw) => SpotubeFullArtistObject.fromJson(
              (raw as Map).cast<String, dynamic>(),
            ),
          )
          .toList(),
      seedTrackName: json["seedTrackName"] as String?,
    );
  }
}

/// What the local listening history tells us about the user's taste.
class _HistoryDigest {
  /// Tracks to build radios from, most recently played first.
  final List<SpotubeTrackObject> seeds;

  /// Identity keys of everything recently played, so recommendations don't
  /// hand back songs the user just listened to.
  final Set<String> playedSongKeys;

  /// Normalised names of artists already in rotation — those are not
  /// discoveries, so they are dropped from the artist suggestions.
  final Set<String> playedArtistNames;

  const _HistoryDigest({
    required this.seeds,
    required this.playedSongKeys,
    required this.playedArtistNames,
  });
}

class _CachedRecommendations {
  final YoutubeMusicRecommendations recommendations;
  final String signature;
  final DateTime generatedAt;

  const _CachedRecommendations({
    required this.recommendations,
    required this.signature,
    required this.generatedAt,
  });

  Duration get age => DateTime.now().difference(generatedAt);
}

/// Builds the home page's recommendations out of YouTube Music.
///
/// YouTube Music's radios are the best free recommendation engine we can reach,
/// but its ids are useless to the rest of the app: playback, artist pages and
/// saving all speak the active metadata plugin's id space. So YouTube Music is
/// used purely for *taste* — which songs and artists to suggest — and every
/// suggestion is then looked up through the plugin and dropped if it cannot be
/// matched confidently.
///
/// The seeds come from local history, which is what makes anonymous YouTube
/// Music responses feel personal.
class YoutubeMusicRecommendationsNotifier
    extends AsyncNotifier<YoutubeMusicRecommendations> {
  static const _cacheKey = "youtubeMusicHomeRecommendations";
  static const _cacheVersion = 1;

  /// Below this age the cache is served untouched, even when the seeds have
  /// moved on. Without it every song played would trigger a full rebuild.
  static const _minRefreshInterval = Duration(hours: 1);

  /// Above this age the cache is always rebuilt in the background.
  static const _maxCacheAge = Duration(hours: 12);

  static const _seedCount = 4;
  static const _historyDepth = 60;
  static const _trackTarget = 20;
  static const _artistTarget = 8;

  /// Cap on plugin searches per rebuild, so a plugin that matches poorly
  /// cannot walk the whole radio queue.
  static const _maxTrackLookups = 45;

  /// How many plugin searches run at once while resolving.
  static const _lookupConcurrency = 3;

  bool _disposed = false;

  /// How far into the history the seeds are taken from; advanced by [refresh].
  int _seedOffset = 0;

  YoutubeMusicService get _youtubeMusic => ref.read(youtubeMusicServiceProvider);

  @override
  Future<YoutubeMusicRecommendations> build() async {
    ref.onDispose(() => _disposed = true);

    // Re-derive when the plugin changes or the user signs in: both change what
    // suggestions can be resolved to.
    ref.watch(metadataPluginAuthenticatedProvider);

    final plugin = await ref.watch(metadataPluginProvider.future);
    final pluginConfig = await ref.watch(
      metadataPluginsProvider.selectAsync(
        (state) => state.defaultMetadataPluginConfig,
      ),
    );

    if (plugin == null || pluginConfig == null) {
      return const YoutubeMusicRecommendations();
    }

    final digest = await _readHistory();
    if (digest.seeds.isEmpty) {
      // Nothing has been played yet — the plugin's own browse sections are all
      // the home page can honestly show.
      return const YoutubeMusicRecommendations();
    }

    final signature = _seedSignatureOf(digest);
    // Cached items carry the previous plugin's ids, which nothing in the app
    // could open or play, so a plugin switch always rebuilds from scratch.
    final cached = _readCache(pluginConfig.slug);

    if (cached != null) {
      final isFresh = cached.age < _minRefreshInterval ||
          (cached.signature == signature && cached.age < _maxCacheAge);

      if (isFresh) return cached.recommendations;

      // Serve what we have and rebuild behind it, so the home page never waits
      // on ~30 network round trips it already has an answer for.
      unawaited(
        _rebuildInBackground(plugin, pluginConfig.slug, digest, signature),
      );
      return cached.recommendations;
    }

    return await _generate(plugin, pluginConfig.slug, digest, signature) ??
        const YoutubeMusicRecommendations();
  }

  /// Rebuilds the recommendations, ignoring the cache and moving on to the next
  /// set of seeds — pressing refresh should hand back a different row, not the
  /// same radios re-fetched.
  Future<void> refresh() async {
    _seedOffset += _seedCount;
    final plugin = await ref.read(metadataPluginProvider.future);
    final pluginConfig = await ref.read(
      metadataPluginsProvider.selectAsync(
        (state) => state.defaultMetadataPluginConfig,
      ),
    );
    if (plugin == null || pluginConfig == null) return;

    final digest = await _readHistory();
    if (digest.seeds.isEmpty) return;

    final previous = state.valueOrNull;

    state = const AsyncLoading<YoutubeMusicRecommendations>().copyWithPrevious(
      state,
    );

    final result = await _generate(
      plugin,
      pluginConfig.slug,
      digest,
      _seedSignatureOf(digest),
    );

    if (_disposed) return;
    // A failed refresh keeps what was on screen rather than emptying the row.
    state = AsyncData(
      result ?? previous ?? const YoutubeMusicRecommendations(),
    );
  }

  Future<void> _rebuildInBackground(
    MetadataPlugin plugin,
    String pluginSlug,
    _HistoryDigest digest,
    String signature,
  ) async {
    final result = await _generate(plugin, pluginSlug, digest, signature);
    if (result == null || result.isEmpty || _disposed) return;

    state = AsyncData(result);
  }

  /// Runs the whole pipeline. Returns null when it could not produce anything,
  /// which callers treat as "leave whatever is on screen alone" — a failed
  /// recommendation fetch should never blank out the home page.
  Future<YoutubeMusicRecommendations?> _generate(
    MetadataPlugin plugin,
    String pluginSlug,
    _HistoryDigest digest,
    String signature,
  ) async {
    try {
      final seedVideoIds = await _resolveSeedVideoIds(digest.seeds);
      if (seedVideoIds.isEmpty) return null;

      final watchNexts = await Future.wait(
        seedVideoIds.entries.map((entry) async {
          try {
            return await _youtubeMusic.watchNext(entry.value);
          } catch (error, stackTrace) {
            AppLogger.log.d(
              "YouTube Music radio failed for ${entry.key}: $error",
              error: error,
              stackTrace: stackTrace,
            );
            return const YoutubeMusicWatchNext(radio: []);
          }
        }),
      );

      final pool = _interleave(watchNexts.map((next) => next.radio).toList());
      final candidates = pool
          .where(
            (song) => !digest.playedSongKeys.contains(
              songIdentityKey(song.title, song.artist),
            ),
          )
          .toList();

      final tracks = await _resolveTracks(plugin, candidates);
      final artists = await _resolveArtists(
        plugin,
        watchNexts.firstWhereOrNull((next) => next.relatedBrowseId != null),
        digest,
      );

      final result = YoutubeMusicRecommendations(
        tracks: tracks,
        artists: artists,
        seedTrackName: digest.seeds.firstOrNull?.name,
      );

      // An empty result is cached too: a plugin whose catalogue simply doesn't
      // line up with YouTube Music's would otherwise repeat this whole sweep on
      // every visit to the home page.
      await _writeCache(result, pluginSlug, signature);

      return result;
    } catch (error, stackTrace) {
      // Recommendations are additive; a failure hides the section instead of
      // breaking the page.
      AppLogger.reportError(error, stackTrace);
      return null;
    }
  }

  /// Reads the tracks the user actually listened to, newest first.
  Future<_HistoryDigest> _readHistory() async {
    final database = ref.read(databaseProvider);

    final entries = await (database.select(database.historyTable)
          ..where((table) => table.type.equalsValue(HistoryEntryType.track))
          ..orderBy([
            (table) => OrderingTerm(
                  expression: table.createdAt,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(_historyDepth * 4))
        .get();

    final recentTracks = <SpotubeTrackObject>[];
    final seenTrackIds = <String>{};
    final playedSongKeys = <String>{};
    final playedArtistNames = <String>{};

    for (final entry in entries) {
      final track = entry.track;
      if (track == null) continue;

      playedSongKeys.add(
        songIdentityKey(track.name, track.artists.firstOrNull?.name),
      );
      playedArtistNames.addAll(
        track.artists.map((artist) => normalizeArtistName(artist.name)),
      );

      if (seenTrackIds.add(track.id) && recentTracks.length < _historyDepth) {
        recentTracks.add(track);
      }
    }

    return _HistoryDigest(
      seeds: _pickSeeds(recentTracks),
      playedSongKeys: playedSongKeys,
      playedArtistNames: playedArtistNames,
    );
  }

  /// Picks the songs to build radios from: recent, but one per artist so four
  /// seeds don't all pull from the same album, and rotated by [_seedOffset] so
  /// refreshing reaches further back into the history.
  List<SpotubeTrackObject> _pickSeeds(List<SpotubeTrackObject> recentTracks) {
    final candidates = <SpotubeTrackObject>[];
    final usedArtists = <String>{};

    for (final track in recentTracks) {
      if (track is! SpotubeFullTrackObject) continue;

      final artist = normalizeArtistName(track.artists.firstOrNull?.name ?? "");
      if (artist.isNotEmpty && !usedArtists.add(artist)) continue;

      candidates.add(track);
    }

    // Fall back to plain recency when everything played is by one artist.
    if (candidates.isEmpty) {
      candidates.addAll(recentTracks.whereType<SpotubeFullTrackObject>());
    }

    if (candidates.isEmpty) return const [];

    final start = _seedOffset % candidates.length;

    return [
      ...candidates.skip(start),
      ...candidates.take(start),
    ].take(_seedCount).toList();
  }

  /// Maps each seed to a YouTube video id, preferring the one the audio source
  /// already matched for playback — that lookup is free and is the exact video
  /// the user heard.
  Future<Map<String, String>> _resolveSeedVideoIds(
    List<SpotubeTrackObject> seeds,
  ) async {
    final videoIds = <String, String>{};
    final cachedIds = await _cachedSourceVideoIds(
      seeds.map((seed) => seed.id).toList(),
    );

    for (final seed in seeds) {
      final cached = cachedIds[seed.id];
      if (cached != null) {
        videoIds[seed.id] = cached;
        continue;
      }

      try {
        final found = await _youtubeMusic.findSongId(
          seed.name,
          seed.artists.firstOrNull?.name,
        );
        if (found != null) videoIds[seed.id] = found;
      } catch (error, stackTrace) {
        AppLogger.log.d(
          "YouTube Music lookup failed for ${seed.name}: $error",
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    return videoIds;
  }

  static final _videoIdPattern = RegExp(r"^[A-Za-z0-9_-]{11}$");

  /// Video ids the audio source plugin already matched for these tracks.
  ///
  /// Only YouTube-backed sources are consulted; another source's ids would be
  /// meaningless to YouTube Music.
  Future<Map<String, String>> _cachedSourceVideoIds(List<String> trackIds) async {
    if (trackIds.isEmpty) return const {};

    final audioSourceConfig = await ref.read(
      metadataPluginsProvider.selectAsync(
        (state) => state.defaultAudioSourcePluginConfig,
      ),
    );

    if (audioSourceConfig == null ||
        !audioSourceConfig.slug.toLowerCase().contains("youtube")) {
      return const {};
    }

    final database = ref.read(databaseProvider);
    final matches = await (database.select(database.sourceMatchTable)
          ..where(
            (table) =>
                table.trackId.isIn(trackIds) &
                table.sourceType.equals(audioSourceConfig.slug),
          )
          ..orderBy([
            (table) => OrderingTerm(
                  expression: table.createdAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();

    final videoIds = <String, String>{};
    for (final match in matches) {
      if (videoIds.containsKey(match.trackId)) continue;

      try {
        final sourceInfo = jsonDecode(match.sourceInfo);
        final id = sourceInfo is Map ? sourceInfo["id"] : null;
        if (id is String && _videoIdPattern.hasMatch(id)) {
          videoIds[match.trackId] = id;
        }
      } catch (_) {
        // A malformed row just means we search YouTube Music by name instead.
      }
    }

    return videoIds;
  }

  /// Round-robins the radios so the result reflects every seed, not just the
  /// most recently played one.
  List<YoutubeMusicSong> _interleave(List<List<YoutubeMusicSong>> radios) {
    final interleaved = <YoutubeMusicSong>[];
    final seenKeys = <String>{};
    final longest = radios.fold<int>(
      0,
      (longest, radio) => radio.length > longest ? radio.length : longest,
    );

    for (var index = 0; index < longest; index++) {
      for (final radio in radios) {
        if (index >= radio.length) continue;

        final song = radio[index];
        if (!seenKeys.add(songIdentityKey(song.title, song.artist))) continue;

        interleaved.add(song);
      }
    }

    return interleaved;
  }

  Future<List<SpotubeFullTrackObject>> _resolveTracks(
    MetadataPlugin plugin,
    List<YoutubeMusicSong> candidates,
  ) async {
    final resolved = <SpotubeFullTrackObject>[];
    final resolvedIds = <String>{};
    var lookups = 0;

    for (final chunk in candidates.slices(_lookupConcurrency)) {
      if (resolved.length >= _trackTarget || lookups >= _maxTrackLookups) break;
      if (_disposed) break;

      lookups += chunk.length;

      final matches = await Future.wait(
        chunk.map((song) => _resolveTrack(plugin, song)),
      );

      for (final track in matches.nonNulls) {
        if (resolvedIds.add(track.id)) resolved.add(track);
      }
    }

    return resolved.take(_trackTarget).toList();
  }

  Future<SpotubeFullTrackObject?> _resolveTrack(
    MetadataPlugin plugin,
    YoutubeMusicSong song,
  ) async {
    try {
      final results = await plugin.search.tracks(song.searchQuery, limit: 5);

      return results.items.firstWhereOrNull(
        (track) => isLikelySameSong(song, track),
      );
    } catch (error, stackTrace) {
      AppLogger.log.d(
        "Could not resolve ${song.title}: $error",
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<List<SpotubeFullArtistObject>> _resolveArtists(
    MetadataPlugin plugin,
    YoutubeMusicWatchNext? watchNext,
    _HistoryDigest digest,
  ) async {
    final browseId = watchNext?.relatedBrowseId;
    if (browseId == null) return const [];

    final YoutubeMusicRelated related;
    try {
      related = await _youtubeMusic.related(browseId);
    } catch (error, stackTrace) {
      AppLogger.log.d(
        "YouTube Music related lookup failed: $error",
        error: error,
        stackTrace: stackTrace,
      );
      return const [];
    }

    // Artists already in rotation aren't discoveries.
    final suggestions = related.artists
        .where(
          (artist) =>
              !digest.playedArtistNames.contains(
                normalizeArtistName(artist.name),
              ),
        )
        .take(_artistTarget * 2)
        .toList();

    final resolved = <SpotubeFullArtistObject>[];
    final resolvedIds = <String>{};

    for (final chunk in suggestions.slices(_lookupConcurrency)) {
      if (resolved.length >= _artistTarget) break;
      if (_disposed) break;

      final matches = await Future.wait(
        chunk.map((artist) => _resolveArtist(plugin, artist.name)),
      );

      for (final artist in matches.nonNulls) {
        if (resolvedIds.add(artist.id)) resolved.add(artist);
      }
    }

    return resolved.take(_artistTarget).toList();
  }

  Future<SpotubeFullArtistObject?> _resolveArtist(
    MetadataPlugin plugin,
    String name,
  ) async {
    try {
      final results = await plugin.search.artists(name, limit: 3);

      return results.items.firstWhereOrNull(
        (artist) => isLikelySameArtist(name, artist),
      );
    } catch (error, stackTrace) {
      AppLogger.log.d(
        "Could not resolve artist $name: $error",
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Identifies the taste the cache was built from, so new listening
  /// eventually invalidates it.
  String _seedSignatureOf(_HistoryDigest digest) {
    return digest.seeds.map((seed) => seed.id).join("|");
  }

  _CachedRecommendations? _readCache(String pluginSlug) {
    final raw = KVStoreService.sharedPreferences.getString(_cacheKey);
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json["version"] != _cacheVersion) return null;
      if (json["pluginSlug"] != pluginSlug) return null;

      final generatedAt = DateTime.tryParse(
        json["generatedAt"] as String? ?? "",
      );
      final signature = json["signature"] as String?;
      if (generatedAt == null || signature == null) return null;

      return _CachedRecommendations(
        recommendations: YoutubeMusicRecommendations.fromJson(
          (json["recommendations"] as Map).cast<String, dynamic>(),
        ),
        signature: signature,
        generatedAt: generatedAt,
      );
    } catch (error, stackTrace) {
      AppLogger.log.d(
        "Discarding unreadable recommendation cache: $error",
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _writeCache(
    YoutubeMusicRecommendations recommendations,
    String pluginSlug,
    String signature,
  ) async {
    await KVStoreService.sharedPreferences.setString(
      _cacheKey,
      jsonEncode({
        "version": _cacheVersion,
        "pluginSlug": pluginSlug,
        "signature": signature,
        "generatedAt": DateTime.now().toIso8601String(),
        "recommendations": recommendations.toJson(),
      }),
    );
  }
}

final youtubeMusicRecommendationsProvider = AsyncNotifierProvider<
    YoutubeMusicRecommendationsNotifier, YoutubeMusicRecommendations>(
  YoutubeMusicRecommendationsNotifier.new,
);
