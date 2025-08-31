// Web-specific storage implementation using package:web
import 'dart:convert';
import 'dart:js_interop';

@JS('window.localStorage')
external JSObject get _localStorage;

extension LocalStorageExtension on JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
}

Future<void> saveEndpoint(String key, String value) async {
  // write a simple top-level key so it's easy to inspect in DevTools
  _localStorage.setItem(key, value);

  // Also update the SharedPreferences blob stored under 'flutter.SharedPreferences'
  // so other code that inspects SharedPreferences on web will see the saved value.
  try {
    final prefsRaw = _localStorage.getItem('flutter.SharedPreferences');
    Map<String, dynamic> prefs = {};
    if (prefsRaw != null && prefsRaw.isNotEmpty) {
      prefs = json.decode(prefsRaw) as Map<String, dynamic>;
    }
    prefs[key] = value;
    _localStorage.setItem('flutter.SharedPreferences', json.encode(prefs));
  } catch (e) {
    // ignore errors writing SharedPreferences blob
  }
}

Future<String?> loadEndpoint(String key) async {
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

Future<void> saveTheme(String key, String value) async {
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

Future<String?> loadTheme(String key) async {
  final v = _localStorage.getItem(key);
  if (v != null && v.isNotEmpty) return v;
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
