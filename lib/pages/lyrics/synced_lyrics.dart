import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:openmusic/collections/openmusic_icons.dart';
import 'package:openmusic/models/metadata/metadata.dart';
import 'package:openmusic/modules/lyrics/lyrics_line.dart';
import 'package:openmusic/modules/lyrics/zoom_controls.dart';
import 'package:openmusic/components/shimmers/shimmer_lyrics.dart';
import 'package:openmusic/extensions/constrains.dart';
import 'package:openmusic/extensions/context.dart';
import 'package:openmusic/hooks/controllers/use_auto_scroll_controller.dart';
import 'package:openmusic/modules/lyrics/use_synced_lyrics.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:openmusic/provider/audio_player/audio_player.dart';
import 'package:openmusic/provider/lyrics/synced.dart';
import 'package:openmusic/services/audio_player/audio_player.dart';
import 'package:openmusic/services/logger/logger.dart';

/// Scrolling a fraction ahead of the beat keeps the active line from arriving
/// at the centre late. Only applied when there are no word timings — with them
/// the fill already telegraphs where the line is going.
const _scrollLookAhead = Duration(milliseconds: 250);

class SyncedLyrics extends HookConsumerWidget {
  final PaletteColor palette;
  final bool? isModal;
  final int defaultTextZoom;

  const SyncedLyrics({
    required this.palette,
    this.isModal,
    this.defaultTextZoom = 100,
    super.key,
  });

  @override
  Widget build(BuildContext context, ref) {
    final mediaQuery = MediaQuery.sizeOf(context);
    final theme = Theme.of(context);

    final playlist = ref.watch(audioPlayerProvider);
    final activeTrack = playlist.activeTrack;

    final controller = useAutoScrollController();

    final offset = ref.watch(lyricsOffsetProvider(activeTrack)).asData?.value ?? 0;

    final timedLyricsQuery = ref.watch(syncedLyricsProvider(activeTrack));
    final lyricValue = timedLyricsQuery.asData?.value;
    final lines = lyricValue?.lyrics ?? const [];

    final isPlaying = ref.watch(
      audioPlayerProvider.select((s) => s.playing),
    );
    final position = useSmoothPosition(isPlaying: isPlaying);

    final hasWordTimings = lyricValue?.hasWordTimings ?? false;
    final scrollPosition =
        hasWordTimings ? position : position + _scrollLookAhead;

    final active = useActiveLyricLines(lines, position, offset);
    final scrollTarget =
        useActiveLyricLines(lines, scrollPosition, offset).current;

    final textZoomLevel = useState<int>(defaultTextZoom);

    final typography = Theme.of(context).typography;

    final isStatic = lyricValue != null && !lyricValue.isSynced;

    ref.listen(audioPlayerProvider.select((s) => s.activeTrack), (
      previous,
      next,
    ) {
      controller.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });

    final headlineTextStyle = (mediaQuery.mdAndUp
            ? typography.h3
            : typography.h4.copyWith(fontSize: 25))
        .copyWith(color: palette.titleTextColor);

    final bodyTextTheme = typography.large.copyWith(
      color: palette.bodyTextColor,
    );

    // Keep the view pinned to the top when playback restarts from zero.
    useEffect(() {
      StreamSubscription? subscription;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        subscription = audioPlayer.positionStream.listen((event) {
          try {
            if (event > Duration.zero || !controller.hasClients) return;
            controller.animateTo(
              0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
          } catch (e, stack) {
            AppLogger.reportError(e, stack);
          }
        });
      });

      return subscription?.cancel;
    }, [controller]);

