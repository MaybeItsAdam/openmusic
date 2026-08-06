import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_undraw/flutter_undraw.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:openmusic/collections/fake.dart';
import 'package:openmusic/components/fallbacks/error_box.dart';
import 'package:openmusic/components/waypoint.dart';
import 'package:openmusic/extensions/constrains.dart';
import 'package:openmusic/extensions/context.dart';
import 'package:openmusic/modules/artist/artist_card.dart';
import 'package:openmusic/modules/search/loading.dart';
import 'package:openmusic/pages/search/search.dart';
import 'package:openmusic/provider/metadata_plugin/search/artists.dart';

class SearchPageArtistsTab extends HookConsumerWidget {
  const SearchPageArtistsTab({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final controller = useScrollController();

    final searchTerm = ref.watch(searchTermStateProvider);
    final searchArtistsSnapshot = ref.watch(
      metadataPluginSearchArtistsProvider(searchTerm),
    );
    final searchArtistsNotifier = ref.read(
      metadataPluginSearchArtistsProvider(searchTerm).notifier,
    );
    final searchArtists = searchArtistsSnapshot.asData?.value.items ?? [];

    if (searchArtistsSnapshot.hasError) {
      return ErrorBox(
        error: searchArtistsSnapshot.error!,
        onRetry: () {
          ref.invalidate(metadataPluginSearchArtistsProvider(searchTerm));
        },
      );
    }

    return SearchPlaceholder(
      snapshot: searchArtistsSnapshot,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: LayoutBuilder(
          builder: (context, constrains) {
            if (searchArtistsSnapshot.hasValue && searchArtists.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 10,
                  children: [
                    Undraw(
                      height: 200 * context.theme.scaling,
                      illustration: UndrawIllustration.taken,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    Text(
                      context.l10n.nothing_found,
                      textAlign: TextAlign.center,
                    ).muted().small(),
                  ],
                ),
              );
            }

            return GridView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: searchArtists.length + 1,
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisExtent: constrains.smAndDown ? 225 : 250,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemBuilder: (context, index) {
                if (searchArtists.isNotEmpty && index == searchArtists.length) {
                  if (searchArtistsSnapshot.asData?.value.hasMore != true) {
                    return const SizedBox.shrink();
                  }

                  return Waypoint(
                    controller: controller,
                    isGrid: true,
                    onTouchEdge: searchArtistsNotifier.fetchMore,
                    child: Skeletonizer(
                      enabled: true,
                      child: ArtistCard(FakeData.artist),
                    ),
                  );
                }

                return Skeletonizer(
                  enabled: searchArtistsSnapshot.isLoading,
                  child: ArtistCard(
                    searchArtists.elementAtOrNull(index) ?? FakeData.artist,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
