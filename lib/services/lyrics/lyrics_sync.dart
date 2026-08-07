import 'package:openmusic/models/lyrics.dart';

/// How far ahead of a line's timestamp it becomes current. Highlighting a
/// fraction early reads as "on the beat"; highlighting exactly on time reads
/// as late.
const _leadThreshold = Duration(milliseconds: 100);

/// Index of the line that should be highlighted at [position], or -1 before the
/// first line starts.
///
/// Binary search over timestamps, so two lines inside the same second resolve
/// distinctly — the whole point of storing millisecond timings.
int findCurrentLineIndex(List<LyricSlice> lines, Duration position) {
  if (lines.isEmpty) return -1;

  final cutoff = position + _leadThreshold;

  var low = 0;
  var high = lines.length;

  // Find the first line whose time is >= cutoff; the current line is the one
  // before it.
  while (low < high) {
    final mid = (low + high) >> 1;
    if (lines[mid].time >= cutoff) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }

  return low - 1;
}

/// Every line that is sounding at [position].
///
/// Duets and backing vocals overlap, so more than one line can be active at
/// once. A line ends at its last word's end time when word timings exist,
/// otherwise when the next line begins.
Set<int> findActiveLineIndices(List<LyricSlice> lines, Duration position) {
  if (lines.isEmpty) return const {};

  final active = <int>{};

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.time > position) break;

    final end = lineEndTime(lines, i);
    if (end == null || position < end) {
      active.add(i);
    }
  }

  if (active.isEmpty) return const {};

  // Without word timings there's nothing to disambiguate overlapping lines, so
  // several would stay lit at once. Keep only the most recent lead vocal;
  // background lines are meant to overlap and are left alone.
  final hasWordTimings = active.any(
    (i) => lines[i].words != null && lines[i].words!.isNotEmpty,
  );

  if (!hasWordTimings) {
    final lead = active.where((i) => !lines[i].isBackground).toList()
      ..sort(
        (a, b) => lines[a].time.compareTo(lines[b].time),
      );
    if (lead.length > 1) {
      active.removeAll(lead.sublist(0, lead.length - 1));
    }
  }

  return active;
}

/// When the line at [index] stops sounding, or null if it runs to the end.
Duration? lineEndTime(List<LyricSlice> lines, int index) {
  final line = lines[index];

  if (line.words != null && line.words!.isNotEmpty) {
    return line.words!.last.end;
  }
  if (line.endTime != null) {
    return line.endTime;
  }

  for (var next = index + 1; next < lines.length; next++) {
    // Skip lines sharing this timestamp — they're simultaneous voices, not the
    // thing that ends this one.
    if (lines[next].time > line.time) return lines[next].time;
  }

  return null;
}

/// How much of the line at [index] has been sung, in `0.0..1.0`.
///
/// Used for karaoke fill. Falls back to a binary on/off when the line has no
/// word timings.
double lineProgress(List<LyricSlice> lines, int index, Duration position) {
  final line = lines[index];
  if (position < line.time) return 0;

  final end = lineEndTime(lines, index);
  if (end == null || end <= line.time) return 1;

  final elapsed = position - line.time;
  final span = end - line.time;
  return (elapsed.inMicroseconds / span.inMicroseconds).clamp(0.0, 1.0);
}

/// How much of [word] has been sung at [position], in `0.0..1.0`.
double wordProgress(WordTimestamp word, Duration position) {
  if (position >= word.end) return 1;
  if (position <= word.start) return 0;

  final span = word.end - word.start;
  if (span <= Duration.zero) return 1;

  return ((position - word.start).inMicroseconds / span.inMicroseconds)
      .clamp(0.0, 1.0);
}
