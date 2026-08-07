import 'package:package_info_plus/package_info_plus.dart';

const _repository = "https://github.com/MaybeItsAdam/openmusic";

String? _cached;

/// Identifies the app to lyrics APIs. LRCLib in particular asks clients to
/// send a descriptive User-Agent.
///
/// Cached after the first call, and falls back to an unversioned string rather
/// than failing the request when platform info isn't available (unit tests, or
/// a platform channel that isn't ready yet).
Future<String> lyricsUserAgent() async {
  if (_cached != null) return _cached!;

  try {
    final info = await PackageInfo.fromPlatform();
    _cached = "OpenMusic v${info.version} ($_repository)";
  } catch (_) {
    _cached = "OpenMusic ($_repository)";
  }

  return _cached!;
}

/// Some endpoints reject anything that doesn't look like a browser.
const browserUserAgent =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
