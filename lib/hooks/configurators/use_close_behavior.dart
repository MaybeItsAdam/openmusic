import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:openmusic/hooks/configurators/use_window_listener.dart';
import 'package:openmusic/models/database/database.dart';
import 'package:openmusic/provider/user_preferences/user_preferences_provider.dart';

import 'package:local_notifier/local_notifier.dart';
import 'package:openmusic/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

final closeNotification = !kIsDesktop
    ? null
    : (LocalNotification(
        title: 'OpenMusic',
        body: 'Running in background. Minimized to System Tray',
        actions: [LocalNotificationAction(text: 'Close The App')],
      )..onClickAction = (value) {
        exit(0);
      });

void useCloseBehavior(WidgetRef ref) {
  useWindowListener(
    onWindowClose: () async {
      final preferences = ref.read(userPreferencesProvider);
      if (preferences.closeBehavior == CloseBehavior.minimizeToTray) {
        await windowManager.hide();
        closeNotification?.show();
      } else {
        exit(0);
      }
    },
  );
}
