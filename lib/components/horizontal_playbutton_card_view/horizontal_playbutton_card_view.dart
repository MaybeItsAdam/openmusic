import 'dart:ui';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:openmusic/collections/fake.dart';
import 'package:openmusic/models/metadata/metadata.dart';
import 'package:openmusic/modules/album/album_card.dart';
import 'package:openmusic/modules/artist/artist_card.dart';
import 'package:openmusic/modules/playlist/playlist_card.dart';
import 'package:openmusic/modules/track/track_card.dart';
import 'package:very_good_infinite_list/very_good_infinite_list.dart';

class HorizontalPlaybuttonCardView<T> extends HookWidget {
  final Widget title;
  final List<T> items;
  final Widget? error;
  final VoidCallback onFetchMore;
  final bool isLoadingNextPage;
  final bool hasNextPage;
  final Widget? titleTrailing;

  HorizontalPlaybuttonCardView({
    required this.title,
    required this.items,
    required this.hasNextPage,
    required this.onFetchMore,
    required this.isLoadingNextPage,
    this.titleTrailing,
    this.error,
    super.key,
  }) : assert(
          items.every(
            (item) =>
                item is SpotubeSimpleAlbumObject ||
                item is SpotubeSimplePlaylistObject ||
                item is SpotubeFullArtistObject ||
                item is SpotubeFullTrackObject,
          ),
        );

  @override
  Widget build(BuildContext context) {
    final scrollController = useScrollController();
    final isArtist = items.every((s) => s is SpotubeFullArtistObject);
    final scale = context.theme.scaling;
    final trackQueue = useMemoized(
      () => items.whereType<SpotubeFullTrackObject>().toList(),
      [items],
    );

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: DefaultTextStyle(
                  style: context.theme.typography.h4.copyWith(
                    color: context.theme.colorScheme.foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: title,
                ),
              ),
              if (titleTrailing != null) titleTrailing!,
            ],
          ),
          if (error != null)
            error!
          else
            SizedBox(
              height: isArtist ? 250 : 225,
              child: NotificationListener(
                // disable multiple scrollbar to use this
                onNotification: (notification) => true,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                  child: items.isEmpty
                      ? ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: 5,
                          itemBuilder: (context, index) {
                            return AlbumCard(FakeData.albumSimple);
                          },
                        )
                      : InfiniteList(
                          scrollController: scrollController,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          itemCount: items.length,
                          onFetchData: onFetchMore,
                          loadingBuilder: (context) => Skeletonizer(
                            enabled: true,
                            child: isArtist
                                ? ArtistCard(FakeData.artist)
                                : AlbumCard(FakeData.albumSimple),
                          ),
                          isLoading: isLoadingNextPage,
                          hasReachedMax: !hasNextPage,
                          separatorBuilder: (context, index) => Gap(12 * scale),
                          itemBuilder: (context, index) {
                            final item = items[index];

                            return switch (item) {
                              SpotubeSimplePlaylistObject() => PlaylistCard(
                                  item as SpotubeSimplePlaylistObject,
                                ),
                              SpotubeSimpleAlbumObject() => AlbumCard(
                                  item as SpotubeSimpleAlbumObject,
                                ),
                              SpotubeFullArtistObject() => ArtistCard(
                                  item as SpotubeFullArtistObject,
                                ),
                              // Tracks play on into the rest of the row, so a
                              // recommendation row behaves like a playlist.
                              SpotubeFullTrackObject() => TrackCard(
                                  item as SpotubeFullTrackObject,
                                  queue: trackQueue,
                                ),
                              _ => const SizedBox.shrink(),
                            };
                          },
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
