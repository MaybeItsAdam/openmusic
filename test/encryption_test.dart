import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the wire format implemented by `DecryptedText`.
///
/// `DecryptedText` is a `part of` the drift database library and reaches into
/// `EncryptedKvStoreService`, which needs platform channels. These tests cover
/// the cryptographic properties directly so the guarantees that matter --
/// per-value IVs, authentication, and legacy readability -- are actually
/// pinned rather than assumed.
const _v2Prefix = 'v2:';
const _ivLength = 12;

String _generateKey() {
  final random = Random.secure();
  return base64.encode(
    Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256))),
  );
}

Encrypter _encrypterFor(String key) =>
    Encrypter(AES(Key.fromBase64(key), mode: AESMode.gcm));

String _encrypt(String key, String value) {
  final iv = IV.fromSecureRandom(_ivLength);
  final encrypted = _encrypterFor(key).encrypt(value, iv: iv);
  return '$_v2Prefix${base64.encode([...iv.bytes, ...encrypted.bytes])}';
}

String _decrypt(String key, String stored) {
  final raw = base64.decode(stored.substring(_v2Prefix.length));
  return _encrypterFor(key).decrypt(
    Encrypted(Uint8List.sublistView(raw, _ivLength)),
    iv: IV(Uint8List.sublistView(raw, 0, _ivLength)),
  );
}

void main() {
  group('AES-GCM at-rest format', () {
    test('round-trips a value', () {
      final key = _generateKey();
      const secret = 'd41d8cd98f00b204e9800998ecf8427e';

      expect(_decrypt(key, _encrypt(key, secret)), secret);
    });

    test('encrypting the same value twice yields different ciphertext', () {
      final key = _generateKey();
      const secret = 'identical plaintext';

      final first = _encrypt(key, secret);
      final second = _encrypt(key, secret);

      // The whole point of the change: the old scheme reused one IV forever,
      // so identical plaintexts produced identical ciphertext and XORing two
      // records leaked their plaintexts.
      expect(first, isNot(second));
      expect(_decrypt(key, first), secret);
      expect(_decrypt(key, second), secret);
    });

    test('tampered ciphertext is rejected rather than silently mangled', () {
      final key = _generateKey();
      final stored = _encrypt(key, 'sensitive');

      final raw = base64.decode(stored.substring(_v2Prefix.length));
      raw[raw.length - 1] ^= 0xFF; // flip bits in the GCM tag
      final tampered = '$_v2Prefix${base64.encode(raw)}';

      expect(() => _decrypt(key, tampered), throwsA(anything));
    });

    test('a different key cannot decrypt', () {
      final stored = _encrypt(_generateKey(), 'sensitive');

      expect(() => _decrypt(_generateKey(), stored), throwsA(anything));
    });

    test('written values carry the v2 prefix so reads can dispatch', () {
      final stored = _encrypt(_generateKey(), 'value');

      expect(stored.startsWith(_v2Prefix), isTrue);
    });
  });

  group('legacy Salsa20 format', () {
    test('remains readable, so stored credentials survive the upgrade', () {
      // A UUID-shaped key and 8-byte IV, exactly as the old scheme stored them.
      const legacyKey = '3f2504e0-4f89-11d3-9a0c-0305e82c3301';
      final legacyIv = IV.fromBase64(base64.encode(List.filled(8, 7)));
      const secret = 'legacy-password-hash';

      final legacy = Encrypter(Salsa20(Key.fromUtf8(legacyKey)));
      final stored = legacy.encrypt(secret, iv: legacyIv).base64;

      expect(stored.startsWith(_v2Prefix), isFalse,
          reason: 'legacy values must not be mistaken for the new format');
      expect(
        legacy.decrypt(Encrypted.fromBase64(stored), iv: legacyIv),
        secret,
      );
    });
  });
}