    // Scroll when the target line changes, rather than while building each
    // item — doing it per item ran a scroll for every rebuild of the active row.
    useEffect(() {
      if (scrollTarget < 0 || isStatic) return null;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!controller.hasClients) return;
        controller.scrollToIndex(
          scrollTarget,
          preferPosition: AutoScrollPosition.middle,
        );
      });
      return null;
    }, [scrollTarget, isStatic]);

    return Stack(
      children: [
        CustomScrollView(
          controller: controller,
          slivers: [
            if (isModal != true)
              SliverAppBar(
                automaticallyImplyLeading: false,
                backgroundColor: Colors.transparent,
                centerTitle: true,
                title: Text(
                  activeTrack?.name ?? context.l10n.not_playing,
                  style: headlineTextStyle,
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(40),
                  child: Text(
                    activeTrack?.artists.asString() ?? "",
                    style:
                        mediaQuery.mdAndUp ? typography.h4 : typography.x2Large,
                  ),
                ),
              ),
            if (lines.isNotEmpty && !isStatic)
              SliverList.builder(
                itemCount: lines.length,
                itemBuilder: (context, index) {
                  final lyricSlice = lines[index];
                  final isActive = active.active.contains(index) ||
                      index == active.current;

                  return AutoScrollTag(
                    key: ValueKey(index),
                    index: index,
                    controller: controller,
                    child: lyricSlice.text.isEmpty
                        ? Container(
                            padding: index == lines.length - 1
                                ? EdgeInsets.only(bottom: mediaQuery.height / 2)
                                : null,
                          )
                        : Center(
                            child: Padding(
                              padding: index == lines.length - 1
                                  ? const EdgeInsets.all(
                                      8.0,
                                    ).copyWith(bottom: 100)
                                  : const EdgeInsets.all(8.0),
                              child: LyricsLine(
                                slice: lyricSlice,
                                isActive: isActive,
                                position: position +
                                    Duration(seconds: offset),
                                activeColor: theme.colorScheme.foreground,
                                inactiveColor:
                                    theme.colorScheme.mutedForeground,
                                fontSize: (isActive ? 28 : 26) *
                                    (textZoomLevel.value / 100),
                                onTap: () async {
                                  final time =
                                      lyricSlice.time -
                                          Duration(seconds: offset);
                                  if (time > audioPlayer.duration ||
                                      time.isNegative) {
                                    return;
                                  }
                                  audioPlayer.seek(time);
                                },
                              ),
                            ),
                          ),
                  );
                },
              ),
            if (activeTrack != null &&
                (timedLyricsQuery.isLoading || timedLyricsQuery.isRefreshing))
              const SliverToBoxAdapter(child: ShimmerLyrics())
            else if (activeTrack != null && timedLyricsQuery.hasError) ...[
              SliverToBoxAdapter(
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    context.l10n.no_lyrics_available,
                    style: bodyTextTheme,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SliverGap(26),
              const SliverToBoxAdapter(
                child: Icon(OpenMusicIcons.noLyrics, size: 60),
              ),
            ] else if (isStatic)
              SliverFillRemaining(
                child: Center(
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: bodyTextTheme,
                      children: [
                        TextSpan(
                          text: context.l10n.synced_lyrics_not_available,
                        ),
                        TextSpan(
                          text: " ${context.l10n.plain_lyrics} ",
                          style: typography.large.copyWith(
                            color: palette.bodyTextColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(text: context.l10n.tab_instead),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: Builder(
            builder: (context) {
              final actions = [
                ZoomControls(
                  value: offset,
                  onChanged: (value) => ref
                      .read(lyricsOffsetProvider(activeTrack).notifier)
                      .set(value),
                  interval: 1,
                  unit: "s",
                  increaseIcon: const Icon(OpenMusicIcons.add),
                  decreaseIcon: const Icon(OpenMusicIcons.remove),
                  direction: isModal == true ? Axis.horizontal : Axis.vertical,
                ),
                ZoomControls(
                  value: textZoomLevel.value,
                  onChanged: (value) => textZoomLevel.value = value,
                  min: 50,
                  max: 200,
                ),
              ];

              return isModal == true
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: actions,
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: actions,
                    );
            },
          ),
        ),
      ],
    );
  }
}
