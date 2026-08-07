import 'package:dio/dio.dart';
import 'package:openmusic/models/database/database.dart';
import 'package:openmusic/models/lyrics.dart';
import 'package:openmusic/services/dio/dio.dart';
import 'package:openmusic/services/lyrics/lyrics_provider.dart';
import 'package:openmusic/services/lyrics/lyrics_user_agent.dart';
import 'package:openmusic/services/lyrics/parsers/ttml_parser.dart';

/// Community mirrors of the same service, tried in order.
const _mirrors = <String>[
  "https://lyricsplus.binimum.org",
  "https://lyricsplus.atomix.one",
  "https://lyricsplus.prjktla.my.id",
  "https://lyricsplus-seven.vercel.app",
];

const _binimumBase = "https://lyrics-api.binimum.org";

/// An ISRC, which the Binimum API can look up directly and unambiguously.
final _isrcRegex = RegExp(r"^[A-Z]{2}[A-Z0-9]{3}\d{2}\d{5}$");

/// Word-level lyrics from the LyricsPlus community service.
///
/// Off by default: it runs on volunteer-hosted mirrors with no availability
/// guarantee. The mirror that last answered is remembered so a healthy run
/// doesn't re-walk the dead ones.
class LyricsPlusProvider extends LyricsProvider {
  static String? _lastWorkingMirror;

  @override
  LyricsProviderId get id => LyricsProviderId.lyricsPlus;

  @override
  Future<SubtitleSimple?> fetch(LyricsQuery query) async {
    // Binimum serves TTML, so when it has the track it usually wins on
    // fidelity; check both and keep whichever is richer.
    final results = await Future.wait([
      _fetchLyricsPlus(query),
      _fetchBinimum(query),
    ]);

    final candidates = results.whereType<List<LyricSlice>>().toList();
    if (candidates.isEmpty) return null;

    candidates.sort(
      (a, b) => LyricsRating.of(b).compareTo(LyricsRating.of(a)),
    );

    return buildSubtitle(
      uri: Uri.parse(_lastWorkingMirror ?? _mirrors.first),
      name: query.title,
      provider: id,
      lyrics: candidates.first,
    );
  }

  Future<List<LyricSlice>?> _fetchLyricsPlus(LyricsQuery query) async {
    final ordered = <String>[
      if (_lastWorkingMirror != null) _lastWorkingMirror!,
      ..._mirrors.where((m) => m != _lastWorkingMirror),
    ];

    for (final mirror in ordered) {
      try {
        final res = await globalDio.getUri(
          Uri.parse("$mirror/v2/lyrics/get").replace(
            queryParameters: {
              "title": query.title,
              "artist": query.primaryArtist,
              if (query.durationSeconds > 0)
                "duration": query.durationSeconds.toString(),
              if (query.album.isNotEmpty) "album": query.album,
            },
          ),
          options: Options(
            headers: {"User-Agent": await lyricsUserAgent()},
            responseType: ResponseType.json,
            receiveTimeout: const Duration(seconds: 6),
            validateStatus: (status) => status != null && status < 500,
          ),
        );

        if (res.statusCode != 200 || res.data is! Map) continue;

        final slices = _parseLyricsPlus((res.data as Map).cast());
        if (slices == null || slices.isEmpty) continue;

        _lastWorkingMirror = mirror;
        return slices;
      } catch (_) {
        // A dead mirror is expected; move to the next one.
        continue;
      }
    }

    return null;
  }

  /// LyricsPlus returns structured JSON rather than LRC, with an optional
  /// `syllabus` array carrying per-word timings.
  List<LyricSlice>? _parseLyricsPlus(Map<String, dynamic> data) {
    final lines = data["lyrics"];
    if (lines is! List) return null;

    final slices = <LyricSlice>[];

    for (final line in lines.whereType<Map<String, dynamic>>()) {
      final startMs = (line["time"] as num?)?.toInt();
      if (startMs == null) continue;

      final text = line["text"] as String? ?? "";
      final durationMs = (line["duration"] as num?)?.toInt();

      final syllabus = line["syllabus"];
      List<WordTimestamp>? words;
      var isBackground = false;

      if (syllabus is List && syllabus.isNotEmpty) {
        words = [];
        for (final word in syllabus.whereType<Map<String, dynamic>>()) {
          final wordStart = (word["time"] as num?)?.toInt();
          final wordDuration = (word["duration"] as num?)?.toInt() ?? 0;
          final wordText = word["text"] as String? ?? "";
          if (wordStart == null || wordText.trim().isEmpty) continue;

          if (word["isBackground"] == true) isBackground = true;

          words.add(
            WordTimestamp(
              text: wordText.trim(),
              start: Duration(milliseconds: wordStart),
              end: Duration(milliseconds: wordStart + wordDuration),
              hasTrailingSpace: wordText.endsWith(" "),
            ),
          );
        }
        if (words.isEmpty) words = null;
      }

      final agent =
          (line["element"] as Map<String, dynamic>?)?["singer"] as String?;

      slices.add(
        LyricSlice(
          time: Duration(milliseconds: startMs),
          endTime: durationMs == null
              ? null
              : Duration(milliseconds: startMs + durationMs),
          text: text.trim(),
          words: words,
          agent: agent,
          isBackground: isBackground,
        ),
      );
    }

    return slices.isEmpty ? null : slices;
  }

  Future<List<LyricSlice>?> _fetchBinimum(LyricsQuery query) async {
    try {
      final isIsrc = _isrcRegex.hasMatch(query.trackId);

      final res = await globalDio.getUri(
        Uri.parse(_binimumBase).replace(
          queryParameters: isIsrc
              ? {"isrc": query.trackId}
              : {
                  "track": query.title,
                  "artist": query.primaryArtist,
                  if (query.album.isNotEmpty) "album": query.album,
                  if (query.durationSeconds > 0)
                    "duration": query.durationSeconds.toString(),
                },
        ),
        options: Options(
          headers: {"User-Agent": await lyricsUserAgent()},
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 6),
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (res.statusCode != 200 || res.data is! Map) return null;

      final results = (res.data as Map)["results"];
      if (results is! List || results.isEmpty) return null;

      for (final result in results.whereType<Map<String, dynamic>>()) {
        final url = result["lyricsUrl"] as String?;
        if (url == null || url.isEmpty) continue;

        final ttml = await globalDio.getUri(
          Uri.parse(url),
          options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 6),
            validateStatus: (status) => status != null && status < 500,
          ),
        );

        if (ttml.statusCode != 200 || ttml.data is! String) continue;

        final slices = parseTtml(ttml.data as String);
        if (slices.isNotEmpty) return slices;
      }
    } catch (_) {
      return null;
    }

    return null;
  }
}
