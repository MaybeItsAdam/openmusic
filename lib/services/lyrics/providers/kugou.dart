import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:openmusic/models/database/database.dart';
import 'package:openmusic/models/lyrics.dart';
import 'package:openmusic/services/dio/dio.dart';
import 'package:openmusic/services/lyrics/lyrics_provider.dart';
import 'package:openmusic/services/lyrics/parsers/lrc_parser.dart';

const _pageSize = 8;
const _durationTolerance = Duration(seconds: 8);

/// Bracket pairs used in CJK titles the way `(...)` is used in Latin ones.
final _cjkBracketRegex = RegExp(r"[（【「『《〈＜(][^）】」』》〉＞)]*[）】」』》〉＞)]");

/// Lines that are metadata (`[by:someone]`, `[作词：…]`) rather than lyrics.
final _metadataLineRegex = RegExp(r".+].+[:：].+");

/// Only lines carrying a timestamp survive normalisation.
final _timedLineRegex = RegExp(r"^\[\d{2}:\d{2}\.\d{2,3}\].*");

/// KuGou's public lyrics search. No authentication, and by far the best source
/// for Chinese, Japanese and Korean tracks, which LRCLib barely covers.
class KuGouLyricsProvider extends LyricsProvider {
  @override
  LyricsProviderId get id => LyricsProviderId.kugou;

  @override
  Future<SubtitleSimple?> fetch(LyricsQuery query) async {
    final candidates = await _findCandidates(query);

    for (final candidate in candidates) {
      final lrc = await _download(candidate);
      if (lrc == null) continue;

      final subtitle = buildSubtitle(
        uri: Uri.parse("https://lyrics.kugou.com/download?id=${candidate.id}"),
        name: query.title,
        provider: id,
        lyrics: parseLrc(lrc),
      );

      if (subtitle != null) return subtitle;
    }

    return null;
  }

  Future<List<_KuGouCandidate>> _findCandidates(LyricsQuery query) async {
    final title = _normalizeTitle(query.title);
    final artist = _normalizeArtist(query.primaryArtist);

    // Searching songs first yields a hash, which identifies the exact recording
    // and gives far better lyrics matches than a keyword search alone.
    final hashes = await _searchSongs(title, artist, query);

    for (final hash in hashes) {
      final byHash = await _searchLyrics({"hash": hash});
      if (byHash.isNotEmpty) return byHash;
    }

    return _searchLyrics({
      "keyword": artist.isEmpty ? title : "$artist - $title",
      if (query.durationSeconds > 0)
        "duration": (query.durationSeconds * 1000).toString(),
    });
  }

  Future<List<String>> _searchSongs(
    String title,
    String artist,
    LyricsQuery query,
  ) async {
    final keyword = artist.isEmpty
        ? title
        : "$title - $artist${query.album.isEmpty ? "" : " ${query.album}"}";

    final json = await _getJson(
      Uri.https("mobileservice.kugou.com", "/api/v3/search/song", {
        "version": "9108",
        "plat": "0",
        "pagesize": "$_pageSize",
        "showtype": "0",
        "keyword": keyword,
      }),
    );

    final info = (json?["data"] as Map<String, dynamic>?)?["info"];
    if (info is! List) return const [];

    final matches = <String>[];

    for (final entry in info.whereType<Map<String, dynamic>>()) {
      final hash = entry["hash"] as String?;
      if (hash == null) continue;

      // KuGou reports duration in seconds here.
      final seconds = (entry["duration"] as num?)?.toInt() ?? 0;
      if (query.durationSeconds > 0 && seconds > 0) {
        final diff = Duration(seconds: (seconds - query.durationSeconds).abs());
        if (diff > _durationTolerance) continue;
      }

      matches.add(hash);
    }

    return matches;
  }

  Future<List<_KuGouCandidate>> _searchLyrics(
      Map<String, String> params) async {
    final json = await _getJson(
      Uri.https("lyrics.kugou.com", "/search", {
        "ver": "1",
        "man": "yes",
        "client": "pc",
        ...params,
      }),
    );

    final candidates = json?["candidates"];
    if (candidates is! List) return const [];

    return candidates
        .whereType<Map<String, dynamic>>()
        .map(
          (e) => _KuGouCandidate(
            id: e["id"]?.toString() ?? "",
            accessKey: e["accesskey"]?.toString() ?? "",
          ),
        )
        .where((e) => e.id.isNotEmpty && e.accessKey.isNotEmpty)
        .toList();
  }

  Future<String?> _download(_KuGouCandidate candidate) async {
    final json = await _getJson(
      Uri.https("lyrics.kugou.com", "/download", {
        "fmt": "lrc",
        "charset": "utf8",
        "client": "pc",
        "ver": "1",
        "id": candidate.id,
        "accesskey": candidate.accessKey,
      }),
    );

    final content = json?["content"] as String?;
    if (content == null || content.isEmpty) return null;

    try {
      return _normalizeLrc(utf8.decode(base64.decode(content)));
    } catch (_) {
      return null;
    }
  }

  /// KuGou serves JSON under `text/html` and `text/plain`, so Dio's automatic
  /// JSON decoding never kicks in. Fetch as plain text and decode by hand.
  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    final res = await globalDio.getUri(
      uri,
      options: Options(
        responseType: ResponseType.plain,
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    if (res.statusCode != 200) return null;

    final body = res.data;
    if (body is Map<String, dynamic>) return body;
    if (body is! String || body.isEmpty) return null;

    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Strips the credit block KuGou wraps its lyrics in. Those lines carry
  /// timestamps, so the LRC parser would otherwise treat them as lyrics.
  String _normalizeLrc(String raw) {
    final lines = raw.split("\n").map((l) => l.trim()).toList();
    final timed = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!_timedLineRegex.hasMatch(line)) continue;

      // Credit lines only ever appear at the very start and very end.
      final nearEdge = i < 30 || i >= lines.length - 30;
      if (nearEdge && _metadataLineRegex.hasMatch(line)) continue;

      timed.add(line);
    }

    return timed.join("\n");
  }

  String _normalizeTitle(String title) {
    return title
        .replaceAll(_cjkBracketRegex, " ")
        .replaceAll(RegExp(r"\s+"), " ")
        .trim();
  }

  /// KuGou indexes collaborations with an ideographic comma.
  String _normalizeArtist(String artist) {
    return artist
        .replaceAll(RegExp(r"\s*(,|&|、|and)\s*", caseSensitive: false), "、")
        .replaceAll(RegExp(r"\s+"), " ")
        .trim();
  }
}

class _KuGouCandidate {
  final String id;
  final String accessKey;

  const _KuGouCandidate({required this.id, required this.accessKey});
}
