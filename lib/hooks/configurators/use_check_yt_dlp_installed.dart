import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:openmusic/models/database/database.dart';
import 'package:openmusic/modules/settings/youtube_engine_not_installed_dialog.dart';
import 'package:openmusic/provider/user_preferences/user_preferences_provider.dart';
import 'package:openmusic/provider/youtube_engine/youtube_engine.dart';

void useCheckYtDlpInstalled(WidgetRef ref) {
  final context = useContext();

  useEffect(() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final youtubeEngine = ref.read(
        userPreferencesProvider.select((value) => value.youtubeClientEngine),
      );

      // yt-dlp is the default engine on desktop but ships separately, so this
      // is the first-run prompt for anyone who doesn't have it yet. Playback
      // falls back to NewPipe meanwhile — see [youtubeEngineProvider].
      if (youtubeEngine == YoutubeClientEngine.ytDlp &&
          !await isYtDlpUsable() &&
          context.mounted) {
        await showDialog(
          context: context,
          builder: (context) =>
              YouTubeEngineNotInstalledDialog(engine: youtubeEngine),
        );
      }
    });

    return null;
  }, []);
}
