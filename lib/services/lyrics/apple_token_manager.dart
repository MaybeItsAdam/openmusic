import 'package:dio/dio.dart';
import 'package:openmusic/services/dio/dio.dart';
import 'package:openmusic/services/lyrics/lyrics_user_agent.dart';

/// The bundled JS file Apple's web player loads, whose name carries a hash.
final _bundleRegex = RegExp(r"/assets/index~[A-Za-z0-9_-]+\.js");

/// A JWT, which is what the bundle embeds as its developer token.
final _jwtRegex =
    RegExp(r"eyJ[A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+");

/// Scrapes the developer token Apple Music's web player uses.
///
/// This is the most fragile part of the lyrics stack by a wide margin: it
/// depends on Apple's bundle filename pattern and on the token being a literal
/// in that bundle. Both change without warning. Every failure path returns null
/// so the Paxsenix provider simply reports a miss and the chain moves on — a
/// broken scrape must never surface as a broken lyrics feature.
class AppleTokenManager {
  static String? _token;

  /// In-flight request, so concurrent callers share one scrape rather than
  /// each hammering Apple with their own.
  static Future<String?>? _inFlight;

  const AppleTokenManager();

  Future<String?> token() {
    if (_token != null) return Future.value(_token);
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  /// Drops the cached token so the next call re-scrapes. Called on a 401.
  void invalidate() {
    _token = null;
  }

  Future<String?> _fetch() async {
    try {
      final page = await globalDio.getUri(
        Uri.parse("https://beta.music.apple.com"),
        options: Options(
          headers: {"User-Agent": browserUserAgent},
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (page.statusCode != 200 || page.data is! String) return null;

      final bundlePath = _bundleRegex.firstMatch(page.data as String)?.group(0);
      if (bundlePath == null) return null;

      final bundle = await globalDio.getUri(
        Uri.parse("https://beta.music.apple.com$bundlePath"),
        options: Options(
          headers: {"User-Agent": browserUserAgent},
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (bundle.statusCode != 200 || bundle.data is! String) return null;

      _token = _jwtRegex.firstMatch(bundle.data as String)?.group(0);
      return _token;
    } catch (_) {
      return null;
    }
  }
}
