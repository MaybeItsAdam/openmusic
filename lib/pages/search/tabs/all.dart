import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:openmusic/components/fallbacks/error_box.dart';
import 'package:openmusic/components/inter_scrollbar/inter_scrollbar.dart';
import 'package:openmusic/modules/search/loading.dart';
import 'package:openmusic/pages/search/search.dart';
import 'package:openmusic/modules/search/sections/albums.dart';
import 'package:openmusic/modules/search/sections/artists.dart';
import 'package:openmusic/modules/search/sections/playlists.dart';
import 'package:openmusic/modules/search/sections/tracks.dart';
import 'package:openmusic/provider/metadata_plugin/search/all.dart';

class SearchPageAllTab extends HookConsumerWidget {
  const SearchPageAllTab({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final scrollController = ScrollController();
    final searchTerm = ref.watch(searchTermStateProvider);
    final searchSnapshot = ref.watch(
      metadataPluginSearchAllProvider(searchTerm),
    );

    if (searchSnapshot.hasError) {
      return ErrorBox(
        error: searchSnapshot.error!,
        onRetry: () {
          ref.invalidate(metadataPluginSearchAllProvider(searchTerm));
        },
      );
    }

    return SearchPlaceholder(
      snapshot: searchSnapshot,
      child: InterScrollbar(
        controller: scrollController,
        child: SingleChildScrollView(
          controller: scrollController,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SearchTracksSection(),
                  SearchPlaylistsSection(),
                  Gap(20),
                  SearchArtistsSection(),
                  Gap(20),
                  SearchAlbumsSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
