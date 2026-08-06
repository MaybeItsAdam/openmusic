import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openmusic/models/metadata/metadata.dart';
import 'package:openmusic/provider/metadata_plugin/core/auth.dart';
import 'package:openmusic/provider/metadata_plugin/utils/paginated.dart';

class MetadataPluginBrowseSectionsNotifier
    extends PaginatedAsyncNotifier<SpotubeBrowseSectionObject<Object>> {
  @override
  Future<SpotubePaginationResponseObject<SpotubeBrowseSectionObject<Object>>>
      fetch(int offset, int limit) async {
    return await (await metadataPlugin).browse.sections(
          limit: limit,
          offset: offset,
        );
  }

  @override
  build() async {
    ref.watch(metadataPluginAuthenticatedProvider);
    return await fetch(0, 20);
  }
}

final metadataPluginBrowseSectionsProvider = AsyncNotifierProvider<
        MetadataPluginBrowseSectionsNotifier,
        SpotubePaginationResponseObject<SpotubeBrowseSectionObject<Object>>>(
    () => MetadataPluginBrowseSectionsNotifier());
