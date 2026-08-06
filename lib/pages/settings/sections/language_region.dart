import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:openmusic/collections/language_codes.dart';
import 'package:openmusic/collections/markets.dart';
import 'package:openmusic/collections/openmusic_icons.dart';
import 'package:openmusic/models/metadata/market.dart';
import 'package:openmusic/modules/settings/section_card_with_heading.dart';
import 'package:openmusic/components/adaptive/adaptive_select_tile.dart';
import 'package:openmusic/extensions/constrains.dart';
import 'package:openmusic/extensions/context.dart';
import 'package:openmusic/l10n/l10n.dart';
import 'package:openmusic/provider/user_preferences/user_preferences_provider.dart';

final localWithName = L10n.all.map((e) {
  final isoCodeName = LanguageLocals.getDisplayLanguage(
    e.languageCode,
    e.countryCode,
  );
  return (
    locale: e,
    name: "${isoCodeName.name} (${isoCodeName.nativeName})",
  );
}).sortedBy((e) => e.name);

class SettingsLanguageRegionSection extends HookConsumerWidget {
  const SettingsLanguageRegionSection({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final preferences = ref.watch(userPreferencesProvider);
    final preferencesNotifier = ref.watch(userPreferencesProvider.notifier);
    final mediaQuery = MediaQuery.of(context);

    return SectionCardWithHeading(
      heading: context.l10n.language_region,
      children: [
        AdaptiveSelectTile<Locale>(
          value: preferences.locale,
          onChanged: (locale) {
            if (locale == null) return;
            preferencesNotifier.setLocale(locale);
          },
          title: Text(context.l10n.language),
          secondary: const Icon(OpenMusicIcons.language),
          options: [
            SelectItemButton(
              value: const Locale("system", "system"),
              child: Text(context.l10n.system_default),
            ),
            for (final (:locale, :name) in localWithName)
              SelectItemButton(value: locale, child: Text(name)),
          ],
        ),
        AdaptiveSelectTile<Market>(
          breakLayout: mediaQuery.lgAndUp,
          secondary: const Icon(OpenMusicIcons.shoppingBag),
          title: Text(context.l10n.market_place_region),
          subtitle: Text(context.l10n.recommendation_country),
          value: preferences.market,
          onChanged: (value) {
            if (value == null) return;
            preferencesNotifier.setRecommendationMarket(value);
          },
          options: marketsMap
              .map(
                (country) => SelectItemButton(
                  value: country.$1,
                  child: Text(country.$2),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
