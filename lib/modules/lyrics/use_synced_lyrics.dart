import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:openmusic/models/lyrics.dart';
import 'package:openmusic/services/audio_player/audio_player.dart';
import 'package:openmusic/services/lyrics/lyrics_sync.dart';

/// The current playback position, advanced every frame.
///
/// `positionStream` only emits a few times a second, which is fine for picking
/// the current line but far too coarse for word-level fill — the highlight
/// would visibly step. Between emissions this extrapolates from the last known
/// position using wall-clock time, so fill moves smoothly at frame rate.
Duration useSmoothPosition({required bool isPlaying}) {
  final position = useState(audioPlayer.position);
  final anchor = useRef(_PositionAnchor(audioPlayer.position, Duration.zero));
  final ticker = useRef<Ticker?>(null);
  final elapsedSinceStart = useRef(Duration.zero);

  useEffect(() {
    final subscription = audioPlayer.positionStream.listen((event) {
      anchor.value = _PositionAnchor(event, elapsedSinceStart.value);
      position.value = event;
    });
    return subscription.cancel;
  }, const []);

  useEffect(() {
    final created = Ticker((elapsed) {
      elapsedSinceStart.value = elapsed;

      if (!isPlaying) return;

      final drift = elapsed - anchor.value.tickerElapsed;
      position.value = anchor.value.position + drift;
    })
      ..start();

    ticker.value = created;
    return created.dispose;
  }, [isPlaying]);

  return position.value;
}

class _PositionAnchor {
  /// The last position the player actually reported.
  final Duration position;

  /// The ticker's elapsed time when that report arrived, used as the origin
  /// for extrapolation.
  final Duration tickerElapsed;

  const _PositionAnchor(this.position, this.tickerElapsed);
}

/// The index of the line to highlight, and every line currently sounding.
///
/// [offset] is in seconds and comes from the per-song setting; positive values
/// pull the lyrics earlier relative to the audio.
({int current, Set<int> active}) useActiveLyricLines(
  List<LyricSlice> lines,
  Duration position,
  int offset,
) {
  final adjusted = position + Duration(seconds: offset);

  // Both are cheap — a binary search and a scan that stops at the current
  // line — so they run per frame rather than being memoised.
  return (
    current: findCurrentLineIndex(lines, adjusted),
    active: findActiveLineIndices(lines, adjusted),
  );
}
