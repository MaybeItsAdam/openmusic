import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:openmusic/collections/routes.gr.dart';
import 'package:openmusic/collections/openmusic_icons.dart';
import 'package:openmusic/models/database/database.dart';
import 'package:openmusic/modules/connect/connect_device.dart';
import 'package:openmusic/modules/home/sections/sections.dart';
import 'package:openmusic/modules/home/sections/new_releases.dart';
import 'package:openmusic/modules/home/sections/recommendations.dart';
import 'package:openmusic/modules/home/sections/recent.dart';
import 'package:openmusic/components/titlebar/titlebar.dart';
import 'package:openmusic/extensions/constrains.dart';
import 'package:openmusic/provider/user_preferences/user_preferences_provider.dart';
import 'package:openmusic/utils/platform.dart';

@RoutePage()
class HomePage extends HookConsumerWidget {
  static const name = "home";
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final theme = Theme.of(context);
    final controller = useScrollController();
    final mediaQuery = MediaQuery.of(context);
    final layoutMode = ref.watch(
      userPreferencesProvider.select((s) => s.layoutMode),
    );

    return SafeArea(
      bottom: false,
      child: Scaffold(
        headers: [if (kTitlebarVisible) const TitleBar(height: 30)],
        child: CustomScrollView(
          controller: controller,
          slivers: [
            if (mediaQuery.smAndDown || layoutMode == LayoutMode.compact)
              SliverAppBar(
                floating: true,
                title: DefaultTextStyle(
                  style: TextStyle(
                    fontFamily: "Cookie",
                    fontSize: 30,
                    letterSpacing: 1.8,
                    color: theme.colorScheme.foreground,
                  ),
                  child: const Text("OpenMusic"),
                ),
                backgroundColor: theme.colorScheme.background,
                foregroundColor: theme.colorScheme.foreground,
                actions: [
                  const ConnectDeviceButton(),
                  const Gap(10),
                  IconButton.ghost(
                    icon: const Icon(OpenMusicIcons.settings, size: 20),
                    onPressed: () {
                      context.navigateTo(const SettingsRoute());
                    },
                  ),
                  const Gap(10),
                ],
              )
            else if (kIsMacOS)
              const SliverGap(10),
            const SliverGap(10),
            SliverList.list(
              children: const [
                HomeRecentlyPlayedSection(),
                // YouTube Music's suggestions, resolved to the active metadata
                // plugin. Sits above the plugin's own sections because it is
                // the only part of the page built from what you actually play.
                HomeMadeForYouSection(),
                HomeNewReleasesSection(),
                HomeSimilarArtistsSection(),
              ],
            ),
            const SliverSafeArea(sliver: HomePageBrowseSection()),
          ],
        ),
      ),
    );
  }
}
