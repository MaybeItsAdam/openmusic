import 'dart:async';

import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:openmusic/models/database/database.dart';
import 'package:openmusic/models/lyrics.dart';
import 'package:openmusic/models/metadata/metadata.dart';
import 'package:openmusic/provider/database/database.dart';
import 'package:openmusic/provider/server/sourced_track_provider.dart';
import 'package:openmusic/provider/user_preferences/user_preferences_provider.dart';
import 'package:openmusic/services/lyrics/lyrics_provider.dart';
import 'package:openmusic/services/lyrics/providers/better_lyrics.dart';
import 'package:openmusic/services/lyrics/providers/kugou.dart';
import 'package:openmusic/services/lyrics/providers/lrclib.dart';
import 'package:openmusic/services/lyrics/providers/lyrics_plus.dart';
import 'package:openmusic/services/lyrics/providers/paxsenix.dart';
import 'package:openmusic/services/lyrics/providers/youtube.dart';
import 'package:openmusic/services/logger/logger.dart';

/// Ceiling for one provider. Past this it's holding up every provider behind
/// it for a result that probably isn't coming.
const _perProviderTimeout = Duration(seconds: 8);

/// Ceiling for the whole chain, so a run of slow providers can't leave the
/// lyrics view spinning indefinitely.
const _totalTimeout = Duration(seconds: 25);

LyricsProvider _buildProvider(LyricsProviderId id) {
  return switch (id) {
    LyricsProviderId.betterLyrics => BetterLyricsProvider(),
    LyricsProviderId.lrclib => LrcLibLyricsProvider(),
    LyricsProviderId.kugou => KuGouLyricsProvider(),
    LyricsProviderId.paxsenix => PaxsenixLyricsProvider(),
    LyricsProviderId.lyricsPlus => LyricsPlusProvider(),
    LyricsProviderId.youtubeSubtitle => YouTubeSubtitleLyricsProvider(),
    LyricsProviderId.youtubeMusic => YouTubeMusicLyricsProvider(),
  };
}

/// The enabled providers, in the user's priority order.
///
/// Any provider missing from the stored order is appended in its default
/// position, so a provider added in a later release isn't invisible to users
/// who already have a saved order.
final lyricsProvidersProvider = Provider<List<LyricsProvider>>((ref) {
  final preferences = ref.watch(userPreferencesProvider);

  final enabled = preferences.lyricsProvidersEnabled.toSet();

  final ordered = <LyricsProviderId>[];
  for (final name in preferences.lyricsProviderOrder) {
    final id = LyricsProviderId.fromNameOrNull(name);
    if (id != null && !ordered.contains(id)) ordered.add(id);
  }
  for (final id in LyricsProviderId.values) {
    if (!ordered.contains(id)) ordered.add(id);
  }

  return ordered
      .where((id) => enabled.contains(id.name))
      .map(_buildProvider)
      .toList();
});

