import 'package:shared_preferences/shared_preferences.dart';

Future<void> saveEndpoint(String key, String value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(key, value);
}

Future<String?> loadEndpoint(String key) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(key);
}

// Theme persistence helpers to match web API
Future<void> saveTheme(String key, String value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(key, value);
}

Future<String?> loadTheme(String key) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(key);
}
