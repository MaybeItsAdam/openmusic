part of '../database.dart';

enum LayoutMode { compact, extended, adaptive }

enum CloseBehavior { minimizeToTray, close }

enum YoutubeClientEngine {
  ytDlp("yt-dlp"),
  youtubeExplode("YouTubeExplode"),
  newPipe("NewPipe");

  final String label;

  const YoutubeClientEngine(this.label);

  /// The engine to use when the platform gets to pick: yt-dlp on desktop,
  /// NewPipe on Android, YouTubeExplode on iOS.
  ///
  /// A SQL column default has to be a single constant, so this — not the
  /// `withDefault` on [PreferencesTable.youtubeClientEngine] — is the default
  /// that actually reaches users. See [PreferencesTable.defaults].
  static YoutubeClientEngine get defaultForPlatform {
    if (YtDlpEngine.isAvailableForPlatform) return YoutubeClientEngine.ytDlp;
    if (NewPipeEngine.isAvailableForPlatform) {
      return YoutubeClientEngine.newPipe;
    }
    return YoutubeClientEngine.youtubeExplode;
  }

  bool isAvailableForPlatform() {
    return switch (this) {
      YoutubeClientEngine.youtubeExplode =>
        YouTubeExplodeEngine.isAvailableForPlatform,
      YoutubeClientEngine.ytDlp => YtDlpEngine.isAvailableForPlatform,
      YoutubeClientEngine.newPipe => NewPipeEngine.isAvailableForPlatform,
    };
  }

  /// The preference is persisted by name, so a value that was valid when it
  /// was written can outlive its platform gate — desktop and Android installs
  /// from before yt-dlp became the default still have `youtubeExplode` stored.
  /// Coerce those onto an engine this platform can actually run.
  YoutubeClientEngine resolveForPlatform() =>
      isAvailableForPlatform() ? this : defaultForPlatform;
}

enum SearchMode {
  youtube._("YouTube"),
  youtubeMusic._("YouTube Music");

  final String label;

  const SearchMode._(this.label);

  factory SearchMode.fromString(String key) {
    return SearchMode.values.firstWhere((e) => e.name == key);
  }
}

class PreferencesTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  BoolColumn get albumColorSync =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get amoledDarkTheme =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get checkUpdate => boolean().withDefault(const Constant(true))();
  BoolColumn get normalizeAudio =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get showSystemTrayIcon =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get systemTitleBar =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get skipNonMusic => boolean().withDefault(const Constant(false))();
  TextColumn get closeBehavior => textEnum<CloseBehavior>().withDefault(
        Constant(CloseBehavior.close.name),
      )();
  TextColumn get accentColorScheme => text()
      .withDefault(const Constant("Slate:0xff64748b"))
      .map(const SpotubeColorConverter())();
  TextColumn get layoutMode =>
      textEnum<LayoutMode>().withDefault(Constant(LayoutMode.adaptive.name))();
  TextColumn get locale => text()
      .withDefault(
        const Constant('{"languageCode":"system","countryCode":"system"}'),
      )
      .map(const LocaleConverter())();
  TextColumn get market =>
      textEnum<Market>().withDefault(Constant(Market.US.name))();
  TextColumn get searchMode =>
      textEnum<SearchMode>().withDefault(Constant(SearchMode.youtube.name))();
  TextColumn get downloadLocation => text().withDefault(const Constant(""))();
  TextColumn get localLibraryLocation =>
      text().withDefault(const Constant("")).map(const StringListConverter())();
  TextColumn get themeMode =>
      textEnum<ThemeMode>().withDefault(Constant(ThemeMode.system.name))();
  TextColumn get audioSourceId => text().nullable()();
  // The real default is [YoutubeClientEngine.defaultForPlatform] — a SQL
  // default cannot branch on platform, and every insert supplies this column
  // explicitly, so this constant only exists to keep the column NOT NULL.
  // Changing it would force a schema bump for no behavioural gain.
  TextColumn get youtubeClientEngine => textEnum<YoutubeClientEngine>()
      .withDefault(Constant(YoutubeClientEngine.youtubeExplode.name))();
  BoolColumn get discordPresence =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get endlessPlayback =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get enableConnect =>
      boolean().withDefault(const Constant(false))();
  IntColumn get connectPort => integer().withDefault(const Constant(-1))();
  BoolColumn get cacheMusic => boolean().withDefault(const Constant(true))();

  // Default values as PreferencesTableData
  static PreferencesTableData defaults() {
    return PreferencesTableData(
      id: 0,
      albumColorSync: true,
      amoledDarkTheme: false,
      checkUpdate: true,
      normalizeAudio: false,
      showSystemTrayIcon: false,
      systemTitleBar: false,
      skipNonMusic: false,
      closeBehavior: CloseBehavior.close,
      accentColorScheme: SpotubeColor(Colors.slate.value, name: "Slate"),
      layoutMode: LayoutMode.adaptive,
      locale: const Locale("system", "system"),
      market: Market.US,
      searchMode: SearchMode.youtube,
      downloadLocation: "",
      localLibraryLocation: [],
      themeMode: ThemeMode.system,
      audioSourceId: null,
      youtubeClientEngine: YoutubeClientEngine.defaultForPlatform,
      discordPresence: true,
      endlessPlayback: true,
      enableConnect: false,
      cacheMusic: true,
      connectPort: -1,
    );
  }
}
