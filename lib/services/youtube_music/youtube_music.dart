import 'package:collection/collection.dart';
import 'package:dio/dio.dart';

/// A song as YouTube Music describes it.
///
/// These are *suggestions*, not playable tracks: the ids belong to YouTube, not
/// to the active metadata plugin, so they have to be resolved against the
/// plugin before anything can be played or opened. See
/// `lib/provider/youtube_music/recommendations.dart`.
class YoutubeMusicSong {
  final String videoId;
  final String title;
  final String? artist;
  final String? album;

  const YoutubeMusicSong({
    required this.videoId,
    required this.title,
    this.artist,
    this.album,
  });

  /// The query used to look this song up through a metadata plugin.
  String get searchQuery =>
      artist == null || artist!.isEmpty ? title : "$title $artist";

  @override
  String toString() => "YoutubeMusicSong($title - $artist, $videoId)";
}

/// An artist YouTube Music links to. Only the display name is useful to us —
/// the browseId is YouTube's, so artists are resolved by name search too.
class YoutubeMusicArtistRef {
  final String browseId;
  final String name;

  const YoutubeMusicArtistRef({required this.browseId, required this.name});

  @override
  String toString() => "YoutubeMusicArtistRef($name, $browseId)";
}

/// The parts of a `next` (watch) response we care about: the radio queue that
/// YouTube Music builds around a song, and the pointer to its related content.
class YoutubeMusicWatchNext {
  final List<YoutubeMusicSong> radio;
  final String? relatedBrowseId;

  const YoutubeMusicWatchNext({required this.radio, this.relatedBrowseId});
}

/// Songs and artists YouTube Music considers related to a song.
class YoutubeMusicRelated {
  final List<YoutubeMusicSong> songs;
  final List<YoutubeMusicArtistRef> artists;

  const YoutubeMusicRelated({required this.songs, required this.artists});

  bool get isEmpty => songs.isEmpty && artists.isEmpty;
}

/// Read-only client for YouTube Music's InnerTube API.
///
/// YouTube Music's recommendations are noticeably better than what the
/// metadata plugins expose, so we use it purely as a suggestion engine. No
/// account, cookie or token is ever sent — every call is anonymous, which is
/// also why the responses are generic-taste rather than personalised. The
/// personalisation comes from the seeds we pick out of local listening history.
class YoutubeMusicService {
  static const _baseUrl = "https://music.youtube.com/youtubei/v1";
  static const _clientName = "WEB_REMIX";
  static const _clientVersion = "1.20240403.01.00";

  /// `params` payload that restricts a search to songs.
  static const _songsSearchFilter = "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D";

  static const _userAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

  final Dio _dio;

  YoutubeMusicService({Dio? dio}) : _dio = dio ?? Dio();

  Map<String, dynamic> get _context => {
        "client": {
          "clientName": _clientName,
          "clientVersion": _clientVersion,
          "hl": "en",
          "gl": "US",
        },
      };

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final response = await _dio.post<dynamic>(
      "$_baseUrl/$endpoint",
      queryParameters: const {"prettyPrint": "false"},
      data: {...body, "context": _context},
      options: Options(
        responseType: ResponseType.json,
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        headers: const {
          "Content-Type": "application/json",
          "Origin": "https://music.youtube.com",
          "Referer": "https://music.youtube.com/",
          "User-Agent": _userAgent,
        },
      ),
    );

