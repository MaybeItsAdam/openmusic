import 'package:flutter/material.dart' show ReorderableListView, ListTile;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:openmusic/collections/openmusic_icons.dart';
import 'package:openmusic/extensions/context.dart';
import 'package:openmusic/models/database/database.dart';
import 'package:openmusic/provider/user_preferences/user_preferences_provider.dart';

/// Reorderable list of lyrics sources, with a toggle per row.
///
/// Order matters: the chain stops at the first provider that returns lyrics,
/// so this is how a user puts the source they trust for their library first.
class LyricsProviderOrderDialog extends HookConsumerWidget {
  const LyricsProviderOrderDialog({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final preferences = ref.watch(userPreferencesProvider);
    final notifier = ref.watch(userPreferencesProvider.notifier);

    final order = _resolveOrder(preferences.lyricsProviderOrder);
    final enabled = preferences.lyricsProvidersEnabled
        .map(LyricsProviderId.fromNameOrNull)
        .whereType<LyricsProviderId>()
        .toSet();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Alert(
        title: Text(context.l10n.lyrics_providers).h4(),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Gap(6),
            Text(context.l10n.lyrics_providers_description).small.muted,
            const Gap(12),
            SizedBox(
              height: 340,
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: order.length,
                onReorder: (oldIndex, newIndex) {
                  // ReorderableListView reports the target index as it would be
                  // *before* the dragged item is removed, so anything moving
                  // down is off by one.
                  final adjusted =
                      newIndex > oldIndex ? newIndex - 1 : newIndex;
                  final next = [...order];
                  next.insert(adjusted, next.removeAt(oldIndex));
                  notifier.setLyricsProviderOrder(next);
                },
                itemBuilder: (context, index) {
                  final id = order[index];
                  final isEnabled = enabled.contains(id);

                  return ListTile(
                    key: ValueKey(id),
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: const MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Icon(OpenMusicIcons.dragHandle),
                      ),
                    ),
                    title: Text(id.label),
                    subtitle: id.isUnofficial
                        ? Text(context.l10n.lyrics_provider_unofficial)
                            .xSmall
                            .muted
                        : null,
                    trailing: Switch(
                      value: isEnabled,
                      onChanged: (value) {
                        final next = {...enabled};
                        if (value) {
                          next.add(id);
                        } else {
                          next.remove(id);
                        }
                        notifier.setLyricsProvidersEnabled(next);
                      },
                    ),
                  );
                },
              ),
            ),
            const Gap(16),
            Button.primary(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.done),
            ),
          ],
        ),
      ),
    );
  }

  /// The stored order, with any provider it doesn't mention appended.
  ///
  /// A saved order predates every provider added after it, so without this a
  /// newly shipped provider would never appear in the list at all.
  List<LyricsProviderId> _resolveOrder(List<String> stored) {
    final resolved = <LyricsProviderId>[];

    for (final name in stored) {
      final id = LyricsProviderId.fromNameOrNull(name);
      if (id != null && !resolved.contains(id)) resolved.add(id);
    }
    for (final id in LyricsProviderId.values) {
      if (!resolved.contains(id)) resolved.add(id);
    }

    return resolved;
  }
}
