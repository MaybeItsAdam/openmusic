import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:openmusic/models/metadata/metadata.dart';
import 'package:openmusic/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:openmusic/services/metadata/errors/exceptions.dart';

final metadataPluginSearchAllProvider = FutureProvider.autoDispose
    .family<SpotubeSearchResponseObject, String>((ref, query) async {
  final metadataPlugin = await ref.watch(metadataPluginProvider.future);

  if (metadataPlugin == null) {
    throw MetadataPluginException.noDefaultMetadataPlugin();
  }

  return metadataPlugin.search.all(query);
});

final metadataPluginSearchChipsProvider = FutureProvider((ref) async {
  final metadataPlugin = await ref.watch(metadataPluginProvider.future);

  if (metadataPlugin == null) {
    throw MetadataPluginException.noDefaultMetadataPlugin();
  }
  return metadataPlugin.search.chips;
});
