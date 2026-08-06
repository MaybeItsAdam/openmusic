import 'dart:async';
import 'dart:ui';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_discord_rpc/flutter_discord_rpc.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:home_widget/home_widget.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:media_kit/media_kit.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'package:openmusic/collections/env.dart';
import 'package:openmusic/collections/intents.dart';
import 'package:openmusic/collections/routes.dart';
import 'package:openmusic/hooks/configurators/use_close_behavior.dart';
import 'package:openmusic/hooks/configurators/use_deep_linking.dart';
import 'package:openmusic/hooks/configurators/use_disable_battery_optimizations.dart';
import 'package:openmusic/hooks/configurators/use_fix_window_stretching.dart';
import 'package:openmusic/hooks/configurators/use_get_storage_perms.dart';
import 'package:openmusic/hooks/configurators/use_has_touch.dart';
import 'package:openmusic/models/database/database.dart';
import 'package:openmusic/modules/settings/color_scheme_picker_dialog.dart';
import 'package:openmusic/provider/audio_player/audio_player_streams.dart';
import 'package:openmusic/provider/database/database.dart';
import 'package:openmusic/provider/glance/glance.dart';
import 'package:openmusic/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:openmusic/provider/metadata_plugin/updater/update_checker.dart';
import 'package:openmusic/provider/server/bonsoir.dart';
import 'package:openmusic/provider/server/server.dart';
import 'package:openmusic/provider/tray_manager/tray_manager.dart';
import 'package:openmusic/l10n/l10n.dart';
import 'package:openmusic/provider/connect/clients.dart';
import 'package:openmusic/provider/user_preferences/user_preferences_provider.dart';
import 'package:openmusic/services/audio_player/audio_player.dart';
import 'package:openmusic/services/cli/cli.dart';
import 'package:openmusic/services/kv_store/encrypted_kv_store.dart';
import 'package:openmusic/services/kv_store/kv_store.dart';
import 'package:openmusic/services/logger/logger.dart';
import 'package:openmusic/services/wm_tools/wm_tools.dart';
import 'package:openmusic/utils/migrations/encryption.dart';
import 'package:openmusic/utils/migrations/sandbox.dart';
import 'package:openmusic/utils/platform.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:window_manager/window_manager.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:yt_dlp_dart/yt_dlp_dart.dart';
import 'package:flutter_new_pipe_extractor/flutter_new_pipe_extractor.dart';

Future<void> main(List<String> rawArgs) async {
  if (rawArgs.contains("web_view_title_bar")) {
    WidgetsFlutterBinding.ensureInitialized();
    if (runWebViewTitleBarWidget(rawArgs)) {
      return;
    }
  }
  final arguments = await startCLI(rawArgs);
  AppLogger.initialize(arguments["verbose"]);

  AppLogger.runZoned(() async {
    final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

    // await registerWindowsScheme("spotify");

    tz.initializeTimeZones();

    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

    MediaKit.ensureInitialized();

    await migrateMacOsFromSandboxToNoSandbox();

    // force High Refresh Rate on some Android devices (like One Plus)
    if (kIsAndroid) {
      await FlutterDisplayMode.setHighRefreshRate();
    }
    if (kIsAndroid || kIsDesktop) {
      await NewPipeExtractor.init();
    }

    if (!kIsWeb) {
      MetadataGod.initialize();
    }

    await KVStoreService.initialize();

    if (kIsDesktop) {
      await windowManager.setPreventClose(true);
      await YtDlp.instance
          .setBinaryLocation(
            KVStoreService.getYoutubeEnginePath(YoutubeClientEngine.ytDlp) ??
                "yt-dlp${kIsWindows ? '.exe' : ''}",
          )
          .catchError((e, stack) => null);
      await FlutterDiscordRPC.initialize(Env.discordAppId);
    }

    if (kIsWindows) {
      await SMTCWindows.initialize();
    }

    await EncryptedKvStoreService.initialize();

    final database = AppDatabase();

    // Idempotent and self-describing, so it is safe to run on every launch and
    // a partial run simply resumes. Deliberately not a schema step: a failure
    // there would brick launch, and no column type changes.
    await migrateLegacyEncryptedValues(database);

    if (kIsDesktop) {
      await localNotifier.setup(appName: "OpenMusic");
      await WindowManagerTools.initialize();
    }

    if (kIsIOS) {
      HomeWidget.setAppGroupId("group.spotube_home_player_widget");
    }

    runApp(
      ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) => database)],
        observers: const [AppLoggerProviderObserver()],
        child: const OpenMusic(),
      ),
    );
  });
}

