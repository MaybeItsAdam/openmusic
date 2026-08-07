import 'package:dio/dio.dart';
import 'package:openmusic/models/database/database.dart';
import 'package:openmusic/models/lyrics.dart';
import 'package:openmusic/services/dio/dio.dart';
import 'package:openmusic/services/lyrics/lyrics_provider.dart';
import 'package:openmusic/services/lyrics/lyrics_text_utils.dart';
import 'package:openmusic/services/lyrics/lyrics_user_agent.dart';
import 'package:openmusic/services/lyrics/parsers/lrc_parser.dart';

/// How far a candidate's duration may differ from the track's before it's
/// considered a different recording.
const _durationTolerance = Duration(seconds: 5);

/// Minimum title similarity to accept a candidate when duration can't be used.
const _similarityThreshold = 0.6;

/// Lyrics credits: [lrclib.net](https://lrclib.net) and their contributors.
/// Thanks for their generous public API.
///
/// Uses `/api/search` rather than `/api/get`. `/api/get` requires the artist,
/// title and album to match LRCLib's record exactly, which fails constantly for
/// tracks whose metadata came from a YouTube title. Searching and then ranking
/// the candidates ourselves resolves far more tracks.
class LrcLibLyricsProvider extends LyricsProvider {
  @override
  LyricsProviderId get id => LyricsProviderId.lrclib;

  @override
  Future<SubtitleSimple?> fetch(LyricsQuery query) async {
    final results = await _search(query);
    if (results.isEmpty) return null;

    final best = _pickBest(results, query);
    if (best == null) return null;

    return _toSubtitle(best, query);
  }

  /// Every candidate this provider can find, best-first. Used by the manual
  /// picker, which shows more than just the automatic choice.
  Future<List<SubtitleSimple>> fetchAll(LyricsQuery query) async {
    final results = await _search(query);
    final ranked = results.toList()
      ..sort((a, b) => _score(b, query).compareTo(_score(a, query)));

    final subtitles = <SubtitleSimple>[];
    var plainCount = 0;

    for (final candidate in ranked) {
      final subtitle = _toSubtitle(candidate, query);
      if (subtitle == null) continue;

      // Plain results are near-duplicates of each other; one is enough.
      if (!subtitle.isSynced) {
        if (plainCount >= 1) continue;
        plainCount++;
      }

      subtitles.add(subtitle);
      if (subtitles.length >= 5) break;
    }

    return subtitles;
  }

  /// Runs the search strategies in order, returning the first non-empty result.
  ///
  /// Each strategy loosens the constraints: an exact-ish match first, then
  /// progressively broader queries, ending with the raw uncleaned metadata in
  /// case the cleaning removed something meaningful.
  Future<List<_LrcLibTrack>> _search(LyricsQuery query) async {
    final title = cleanTitle(query.title);
    final artist = cleanArtist(query.primaryArtist);

    final strategies = <Map<String, String>>[
      {
        "track_name": title,
        if (artist.isNotEmpty) "artist_name": artist,
        if (query.album.isNotEmpty) "album_name": query.album,
      },
      {"track_name": title},
      if (artist.isNotEmpty) {"q": "$artist $title"},
      {"q": title},
      {
        "track_name": query.title,
        if (query.primaryArtist.isNotEmpty) "artist_name": query.primaryArtist,
      },
    ];

    final seen = <String>{};

    for (final params in strategies) {
      // Skip a strategy that's identical to one already tried.
      final key = params.entries.map((e) => "${e.key}=${e.value}").join("&");
      if (!seen.add(key)) continue;

      final results = await _request(params);
      if (results.isNotEmpty) return results;
    }

    return const [];
  }

