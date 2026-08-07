part of '../database.dart';

/// Declared as an index rather than an inline `UNIQUE` on the column, because
/// SQLite cannot add a column constraint to an existing table. An index is the
/// only form of uniqueness a migration can add, so declaring it this way keeps
/// a migrated database byte-identical to a freshly created one — which is what
/// the drift schema verifier checks.
@TableIndex(name: 'uniq_lyrics_track_id', columns: {#trackId}, unique: true)
class LyricsTable extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Unique, so `InsertMode.replace` actually replaces. Without a conflict
  /// target the autoincrement primary key means every insert appends a new
  /// row, and a track with two rows makes `getSingleOrNull` throw forever.
  TextColumn get trackId => text()();
  TextColumn get data => text().map(SubtitleTypeConverter())();

  /// Per-song lyrics offset in milliseconds, applied to the playback position
  /// before looking up the current line. Positive values pull lyrics earlier.
  IntColumn get offsetMs => integer().withDefault(const Constant(0))();
}
