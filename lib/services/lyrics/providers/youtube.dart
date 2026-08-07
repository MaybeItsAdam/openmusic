import 'package:openmusic/models/database/database.dart';
import 'package:openmusic/models/lyrics.dart';
import 'package:openmusic/services/lyrics/innertube_lyrics_client.dart';
import 'package:openmusic/services/lyrics/lyrics_provider.dart';

/// YouTube video ids are always 11 characters. The audio-source plugin's id is
/// opaque, so this is the only signal available that the active source really
/// is YouTube-backed and the id can be handed to innertube.
final _videoIdRegex = RegExp(r"^[A-Za-z0-9_-]{11}$");

bool _hasVideoId(LyricsQuery query) {
  final id = query.sourceId;
  return id != null && _videoIdRegex.hasMatch(id);
}

/// Timed captions from the track's YouTube video.
///
/// Not really lyrics — they're whatever captions the uploader supplied — but
/// they are synced, and for tracks no lyrics database covers they're often the
/// only synced source available.
class YouTubeSubtitleLyricsProvider extends LyricsProvider {
  final InnertubeLyricsClient _client;

  YouTubeSubtitleLyricsProvider([
    this._client = const InnertubeLyricsClient(),
  ]);

  @override
  LyricsProviderId get id => LyricsProviderId.youtubeSubtitle;

  @override
  bool get requiresSourceId => true;

  @override
  bool isAvailable(LyricsQuery query) => _hasVideoId(query);

  @override
  Future<SubtitleSimple?> fetch(LyricsQuery query) async {
    final slices = await _client.transcript(query.sourceId!);
    if (slices == null) return null;

    return buildSubtitle(
      uri: Uri.parse("https://music.youtube.com/watch?v=${query.sourceId}"),
      name: query.title,
      provider: id,
      lyrics: slices,
    );
  }
}

/// YouTube Music's own lyrics panel. Plain text, so it sits last in the chain —
/// but it covers a lot of tracks, and plain lyrics beat none.
class YouTubeMusicLyricsProvider extends LyricsProvider {
  final InnertubeLyricsClient _client;

  YouTubeMusicLyricsProvider([this._client = const InnertubeLyricsClient()]);

  @override
  LyricsProviderId get id => LyricsProviderId.youtubeMusic;

  @override
  bool get requiresSourceId => true;

  @override
  bool isAvailable(LyricsQuery query) => _hasVideoId(query);

  @override
  Future<SubtitleSimple?> fetch(LyricsQuery query) async {
    final slices = await _client.lyrics(query.sourceId!);
    if (slices == null) return null;

    return buildSubtitle(
      uri: Uri.parse("https://music.youtube.com/watch?v=${query.sourceId}"),
      name: query.title,
      provider: id,
      lyrics: slices,
    );
  }
}
