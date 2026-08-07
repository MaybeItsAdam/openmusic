import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/services/lyrics/parsers/lrc_parser.dart';

void main() {
  group("parseLrc timestamps", () {
    test("reads a two-digit fraction as centiseconds", () {
      final lines = parseLrc("[00:12.34]Hello");

      expect(lines, hasLength(1));
      expect(lines.first.time, const Duration(seconds: 12, milliseconds: 340));
      expect(lines.first.text, "Hello");
    });

    test("reads a three-digit fraction as milliseconds", () {
      final lines = parseLrc("[00:12.345]Hello");

      expect(lines.first.time, const Duration(seconds: 12, milliseconds: 345));
    });

    test("expands a line carrying several timestamps", () {
      final lines = parseLrc("[00:10.00][01:20.00]Chorus");

      expect(lines, hasLength(2));
      expect(lines[0].time, const Duration(seconds: 10));
      expect(lines[1].time, const Duration(minutes: 1, seconds: 20));
      expect(lines.every((l) => l.text == "Chorus"), isTrue);
    });

    test("sorts lines by time regardless of source order", () {
      final lines = parseLrc("[00:30.00]Third\n[00:10.00]First");

      expect(lines.map((l) => l.text), ["First", "Third"]);
    });

    test("discards the [offset:] tag rather than applying it", () {
      final lines = parseLrc("[offset:+500]\n[00:10.00]Hello");

      expect(lines, hasLength(1));
      expect(lines.first.time, const Duration(seconds: 10));
    });

    test("drops metadata tags", () {
      final lines = parseLrc("[ar:Artist]\n[ti:Title]\n[00:01.00]Real line");

      expect(lines.map((l) => l.text), ["Real line"]);
    });
  });

  group("parseLrc extended dialect", () {
    test("parses inline rich sync into word timings", () {
      final lines = parseLrc("[00:12.00]<00:12.00>Hello <00:12.50>world");

      expect(lines, hasLength(1));
      expect(lines.first.text, "Hello world");

      final words = lines.first.words!;
      expect(words.map((w) => w.text), ["Hello", "world"]);
      expect(words[0].start, const Duration(seconds: 12));
      expect(words[0].end, const Duration(seconds: 12, milliseconds: 500));
      // The final word has no closing stamp, so it gets the fallback span.
      expect(words[1].end, const Duration(seconds: 13));
    });

    test("parses a trailing word-timing line", () {
      final lines = parseLrc(
        "[00:12.00]Hello world\n<Hello:12.0:12.5|world:12.5:13.0>",
      );

      expect(lines, hasLength(1));
      expect(lines.first.text, "Hello world");

      final words = lines.first.words!;
      expect(words.map((w) => w.text), ["Hello", "world"]);
      expect(words[0].start, const Duration(seconds: 12));
      expect(words[1].end, const Duration(seconds: 13));
    });

    test("keeps a word containing a colon intact", () {
      final lines = parseLrc("[00:01.00]a\n<re:mix:1.0:2.0>");

      expect(lines.first.words!.single.text, "re:mix");
      expect(lines.first.words!.single.start, const Duration(seconds: 1));
      expect(lines.first.words!.single.end, const Duration(seconds: 2));
    });

    test("extracts the agent marker", () {
      final lines = parseLrc("[00:12.00]{agent:v2}Second singer");

      expect(lines.first.agent, "v2");
      expect(lines.first.text, "Second singer");
    });

    test("extracts the background marker", () {
      final lines = parseLrc("[00:12.00]{bg}(ooh)");

      expect(lines.first.isBackground, isTrue);
      expect(lines.first.text, "(ooh)");
    });

    test("splits a multi-word rich-sync group proportionally", () {
      final lines = parseLrc("[00:00.00]<00:00.00>ab cd <00:02.00>e");

      final words = lines.first.words!;
      expect(words.map((w) => w.text), ["ab", "cd", "e"]);
      // "ab" and "cd" share the 0-2s span equally on character count.
      expect(words[0].start, Duration.zero);
      expect(words[0].end, const Duration(seconds: 1));
      expect(words[1].end, const Duration(seconds: 2));
    });
  });

  group("parseLrc cleaning", () {
    test("decodes HTML entities", () {
      final lines = parseLrc("[00:01.00]Don&apos;t &amp; won&apos;t");

      expect(lines.first.text, "Don't & won't");
    });

    test("drops transcriber credit lines", () {
      final lines = parseLrc(
        "[00:01.00]Synced by someone\n"
        "[00:02.00]Lyrics by someone\n"
        "[00:03.00]Real lyrics",
      );

      expect(lines.map((l) => l.text), ["Real lyrics"]);
    });

    test("keeps timed blank lines as instrumental gaps", () {
      final lines = parseLrc("[00:01.00]Sing\n[00:05.00]\n[00:09.00]More");

      expect(lines, hasLength(3));
      expect(lines[1].text, "");
    });
  });

  group("looksSynced", () {
    test("detects a timestamped body", () {
      expect(looksSynced("[00:12.34]Hello"), isTrue);
    });

    test("rejects plain text and null", () {
      expect(looksSynced("Just some words"), isFalse);
      expect(looksSynced(null), isFalse);
      expect(looksSynced(""), isFalse);
    });
  });

  group("parsePlain", () {
    test("gives every line a zero timestamp", () {
      final lines = parsePlain("one\ntwo");

      expect(lines.map((l) => l.text), ["one", "two"]);
      expect(lines.every((l) => l.time == Duration.zero), isTrue);
    });
  });
}
