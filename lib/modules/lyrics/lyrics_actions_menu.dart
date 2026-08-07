import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:openmusic/collections/openmusic_icons.dart';
import 'package:openmusic/components/adaptive/adaptive_pop_sheet_list.dart';
import 'package:openmusic/extensions/context.dart';
import 'package:openmusic/modules/lyrics/lyrics_provider_picker.dart';
import 'package:openmusic/provider/audio_player/audio_player.dart';
import 'package:openmusic/provider/lyrics/synced.dart';

enum _LyricsAction { refetch, search, copy }

/// Refetch / search / copy, for when the automatic pick is wrong or stale.
class LyricsActionsMenu extends ConsumerWidget {
  const LyricsActionsMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(audioPlayerProvider.select((s) => s.activeTrack));

    if (track == null) return const SizedBox.shrink();

    final lyrics = ref.watch(syncedLyricsProvider(track)).asData?.value;
    final hasLyrics = lyrics != null && lyrics.lyrics.isNotEmpty;

    return AdaptivePopSheetList<_LyricsAction>(
      variance: ButtonVariance.ghost,
      tooltip: context.l10n.lyrics,
      icon: const Icon(OpenMusicIcons.moreVertical),
      onSelected: (action) async {
        switch (action) {
          case _LyricsAction.refetch:
            ref.read(syncedLyricsProvider(track).notifier).refetch();
          case _LyricsAction.search:
            showDialog(
              context: context,
              barrierColor: Colors.black,
              builder: (context) => LyricsProviderPicker(track: track),
            );
          case _LyricsAction.copy:
            if (lyrics == null) return;
            await Clipboard.setData(
              ClipboardData(text: lyrics.lyrics.map((l) => l.text).join("\n")),
            );
            if (context.mounted) {
              showToast(
                context: context,
                builder: (context, overlay) => SurfaceCard(
                  child: Text(context.l10n.lyrics_copied),
                ),
              );
            }
        }
      },
      items: (context) => [
        AdaptiveMenuButton(
          value: _LyricsAction.refetch,
          leading: const Icon(OpenMusicIcons.refresh),
          child: Text(context.l10n.refetch_lyrics),
        ),
        AdaptiveMenuButton(
          value: _LyricsAction.search,
          leading: const Icon(OpenMusicIcons.search),
          child: Text(context.l10n.search_lyrics),
        ),
        AdaptiveMenuButton(
          value: _LyricsAction.copy,
          enabled: hasLyrics,
          leading: const Icon(OpenMusicIcons.clipboard),
          child: Text(context.l10n.copy_lyrics),
        ),
      ],
    );
  }
}