class SyncedLyricsNotifier
    extends FamilyAsyncNotifier<SubtitleSimple, SpotubeTrackObject?> {
  @override
  FutureOr<SubtitleSimple> build(SpotubeTrackObject? track) async {
    try {
      if (track == null) {
        throw "No track currently";
      }

      final database = ref.watch(databaseProvider);
      final cached = await _readCache(database, track.id);

      if (cached != null) {
        // A cached miss is a real answer: every provider was already asked.
        if (cached.isNotFound) {
          throw Exception("Unable to find lyrics");
        }
        if (cached.lyrics.isNotEmpty) return cached;
      }

      final providers = ref.watch(lyricsProvidersProvider);
      final lyrics = await _runChain(track, providers);

      if (lyrics == null) {
        await _writeCache(
            database, track.id, SubtitleSimple.notFound(track.name));
        throw Exception("Unable to find lyrics");
      }

      await _writeCache(database, track.id, lyrics);
      return lyrics;
    } catch (e, stackTrace) {
      AppLogger.reportError(e, stackTrace);
      rethrow;
    }
  }

  /// Tries each provider in turn, returning the first usable result.
  ///
  /// A provider that fails or times out is logged and skipped — one bad
  /// provider must never take down the chain, which is the whole reason for
  /// having several.
  Future<SubtitleSimple?> _runChain(
    SpotubeTrackObject track,
    List<LyricsProvider> providers,
  ) async {
    final deadline = DateTime.now().add(_totalTimeout);
    var query = _queryFor(track);
    var resolvedSourceId = false;

    for (final provider in providers) {
      if (DateTime.now().isAfter(deadline)) {
        AppLogger.log.w(
          "Lyrics chain for '${track.name}' hit its ${_totalTimeout.inSeconds}s "
          "budget; skipping ${provider.name} and the rest",
        );
        break;
      }

      // Only pay for audio-source resolution once, and only if something in
      // the chain actually needs the video id.
      if (provider.requiresSourceId && !resolvedSourceId) {
        resolvedSourceId = true;
        query = query.withSourceId(await _resolveSourceId(track));
      }

      if (!provider.isAvailable(query)) continue;

      try {
        final result = await provider.fetch(query).timeout(_perProviderTimeout);
        if (result != null && result.lyrics.isNotEmpty) return result;
      } catch (e, stackTrace) {
        AppLogger.reportError(e, stackTrace);
      }
    }

    return null;
  }

  /// The audio source's id for this track, when one can be had cheaply.
  ///
  /// Returns null rather than throwing: the YouTube providers simply report
  /// themselves unavailable, which is the correct outcome when the active
  /// audio-source plugin isn't YouTube-backed.
  Future<String?> _resolveSourceId(SpotubeTrackObject track) async {
    if (track is! SpotubeFullTrackObject) return null;

    try {
      final sourced = await ref
          .read(sourcedTrackProvider(track).future)
          .timeout(_perProviderTimeout);
      return sourced.info.id;
    } catch (e, stackTrace) {
      AppLogger.reportError(e, stackTrace);
      return null;
    }
  }

  /// Re-runs the whole chain, ignoring and replacing whatever is cached.
  Future<void> refetch() async {
    final track = arg;
    if (track == null) return;

    final database = ref.read(databaseProvider);
    state = const AsyncValue.loading();

    try {
      final providers = ref.read(lyricsProvidersProvider);
      final lyrics = await _runChain(track, providers);

      if (lyrics == null) {
        await _writeCache(
          database,
          track.id,
          SubtitleSimple.notFound(track.name),
        );
        state = AsyncValue.error(
          Exception("Unable to find lyrics"),
          StackTrace.current,
        );
        return;
      }

      await _writeCache(database, track.id, lyrics);
      state = AsyncValue.data(lyrics);
    } catch (e, stackTrace) {
      AppLogger.reportError(e, stackTrace);
      state = AsyncValue.error(e, stackTrace);
    }
  }

  /// Replaces the cached lyrics with a result the user picked by hand.
  Future<void> select(SubtitleSimple lyrics) async {
    final track = arg;
    if (track == null) return;

    await _writeCache(ref.read(databaseProvider), track.id, lyrics);
    state = AsyncValue.data(lyrics);
  }
}

LyricsQuery _queryFor(SpotubeTrackObject track) {
  return LyricsQuery(
    trackId: track.id,
    title: track.name,
    artists: track.artists.map((a) => a.name).toList(),
    album: track.album.name,
    duration: Duration(milliseconds: track.durationMs),
  );
}

extension _LyricsQuerySource on LyricsQuery {
  LyricsQuery withSourceId(String? sourceId) {
    return LyricsQuery(
      trackId: trackId,
      title: title,
      artists: artists,
      album: album,
      duration: duration,
      sourceId: sourceId,
    );
  }
}

