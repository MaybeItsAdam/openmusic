part of '../database.dart';

/// A value stored encrypted at rest.
///
/// Written values use AES-GCM with a per-value random IV. Reads also accept the
/// legacy format so credentials stored by older builds survive the upgrade.
///
/// The legacy format was Salsa20 with a single IV persisted once and reused for
/// every value. A stream cipher with a fixed IV XORs the same keystream into
/// every record, so identical prefixes produced identical ciphertext and XORing
/// two ciphertexts revealed the XOR of their plaintexts -- recoverable without
/// attacking the key at all. It also had no MAC, so ciphertext was malleable.
/// The key was weak independently: `Key.fromUtf8` on a UUIDv4 string yields 36
/// bytes, and pointycastle's Salsa20 takes its 32-byte branch only at exactly
/// 32, so it silently fell back to using bytes 0-15 twice -- and bytes 0-15 of
/// a UUIDv4 string carry roughly 52 bits of entropy.
class DecryptedText {
  final String value;
  const DecryptedText(this.value);

  /// Marks the AES-GCM format. Values without it are read as legacy Salsa20.
  static const _v2Prefix = 'v2:';

  /// GCM's standard nonce length.
  static const _ivLength = 12;

  static Encrypter? _aesGcm;

  static Encrypter get _encrypter => _aesGcm ??= Encrypter(
        AES(
          Key.fromBase64(EncryptedKvStoreService.encryptionKeySync),
          mode: AESMode.gcm,
        ),
      );

  factory DecryptedText.decrypted(String stored) {
    if (stored.startsWith(_v2Prefix)) {
      final raw = base64.decode(stored.substring(_v2Prefix.length));
      final iv = IV(Uint8List.sublistView(raw, 0, _ivLength));
      final cipherText = Uint8List.sublistView(raw, _ivLength);

      return DecryptedText(
        _encrypter.decrypt(Encrypted(cipherText), iv: iv),
      );
    }

    return DecryptedText(decryptLegacy(stored));
  }

  /// Decrypts a value written by the pre-AES-GCM scheme.
  ///
  /// Kept separate and uncached so the re-encryption migration can hold a
  /// legacy reader and the current writer at the same time.
  static String decryptLegacy(String stored) {
    final iv = KVStoreService.ivKey;
    if (iv == null) {
      throw StateError('No legacy IV is available to decrypt this value.');
    }

    final legacy = Encrypter(
      Salsa20(Key.fromUtf8(EncryptedKvStoreService.legacyEncryptionKeySync)),
    );

    return legacy.decrypt(Encrypted.fromBase64(stored), iv: iv);
  }

  String encrypt() {
    // A fresh IV per value: reusing one is what broke the previous scheme.
    final iv = IV.fromSecureRandom(_ivLength);
    final encrypted = _encrypter.encrypt(value, iv: iv);

    return '$_v2Prefix${base64.encode([...iv.bytes, ...encrypted.bytes])}';
  }
}

class EncryptedTextConverter extends TypeConverter<DecryptedText, String> {
  @override
  DecryptedText fromSql(String fromDb) {
    return DecryptedText.decrypted(fromDb);
  }

  @override
  String toSql(DecryptedText value) {
    return value.encrypt();
  }
}