    final data = response.data;
    if (data is! Map) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message: "Unexpected YouTube Music response for $endpoint",
      );
    }

    return data.cast<String, dynamic>();
  }

  /// Finds the YouTube Music id of a song, used as the seed of a radio.
  Future<String?> findSongId(String title, String? artist) async {
    final query = [title, artist].nonNulls.join(" ").trim();
    if (query.isEmpty) return null;

    final response = await _post("search", {
      "query": query,
      "params": _songsSearchFilter,
    });

    for (final item in findRenderers(
      response,
      "musicResponsiveListItemRenderer",
    )) {
      final song = parseResponsiveListItem(item);
      if (song != null) return song.videoId;
    }

    return null;
  }

  /// The radio ("Up next") YouTube Music builds around [videoId] — its core
  /// recommendation surface for a single song — plus the pointer to the
  /// related-content page for that song.
  ///
  /// The seed itself is dropped from the returned queue.
  Future<YoutubeMusicWatchNext> watchNext(String videoId) async {
    final response = await _post("next", {
      "videoId": videoId,
      "playlistId": "RDAMVM$videoId",
      "isAudioOnly": true,
    });

    final radio = <YoutubeMusicSong>[];
    final seenIds = <String>{videoId};

    for (final item in findRenderers(response, "playlistPanelVideoRenderer")) {
      final song = parsePlaylistPanelVideo(item);
      if (song == null || !seenIds.add(song.videoId)) continue;
      radio.add(song);
    }

    return YoutubeMusicWatchNext(
      radio: radio,
      relatedBrowseId: _findRelatedBrowseId(response),
    );
  }

  /// Songs and artists YouTube Music links from a song's "Related" tab.
  ///
  /// [browseId] comes from [watchNext]; the ids are not stable enough to guess.
  Future<YoutubeMusicRelated> related(String browseId) async {
    final response = await _post("browse", {"browseId": browseId});

    final songs = <YoutubeMusicSong>[];
    final seenSongIds = <String>{};
    for (final item in findRenderers(
      response,
      "musicResponsiveListItemRenderer",
    )) {
      final song = parseResponsiveListItem(item);
      if (song == null || !seenSongIds.add(song.videoId)) continue;
      songs.add(song);
    }

    final artists = <YoutubeMusicArtistRef>[];
    final seenArtistIds = <String>{};
    for (final item in findRenderers(response, "musicTwoRowItemRenderer")) {
      final artist = parseTwoRowArtist(item);
      if (artist == null || !seenArtistIds.add(artist.browseId)) continue;
      artists.add(artist);
    }

    return YoutubeMusicRelated(songs: songs, artists: artists);
  }

  String? _findRelatedBrowseId(Map<String, dynamic> response) {
    for (final tab in findRenderers(response, "tabRenderer")) {
      final browseEndpoint = tab["endpoint"] is Map
          ? (tab["endpoint"] as Map)["browseEndpoint"]
          : null;
      if (browseEndpoint is! Map) continue;

      if (_pageTypeOf(browseEndpoint) != "MUSIC_PAGE_TYPE_TRACK_RELATED") {
        continue;
      }

      final browseId = browseEndpoint["browseId"];
      if (browseId is String && browseId.isNotEmpty) return browseId;
    }

    return null;
  }
}

/// Walks an InnerTube response and yields every occurrence of [key].
///
/// InnerTube nests its renderers differently between endpoints and reshuffles
/// the wrappers without notice, so searching for the renderer by name survives
/// far more of those changes than hard-coded paths would.
Iterable<Map<String, dynamic>> findRenderers(Object? node, String key) sync* {
  if (node is Map) {
    for (final entry in node.entries) {
      if (entry.key == key && entry.value is Map) {
        yield (entry.value as Map).cast<String, dynamic>();
      } else {
        yield* findRenderers(entry.value, key);
      }
    }
  } else if (node is List) {
    for (final item in node) {
      yield* findRenderers(item, key);
    }
  }
}

/// Flattens InnerTube's `{runs: [...]}` / `{simpleText: ...}` text objects.
String? runsText(Object? node) {
  if (node is! Map) return null;

  final runs = node["runs"];
  if (runs is List) {
    final text = runs
        .map((run) => run is Map && run["text"] is String ? run["text"] : "")
        .join();
    return text.isEmpty ? null : text;
  }

  final simpleText = node["simpleText"];
  return simpleText is String && simpleText.isNotEmpty ? simpleText : null;
}

