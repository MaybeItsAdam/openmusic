import 'package:openmusic/models/metadata/metadata.dart';
import 'package:openmusic/services/youtube_music/youtube_music.dart';

final _bracketedPattern = RegExp(r"[\(\[\{][^\)\]\}]*[\)\]\}]");
final _featuringPattern = RegExp(
  r"\b(feat|ft|featuring|with)\.?\s.*$",
  caseSensitive: false,
);
final _noisePattern = RegExp(
  r"\b(official|officiel|music|lyrics?|video|audio|visuali[sz]er|remaster(ed)?|"
  r"explicit|clean|hd|hq|4k|mv|version|edit)\b",
  caseSensitive: false,
);
final _topicSuffixPattern = RegExp(r"\s*-\s*topic\s*$", caseSensitive: false);
final _punctuationPattern = RegExp(r"[^\p{L}\p{N}]+", unicode: true);

/// Strips the decoration YouTube titles carry ("(Official Video)", "feat. …",
/// "[4K Remaster]") so a YouTube song can be compared with a metadata plugin's
/// far cleaner title. Falls back to a plain casefold when stripping would empty
/// the string, which happens for titles written in scripts the noise words
/// don't apply to.
String normalizeSongTitle(String input) {
  final stripped = input
      .replaceAll(_bracketedPattern, " ")
      .replaceAll(_featuringPattern, " ")
      .replaceAll(_noisePattern, " ")
      .toLowerCase()
      .replaceAll(_punctuationPattern, " ")
      .trim();

  if (stripped.isNotEmpty) return stripped;

  return input.toLowerCase().replaceAll(_punctuationPattern, " ").trim();
}

/// Same idea for artists, plus the "- Topic" suffix YouTube appends to the
/// auto-generated channels most music tracks are uploaded under.
String normalizeArtistName(String input) {
  final stripped = input
      .replaceAll(_topicSuffixPattern, " ")
      .replaceAll(_bracketedPattern, " ")
      .toLowerCase()
      .replaceAll(_punctuationPattern, " ")
      .trim();

  if (stripped.isNotEmpty) return stripped;

  return input.toLowerCase().replaceAll(_punctuationPattern, " ").trim();
}

/// Identity of a song across the two catalogues, used to drop duplicates and
/// anything already in the listening history.
String songIdentityKey(String title, String? artist) {
  final normalizedArtist = normalizeArtistName(artist ?? "");
  return "${normalizeSongTitle(title)}::$normalizedArtist";
}

/// Titles a YouTube entry might really be. Uploads are inconsistent about
/// whether the artist is part of the title, so "Rick Astley - Together
/// Forever" has to be able to match a plugin's "Together Forever".
List<String> _titleCandidates(String title) {
  final candidates = [normalizeSongTitle(title)];

  final separator = title.indexOf(" - ");
  if (separator > 0 && separator < title.length - 3) {
    candidates.add(normalizeSongTitle(title.substring(separator + 3)));
  }

  return candidates.where((candidate) => candidate.isNotEmpty).toList();
}

bool _looseEquals(String a, String b) {
  if (a == b) return true;

  // Containment only counts once both sides are long enough that a shared
  // substring means something — otherwise "go" matches half a catalogue.
  if (a.length < 5 || b.length < 5) return false;

  return a.contains(b) || b.contains(a);
}

/// Whether a plugin search result is plausibly the YouTube Music song.
///
/// Deliberately strict on the artist: a wrong-but-similarly-titled track is
/// worse than a missing recommendation, since the whole point is that the
/// suggestion came from somewhere with good taste.
bool isLikelySameSong(YoutubeMusicSong song, SpotubeTrackObject track) {
  final trackTitle = normalizeSongTitle(track.name);
  if (trackTitle.isEmpty) return false;

  final titleMatches = _titleCandidates(
    song.title,
  ).any((candidate) => _looseEquals(candidate, trackTitle));

  if (!titleMatches) return false;

  final songArtist = normalizeArtistName(song.artist ?? "");
  if (songArtist.isEmpty) return true;

  return track.artists.any((artist) {
    final candidate = normalizeArtistName(artist.name);
    return candidate.isNotEmpty && _looseEquals(candidate, songArtist);
  });
}

/// Whether a plugin artist search result is the YouTube Music artist.
bool isLikelySameArtist(String name, SpotubeFullArtistObject artist) {
  final a = normalizeArtistName(name);
  final b = normalizeArtistName(artist.name);

  return a.isNotEmpty && b.isNotEmpty && a == b;
}
