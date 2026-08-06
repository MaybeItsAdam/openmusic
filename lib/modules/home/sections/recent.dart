import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:openmusic/collections/fake.dart';
import 'package:openmusic/components/horizontal_playbutton_card_view/horizontal_playbutton_card_view.dart';
import 'package:openmusic/extensions/context.dart';
import 'package:openmusic/models/database/database.dart';
import 'package:openmusic/provider/history/recent.dart';

class HomeRecentlyPlayedSection extends HookConsumerWidget {
  const HomeRecentlyPlayedSection({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final history = ref.watch(recentlyPlayedItems);
    final historyData =
        history.asData?.value ?? FakeData.historyRecentlyPlayedItems;

    if (history.asData?.value.isEmpty == true) {
      return const SizedBox();
    }

    return Skeletonizer(
      enabled: history.isLoading,
      child: HorizontalPlaybuttonCardView(
        title: Text(context.l10n.recently_played),
        items: [
          for (final item in historyData)
            if (item.playlist != null)
              item.playlist
            else if (item.album != null)
              item.album,
        ],
        hasNextPage: false,
        isLoadingNextPage: false,
        onFetchMore: () {},
      ),
    );
  }
}
