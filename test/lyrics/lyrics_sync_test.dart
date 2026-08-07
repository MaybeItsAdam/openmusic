import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/models/lyrics.dart';
import 'package:openmusic/services/lyrics/lyrics_sync.dart';

LyricSlice line(int ms, String text,
    {List<WordTimestamp>? words, bool bg = false}) {
  return LyricSlice(
    time: Duration(milliseconds: ms),
    text: text,
    words: words,
    isBackground: bg,
  );
}

void main() {
  group("findCurrentLineIndex", () {
    final lines = [
      line(0, "first"),
      line(5000, "second"),
      line(10000, "third"),
    ];

    test("returns -1 before the first line", () {
      // The 100ms lead means the first line becomes current slightly early,
      // so step back far enough to be genuinely before it.
      expect(
          findCurrentLineIndex(lines, const Duration(milliseconds: -500)), -1);
    });

    test("returns the line that is sounding", () {
      expect(findCurrentLineIndex(lines, const Duration(seconds: 6)), 1);
      expect(findCurrentLineIndex(lines, const Duration(seconds: 12)), 2);
    });

    test("highlights slightly ahead of the timestamp", () {
      // 4.95s is before "second" starts, but within the 100ms lead.
      expect(
          findCurrentLineIndex(lines, const Duration(milliseconds: 4950)), 1);
    });

    test("returns -1 for empty lyrics", () {
      expect(findCurrentLineIndex(const [], Duration.zero), -1);
    });

    test("distinguishes two lines inside the same second", () {
      // The regression this rewrite exists to fix: a seconds-keyed lookup
      // collapsed these two into one entry and lost the second.
      final packed = [
        line(12100, "first half"),
        line(12600, "second half"),
      ];

      expect(
          findCurrentLineIndex(packed, const Duration(milliseconds: 12200)), 0);
      expect(
          findCurrentLineIndex(packed, const Duration(milliseconds: 12700)), 1);
    });
  });

  group("lineEndTime", () {
    test("uses the last word's end when word timings exist", () {
      final lines = [
        line(
          1000,
          "hi",
          words: const [
            WordTimestamp(
              text: "hi",
              start: Duration(milliseconds: 1000),
              end: Duration(milliseconds: 1500),
            ),
          ],
        ),
        line(9000, "later"),
      ];

      expect(lineEndTime(lines, 0), const Duration(milliseconds: 1500));
    });

    test("falls back to the next line's start", () {
      final lines = [line(1000, "a"), line(4000, "b")];

      expect(lineEndTime(lines, 0), const Duration(milliseconds: 4000));
    });

    test("returns null for the final line", () {
      expect(lineEndTime([line(1000, "a")], 0), isNull);
    });

    test("skips lines sharing the same timestamp", () {
      // Simultaneous voices don't end each other.
      final lines = [line(1000, "v1"), line(1000, "v2"), line(5000, "next")];

      expect(lineEndTime(lines, 0), const Duration(milliseconds: 5000));
    });
  });

  group("findActiveLineIndices", () {
    test("is empty before playback reaches the first line", () {
      final lines = [line(5000, "a")];

      expect(findActiveLineIndices(lines, Duration.zero), isEmpty);
    });

    test("keeps only the latest lead line without word timings", () {
      final lines = [line(0, "a"), line(1000, "b"), line(9000, "c")];

      expect(
        findActiveLineIndices(lines, const Duration(milliseconds: 2000)),
        {1},
      );
    });

    test("keeps a background line alongside its lead", () {
      final lines = [
        line(0, "lead"),
        line(0, "backing", bg: true),
        line(9000, "next"),
      ];

      expect(
        findActiveLineIndices(lines, const Duration(milliseconds: 500)),
        {0, 1},
      );
    });
  });

  group("wordProgress", () {
    const word = WordTimestamp(
      text: "hello",
      start: Duration(seconds: 1),
      end: Duration(seconds: 2),
    );

    test("is 0 before, 1 after", () {
      expect(wordProgress(word, Duration.zero), 0);
      expect(wordProgress(word, const Duration(seconds: 5)), 1);
    });

    test("is halfway through the span", () {
      expect(
        wordProgress(word, const Duration(milliseconds: 1500)),
        closeTo(0.5, 0.001),
      );
    });

    test("treats a zero-length word as complete", () {
      const instant = WordTimestamp(
        text: "x",
        start: Duration(seconds: 1),
        end: Duration(seconds: 1),
      );

      expect(wordProgress(instant, const Duration(seconds: 1)), 1);
    });
  });
}
