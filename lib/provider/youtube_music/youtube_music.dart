import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:openmusic/services/youtube_music/youtube_music.dart';

final youtubeMusicServiceProvider = Provider<YoutubeMusicService>((ref) {
  return YoutubeMusicService();
});
