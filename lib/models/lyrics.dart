/// Sentinel provider name for a track that every provider failed to resolve.
///
/// A miss is cached as a real row so the whole provider chain isn't re-run on
/// every single play of a track that simply has no lyrics anywhere.
const kLyricsNotFoundProvider = "__not_found__";

class SubtitleSimple {
  Uri uri;
  String name;
  List<LyricSlice> lyrics;
  int rating;
  String provider;

  SubtitleSimple({
    required this.uri,
    required this.name,
    required this.lyrics,
    required this.rating,
    required this.provider,
  });

  /// The negative-cache marker. Persisted like any other result.
  factory SubtitleSimple.notFound(String name) {
    return SubtitleSimple(
      uri: Uri.parse("openmusic://lyrics/not-found"),
      name: name,
      lyrics: const [],
      rating: 0,
      provider: kLyricsNotFoundProvider,
    );
  }

  bool get isNotFound => provider == kLyricsNotFoundProvider;

  /// Whether any line carries a timestamp. A provider that only returned plain
  /// text yields every line at [Duration.zero].
  bool get isSynced => lyrics.any((l) => l.time > Duration.zero);

  /// Whether any line carries per-word timings, i.e. karaoke rendering is
  /// possible. Only TTML/rich-sync capable providers set these.
  bool get hasWordTimings =>
      lyrics.any((l) => l.words != null && l.words!.isNotEmpty);

  factory SubtitleSimple.fromJson(Map<String, dynamic> json) {
    return SubtitleSimple(
      uri: Uri.parse(json["uri"] as String),
      name: json["name"] as String,
      lyrics: (json["lyrics"] as List<dynamic>)
          .map((e) => LyricSlice.fromJson(e as Map<String, dynamic>))
          .toList(),
      rating: json["rating"] as int,
      provider: json["provider"] as String? ?? "unknown",
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "uri": uri.toString(),
      "name": name,
      "lyrics": lyrics.map((e) => e.toJson()).toList(),
      "rating": rating,
      "provider": provider,
    };
  }
}

/// A single timed word within a [LyricSlice], used for karaoke-style fill.
class WordTimestamp {
  final String text;
  final Duration start;
  final Duration end;

  /// Whether a space follows this word in the rendered line. Word timings come
  /// from formats that drop the original whitespace, so it has to be tracked.
  final bool hasTrailingSpace;

  const WordTimestamp({
    required this.text,
    required this.start,
    required this.end,
    this.hasTrailingSpace = true,
  });

  factory WordTimestamp.fromJson(Map<String, dynamic> json) {
    return WordTimestamp(
      text: json["text"] as String? ?? "",
      start: Duration(milliseconds: (json["start"] as num?)?.toInt() ?? 0),
      end: Duration(milliseconds: (json["end"] as num?)?.toInt() ?? 0),
      hasTrailingSpace: json["hasTrailingSpace"] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "text": text,
      "start": start.inMilliseconds,
      "end": end.inMilliseconds,
      if (!hasTrailingSpace) "hasTrailingSpace": false,
    };
  }

  @override
  String toString() => "WordTimestamp($text, $start-$end)";
}

class LyricSlice {
  Duration time;

  /// When the line stops being current. Null means "until the next line".
  Duration? endTime;

  String text;

  /// Per-word timings, when the source format carried them.
  List<WordTimestamp>? words;

  /// Voice marker from the extended LRC dialect (`{agent:v1}`, `{agent:v2}`),
  /// used to lay out duets on opposite sides.
  String? agent;

  /// A `{bg}` line — backing vocals, rendered smaller and dimmer.
  bool isBackground;

  LyricSlice({
    required this.time,
    required this.text,
    this.endTime,
    this.words,
    this.agent,
    this.isBackground = false,
  });

  /// Every field added after the original two is optional here on purpose:
  /// users have `SubtitleSimple` blobs already sitting in `LyricsTable.data`
  /// that predate them, and those rows must keep decoding.
  factory LyricSlice.fromJson(Map<String, dynamic> json) {
    final rawWords = json["words"] as List<dynamic>?;
    final rawEnd = json["endTime"] as num?;

    return LyricSlice(
      time: Duration(milliseconds: (json["time"] as num).toInt()),
      text: json["text"] as String,
      endTime: rawEnd == null ? null : Duration(milliseconds: rawEnd.toInt()),
      words: rawWords
          ?.map((e) => WordTimestamp.fromJson(e as Map<String, dynamic>))
          .toList(),
      agent: json["agent"] as String?,
      isBackground: json["isBackground"] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "time": time.inMilliseconds,
      "text": text,
      if (endTime != null) "endTime": endTime!.inMilliseconds,
      if (words != null) "words": words!.map((e) => e.toJson()).toList(),
      if (agent != null) "agent": agent,
      if (isBackground) "isBackground": true,
    };
  }

  @override
  String toString() {
    return "LyricsSlice({time: $time, text: $text})";
  }
}
