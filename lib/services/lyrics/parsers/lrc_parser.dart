import 'package:openmusic/models/lyrics.dart';
import 'package:openmusic/services/lyrics/lyrics_text_utils.dart';

/// One or more leading timestamps followed by the line body.
final _lineRegex = RegExp(r"^((?:\[\d{1,2}:\d{2}[.:]\d{2,3}\]\s*)+)(.*)$");

final _timeRegex = RegExp(r"\[(\d{1,2}):(\d{2})[.:](\d{2,3})\]");

/// Musixmatch-style inline word timing: `<00:12.34>word `.
final _richWordRegex = RegExp(r"<(\d{1,2}):(\d{2})[.:](\d{2,3})>([^<]*)");

/// A trailing word-timing line: `<Hello:12.34:12.98|world:12.98:13.40>`.
final _wordTimingLineRegex = RegExp(r"^<(.+)>$");

final _agentRegex = RegExp(r"\{agent:([^}]+)\}");
final _bgRegex = RegExp(r"^\{bg\}");

/// LRC metadata tags (`[ar:…]`, `[offset:…]`, …) rather than timed lines.
final _metadataTagRegex = RegExp(r"^\[[a-zA-Z#]+:.*\]$");

/// Fallback span for the final word of a line when nothing bounds it.
const _trailingWordSpan = Duration(milliseconds: 500);

/// Parses LRC, including the extended dialect that carries word timings and
/// multi-voice markers:
///
/// ```
/// [00:12.34]Plain line
/// [00:12.34]<00:12.34>Rich <00:12.98>sync
/// [00:12.34]Words below
/// <Words:12.34:12.98|below:12.98:13.40>
/// [00:12.34]{agent:v2}Second singer
/// [00:12.34]{bg}(backing vocals)
/// ```
///
/// Returns lines sorted by timestamp. `[offset:…]` is intentionally discarded —
/// offset is a per-song user setting here, not a property of the lyrics body.
List<LyricSlice> parseLrc(String raw) {
  final body = decodeHtmlEntities(unescapeLyricsBody(raw));

  final lines = filterLyricsCreditLines(
    body
        .split("\n")
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !_metadataTagRegex.hasMatch(line))
        .toList(),
  );

  final slices = <LyricSlice>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    // A word-timing line belongs to the slice above it, not to itself.
    if (_wordTimingLineRegex.hasMatch(line)) continue;

    final match = _lineRegex.firstMatch(line);
    if (match == null) continue;

    final stamps =
        _timeRegex.allMatches(match.group(1)!).map(_durationFromMatch).toList();
    if (stamps.isEmpty) continue;

    var content = match.group(2)!.trim();

    final isBackground = _bgRegex.hasMatch(content);
    if (isBackground) {
      content = content.replaceFirst(_bgRegex, "").trim();
    }

    String? agent;
    final agentMatch = _agentRegex.firstMatch(content);
    if (agentMatch != null) {
      agent = agentMatch.group(1);
      content = content.replaceFirst(_agentRegex, "").trim();
    }

    // Inline rich sync wins; otherwise look for a `<a:1:2|b:2:3>` line below.
    var words = _parseInlineWords(content, stamps.first);
    if (words != null) {
      content = _stripInlineTimings(content);
    } else {
      final next = i + 1 < lines.length ? lines[i + 1] : null;
      if (next != null) {
        final wordLine = _wordTimingLineRegex.firstMatch(next);
        if (wordLine != null) {
          words = _parseWordTimingLine(wordLine.group(1)!);
        }
      }
    }

    if (content.isEmpty && (words == null || words.isEmpty)) {
      // Keep timed blank lines: they render as instrumental gaps.
      for (final stamp in stamps) {
        slices.add(LyricSlice(time: stamp, text: ""));
      }
      continue;
    }

    for (final stamp in stamps) {
      slices.add(
        LyricSlice(
          time: stamp,
          text: content,
          words: words,
          agent: agent,
          isBackground: isBackground,
          endTime: words != null && words.isNotEmpty ? words.last.end : null,
        ),
      );
    }
  }

  slices.sort((a, b) => a.time.compareTo(b.time));
  return slices;
}