  Future<List<_LrcLibTrack>> _request(Map<String, String> params) async {
    final res = await globalDio.getUri(
      Uri(
        scheme: "https",
        host: "lrclib.net",
        path: "/api/search",
        queryParameters: params,
      ),
      options: Options(
        headers: {"User-Agent": await lyricsUserAgent()},
        responseType: ResponseType.json,
        // A miss is a 404 here, which is an ordinary outcome, not a fault.
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    if (res.statusCode != 200 || res.data is! List) return const [];

    return (res.data as List)
        .whereType<Map<String, dynamic>>()
        .map(_LrcLibTrack.fromJson)
        .where((t) => t.hasLyrics)
        .toList();
  }

  _LrcLibTrack? _pickBest(List<_LrcLibTrack> results, LyricsQuery query) {
    if (query.durationSeconds > 0) {
      final withinTolerance = results
          .where(
            (t) => (t.duration - query.duration).abs() <= _durationTolerance,
          )
          .toList();

      if (withinTolerance.isNotEmpty) {
        withinTolerance
            .sort((a, b) => _score(b, query).compareTo(_score(a, query)));
        return withinTolerance.first;
      }
    }

    // No usable duration, or nothing matched it. Fall back to title similarity.
    final title = cleanTitle(query.title);
    _LrcLibTrack? best;
    var bestScore = _similarityThreshold;

    for (final candidate in results) {
      var score = stringSimilarity(title, cleanTitle(candidate.trackName));
      if (candidate.hasSyncedLyrics) score += 0.1;

      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    return best;
  }

  double _score(_LrcLibTrack candidate, LyricsQuery query) {
    var score = stringSimilarity(
      cleanTitle(query.title),
      cleanTitle(candidate.trackName),
    );

    if (query.durationSeconds > 0) {
      final diff = (candidate.duration - query.duration).abs();
      if (diff <= const Duration(seconds: 2)) {
        score += 1.0;
      } else if (diff <= _durationTolerance) {
        score += 0.5;
      } else {
        score -= 0.5;
      }
    }

    if (candidate.hasSyncedLyrics) score += 0.3;

    if (query.primaryArtist.isNotEmpty) {
      score += stringSimilarity(
            cleanArtist(query.primaryArtist),
            cleanArtist(candidate.artistName),
          ) *
          0.5;
    }

    return score;
  }

  SubtitleSimple? _toSubtitle(_LrcLibTrack track, LyricsQuery query) {
    final uri = Uri.parse("https://lrclib.net/api/get/${track.id}");

    if (track.hasSyncedLyrics) {
      final lyrics = parseLrc(track.syncedLyrics!);
      final subtitle = buildSubtitle(
        uri: uri,
        name: query.title,
        provider: id,
        lyrics: lyrics,
      );
      if (subtitle != null) return subtitle;
    }

    if (track.plainLyrics?.isNotEmpty == true) {
      return buildSubtitle(
        uri: uri,
        name: query.title,
        provider: id,
        lyrics: parsePlain(track.plainLyrics!),
      );
    }

    return null;
  }
}

class _LrcLibTrack {
  final int id;
  final String trackName;
  final String artistName;
  final Duration duration;
  final String? plainLyrics;
  final String? syncedLyrics;

  const _LrcLibTrack({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.duration,
    this.plainLyrics,
    this.syncedLyrics,
  });

  factory _LrcLibTrack.fromJson(Map<String, dynamic> json) {
    return _LrcLibTrack(
      id: (json["id"] as num?)?.toInt() ?? 0,
      trackName: json["trackName"] as String? ?? "",
      artistName: json["artistName"] as String? ?? "",
      // LRCLib reports duration in seconds, sometimes fractional.
      duration: Duration(
        milliseconds: (((json["duration"] as num?) ?? 0) * 1000).round(),
      ),
      plainLyrics: json["plainLyrics"] as String?,
      syncedLyrics: json["syncedLyrics"] as String?,
    );
  }

  bool get hasSyncedLyrics => syncedLyrics?.isNotEmpty == true;

  bool get hasLyrics => hasSyncedLyrics || plainLyrics?.isNotEmpty == true;
}
