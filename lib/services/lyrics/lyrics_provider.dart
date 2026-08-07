import 'package:openmusic/models/database/database.dart';
import 'package:openmusic/models/lyrics.dart';

/// Everything a provider might need to identify a track.
class LyricsQuery {
  final String trackId;
  final String title;
  final List<String> artists;
  final String album;
  final Duration duration;

  /// The audio source's own id for this track — a YouTube video id when the
  /// active audio-source plugin is YouTube-backed, otherwise null. Only the
  /// YouTube providers need it, and they report themselves unavailable without
  /// one rather than guessing.
  final String? sourceId;

  const LyricsQuery({
    required this.trackId,
    required this.title,
    required this.artists,
    required this.album,
    required this.duration,
    this.sourceId,
  });

  String get primaryArtist => artists.isEmpty ? "" : artists.first;

  /// Duration in whole seconds, or -1 when unknown — the sentinel the upstream
  /// providers use to mean "don't filter on duration".
  int get durationSeconds => duration > Duration.zero ? duration.inSeconds : -1;
}

/// A single lyrics source.
///
/// Implementations must not throw for an ordinary miss — return null instead,
/// so the chain moves on quietly. Throwing is reserved for genuine faults, and
/// the orchestrator logs those without aborting the chain either.
abstract class LyricsProvider {
  LyricsProviderId get id;

  String get name => id.label;

  /// Whether this provider can be attempted for [query] at all. Used to skip
  /// providers that need data the current track doesn't have.
  bool isAvailable(LyricsQuery query) => true;

  /// Whether [LyricsQuery.sourceId] must be populated before this provider can
  /// run. Resolving it means waiting on audio-source matching, so the chain
  /// only does that work once a provider actually asks for it.
  bool get requiresSourceId => false;

  Future<SubtitleSimple?> fetch(LyricsQuery query);
}

/// Ranks results so the best available form wins when several providers
/// answer. Word timings beat line timings, which beat plain text.
abstract final class LyricsRating {
  static const wordSynced = 150;
  static const lineSynced = 100;
  static const plain = 0;

  static int of(List<LyricSlice> lyrics) {
    if (lyrics.any((l) => l.words != null && l.words!.isNotEmpty)) {
      return wordSynced;
    }
    if (lyrics.any((l) => l.time > Duration.zero)) return lineSynced;
    return plain;
  }
}

/// Builds a result, or null when [lyrics] came back empty — which every caller
/// treats as a miss.
SubtitleSimple? buildSubtitle({
  required Uri uri,
  required String name,
  required LyricsProviderId provider,
  required List<LyricSlice> lyrics,
}) {
  final usable = lyrics.where((l) => l.text.trim().isNotEmpty).toList();
  if (usable.isEmpty) return null;

  return SubtitleSimple(
    uri: uri,
    name: name,
    // Keep blank timed lines: they render as instrumental gaps. They just
    // don't count towards "did we actually get anything".
    lyrics: lyrics,
    rating: LyricsRating.of(lyrics),
    provider: provider.label,
  );
}
