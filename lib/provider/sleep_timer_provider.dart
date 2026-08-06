import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:openmusic/services/audio_player/audio_player.dart';

class SleepTimerNotifier extends StateNotifier<Duration?> {
  SleepTimerNotifier() : super(null);

  Timer? _timer;

  void setSleepTimer(Duration duration) {
    // Without this, changing an active timer leaves the previous one running
    // and it still fires at its original deadline.
    _timer?.cancel();
    state = duration;

    _timer = Timer(duration, () async {
      state = null;
      // Pausing rather than exiting: the process exit skipped player state
      // persistence entirely, and terminating the app programmatically is
      // grounds for App Store rejection on iOS.
      await audioPlayer.pause();
    });
  }

  void cancelSleepTimer() {
    state = null;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final sleepTimerProvider = StateNotifierProvider<SleepTimerNotifier, Duration?>(
  (ref) => SleepTimerNotifier(),
);
