import 'dart:io';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:openmusic/models/database/database.dart';
import 'package:openmusic/modules/settings/youtube_engine_not_installed_dialog.dart';
import 'package:openmusic/provider/user_preferences/user_preferences_provider.dart';
import 'package:openmusic/services/kv_store/kv_store.dart';
import 'package:openmusic/services/youtube_engine/yt_dlp_engine.dart';

void useCheckYtDlpInstalled(WidgetRef ref) {
  final context = useContext();

  useEffect(() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final youtubeEngine = ref.read(
        userPreferencesProvider.select((value) => value.youtubeClientEngine),
      );

      final customPath = KVStoreService.getYoutubeEnginePath(
        YoutubeClientEngine.ytDlp,
      );

      if (youtubeEngine == YoutubeClientEngine.ytDlp &&
          !await YtDlpEngine.isInstalled() &&
          (customPath == null || !await File(customPath).exists()) &&
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
