import 'package:flutter/material.dart' show ListTile;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:openmusic/collections/openmusic_icons.dart';
import 'package:openmusic/extensions/context.dart';
import 'package:openmusic/models/lyrics.dart';
import 'package:openmusic/models/metadata/metadata.dart';
import 'package:openmusic/provider/lyrics/synced.dart';

/// Lets the user override the automatic pick.
///
/// The chain stops at the first provider with a result, which is usually right
/// but occasionally lands on the wrong recording — a live version, or a cover.
/// This queries everything at once and shows what each source actually has.
class LyricsProviderPicker extends HookConsumerWidget {
  final SpotubeTrackObject track;

  const LyricsProviderPicker({required this.track, super.key});

  @override
  Widget build(BuildContext context, ref) {
    final results = ref.watch(allProviderLyricsProvider(track));

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Alert(
        title: Text(context.l10n.search_lyrics).h4(),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 340,
              child: results.when(
                loading: () => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const Gap(16),
                      Text(context.l10n.searching_lyrics_providers).small.muted,
                    ],
                  ),
                ),
                error: (_, __) => Center(
                  child:
                      Text(context.l10n.no_lyrics_found_anywhere).small.muted,
                ),
                data: (data) {
                  if (data.isEmpty) {
                    return Center(
                      child: Text(context.l10n.no_lyrics_found_anywhere)
                          .small
                          .muted,
                    );
                  }

                  return ListView.builder(
                    itemCount: data.length,
                    itemBuilder: (context, index) {
                      final subtitle = data[index];

                      return ListTile(
                        leading: Icon(
                          subtitle.isSynced
                              ? OpenMusicIcons.lyrics
                              : OpenMusicIcons.lyricsOff,
                        ),
                        title: Text(subtitle.provider),
                        subtitle: Text(
                          "${_kindLabel(context, subtitle)} · "
                          "${context.l10n.lyrics_line_count(subtitle.lyrics.length)}",
                        ).xSmall.muted,
                        onTap: () async {
                          await ref
                              .read(syncedLyricsProvider(track).notifier)
                              .select(subtitle);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const Gap(16),
            Button.secondary(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.cancel),
            ),
          ],
        ),
      ),
    );
  }

  String _kindLabel(BuildContext context, SubtitleSimple subtitle) {
    if (subtitle.hasWordTimings) return context.l10n.lyrics_word_synced;
    if (subtitle.isSynced) return context.l10n.lyrics_line_synced;
    return context.l10n.lyrics_plain;
  }
}
