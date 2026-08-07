import 'package:dio/dio.dart';
import 'package:openmusic/models/database/database.dart';
import 'package:openmusic/models/lyrics.dart';
import 'package:openmusic/services/dio/dio.dart';
import 'package:openmusic/services/lyrics/apple_token_manager.dart';
import 'package:openmusic/services/lyrics/lyrics_provider.dart';
import 'package:openmusic/services/lyrics/lyrics_text_utils.dart';
import 'package:openmusic/services/lyrics/lyrics_user_agent.dart';
import 'package:openmusic/services/lyrics/parsers/lrc_parser.dart';
import 'package:openmusic/services/lyrics/parsers/ttml_parser.dart';

const _appleCatalogBase = "https://amp-api.music.apple.com/v1/catalog/us";

/// Apple Music lyrics, via a third-party proxy.
///
/// Off by default. It reaches Apple's catalogue with a token scraped out of
/// the web player (see [AppleTokenManager]) and then fetches the lyrics from a
/// community proxy, so both halves can break independently and without notice.
/// When it works it gives the best word-level timings of any provider here.
class PaxsenixLyricsProvider extends LyricsProvider {
  final AppleTokenManager _tokens;

  PaxsenixLyricsProvider([this._tokens = const AppleTokenManager()]);

  @override
  LyricsProviderId get id => LyricsProviderId.paxsenix;

  @override
  Future<SubtitleSimple?> fetch(LyricsQuery query) async {
    final songId = await _findSong(query);
    if (songId == null) return null;

    final res = await globalDio.getUri(
      Uri.https("lyrics.paxsenix.org", "/apple-music/lyrics", {"id": songId}),
      options: Options(
        headers: {"User-Agent": await lyricsUserAgent()},
        responseType: ResponseType.json,
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    if (res.statusCode != 200 || res.data is! Map) return null;

    final data = (res.data as Map).cast<String, dynamic>();
    final lyrics = _parseResponse(data);
    if (lyrics == null) return null;

    return buildSubtitle(
      uri: Uri.https("lyrics.paxsenix.org", "/apple-music/lyrics"),
      name: query.title,
      provider: id,
      lyrics: lyrics,
    );
  }

  /// Reads the response in descending order of fidelity: TTML carries word
  /// timings, the eLRC variants carry line timings plus voice markers, and
  /// plain text is the floor.
  List<LyricSlice>? _parseResponse(Map<String, dynamic> data) {
    final ttml = data["ttmlContent"] as String?;
    if (ttml != null && ttml.isNotEmpty) {
      final parsed = parseTtml(ttml);
      if (parsed.isNotEmpty) return parsed;
    }

    for (final key in const ["elrcMultiPerson", "elrc"]) {
      final value = data[key] as String?;
      if (value == null || value.isEmpty) continue;
      final parsed = parseLrc(value);
      if (parsed.isNotEmpty) return parsed;
    }

    final plain = data["plain"] as String?;
    if (plain != null && plain.isNotEmpty) {
      final parsed = parsePlain(plain);
      if (parsed.isNotEmpty) return parsed;
    }

    return null;
  }

  Future<String?> _findSong(LyricsQuery query) async {
    var token = await _tokens.token();
    if (token == null) return null;

    var results = await _search(query, token);

    // A stale token is the common failure. Re-scrape once, then give up.
    if (results == null) {
      _tokens.invalidate();
      token = await _tokens.token();
      if (token == null) return null;
      results = await _search(query, token);
      if (results == null) return null;
    }

    if (results.isEmpty) return null;

    results.sort((a, b) => _score(b, query).compareTo(_score(a, query)));
    return results.first.id;
  }

  /// Returns null when the token was rejected, an empty list for a genuine
  /// miss — the caller retries only the former.
  Future<List<_AppleSong>?> _search(LyricsQuery query, String token) async {
    final term = "${query.primaryArtist} ${cleanTitle(query.title)}".trim();

    final res = await globalDio.getUri(
      Uri.parse("$_appleCatalogBase/search").replace(
        queryParameters: {
          "term": term,
          "types": "songs",
          "limit": "25",
          "l": "en-US",
          // Deliberately not `format[resources]=map`: that form returns bare
          // ids plus a separate resources map, whereas the default inlines the
          // song objects this parser reads.
          "platform": "web",
        },
      ),
      options: Options(
        headers: {
          "Authorization": "Bearer $token",
          "Origin": "https://music.apple.com",
          "Referer": "https://music.apple.com/",
          "x-apple-renewal": "true",
          "User-Agent": browserUserAgent,
        },
        responseType: ResponseType.json,
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    if (res.statusCode == 401 || res.statusCode == 403) return null;
    if (res.statusCode != 200 || res.data is! Map) return const [];

    final songs =
        ((res.data as Map)["results"] as Map<String, dynamic>?)?["songs"];
    final list = (songs as Map<String, dynamic>?)?["data"];
    if (list is! List) return const [];

    return list
        .whereType<Map<String, dynamic>>()
        .map(_AppleSong.fromJson)
        .where((s) => s.id.isNotEmpty)
        .toList();
  }

  double _score(_AppleSong song, LyricsQuery query) {
    var score = 0.0;

    if (query.duration > Duration.zero && song.duration > Duration.zero) {
      final diff = (song.duration - query.duration).abs();
      if (diff <= const Duration(seconds: 2)) {
        score += 100;
      } else if (diff <= const Duration(seconds: 5)) {
        score += 50;
      } else if (diff <= const Duration(seconds: 10)) {
        score += 10;
      } else {
        score -= 50;
      }
    }

    final wanted = cleanTitle(query.title).toLowerCase();
    final found = song.title.toLowerCase();

    if (wanted == found) {
      score += 80;
    } else if (found.contains(wanted) || wanted.contains(found)) {
      score += 40;
    }

    // A remix or a "mixed" edit is a different recording with different words.
    for (final marker in const ["mixed", "remix"]) {
      if (wanted.contains(marker) != found.contains(marker)) {
        score -= marker == "mixed" ? 60 : 40;
      }
    }

    final artist = query.primaryArtist.toLowerCase();
    if (artist.isNotEmpty) {
      final songArtist = song.artist.toLowerCase();
      if (songArtist.contains(artist) || artist.contains(songArtist)) {
        score += 50;
      } else if (stringSimilarity(artist, songArtist) > 0.6) {
        score += 25;
      }
    }

    return score;
  }
}

class _AppleSong {
  final String id;
  final String title;
  final String artist;
  final Duration duration;

  const _AppleSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
  });

  factory _AppleSong.fromJson(Map<String, dynamic> json) {
    final attributes =
        (json["attributes"] as Map<String, dynamic>?) ?? const {};

    return _AppleSong(
      id: json["id"]?.toString() ?? "",
      title: attributes["name"] as String? ?? "",
      artist: attributes["artistName"] as String? ?? "",
      duration: Duration(
        milliseconds: (attributes["durationInMillis"] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
