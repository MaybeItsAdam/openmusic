import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:openmusic/collections/routes.gr.dart';
import 'package:openmusic/components/dialogs/select_device_dialog.dart';
import 'package:openmusic/components/playbutton_view/playbutton_card.dart';
import 'package:openmusic/components/playbutton_view/playbutton_tile.dart';
import 'package:openmusic/extensions/context.dart';
import 'package:openmusic/models/connect/connect.dart';
import 'package:openmusic/models/metadata/metadata.dart';
import 'package:openmusic/provider/audio_player/audio_player.dart';
import 'package:openmusic/provider/audio_player/querying_track_info.dart';
import 'package:openmusic/provider/connect/connect.dart';
import 'package:openmusic/services/audio_player/audio_player.dart';

/// A card for a single track, shaped like [AlbumCard] so track sections can sit
/// next to album and playlist sections without looking foreign.
///
/// [queue] is what plays when the card is started — a track shown inside a
/// recommendation row should continue into the rest of that row rather than
/// stopping after one song. It defaults to the track on its own.
class TrackCard extends HookConsumerWidget {
  final SpotubeFullTrackObject track;
  final List<SpotubeFullTrackObject>? queue;
  final bool _isTile;

  const TrackCard(this.track, {this.queue, super.key}) : _isTile = false;

  const TrackCard.tile(this.track, {this.queue, super.key}) : _isTile = true;

  @override
  Widget build(BuildContext context, ref) {
    final playlist = ref.watch(audioPlayerProvider);
    final playing =
        useStream(audioPlayer.playingStream).data ?? audioPlayer.isPlaying;
    final playlistNotifier = ref.watch(audioPlayerProvider.notifier);
    final isFetchingActiveTrack = ref.watch(queryingTrackInfoProvider);

    final isTrackPlaying = playlist.activeTrack?.id == track.id;
    final updating = useState(false);

    final imageUrl = useMemoized(
      () => track.album.images.from200PxTo300PxOrSmallestImage(),
      [track.album.images],
    );

    final onTap = useCallback(() {
      context.navigateTo(TrackRoute(trackId: track.id));
    }, [context, track.id]);

    final onPlaybuttonPressed = useCallback(
      () async {
        updating.value = true;
        try {
          if (isTrackPlaying) {
            return playing ? audioPlayer.pause() : audioPlayer.resume();
          }

          final tracks = queue ?? [track];
          final initialIndex = tracks.indexWhere((t) => t.id == track.id);

          final isRemoteDevice = await showSelectDeviceDialog(context, ref);
          if (isRemoteDevice == null) return;

          if (isRemoteDevice) {
            final remotePlayback = ref.read(connectProvider.notifier);
            await remotePlayback.load(
              WebSocketLoadEventData.playlist(
                tracks: tracks,
                initialIndex: initialIndex < 0 ? 0 : initialIndex,
              ),
            );
          } else if (playlist.tracks.any((t) => t.id == track.id)) {
            await playlistNotifier.jumpToTrack(track);
          } else {
            await playlistNotifier.load(
              tracks,
              initialIndex: initialIndex < 0 ? 0 : initialIndex,
              autoPlay: true,
            );
          }
        } finally {
          updating.value = false;
        }
      },
      [
        isTrackPlaying,
        playing,
        queue,
        track,
        context,
        ref,
        playlist.tracks,
        playlistNotifier,
        updating,
      ],
    );

    final onAddToQueuePressed = useCallback(() async {
      if (playlist.tracks.any((t) => t.id == track.id)) return;

      await playlistNotifier.addTrack(track);

      if (!context.mounted) return;

      showToast(
        context: context,
        builder: (context, overlay) {
          return SurfaceCard(
            child: Basic(
              content: Text(context.l10n.added_to_queue(1)),
              trailing: Button.outline(
                child: Text(context.l10n.undo),
                onPressed: () {
                  playlistNotifier.removeTrack(track.id);
                },
              ),
            ),
          );
        },
      );
    }, [playlist.tracks, playlistNotifier, track, context]);

    final isLoading = (isTrackPlaying && isFetchingActiveTrack) ||
        updating.value;
    final description = track.artists.map((artist) => artist.name).join(", ");

    if (_isTile) {
      return PlaybuttonTile(
        imageUrl: imageUrl,
        isPlaying: isTrackPlaying,
        isLoading: isLoading,
        title: track.name,
        description: description,
        onTap: onTap,
        onPlaybuttonPressed: onPlaybuttonPressed,
        onAddToQueuePressed: onAddToQueuePressed,
      );
    }

    return PlaybuttonCard(
      imageUrl: imageUrl,
      isPlaying: isTrackPlaying,
      isLoading: isLoading,
      title: track.name,
      description: description,
      onTap: onTap,
      onPlaybuttonPressed: onPlaybuttonPressed,
      onAddToQueuePressed: onAddToQueuePressed,
    );
  }
}
