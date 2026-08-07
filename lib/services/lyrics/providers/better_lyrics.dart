import 'package:dio/dio.dart';
import 'package:openmusic/models/database/database.dart';
import 'package:openmusic/models/lyrics.dart';
import 'package:openmusic/services/dio/dio.dart';
import 'package:openmusic/services/lyrics/lyrics_provider.dart';
import 'package:openmusic/services/lyrics/lyrics_user_agent.dart';
import 'package:openmusic/services/lyrics/parsers/ttml_parser.dart';

/// Returns TTML, so this is one of the few sources that can drive word-level
/// karaoke rendering.
class BetterLyricsProvider extends LyricsProvider {
  @override
  LyricsProviderId get id => LyricsProviderId.betterLyrics;

  @override
  Future<SubtitleSimple?> fetch(LyricsQuery query) async {
    final res = await globalDio.getUri(
      Uri.https("lyrics-api.boidu.dev", "/getLyrics", {
        // Deliberately the raw title, not the cleaned one: stripping
        // "(Remastered)" here matches the wrong recording rather than none.
        "s": query.title,
        "a": query.primaryArtist,
        if (query.duration > Duration.zero)
          "d": query.duration.inMilliseconds.toString(),
        if (query.album.isNotEmpty) "al": query.album,
      }),
      options: Options(
        headers: {
          "User-Agent": browserUserAgent,
          "Accept": "application/json",
        },
        responseType: ResponseType.json,
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    if (res.statusCode != 200) return null;

    final data = res.data;
    if (data is! Map) return null;

    final ttml = data["ttml"] as String?;
    if (ttml == null || ttml.isEmpty) return null;

    return buildSubtitle(
      uri: Uri.https("lyrics-api.boidu.dev", "/getLyrics"),
      name: query.title,
      provider: id,
      lyrics: parseTtml(ttml),
    );
  }
}