class OpenMusic extends HookConsumerWidget {
  const OpenMusic({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final themeMode = ref.watch(
      userPreferencesProvider.select((s) => s.themeMode),
    );
    final locale = ref.watch(userPreferencesProvider.select((s) => s.locale));
    final accentMaterialColor = ref.watch(
      userPreferencesProvider.select((s) => s.accentColorScheme),
    );
    final router = useMemoized(() => AppRouter(ref), []);
    final hasTouchSupport = useHasTouch();

    ref.listen(audioPlayerStreamListenersProvider, (_, __) {});
    ref.listen(bonsoirProvider, (_, __) {});
    ref.listen(connectClientsProvider, (_, __) {});
    ref.listen(serverProvider, (_, __) {});
    ref.listen(trayManagerProvider, (_, __) {});
    ref.listen(metadataPluginsProvider, (_, __) {});
    ref.listen(metadataPluginProvider, (_, __) {});
    ref.listen(audioSourcePluginProvider, (_, __) {});
    ref.listen(metadataPluginUpdateCheckerProvider, (_, __) {});
    ref.listen(audioSourcePluginUpdateCheckerProvider, (_, __) {});

    useFixWindowStretching();
    useDisableBatteryOptimizations();
    useDeepLinking(ref, router);
    useCloseBehavior(ref);
    useGetStoragePermissions(ref);

    useEffect(() {
      FlutterNativeSplash.remove();

      if (kIsMobile) {
        HomeWidget.registerInteractivityCallback(glanceBackgroundCallback);
      }

      return () {
        /// For enabling hot reload for audio player
        if (!kDebugMode) return;
        audioPlayer.dispose();
      };
    }, []);

    return ShadcnApp.router(
      supportedLocales: L10n.all,
      locale: locale.languageCode == "system" ? null : locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router.config(),
      debugShowCheckedModeBanner: false,
      title: 'OpenMusic',
      builder: (context, child) {
        child = ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: hasTouchSupport
                ? {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.invertedStylus,
                  }
                : null,
          ),
          child: child!,
        );

        if (kIsLinux) {
          child = DragToResizeArea(resizeEdgeSize: 2.5, child: child);
        }

        return child;
      },
      scaling: const AdaptiveScaling(1),
      theme: ThemeData(
        radius: .5,
        iconTheme: const IconThemeProperties(),
        colorScheme:
            colorSchemeMap[accentMaterialColor.name]?.call(ThemeMode.light) ??
                LegacyColorSchemes.lightSlate(),
        surfaceOpacity: 1,
        surfaceBlur: 0,
      ),
      darkTheme: ThemeData(
        radius: .5,
        iconTheme: const IconThemeProperties(),
        colorScheme:
            colorSchemeMap[accentMaterialColor.name]?.call(ThemeMode.dark) ??
                LegacyColorSchemes.darkSlate(),
        surfaceOpacity: 1,
        surfaceBlur: 0,
      ),
      materialTheme: material.ThemeData(
        brightness: switch (themeMode) {
          ThemeMode.system => MediaQuery.platformBrightnessOf(context),
          ThemeMode.light => Brightness.light,
          ThemeMode.dark => Brightness.dark,
        },
        splashFactory: material.NoSplash.splashFactory,
        appBarTheme: const material.AppBarTheme(
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          shadowColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      themeMode: themeMode,
      shortcuts: {
        ...WidgetsApp.defaultShortcuts.map((key, value) {
          return MapEntry(
            LogicalKeySet.fromSet(key.triggers?.toSet() ?? {}),
            value,
          );
        }),
        LogicalKeySet(LogicalKeyboardKey.space): PlayPauseIntent(ref),
        LogicalKeySet(LogicalKeyboardKey.comma, LogicalKeyboardKey.control):
            NavigationIntent(router, "/settings"),
        LogicalKeySet(
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): HomeTabIntent(
          router,
          tab: HomeTabs.browse,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): HomeTabIntent(
          router,
          tab: HomeTabs.search,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.digit3,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): HomeTabIntent(
          router,
          tab: HomeTabs.lyrics,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.digit4,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): HomeTabIntent(
          router,
          tab: HomeTabs.userPlaylists,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.digit5,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): HomeTabIntent(
          router,
          tab: HomeTabs.userArtists,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.digit6,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): HomeTabIntent(
          router,
          tab: HomeTabs.userAlbums,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.digit7,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): HomeTabIntent(
          router,
          tab: HomeTabs.userLocalLibrary,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.digit8,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): HomeTabIntent(
          router,
          tab: HomeTabs.userDownloads,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.keyW,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): CloseAppIntent(),
      },
      actions: {
        ...WidgetsApp.defaultActions,
        PlayPauseIntent: PlayPauseAction(),
        NavigationIntent: NavigationAction(),
        HomeTabIntent: HomeTabAction(),
        CloseAppIntent: CloseAppAction(),
      },
    );
  }
}
