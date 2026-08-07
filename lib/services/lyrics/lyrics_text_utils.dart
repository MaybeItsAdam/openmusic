import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fuzzy;
import 'package:html_unescape/html_unescape.dart';

final _htmlUnescape = HtmlUnescape();

/// Decorations YouTube-sourced titles carry that lyrics databases never do.
final _titleNoiseRegex = RegExp(
  r"\s*[\(\[]\s*(official\s*)?(music\s*)?(video|audio|lyrics?|visualizer|"
  r"mv|m/v|hd|hq|4k|remaster(ed)?(\s*\d{4})?|explicit|clean|"
  r"full\s*version|color\s*coded)[^\)\]]*[\)\]]",
  caseSensitive: false,
);

/// CJK bracket pairs used the same way as `(...)` above.
final _cjkBracketRegex = RegExp(r"[【（「『《〈＜][^】）」』》〉＞]*[】）」』》〉＞]");

final _featureRegex = RegExp(
  r"\s*[\(\[]?\s*(feat\.?|ft\.?|featuring|with)\s+[^\)\]]*[\)\]]?\s*$",
  caseSensitive: false,
);

/// A trailing `| Some Channel` suffix.
final _pipeSuffixRegex = RegExp(r"\s*\|.*$");

/// Separators that introduce a secondary artist. The first artist is the one
/// lyrics databases index under.
final _artistSplitRegex = RegExp(
  r"\s*(?:,|&|;|\bx\b|\band\b|\bfeat\.?\b|\bft\.?\b|\bfeaturing\b|\bwith\b)\s*",
  caseSensitive: false,
);

/// Lines that credit the transcriber rather than being part of the song.
final _creditPrefixes = <String>[
  "synced by",
  "lyrics by",
  "music by",
  "arranged by",
  "composed by",
  "written by",
];

/// Markup the extended LRC dialect adds, stripped before credit matching so a
/// credit line still matches when it carries an agent or background tag.
final _lyricsMarkupRegex = RegExp(
  r"^\s*(?:\[\d{1,2}:\d{2}[.:]\d{2,3}\]\s*)*"
  r"(?:\{agent:[^}]*\}|\{bg\}|v\d+:)*\s*",
);

/// Strips release-noise from a track title so it can be matched against a
/// lyrics database. `"Song (Official Music Video) | Label"` becomes `"Song"`.
String cleanTitle(String title) {
  var result = title;
  result = result.replaceAll(_titleNoiseRegex, " ");
  result = result.replaceAll(_cjkBracketRegex, " ");
  result = result.replaceAll(_pipeSuffixRegex, " ");
  result = result.replaceAll(_featureRegex, " ");
  result = result.replaceAll(RegExp(r"\s+"), " ").trim();

  // Never strip the title down to nothing — a search for "" matches everything.
  return result.isEmpty ? title.trim() : result;
}

/// Reduces a possibly-collaborative artist credit to the primary artist.
String cleanArtist(String artist) {
  final parts = artist.split(_artistSplitRegex).where((e) => e.isNotEmpty);
  final primary = parts.isEmpty ? artist : parts.first;
  final result = primary.replaceAll(RegExp(r"\s+"), " ").trim();
  return result.isEmpty ? artist.trim() : result;
}

String decodeHtmlEntities(String input) {
  try {
    return _htmlUnescape.convert(input);
  } catch (_) {
    // Malformed entities shouldn't cost us the whole lyrics body.
    return input;
  }
}

/// Undoes the escaping some providers apply when they embed LRC inside JSON
/// strings, and drops the wrapping quotes a few of them leave behind.
String unescapeLyricsBody(String input) {
  var result = input
      .replaceAll(r"\r\n", "\n")
      .replaceAll(r"\n", "\n")
      .replaceAll(r"\r", "\n")
      .replaceAll(r"\t", " ")
      .replaceAll(r"\\", r"\");

  if (result.length >= 2 && result.startsWith('"') && result.endsWith('"')) {
    result = result.substring(1, result.length - 1);
  }

  return result;
}

/// Removes transcriber-credit lines. Providers routinely append these and they
/// look like lyrics once timestamps are stripped.
List<String> filterLyricsCreditLines(List<String> lines) {
  return lines.where((line) {
    final bare = line.replaceFirst(_lyricsMarkupRegex, "").trim().toLowerCase();
    if (bare.isEmpty) return true;
    return !_creditPrefixes.any(bare.startsWith);
  }).toList();
}

/// Normalised similarity in `0.0..1.0`, used to pick between candidate results
/// when duration isn't available to disambiguate them.
double stringSimilarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  return fuzzy.ratio(a.toLowerCase(), b.toLowerCase()) / 100;
}
