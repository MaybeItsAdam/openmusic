import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/models/lyrics.dart';

void main() {
  group("cache compatibility", () {
    test("decodes a blob written before word timings existed", () {
      // Exactly the shape older versions persisted into LyricsTable.data.
      // Users upgrading have these rows already; they must keep decoding.
      const legacy = '''
      {
        "uri": "https://lrclib.net/api/get/1",
        "name": "Song",
        "rating": 100,
        "provider": "LRCLib",
        "lyrics": [
          {"time": 0, "text": "first"},
          {"time": 1500, "text": "second"}
        ]
      }
      ''';

      final subtitle = SubtitleSimple.fromJson(jsonDecode(legacy));

      expect(subtitle.provider, "LRCLib");
      expect(subtitle.lyrics, hasLength(2));
      expect(subtitle.lyrics[1].time, const Duration(milliseconds: 1500));
      expect(subtitle.lyrics[1].words, isNull);
      expect(subtitle.lyrics[1].agent, isNull);
      expect(subtitle.lyrics[1].endTime, isNull);
      expect(subtitle.lyrics[1].isBackground, isFalse);
    });

    test("decodes a blob with no provider field at all", () {
      const ancient = '''
      {
        "uri": "https://example.com",
        "name": "Song",
        "rating": 0,
        "lyrics": [{"time": 0, "text": "x"}]
      }
      ''';

      expect(SubtitleSimple.fromJson(jsonDecode(ancient)).provider, "unknown");
    });

    test("round-trips word timings, agent and background", () {
      final original = SubtitleSimple(
        uri: Uri.parse("https://example.com"),
        name: "Song",
        rating: 150,
        provider: "Paxsenix",
        lyrics: [
          LyricSlice(
            time: const Duration(seconds: 1),
            endTime: const Duration(seconds: 3),
            text: "hi there",
            agent: "v2",
            isBackground: true,
            words: const [
              WordTimestamp(
                text: "hi",
                start: Duration(seconds: 1),
                end: Duration(seconds: 2),
                hasTrailingSpace: false,
              ),
              WordTimestamp(
                text: "there",
                start: Duration(seconds: 2),
                end: Duration(seconds: 3),
              ),
            ],
          ),
        ],
      );

      final decoded = SubtitleSimple.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      final slice = decoded.lyrics.single;
      expect(slice.agent, "v2");
      expect(slice.isBackground, isTrue);
      expect(slice.endTime, const Duration(seconds: 3));
      expect(slice.words, hasLength(2));
      expect(slice.words![0].hasTrailingSpace, isFalse);
      expect(slice.words![1].hasTrailingSpace, isTrue);
    });
  });

  group("result classification", () {
    test("notFound is recognised and carries no lyrics", () {
      final missing = SubtitleSimple.notFound("Song");

      expect(missing.isNotFound, isTrue);
      expect(missing.lyrics, isEmpty);
      // It survives a round-trip through the cache, which is the whole point
      // of storing a miss rather than nothing.
      expect(
        SubtitleSimple.fromJson(jsonDecode(jsonEncode(missing.toJson())))
            .isNotFound,
        isTrue,
      );
    });

    test("isSynced is false when every line sits at zero", () {
      final plain = SubtitleSimple(
        uri: Uri.parse("https://example.com"),
        name: "Song",
        rating: 0,
        provider: "LRCLib",
        lyrics: [
          LyricSlice(time: Duration.zero, text: "a"),
          LyricSlice(time: Duration.zero, text: "b"),
        ],
      );

      expect(plain.isSynced, isFalse);
      expect(plain.hasWordTimings, isFalse);
    });

    test("hasWordTimings is true when any line carries words", () {
      final synced = SubtitleSimple(
        uri: Uri.parse("https://example.com"),
        name: "Song",
        rating: 150,
        provider: "BetterLyrics",
        lyrics: [
          LyricSlice(
            time: const Duration(seconds: 1),
            text: "a",
            words: const [
              WordTimestamp(
                text: "a",
                start: Duration(seconds: 1),
                end: Duration(seconds: 2),
              ),
            ],
          ),
        ],
      );

      expect(synced.isSynced, isTrue);
      expect(synced.hasWordTimings, isTrue);
    });
  });
}
