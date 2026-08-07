import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:openmusic/models/lyrics.dart';
import 'package:openmusic/services/dio/dio.dart';

/// The public web key YouTube Music ships in its own page source.
const _innertubeKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX3";

const _innertubeBase = "https://music.youtube.com/youtubei/v1";

/// WEB_REMIX is the YouTube Music web client; the lyrics and transcript
/// surfaces only exist for it.
Map<String, dynamic> _context() {
  return {
    "client": {
      "clientName": "WEB_REMIX",
      "clientVersion": "1.20240101.01.00",
      "hl": "en",
      "gl": "US",
    },
  };
}

/// A deliberately tiny innertube client covering only the two lyrics surfaces.
///
/// OpenMusic delegates all real YouTube work to plugins and the swappable
/// engines in `lib/services/youtube_engine/`; neither exposes captions or the
/// lyrics panel, and both endpoints here are a single POST, so a full
/// innertube client would be far more machinery than the job needs.
class InnertubeLyricsClient {
  const InnertubeLyricsClient();

  Future<Map<String, dynamic>?> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await globalDio.postUri(
      Uri.parse("$_innertubeBase/$path?key=$_innertubeKey"),
      data: body,
      options: Options(
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Format-Version": "1",
          "Origin": "https://music.youtube.com",
          "Referer": "https://music.youtube.com/",
        },
        responseType: ResponseType.json,
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    if (res.statusCode != 200) return null;
    final data = res.data;
    return data is Map<String, dynamic> ? data : null;
  }

  /// Timed captions for [videoId], as line-synced lyrics.
  ///
  /// The `params` blob is a hand-rolled protobuf message: field 1 (a
  /// length-delimited string) holding the video id, base64-encoded. `\n` is
  /// the tag byte for field 1, and `\x0b` is the length prefix that upstream
  /// hardcodes for 11-character video ids.
  Future<List<LyricSlice>?> transcript(String videoId) async {
    final params = base64.encode(
      utf8.encode("\n${String.fromCharCode(videoId.length)}$videoId"),
    );

    final json = await _post("get_transcript", {
      "context": _context(),
      "params": params,
    });
    if (json == null) return null;

    final actions = json["actions"];
    if (actions is! List) return null;

    for (final action in actions.whereType<Map<String, dynamic>>()) {
      final cueGroups = _dig(action, const [
        "updateEngagementPanelAction",
        "content",
        "transcriptRenderer",
        "body",
        "transcriptBodyRenderer",
        "cueGroups",
      ]);
      if (cueGroups is! List) continue;

      final slices = <LyricSlice>[];

      for (final group in cueGroups.whereType<Map<String, dynamic>>()) {
        final cues = _dig(group, const [
          "transcriptCueGroupRenderer",
          "cues",
        ]);
        if (cues is! List) continue;

        for (final cue in cues.whereType<Map<String, dynamic>>()) {
          final renderer = cue["transcriptCueRenderer"];
          if (renderer is! Map) continue;

          final text = (_dig(renderer, const ["cue", "simpleText"]) as String?)
              // Instrumental sections come through as a bare musical note.
              ?.replaceAll("♪", "")
              .trim();
          if (text == null || text.isEmpty) continue;

          final startMs = int.tryParse("${renderer["startOffsetMs"]}");
          if (startMs == null) continue;

          final durationMs = int.tryParse("${renderer["durationMs"]}");

          slices.add(
            LyricSlice(
              time: Duration(milliseconds: startMs),
              endTime: durationMs == null
                  ? null
                  : Duration(milliseconds: startMs + durationMs),
              text: text,
            ),
          );
        }
      }

      if (slices.isNotEmpty) return slices;
    }

    return null;
  }

  /// YouTube Music's own lyrics panel. Plain text only — no timings.
  Future<List<LyricSlice>?> lyrics(String videoId) async {
    final next = await _post("next", {
      "context": _context(),
      "videoId": videoId,
    });
    if (next == null) return null;

    final browseId = _findLyricsBrowseId(next);
    if (browseId == null) return null;

    final browse = await _post("browse", {
      "context": _context(),
      "browseId": browseId,
    });
    if (browse == null) return null;

    final runs = _dig(browse, const [
      "contents",
      "sectionListRenderer",
      "contents",
    ]);
    if (runs is! List) return null;

    for (final section in runs.whereType<Map<String, dynamic>>()) {
      final description = _dig(section, const [
        "musicDescriptionShelfRenderer",
        "description",
        "runs",
      ]);
      if (description is! List || description.isEmpty) continue;

      final text = description
          .whereType<Map<String, dynamic>>()
          .map((r) => r["text"] as String? ?? "")
          .join();

      if (text.trim().isEmpty) continue;

      return text
          .split("\n")
          .map((line) => LyricSlice(text: line.trim(), time: Duration.zero))
          .toList();
    }

    return null;
  }

  /// The lyrics tab is one of several tabs on the watch-next response, and its
  /// position isn't fixed, so find it by its own marker rather than by index.
  String? _findLyricsBrowseId(Map<String, dynamic> next) {
    final tabs = _dig(next, const [
      "contents",
      "singleColumnMusicWatchNextResultsRenderer",
      "tabbedRenderer",
      "watchNextTabbedResultsRenderer",
      "tabs",
    ]);
    if (tabs is! List) return null;

    for (final tab in tabs.whereType<Map<String, dynamic>>()) {
      final renderer = tab["tabRenderer"];
      if (renderer is! Map) continue;

      final title = renderer["title"];
      final browseId = _dig(renderer, const [
        "endpoint",
        "browseEndpoint",
        "browseId",
      ]);
      if (browseId is! String) continue;

      if (title == "Lyrics" || browseId.startsWith("MPLY")) return browseId;
    }

    return null;
  }
}

/// Walks a nested JSON map, returning null the moment the path breaks. These
/// innertube responses are deep and every level is optional.
Object? _dig(Object? node, List<String> path) {
  var current = node;
  for (final key in path) {
    if (current is! Map) return null;
    current = current[key];
  }
  return current;
}
