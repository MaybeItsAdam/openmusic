import 'package:hetu_spotube_plugin/hetu_spotube_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesLocalStorage implements Localstorage {
  final SharedPreferences _prefs;
  final String pluginSlug;

  SharedPreferencesLocalStorage(this._prefs, this.pluginSlug);

  String prefix(String key) {
    return 'spotube_plugin.$pluginSlug.$key';
  }

  @override
  Future<void> clear() async {
    // Every other method is namespaced to this plugin, but clear() used to call
    // _prefs.clear(), wiping all of SharedPreferences: other plugins' tokens
    // and, worse, KVStoreService's `encryption` and `iv` entries, which
    // permanently destroys the ability to decrypt stored credentials.
    final ownedKeys =
        _prefs.getKeys().where((key) => key.startsWith(prefix(""))).toList();

    for (final key in ownedKeys) {
      await _prefs.remove(key);
    }
  }

  @override
  Future<bool> containsKey(String key) async {
    return _prefs.containsKey(prefix(key));
  }

  @override
  Future<bool?> getBool(String key) async {
    return _prefs.getBool(prefix(key));
  }

  @override
  Future<double?> getDouble(String key) async {
    return _prefs.getDouble(prefix(key));
  }

  @override
  Future<int?> getInt(String key) async {
    return _prefs.getInt(prefix(key));
  }

  @override
  Future<String?> getString(String key) async {
    return _prefs.getString(prefix(key));
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    return _prefs.getStringList(prefix(key));
  }

  @override
  Future<void> remove(String key) async {
    await _prefs.remove(prefix(key));
  }

  @override
  Future<void> setBool(String key, bool value) async {
    await _prefs.setBool(prefix(key), value);
  }

  @override
  Future<void> setDouble(String key, double value) async {
    await _prefs.setDouble(prefix(key), value);
  }

  @override
  Future<void> setInt(String key, int value) async {
    await _prefs.setInt(prefix(key), value);
  }

  @override
  Future<void> setString(String key, String value) async {
    await _prefs.setString(prefix(key), value);
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    await _prefs.setStringList(prefix(key), value);
  }
}
