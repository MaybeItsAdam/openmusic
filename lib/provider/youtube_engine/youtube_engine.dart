import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openmusic/models/database/database.dart';
import 'package:openmusic/provider/user_preferences/user_preferences_provider.dart';
import 'package:openmusic/services/kv_store/kv_store.dart';
import 'package:openmusic/services/youtube_engine/newpipe_engine.dart';
import 'package:openmusic/services/youtube_engine/youtube_engine.dart';
import 'package:openmusic/services/youtube_engine/youtube_explode_engine.dart';
import 'package:openmusic/services/youtube_engine/yt_dlp_engine.dart';

/// Whether the yt-dlp binary can actually be executed on this machine.
///
/// [YtDlpEngine.isInstalled] only looks at `PATH`, so a user who pointed us at
/// a custom binary through the "not installed" dialog counts as installed too.
Future<bool> isYtDlpUsable() async {
  if (!YtDlpEngine.isAvailableForPlatform) return false;
  if (await YtDlpEngine.isInstalled()) return true;

  final customPath = KVStoreService.getYoutubeEnginePath(
    YoutubeClientEngine.ytDlp,
  );

  return customPath != null && await File(customPath).exists();
}

/// yt-dlp is an external binary rather than a bundled dependency, so being the
/// default engine on desktop is not the same as being usable. Invalidate this
/// after the user installs it or sets a custom path.
final ytDlpInstalledProvider = FutureProvider<bool>((ref) => isYtDlpUsable());

final youtubeEngineProvider = Provider<YouTubeEngine>((ref) {
  final engineMode = ref.watch(
    userPreferencesProvider.select((value) => value.youtubeClientEngine),
  );

  if (engineMode == YoutubeClientEngine.ytDlp &&
      YtDlpEngine.isAvailableForPlatform) {
    // Assume it's there while the check is in flight, otherwise every launch
    // would briefly swap the engine out from under the player.
    final isInstalled = ref.watch(ytDlpInstalledProvider).valueOrNull ?? true;

    if (isInstalled) {
      return YtDlpEngine();
    }
    // The install prompt has already been shown by `useCheckYtDlpInstalled`;
    // keep playing through NewPipe instead of failing every request.
  } else if (engineMode == YoutubeClientEngine.newPipe &&
      NewPipeEngine.isAvailableForPlatform) {
    return NewPipeEngine();
  } else if (engineMode == YoutubeClientEngine.youtubeExplode &&
      YouTubeExplodeEngine.isAvailableForPlatform) {
    return YouTubeExplodeEngine();
  }

  // Either the preference is not available on this platform (an older install
  // may still have `youtubeExplode` persisted on desktop/Android) or yt-dlp is
  // missing. Fall back to whatever this platform can actually run.
  if (NewPipeEngine.isAvailableForPlatform) {
    return NewPipeEngine();
  }

  return YouTubeExplodeEngine();
});
