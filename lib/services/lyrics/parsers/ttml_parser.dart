import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:openmusic/models/lyrics.dart';

/// `hh:mm:ss.fff`, `mm:ss.fff` — TTML "clock time".
final _clockTimeRegex = RegExp(r"^(?:(\d+):)?(\d{1,2}):(\d{2})(?:[.:](\d+))?$");

/// `12.5s`, `1234ms`, `2m`, `1h` — TTML "offset time".
final _offsetTimeRegex = RegExp(r"^(\d+(?:\.\d+)?)(h|ms|m|s)$");

/// Parses Apple-Music-style TTML into timed lines with per-word timings.
///
/// TTML is the pivot format for the providers that can supply karaoke timing:
/// BetterLyrics returns it directly, Paxsenix returns it as `ttmlContent`, and
/// LyricsPlus's Binimum source links to it.
///
/// Each `<p>` is a line. `<span>` children with `begin`/`end` are words. A span
/// carrying `ttm:role="x-bg"` marks backing vocals, which become their own
/// line, and `ttm:agent` distinguishes voices in a duet.
List<LyricSlice> parseTtml(String raw) {
  // Fragment parsing avoids the html/head/body scaffolding a full document
  // parse would impose on `<tt><body>…`, which would fight TTML's own <body>.
  final fragment = html_parser.parseFragment(raw);

  final paragraphs = <dom.Element>[];
  void collect(dom.Node node) {
    for (final child in node.nodes) {
      if (child is dom.Element) {
        if (child.localName == "p") {
          paragraphs.add(child);
        } else {
          collect(child);
        }
      }
    }
  }

  collect(fragment);

  final slices = <LyricSlice>[];

  for (final p in paragraphs) {
    final lineStart = _timeOf(p, "begin");
    final lineEnd = _timeOf(p, "end");
    final agent = _normalizeAgent(_attr(p, "ttm:agent") ?? _attr(p, "agent"));

    final lead = <WordTimestamp>[];
    final background = <WordTimestamp>[];
    final leadText = StringBuffer();
    final backgroundText = StringBuffer();

    _walk(p.nodes, lead, leadText, background, backgroundText);

    if (lead.isNotEmpty) {
      slices.add(
        LyricSlice(
          time: lead.first.start,
          endTime: lineEnd ?? lead.last.end,
          text: _joinWords(lead),
          words: lead,
          agent: agent,
        ),
      );
    } else {
      // A line with no timed spans still has its own begin/end.
      final text = leadText.toString().replaceAll(RegExp(r"\s+"), " ").trim();
      if (text.isNotEmpty && lineStart != null) {
        slices.add(
          LyricSlice(
            time: lineStart,
            endTime: lineEnd,
            text: text,
            agent: agent,
          ),
        );
      }
    }

    if (background.isNotEmpty) {
      slices.add(
        LyricSlice(
          time: background.first.start,
          endTime: background.last.end,
          text: _joinWords(background),
          words: background,
          agent: agent,
          isBackground: true,
        ),
      );
    }
  }

  slices.sort((a, b) => a.time.compareTo(b.time));
  return slices;
}

/// Walks a `<p>`'s children, routing timed spans into [lead] or [background].
///
/// Sibling context matters: TTML keeps inter-word spacing either inside a span
/// (`<span>Hello </span>`) or in the text node between two spans
/// (`<span>Hello</span> <span>world</span>`). Both have to be honoured, or CJK
/// lyrics gain spaces they shouldn't have and Latin ones lose the spaces they
/// should.
void _walk(
  List<dom.Node> nodes,
  List<WordTimestamp> lead,
  StringBuffer leadText,
  List<WordTimestamp> background,
  StringBuffer backgroundText,
) {
  for (var i = 0; i < nodes.length; i++) {
    final node = nodes[i];

    if (node is dom.Text) {
      if (node.text.trim().isNotEmpty) leadText.write(node.text);
      continue;
    }
    if (node is! dom.Element) continue;

    final isBackground =
        (_attr(node, "ttm:role") ?? _attr(node, "role")) == "x-bg";

    // A background group wraps its own timed spans rather than holding text.
    if (isBackground) {
      _walk(node.nodes, background, backgroundText, background, backgroundText);
      continue;
    }

    if (node.children.isNotEmpty) {
      _walk(node.nodes, lead, leadText, background, backgroundText);
      continue;
    }

    final text = node.text;
    leadText.write(text);

    final begin = _timeOf(node, "begin");
    if (begin == null || text.trim().isEmpty) continue;

    final followedByWhitespace = _startsWithWhitespace(nodes, i + 1);

    lead.add(
      WordTimestamp(
        text: text.trim(),
        start: begin,
        end: _timeOf(node, "end") ?? begin + const Duration(milliseconds: 500),
        hasTrailingSpace: text.endsWith(" ") || followedByWhitespace,
      ),
    );
  }
}

/// Whether the node at [index] begins with whitespace, i.e. the previous word
/// is followed by a space in the source.
bool _startsWithWhitespace(List<dom.Node> nodes, int index) {
  if (index >= nodes.length) return false;
  final next = nodes[index];
  if (next is! dom.Text) return false;
  return next.text.isNotEmpty && next.text.startsWith(RegExp(r"\s"));
}

String _joinWords(List<WordTimestamp> words) {
  final buffer = StringBuffer();
  for (var i = 0; i < words.length; i++) {
    buffer.write(words[i].text);
    if (i < words.length - 1 && words[i].hasTrailingSpace) buffer.write(" ");
  }
  return buffer.toString().trim();
}

String? _attr(dom.Element element, String name) {
  for (final entry in element.attributes.entries) {
    final key = entry.key;
    final asString = key is String ? key : key.toString();
    if (asString.toLowerCase() == name.toLowerCase()) return entry.value;
  }
  return null;
}

Duration? _timeOf(dom.Element element, String name) {
  final raw = _attr(element, name);
  if (raw == null) return null;
  return parseTtmlTime(raw);
}

/// `{agent:v1}` in the LRC dialect; TTML spells the same thing `ttm:agent="v1"`
/// or `ttm:agent="#v1"`.
String? _normalizeAgent(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return raw.startsWith("#") ? raw.substring(1) : raw;
}

/// Parses a TTML time expression in either clock (`00:01:23.450`) or offset
/// (`83.45s`, `1234ms`) form.
Duration? parseTtmlTime(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;

  final clock = _clockTimeRegex.firstMatch(value);
  if (clock != null) {
    final hours = int.tryParse(clock.group(1) ?? "0") ?? 0;
    final minutes = int.parse(clock.group(2)!);
    final seconds = int.parse(clock.group(3)!);
    final fraction = clock.group(4);

    var millis = 0;
    if (fraction != null && fraction.isNotEmpty) {
      // Normalise whatever precision was written to milliseconds.
      millis = (double.parse("0.$fraction") * 1000).round();
    }

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: millis,
    );
  }

  final offset = _offsetTimeRegex.firstMatch(value);
  if (offset != null) {
    final amount = double.parse(offset.group(1)!);
    return switch (offset.group(2)!) {
      "h" => Duration(microseconds: (amount * 3600 * 1000000).round()),
      "m" => Duration(microseconds: (amount * 60 * 1000000).round()),
      "s" => Duration(microseconds: (amount * 1000000).round()),
      "ms" => Duration(microseconds: (amount * 1000).round()),
      _ => null,
    };
  }

  // Bare seconds, which some generators emit despite the spec.
  final bare = double.tryParse(value);
  if (bare != null) {
    return Duration(microseconds: (bare * 1000000).round());
  }

  return null;
}
