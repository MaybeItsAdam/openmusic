import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:openmusic/collections/fake.dart';
import 'package:openmusic/collections/openmusic_icons.dart';
import 'package:openmusic/components/horizontal_playbutton_card_view/horizontal_playbutton_card_view.dart';
import 'package:openmusic/extensions/context.dart';
import 'package:openmusic/models/metadata/metadata.dart';
import 'package:openmusic/provider/blacklist_provider.dart';
import 'package:openmusic/provider/youtube_music/recommendations.dart';

/// Songs YouTube Music suggests based on what has been played locally.
///
/// The section removes itself entirely when there is nothing to show — no
/// history yet, no metadata plugin, or a failed fetch — because it is an extra
/// on top of the plugin's own browse sections, not a replacement for them.
class HomeMadeForYouSection extends HookConsumerWidget {
  const HomeMadeForYouSection({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final recommendations = ref.watch(youtubeMusicRecommendationsProvider);
    final seedTrackName = recommendations.asData?.value.seedTrackName;

    // Suggesting something the user blacklisted would be worse than suggesting
    // nothing, and the blacklist can change after the cache was written.
    ref.watch(blacklistProvider);
    final blacklist = ref.watch(blacklistProvider.notifier);
    final tracks = blacklist
        .filter(recommendations.asData?.value.tracks ?? const [])
        .whereType<SpotubeFullTrackObject>()
        .toList();

    if (recommendations.hasError) return const SizedBox.shrink();

    if (recommendations.isLoading && tracks.isEmpty) {
      return Skeletonizer(
        enabled: true,
        child: HorizontalPlaybuttonCardView<SpotubeFullTrackObject>(
          items: List.filled(6, FakeData.track),
          title: Text(context.l10n.made_for_you),
          hasNextPage: false,
          isLoadingNextPage: false,
          onFetchMore: () {},
        ),
      );
    }

    if (tracks.isEmpty) return const SizedBox.shrink();

    return HorizontalPlaybuttonCardView<SpotubeFullTrackObject>(
      items: tracks,
      title: Text(context.l10n.made_for_you),
      titleTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (seedTrackName != null)
            Flexible(
              child: Text(
                context.l10n.because_you_listened_to(seedTrackName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ).small.muted,
            ),
          IconButton.ghost(
            icon: const Icon(OpenMusicIcons.refresh, size: 16),
            size: ButtonSize.small,
            enabled: !recommendations.isLoading,
            onPressed: () {
              ref.read(youtubeMusicRecommendationsProvider.notifier).refresh();
            },
          ),
        ],
      ),
      hasNextPage: false,
      isLoadingNextPage: false,
      onFetchMore: () {},
    );
  }
}

/// Artists YouTube Music links to the ones already in rotation, resolved
/// against the metadata plugin so their pages open like any other artist.
class HomeSimilarArtistsSection extends HookConsumerWidget {
  const HomeSimilarArtistsSection({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final recommendations = ref.watch(youtubeMusicRecommendationsProvider);

    ref.watch(blacklistProvider);
    final blacklist = ref.watch(blacklistProvider.notifier);
    final artists = (recommendations.asData?.value.artists ?? const [])
        .whereNot((artist) => blacklist.containsArtist(artist.id))
        .toList();

    if (recommendations.hasError || artists.isEmpty) {
      return const SizedBox.shrink();
    }

    return HorizontalPlaybuttonCardView<SpotubeFullArtistObject>(
      items: artists,
      title: Text(context.l10n.artists_you_might_like),
      hasNextPage: false,
      isLoadingNextPage: false,
      onFetchMore: () {},
    );
  }
}