Future<SubtitleSimple?> _readCache(AppDatabase database, String trackId) async {
  final rows = await (database.select(database.lyricsTable)
        ..where((tbl) => tbl.trackId.equals(trackId))
        ..limit(1))
      .get();

  return rows.isEmpty ? null : rows.first.data;
}

Future<void> _writeCache(
  AppDatabase database,
  String trackId,
  SubtitleSimple lyrics,
) async {
  // `track_id` is unique as of schema v11, so this genuinely replaces rather
  // than appending a second row for the track.
  await database.into(database.lyricsTable).insert(
        LyricsTableCompanion.insert(trackId: trackId, data: lyrics),
        mode: InsertMode.insertOrReplace,
      );
}

final syncedLyricsProvider = AsyncNotifierProviderFamily<SyncedLyricsNotifier,
    SubtitleSimple, SpotubeTrackObject?>(() => SyncedLyricsNotifier());

/// The per-song lyrics offset, in seconds, persisted alongside the lyrics.
///
/// Replaces the old in-memory delay, which reset to zero on every track change
/// and so had to be re-dialled every time the song came round again.
class LyricsOffsetNotifier
    extends FamilyAsyncNotifier<int, SpotubeTrackObject?> {
  @override
  FutureOr<int> build(SpotubeTrackObject? track) async {
    if (track == null) return 0;

    final database = ref.watch(databaseProvider);
    final rows = await (database.select(database.lyricsTable)
          ..where((tbl) => tbl.trackId.equals(track.id))
          ..limit(1))
        .get();

    return rows.isEmpty ? 0 : rows.first.offsetMs ~/ 1000;
  }

  Future<void> set(int seconds) async {
    final track = arg;
    if (track == null) return;

    state = AsyncValue.data(seconds);

    final database = ref.read(databaseProvider);
    // Updates only: the row is created when the lyrics themselves are cached,
    // and an offset without lyrics has nothing to apply to.
    await (database.update(database.lyricsTable)
          ..where((tbl) => tbl.trackId.equals(track.id)))
        .write(LyricsTableCompanion(offsetMs: Value(seconds * 1000)));
  }
}

final lyricsOffsetProvider =
    AsyncNotifierProviderFamily<LyricsOffsetNotifier, int, SpotubeTrackObject?>(
  () => LyricsOffsetNotifier(),
);

/// Every enabled provider's result for a track, gathered concurrently.
///
/// Backs the manual picker, which exists for when the automatic choice picked
/// the wrong recording.
final allProviderLyricsProvider = FutureProvider.autoDispose
    .family<List<SubtitleSimple>, SpotubeTrackObject?>((ref, track) async {
  if (track == null) return const [];

  final providers = ref.watch(lyricsProvidersProvider);
  final query = _queryFor(track);

  String? sourceId;
  if (providers.any((p) => p.requiresSourceId) &&
      track is SpotubeFullTrackObject) {
    try {
      final sourced = await ref
          .read(sourcedTrackProvider(track).future)
          .timeout(_perProviderTimeout);
      sourceId = sourced.info.id;
    } catch (_) {
      sourceId = null;
    }
  }

  final resolved = query.withSourceId(sourceId);

  final results = await Future.wait(
    providers.where((p) => p.isAvailable(resolved)).map((provider) async {
      try {
        // LRCLib can offer several distinct recordings; the rest return one.
        if (provider is LrcLibLyricsProvider) {
          return await provider.fetchAll(resolved).timeout(_perProviderTimeout);
        }
        final result =
            await provider.fetch(resolved).timeout(_perProviderTimeout);
        return result == null ? <SubtitleSimple>[] : [result];
      } catch (e, stackTrace) {
        AppLogger.reportError(e, stackTrace);
        return <SubtitleSimple>[];
      }
    }),
  );

  return results.expand((e) => e).where((e) => e.lyrics.isNotEmpty).toList()
    ..sort((a, b) => b.rating.compareTo(a.rating));
});
