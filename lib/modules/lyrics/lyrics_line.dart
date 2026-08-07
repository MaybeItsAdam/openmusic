import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:openmusic/models/lyrics.dart';
import 'package:openmusic/services/lyrics/lyrics_sync.dart';

/// How far into a word the per-character stagger spreads. Characters finish
/// filling across this fraction of the word's own span, which reads as a sweep
/// rather than the whole word flipping at once.
const _charStagger = 0.35;

/// One lyrics line, with per-word karaoke fill when the provider supplied word
/// timings and a plain highlight when it didn't.
///
/// Fill is rendered as per-word [TextSpan]s with lerped colours rather than a
/// [ShaderMask] gradient: a gradient is measured across the whole widget, so it
/// breaks as soon as a line wraps onto two rows, which long lyrics constantly
/// do.
class LyricsLine extends StatelessWidget {
  final LyricSlice slice;

  /// Whether this line is the one currently being sung.
  final bool isActive;

  /// Playback position, already offset-adjusted.
  final Duration position;

  final Color activeColor;
  final Color inactiveColor;
  final double fontSize;
  final VoidCallback? onTap;

  const LyricsLine({
    required this.slice,
    required this.isActive,
    required this.position,
    required this.activeColor,
    required this.inactiveColor,
    required this.fontSize,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final scale = slice.isBackground ? 0.8 : 1.0;

    final style = TextStyle(
      fontSize: fontSize * scale,
      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
      color: isActive ? activeColor : inactiveColor,
    );

    final hasWordTimings = slice.words != null && slice.words!.isNotEmpty;

    final Widget text;
    if (isActive && hasWordTimings) {
      text = Text.rich(
        TextSpan(children: _wordSpans(style)),
        textAlign: _align,
      );
    } else {
      text = AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 250),
        style: style.copyWith(
          color: slice.isBackground
              ? (isActive ? activeColor : inactiveColor).withValues(alpha: 0.7)
              : style.color,
        ),
        child: Text(slice.text, textAlign: _align),
      );
    }

    if (onTap == null) return text;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: text),
    );
  }

  /// `{agent:v1}` and `{agent:v2}` mark the two voices in a duet; laying them
  /// out on opposite sides is how the source formats intend them to read.
  TextAlign get _align {
    return switch (slice.agent) {
      "v2" => TextAlign.right,
      "v1" => TextAlign.left,
      _ => TextAlign.center,
    };
  }

  List<InlineSpan> _wordSpans(TextStyle style) {
    final words = slice.words!;
    final spans = <InlineSpan>[];

    for (final word in words) {
      final progress = wordProgress(word, position);

      if (progress <= 0 || progress >= 1) {
        // Fully unsung or fully sung — one span for the whole word.
        spans.add(
          TextSpan(
            text: word.text,
            style: style.copyWith(
              color: progress >= 1 ? activeColor : inactiveColor,
            ),
          ),
        );
      } else {
        // Only the word being sung right now pays for per-character spans.
        spans.addAll(_characterSpans(word.text, progress, style));
      }

      if (word.hasTrailingSpace) {
        spans.add(TextSpan(text: " ", style: style));
      }
    }

    return spans;
  }

  /// Splits the active word so each character lights slightly after the one
  /// before it.
  List<InlineSpan> _characterSpans(
    String text,
    double progress,
    TextStyle style,
  ) {
    final characters = text.split("");
    final spans = <InlineSpan>[];

    for (var i = 0; i < characters.length; i++) {
      final start = (i / characters.length) * _charStagger;
      final span = 1 - _charStagger;
      final charProgress = ((progress - start) / span).clamp(0.0, 1.0);

      spans.add(
        TextSpan(
          text: characters[i],
          style: style.copyWith(
            color: Color.lerp(inactiveColor, activeColor, charProgress),
          ),
        ),
      );
    }

    return spans;
  }
}
