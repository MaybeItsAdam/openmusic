import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:openmusic/models/metadata/metadata.dart';
import 'package:openmusic/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:openmusic/services/metadata/errors/exceptions.dart';

final metadataPluginTrackProvider =
    FutureProvider.family<SpotubeFullTrackObject, String>((ref, trackId) async {
  final metadataPlugin = await ref.watch(metadataPluginProvider.future);

  if (metadataPlugin == null) {
    throw MetadataPluginException.noDefaultMetadataPlugin();
  }

  return metadataPlugin.track.getTrack(trackId);
});
