import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/models/metadata/metadata.dart';
import 'package:openmusic/provider/youtube_music/recommendations.dart';
import 'package:openmusic/services/youtube_music/song_matching.dart';
import 'package:openmusic/services/youtube_music/youtube_music.dart';

/// Shapes copied from live `music.youtube.com/youtubei/v1` responses, trimmed
/// to the fields the parsers read. They are the contract this code depends on,
/// so a change in what we accept shows up here first.
Map<String, dynamic> _radioEntry({
  required String videoId,
  required String title,
  required String artist,
  bool linkArtist = true,
}) {
  return {
    "title": {
      "runs": [
        {"text": title},
      ],
    },
    "longBylineText": {
      "runs": [
        {
          "text": artist,
          if (linkArtist)
            "navigationEndpoint": {
              "browseEndpoint": {
                "browseId": "UCartist",
                "browseEndpointContextSupportedConfigs": {
                  "browseEndpointContextMusicConfig": {
                    "pageType": "MUSIC_PAGE_TYPE_ARTIST",
                  },
                },
              },
            },
        },
        {"text": " • "},
        {"text": "204M views"},
      ],
    },
    "navigationEndpoint": {
      "watchEndpoint": {"videoId": videoId, "playlistId": "RDAMVMseed"},
    },
  };
}

Map<String, dynamic> _songRow({
  required String videoId,
  required String title,
  required String artist,
  required String album,
}) {
  return {
    "flexColumns": [
      for (final text in [title, artist, album])
        {
          "musicResponsiveListItemFlexColumnRenderer": {
            "text": {
              "runs": [
                {"text": text},
              ],
            },
          },
        },
    ],
    "overlay": {
      "musicItemThumbnailOverlayRenderer": {
        "content": {
          "musicPlayButtonRenderer": {
            "playNavigationEndpoint": {
              "watchEndpoint": {"videoId": videoId},
            },
          },
        },
      },
    },
  };
}

Map<String, dynamic> _carouselCard({
  required String browseId,
  required String name,
  required String pageType,
}) {
  return {
    "title": {
      "runs": [
        {"text": name},
      ],
    },
    "navigationEndpoint": {
      "browseEndpoint": {
        "browseId": browseId,
        "browseEndpointContextSupportedConfigs": {
          "browseEndpointContextMusicConfig": {"pageType": pageType},
        },
      },
    },
  };
}

