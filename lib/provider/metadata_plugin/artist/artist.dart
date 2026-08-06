import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openmusic/models/metadata/metadata.dart';
import 'package:openmusic/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:openmusic/provider/metadata_plugin/utils/common.dart';
import 'package:openmusic/services/metadata/errors/exceptions.dart';

final metadataPluginArtistProvider = FutureProvider.autoDispose
    .family<SpotubeFullArtistObject, String>((ref, artistId) async {
  ref.cacheFor();

  final metadataPlugin = await ref.watch(metadataPluginProvider.future);

  if (metadataPlugin == null) {
    throw MetadataPluginException.noDefaultMetadataPlugin();
  }

  return metadataPlugin.artist.getArtist(artistId);
});
