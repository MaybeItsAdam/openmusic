import 'package:audio_service/audio_service.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openmusic/collections/env.dart';
import 'package:openmusic/models/metadata/metadata.dart';
import 'package:openmusic/provider/audio_player/audio_player.dart';
import 'package:openmusic/services/audio_player/audio_player.dart';
import 'package:openmusic/services/audio_services/mobile_audio_service.dart';
import 'package:openmusic/services/audio_services/windows_audio_service.dart';
import 'package:openmusic/utils/platform.dart';

class AudioServices with WidgetsBindingObserver {
  final MobileAudioService? mobile;
  final WindowsAudioService? smtc;

  AudioServices(this.mobile, this.smtc) {
    WidgetsBinding.instance.addObserver(this);
  }

  static Future<AudioServices> create(
    Ref ref,
    AudioPlayerNotifier playback,
  ) async {
    final mobile = kIsMobile || kIsMacOS || kIsLinux
        ? await AudioService.init(
            builder: () => MobileAudioService(playback),
            config: AudioServiceConfig(
              androidNotificationChannelId: switch ((
                kIsLinux,
                Env.releaseChannel,
              )) {
                (true, _) => "openmusic",
                (_, ReleaseChannel.stable) => "io.github.maybeitsadam.openmusic",
                (_, ReleaseChannel.nightly) => "io.github.maybeitsadam.openmusic.nightly",
              },
              androidNotificationChannelName: 'OpenMusic',
              androidNotificationOngoing: false,
              androidStopForegroundOnPause: false,
              androidNotificationChannelDescription: "OpenMusic Media Controls",
            ),
          )
        : null;
    final smtc = kIsWindows ? WindowsAudioService(ref, playback) : null;

    return AudioServices(mobile, smtc);
  }

  Future<void> addTrack(SpotubeTrackObject track) async {
    await smtc?.addTrack(track);
    mobile?.addItem(
      MediaItem(
        id: track.id,
        album: track.album.name,
        title: track.name,
        artist: track.artists.asString(),
        duration: Duration(milliseconds: track.durationMs),
        artUri: (track.album.images).asUri(
          placeholder: ImagePlaceholder.albumArt,
        ),
        playable: true,
      ),
    );
  }

  void activateSession() {
    mobile?.session?.setActive(true);
  }

  void deactivateSession() {
    mobile?.session?.setActive(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.detached:
        deactivateSession();
        audioPlayer.pause();
        break;
      default:
        break;
    }
  }

  void dispose() {
    smtc?.dispose();
    WidgetsBinding.instance.removeObserver(this);
  }
}