SpotubeFullTrackObject _track(String name, List<String> artists) {
  return SpotubeTrackObject.full(
    id: "track-$name",
    name: name,
    externalUri: "https://example.com/$name",
    artists: [
      for (final artist in artists)
        SpotubeSimpleArtistObject(
          id: artist,
          name: artist,
          externalUri: "https://example.com/$artist",
        ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: "album",
      name: "Album",
      externalUri: "https://example.com/album",
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 200000,
    isrc: "",
    explicit: false,
  ) as SpotubeFullTrackObject;
}

void main() {
  group("InnerTube parsing", () {
    test("finds renderers wherever they are nested", () {
      final response = {
        "contents": {
          "tabs": [
            {
              "tabRenderer": {
                "content": {
                  "items": [
                    {"playlistPanelVideoRenderer": _radioEntry(
                      videoId: "aaaaaaaaaaa",
                      title: "One",
                      artist: "Artist",
                    )},
                    {"playlistPanelVideoRenderer": _radioEntry(
                      videoId: "bbbbbbbbbbb",
                      title: "Two",
                      artist: "Artist",
                    )},
                  ],
                },
              },
            },
          ],
        },
      };

      final found = findRenderers(
        response,
        "playlistPanelVideoRenderer",
      ).toList();

      expect(found, hasLength(2));
    });

    test("reads a radio entry", () {
      final song = parsePlaylistPanelVideo(
        _radioEntry(
          videoId: "yPYZpwSpKmA",
          title: "Together Forever (2022 Remaster)",
          artist: "Rick Astley",
        ),
      );

      expect(song, isNotNull);
      expect(song!.videoId, "yPYZpwSpKmA");
      expect(song.title, "Together Forever (2022 Remaster)");
      expect(song.artist, "Rick Astley");
      expect(song.searchQuery, "Together Forever (2022 Remaster) Rick Astley");
    });

    test("reads the artist out of an unlinked byline", () {
      final song = parsePlaylistPanelVideo(
        _radioEntry(
          videoId: "yPYZpwSpKmA",
          title: "Together Forever",
          artist: "Rick Astley",
          linkArtist: false,
        ),
      );

      expect(song?.artist, "Rick Astley");
    });

    test("reads a song row", () {
      final song = parseResponsiveListItem(
        _songRow(
          videoId: "x_XS5q0EUQs",
          title: "Another Day in Paradise",
          artist: "Phil Collins",
          album: "...But Seriously",
        ),
      );

      expect(song, isNotNull);
      expect(song!.videoId, "x_XS5q0EUQs");
      expect(song.title, "Another Day in Paradise");
      expect(song.artist, "Phil Collins");
      expect(song.album, "...But Seriously");
    });

    test("keeps artist cards and drops everything else in a carousel", () {
      final artist = parseTwoRowArtist(
        _carouselCard(
          browseId: "UChva71IdUXvTn8uHGtJkB_w",
          name: "Culture Club",
          pageType: "MUSIC_PAGE_TYPE_ARTIST",
        ),
      );
      final playlist = parseTwoRowArtist(
        _carouselCard(
          browseId: "VLPLxxxx",
          name: "80s Hits",
          pageType: "MUSIC_PAGE_TYPE_PLAYLIST",
        ),
      );

      expect(artist?.name, "Culture Club");
      expect(artist?.browseId, "UChva71IdUXvTn8uHGtJkB_w");
      expect(playlist, isNull);
    });

    test("skips entries with no playable id", () {
      expect(
        parsePlaylistPanelVideo({
          "title": {
            "runs": [
              {"text": "Unplayable"},
            ],
          },
        }),
        isNull,
      );
    });
  });

  group("normalisation", () {
    test("strips YouTube's title decoration", () {
      expect(
        normalizeSongTitle("Never Gonna Give You Up (Official Video)"),
        "never gonna give you up",
      );
      expect(
        normalizeSongTitle("Together Forever [2022 Remaster]"),
        "together forever",
      );
      expect(
        normalizeSongTitle("Levitating feat. DaBaby"),
        "levitating",
      );
    });

    test("keeps titles that are all decoration words", () {
      expect(normalizeSongTitle("Official"), isNotEmpty);
    });

    test("keeps non-latin titles intact", () {
      expect(normalizeSongTitle("夜に駆ける"), "夜に駆ける");
    });

    test("strips the auto-generated channel suffix from artists", () {
      expect(normalizeArtistName("Rick Astley - Topic"), "rick astley");
    });

    test("gives decorated and clean titles the same identity", () {
      expect(
        songIdentityKey("Together Forever (2022 Remaster)", "Rick Astley"),
        songIdentityKey("Together Forever", "Rick Astley - Topic"),
      );
    });
  });

  group("matching a YouTube song to a plugin track", () {
    test("matches through remaster and video suffixes", () {
      const song = YoutubeMusicSong(
        videoId: "aaaaaaaaaaa",
        title: "Together Forever (2022 Remaster)",
        artist: "Rick Astley",
      );

      expect(
        isLikelySameSong(song, _track("Together Forever", ["Rick Astley"])),
        isTrue,
      );
    });

    test("matches when the uploader put the artist in the title", () {
      const song = YoutubeMusicSong(
        videoId: "aaaaaaaaaaa",
        title: "Rick Astley - Never Gonna Give You Up",
        artist: "Rick Astley",
      );

      expect(
        isLikelySameSong(
          song,
          _track("Never Gonna Give You Up", ["Rick Astley"]),
        ),
        isTrue,
      );
    });

    test("matches a featured artist credited on either side", () {
      const song = YoutubeMusicSong(
        videoId: "aaaaaaaaaaa",
        title: "Levitating (feat. DaBaby)",
        artist: "Dua Lipa",
      );

      expect(
        isLikelySameSong(song, _track("Levitating", ["Dua Lipa", "DaBaby"])),
        isTrue,
      );
    });

    test("rejects the same title by a different artist", () {
      const song = YoutubeMusicSong(
        videoId: "aaaaaaaaaaa",
        title: "Hurt",
        artist: "Johnny Cash",
      );

      expect(isLikelySameSong(song, _track("Hurt", ["Nine Inch Nails"])), isFalse);
    });

    test("rejects an unrelated title by the same artist", () {
      const song = YoutubeMusicSong(
        videoId: "aaaaaaaaaaa",
        title: "Together Forever",
        artist: "Rick Astley",
      );

      expect(
        isLikelySameSong(
          song,
          _track("Never Gonna Give You Up", ["Rick Astley"]),
        ),
        isFalse,
      );
    });

    test("does not let short titles match by containment", () {
      const song = YoutubeMusicSong(
        videoId: "aaaaaaaaaaa",
        title: "Go",
        artist: "Artist",
      );

      expect(isLikelySameSong(song, _track("Go Big", ["Artist"])), isFalse);
    });

    test("accepts a song with no artist byline on title alone", () {
      const song = YoutubeMusicSong(
        videoId: "aaaaaaaaaaa",
        title: "Together Forever",
      );

      expect(
        isLikelySameSong(song, _track("Together Forever", ["Rick Astley"])),
        isTrue,
      );
    });
  });

  group("cached recommendations", () {
    test("survive a JSON round trip", () {
      final original = YoutubeMusicRecommendations(
        tracks: [_track("Together Forever", ["Rick Astley"])],
        artists: [
          SpotubeFullArtistObject(
            id: "artist",
            name: "Culture Club",
            externalUri: "https://example.com/culture-club",
          ),
        ],
        seedTrackName: "Never Gonna Give You Up",
      );

      final restored = YoutubeMusicRecommendations.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(restored.tracks.single, original.tracks.single);
      expect(restored.artists.single, original.artists.single);
      expect(restored.seedTrackName, "Never Gonna Give You Up");
    });

    test("drop entries that no longer parse", () {
      final restored = YoutubeMusicRecommendations.fromJson({
        "tracks": const [],
        "artists": const [],
      });

      expect(restored.isEmpty, isTrue);
    });
  });

  group("matching artists", () {
    SpotubeFullArtistObject artist(String name) => SpotubeFullArtistObject(
          id: name,
          name: name,
          externalUri: "https://example.com/$name",
        );

    test("matches exactly, ignoring case and punctuation", () {
      expect(isLikelySameArtist("Culture Club", artist("culture club")), isTrue);
      expect(isLikelySameArtist("AC/DC", artist("AC DC")), isTrue);
    });

    test("rejects a merely similar name", () {
      expect(isLikelySameArtist("Queen", artist("Queens of the Stone Age")),
          isFalse);
    });
  });
}
