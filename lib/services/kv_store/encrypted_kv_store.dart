import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openmusic/services/kv_store/kv_store.dart';
import 'package:openmusic/services/logger/logger.dart';
import 'package:openmusic/utils/platform.dart';

abstract class EncryptedKvStoreService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    // The data-protection keychain requires a `keychain-access-groups`
    // entitlement, which needs a real signing team. Spotube ships ad-hoc
    // signed, so asking for it fails with errSecMissingEntitlement (-34018)
    // and drops the key into the plaintext fallback -- i.e. the exact outcome
    // moving macOS onto the Keychain was meant to avoid. The file-based
    // keychain needs no entitlement and works on an unsigned build.
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  static FlutterSecureStorage get storage => _storage;

  static const _keyName = 'encryption_v2';

  static String? _encryptionKeySync;
  static String? _legacyEncryptionKeySync;
  static bool _usingPlaintextFallback = false;

  static Future<void> initialize() async {
    _encryptionKeySync = await _loadOrCreateKey();
    // Read-only, for decrypting values written before AES-GCM. Absent on a
    // fresh install, which is fine -- there is nothing old to decrypt.
    _legacyEncryptionKeySync = await _loadLegacyKey();
  }

  /// Base64 of 32 random bytes, suitable for `Key.fromBase64`.
  static String get encryptionKeySync => _encryptionKeySync!;

  /// The UUID-string key used by the legacy Salsa20 scheme, or null when no
  /// legacy key was ever stored.
  static String? get legacyEncryptionKeySyncOrNull => _legacyEncryptionKeySync;

  static String get legacyEncryptionKeySync {
    final key = _legacyEncryptionKeySync;
    if (key == null) {
      throw StateError('No legacy encryption key is available.');
    }
    return key;
  }

  /// True when the key could not be placed in platform secure storage and is
  /// sitting in plaintext SharedPreferences instead. Surface this in settings
  /// rather than letting it pass silently.
  static bool get isUsingPlaintextFallback => _usingPlaintextFallback;

  /// Only non-Flatpak Linux lacks a usable secret service here. macOS and iOS
  /// were previously excluded too, which put the key in plaintext on exactly
  /// the platforms whose Keychain works perfectly well.
  static bool get isUnsupportedPlatform => kIsLinux && !kIsFlatpak;

  static String _generateKey() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    return base64.encode(bytes);
  }

  static Future<String> _loadOrCreateKey() async {
    if (isUnsupportedPlatform) {
      _usingPlaintextFallback = true;
      return _loadOrCreateFallbackKey();
    }

    try {
      final existing = await _storage.read(key: _keyName);
      if (existing != null) return existing;

      // Secure storage holds nothing, but an earlier run may have been pushed
      // into the plaintext fallback -- an ad-hoc macOS build that could not
      // reach the Keychain, say. Anything already at rest is encrypted under
      // that key, so adopt it and promote it rather than minting a new one and
      // orphaning every value it protects.
      final orphaned = KVStoreService.sharedPreferences.getString(_keyName);
      final key = orphaned ?? _generateKey();

      await _storage.write(key: _keyName, value: key);
      // Only once the write succeeded, so a failure here still leaves the
      // fallback readable on the next launch.
      await KVStoreService.sharedPreferences.remove(_keyName);
      return key;
    } catch (error, stackTrace) {
      // Do not fail silently: losing secure storage means the key lands in
      // plaintext, which the user deserves to be able to see.
      AppLogger.reportError(error, stackTrace);
      _usingPlaintextFallback = true;
      return _loadOrCreateFallbackKey();
    }
  }

  static Future<String> _loadOrCreateFallbackKey() async {
    final existing = KVStoreService.sharedPreferences.getString(_keyName);
    if (existing != null) return existing;

    final key = _generateKey();
    // Awaited, unlike the previous implementation, which returned a key before
    // persisting it and could hand out one value while storing another.
    await KVStoreService.sharedPreferences.setString(_keyName, key);
    return key;
  }

  static Future<String?> _loadLegacyKey() async {
    try {
      final stored = await _storage.read(key: 'encryption');
      if (stored != null) return stored;
    } catch (error, stackTrace) {
      AppLogger.reportError(error, stackTrace);
    }

    return KVStoreService.sharedPreferences.getString('encryption');
  }

  /// Removes legacy key material once nothing is encrypted with it.
  static Future<void> discardLegacyKey() async {
    try {
      await _storage.delete(key: 'encryption');
    } catch (error, stackTrace) {
      AppLogger.reportError(error, stackTrace);
    }
    await KVStoreService.sharedPreferences.remove('encryption');
    await KVStoreService.sharedPreferences.remove('iv');
    _legacyEncryptionKeySync = null;
  }
}
