import 'package:drift/drift.dart';
import 'package:openmusic/models/database/database.dart';
import 'package:openmusic/services/kv_store/encrypted_kv_store.dart';
import 'package:openmusic/services/logger/logger.dart';

/// Columns holding values written by the legacy Salsa20 scheme.
///
/// `authentication_table` is a leftover from the removed Spotify integration --
/// nothing reads or writes it -- but its rows are re-encrypted anyway rather
/// than left as the only ciphertext still using the old key.
const _encryptedColumns = <({String table, String column})>[
  (table: 'scrobbler_table', column: 'password_hash'),
  (table: 'authentication_table', column: 'cookie'),
  (table: 'authentication_table', column: 'access_token'),
];

/// Rewrites legacy-encrypted database values under AES-GCM.
///
/// Runs outside the drift migration chain on purpose. The stored format is
/// self-describing (AES-GCM values carry a `v2:` prefix), so this is idempotent
/// and safe to run on every launch: already-migrated values are skipped and a
/// crash part-way through simply resumes next time. Putting it in a schema step
/// would make a single failure brick the app on launch, and the column types do
/// not change, so there is nothing for a schema version to describe.
///
/// A value that cannot be decrypted is deleted rather than kept. That costs the
/// user a re-login, which is the only available outcome once the key is gone --
/// and it can genuinely be gone, because the plugin localstorage API used to
/// call SharedPreferences.clear() and wipe the key along with everything else.
Future<void> migrateLegacyEncryptedValues(AppDatabase database) async {
  // Nothing was ever written with the old key on a fresh install.
  if (EncryptedKvStoreService.legacyEncryptionKeySyncOrNull == null) return;

  var rewritten = 0;
  var discarded = 0;

  for (final target in _encryptedColumns) {
    final List<QueryRow> rows;
    try {
      rows = await database
          .customSelect('SELECT id, ${target.column} FROM ${target.table}')
          .get();
    } catch (error, stackTrace) {
      // A table that no longer exists is not a failure worth aborting for.
      AppLogger.reportError(error, stackTrace);
      continue;
    }

    for (final row in rows) {
      final id = row.read<int>('id');
      final stored = row.read<String?>(target.column);

      if (stored == null || stored.isEmpty) continue;
      if (stored.startsWith('v2:')) continue; // already migrated

      try {
        // Read with the legacy key, write with the current one. Both are
        // needed at once, which is why the legacy reader is not cached
        // alongside the AES-GCM encrypter.
        final plaintext = DecryptedText.decryptLegacy(stored);

        await database.customStatement(
          'UPDATE ${target.table} SET ${target.column} = ? WHERE id = ?',
          [DecryptedText(plaintext).encrypt(), id],
        );
        rewritten++;
      } catch (error, stackTrace) {
        AppLogger.reportError(error, stackTrace);

        await database.customStatement(
          'DELETE FROM ${target.table} WHERE id = ?',
          [id],
        );
        discarded++;
      }
    }
  }

  AppLogger.log.i(
    're-encrypted $rewritten stored credential(s), '
    'discarded $discarded undecryptable one(s)',
  );

  // Every row above was either rewritten or deleted, so nothing depends on the
  // old key or its reused IV any more.
  await EncryptedKvStoreService.discardLegacyKey();
}
