import 'dart:io';

import 'package:openmusic/services/audio_player/audio_player.dart';
import 'package:openmusic/services/logger/logger.dart';

/// Shuts the process down without leaving libmpv mid-flight.
///
/// Quitting during an in-progress open aborts the process instead of exiting:
/// mpv's opener thread reports failures through an FFI trampoline, and once
/// `exit` has started tearing the Dart VM down that trampoline no longer
/// resolves, so the runtime asserts and raises SIGABRT. A failing source makes
/// this easy to hit, because every retry puts another open in flight. Stopping
/// playback first drops the pending open, leaving nothing to call back in.
///
/// The wait is bounded: a stalled open can sit on libmpv's 120s
/// `network-timeout`, and a quit must not hang behind it. Timing out only
/// returns us to the previous behaviour, so it costs nothing to try.
Future<Never> quitApp() async {
  try {
    await audioPlayer.stop().timeout(const Duration(seconds: 3));
  } catch (error, stackTrace) {
    AppLogger.reportError(error, stackTrace);
  }
  exit(0);
}