String? _pageTypeOf(Map endpoint) {
  final configs = endpoint["browseEndpointContextSupportedConfigs"];
  if (configs is! Map) return null;
  final musicConfig = configs["browseEndpointContextMusicConfig"];
  if (musicConfig is! Map) return null;
  final pageType = musicConfig["pageType"];
  return pageType is String ? pageType : null;
}

/// The artist name out of a byline like "Artist • Album • 3:24".
///
/// Runs that link to an artist page are preferred over positional guessing,
/// because bylines are localised and their layout differs per endpoint.
String? _artistFromByline(Object? byline) {
  if (byline is! Map) return null;
  final runs = byline["runs"];
  if (runs is! List) return null;

  for (final run in runs) {
    if (run is! Map) continue;
    final endpoint = run["navigationEndpoint"];
    if (endpoint is! Map) continue;
    final browseEndpoint = endpoint["browseEndpoint"];
    if (browseEndpoint is! Map) continue;

    if (_pageTypeOf(browseEndpoint) == "MUSIC_PAGE_TYPE_ARTIST" &&
        run["text"] is String) {
      return run["text"] as String;
    }
  }

  // Unlinked bylines still name the artist first, ahead of the " • " parts.
  final first = runs.firstOrNull;
  if (first is Map && first["text"] is String) {
    final text = (first["text"] as String).trim();
    if (text.isNotEmpty && text != "•") return text;
  }

  return null;
}

String? _videoIdOf(Map<String, dynamic> renderer) {
  final direct = renderer["videoId"];
  if (direct is String && direct.isNotEmpty) return direct;

  final playlistItemData = renderer["playlistItemData"];
  if (playlistItemData is Map && playlistItemData["videoId"] is String) {
    return playlistItemData["videoId"] as String;
  }

  for (final endpoint in findRenderers(renderer, "watchEndpoint")) {
    final videoId = endpoint["videoId"];
    if (videoId is String && videoId.isNotEmpty) return videoId;
  }

  return null;
}

/// Parses a queue entry from a radio/"Up next" panel.
YoutubeMusicSong? parsePlaylistPanelVideo(Map<String, dynamic> renderer) {
  final title = runsText(renderer["title"]);
  final videoId = _videoIdOf(renderer);
  if (title == null || videoId == null) return null;

  return YoutubeMusicSong(
    videoId: videoId,
    title: title,
    artist: _artistFromByline(renderer["longBylineText"]) ??
        _artistFromByline(renderer["shortBylineText"]),
  );
}

/// Parses a song row as used by search results and related-content carousels.
YoutubeMusicSong? parseResponsiveListItem(Map<String, dynamic> renderer) {
  final videoId = _videoIdOf(renderer);
  if (videoId == null) return null;

  final flexColumns = renderer["flexColumns"];
  if (flexColumns is! List || flexColumns.isEmpty) return null;

  final columns = flexColumns
      .map((column) {
        if (column is! Map) return null;
        final inner = column["musicResponsiveListItemFlexColumnRenderer"];
        return inner is Map ? inner["text"] : null;
      })
      .toList()
      .cast<Object?>();

  final title = runsText(columns.first);
  if (title == null) return null;

  return YoutubeMusicSong(
    videoId: videoId,
    title: title,
    artist:
        columns.length > 1 ? _artistFromByline(columns.elementAt(1)) : null,
    album: columns.length > 2 ? runsText(columns.elementAt(2)) : null,
  );
}

/// Parses a carousel card, keeping only the ones pointing at an artist page.
YoutubeMusicArtistRef? parseTwoRowArtist(Map<String, dynamic> renderer) {
  final endpoint = renderer["navigationEndpoint"];
  if (endpoint is! Map) return null;

  final browseEndpoint = endpoint["browseEndpoint"];
  if (browseEndpoint is! Map) return null;
  if (_pageTypeOf(browseEndpoint) != "MUSIC_PAGE_TYPE_ARTIST") return null;

  final browseId = browseEndpoint["browseId"];
  final name = runsText(renderer["title"]);
  if (browseId is! String || browseId.isEmpty || name == null) return null;

  return YoutubeMusicArtistRef(browseId: browseId, name: name);
}