/// True when [raw] looks like it carries timestamps at all, as opposed to being
/// a block of plain text.
bool looksSynced(String? raw) {
  if (raw == null) return false;
  final trimmed = raw.trimLeft();
  if (trimmed.isEmpty) return false;
  return RegExp(r"\[\d{1,2}:\d{2}").hasMatch(
    trimmed.substring(0, trimmed.length.clamp(0, 4096)),
  );
}

/// Converts plain text into untimed slices, so a plain-only provider still
/// flows through the same rendering path.
List<LyricSlice> parsePlain(String raw) {
  final body = decodeHtmlEntities(unescapeLyricsBody(raw));
  return filterLyricsCreditLines(body.split("\n"))
      .map((line) => LyricSlice(text: line.trim(), time: Duration.zero))
      .toList();
}

Duration _durationFromMatch(RegExpMatch match) {
  final minutes = int.parse(match.group(1)!);
  final seconds = int.parse(match.group(2)!);
  final fraction = match.group(3)!;

  // Two digits are centiseconds, three are milliseconds.
  final millis =
      fraction.length == 2 ? int.parse(fraction) * 10 : int.parse(fraction);

  return Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
}

String _stripInlineTimings(String content) {
  return content
      .replaceAll(RegExp(r"<\d{1,2}:\d{2}[.:]\d{2,3}>"), "")
      .replaceAll(RegExp(r"\s+"), " ")
      .trim();
}

/// Parses `<00:12.34>Hello <00:12.98>world`, where each stamp opens a span that
/// the following stamp closes.
List<WordTimestamp>? _parseInlineWords(String content, Duration lineStart) {
  final matches = _richWordRegex.allMatches(content).toList();
  if (matches.isEmpty) return null;

  final words = <WordTimestamp>[];

  for (var i = 0; i < matches.length; i++) {
    final start = _durationFromMatch(matches[i]);
    final end = i + 1 < matches.length
        ? _durationFromMatch(matches[i + 1])
        : start + _trailingWordSpan;

    final chunk = matches[i].group(4) ?? "";
    if (chunk.trim().isEmpty) continue;

    // A single stamp can cover several words; split its span proportionally by
    // character count so each word still fills at a plausible rate.
    final pieces = chunk.trim().split(RegExp(r"\s+"));
    final totalChars = pieces.fold<int>(0, (sum, w) => sum + w.length);
    final span = end - start;

    var cursor = start;
    for (var p = 0; p < pieces.length; p++) {
      final share = totalChars == 0
          ? span ~/ pieces.length
          : Duration(
              microseconds:
                  (span.inMicroseconds * pieces[p].length / totalChars).round(),
            );
      final wordEnd = p == pieces.length - 1 ? end : cursor + share;

      words.add(
        WordTimestamp(
          text: pieces[p],
          start: cursor,
          end: wordEnd,
          hasTrailingSpace: p < pieces.length - 1 || chunk.endsWith(" "),
        ),
      );
      cursor = wordEnd;
    }
  }

  if (words.isEmpty) return null;

  // Guard against a first stamp that precedes the line's own timestamp.
  if (words.first.start < lineStart) {
    words[0] = WordTimestamp(
      text: words.first.text,
      start: lineStart,
      end: words.first.end < lineStart ? lineStart : words.first.end,
      hasTrailingSpace: words.first.hasTrailingSpace,
    );
  }

  return words;
}

/// Parses `word:startSeconds:endSeconds|word:startSeconds:endSeconds`.
///
/// The word itself may contain colons, so the last two segments are taken as
/// the bounds and everything before them is the text.
List<WordTimestamp>? _parseWordTimingLine(String body) {
  final words = <WordTimestamp>[];

  for (final entry in body.split("|")) {
    final parts = entry.split(":");
    if (parts.length < 3) continue;

    final end = double.tryParse(parts.removeLast());
    final start = double.tryParse(parts.removeLast());
    if (start == null || end == null) continue;

    final text = parts.join(":");
    if (text.isEmpty) continue;

    words.add(
      WordTimestamp(
        text: text,
        start: Duration(microseconds: (start * 1000000).round()),
        end: Duration(microseconds: (end * 1000000).round()),
      ),
    );
  }

  return words.isEmpty ? null : words;
}
