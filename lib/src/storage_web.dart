// Web-specific storage implementation using package:web
import 'dart:convert';
import 'dart:js_interop';

@JS('window.localStorage')
external JSObject get _localStorage;

extension LocalStorageExtension on JSObject {
  external String? getItem(String key);

  external void setItem(String key, String value);
}

Future<String?> loadSetting(String key) async {
  // prefer the simple top-level key
  final v = _localStorage.getItem(key);
  if (v != null && v.isNotEmpty) return v;

  // fallback: try the SharedPreferences blob
  try {
    final prefsRaw = _localStorage.getItem('flutter.SharedPreferences');
    if (prefsRaw != null && prefsRaw.isNotEmpty) {
      final Map<String, dynamic> prefs = json.decode(prefsRaw) as Map<String, dynamic>;
      final stored = prefs[key];
      if (stored is String && stored.isNotEmpty) return stored;
    }
  } catch (e) {
    // ignore
  }
  return null;
}

Future<void> saveSetting(String key, String value) async {
  // write simple top-level key
  _localStorage.setItem(key, value);
  // also update SharedPreferences blob
  try {
    final prefsRaw = _localStorage.getItem('flutter.SharedPreferences');
    Map<String, dynamic> prefs = {};
    if (prefsRaw != null && prefsRaw.isNotEmpty) {
      prefs = json.decode(prefsRaw) as Map<String, dynamic>;
    }
    prefs[key] = value;
    _localStorage.setItem('flutter.SharedPreferences', json.encode(prefs));
  } catch (e) {
    // ignore
  }
}
