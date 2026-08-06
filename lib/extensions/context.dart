import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:openmusic/l10n/l10n.dart';

extension AppLocale on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
