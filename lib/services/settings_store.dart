import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_seed_color.dart';
import '../models/relay.dart';

class SettingsStore {
  SettingsStore._();

  static const _themeModeKey = 'theme_mode';
  static const _seedColorKey = 'seed_color';
  static const _bookmarkedIdsKey = 'bookmarked_ids';
  static const _selectedRelaysKey = 'selected_relays';

  static Future<ThemeMode> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString(_themeModeKey)) {
      'dark' => ThemeMode.dark,
      _ => ThemeMode.light,
    };
  }

  static Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _themeModeKey,
      mode == ThemeMode.dark ? 'dark' : 'light',
    );
  }

  static Future<AppSeedColor> loadSeedColor() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_seedColorKey);
    return AppSeedColor.values.firstWhere(
      (color) => color.name == name,
      orElse: () => AppSeedColor.blue,
    );
  }

  static Future<void> saveSeedColor(AppSeedColor color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_seedColorKey, color.name);
  }

  static Future<Set<String>> loadBookmarkedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_bookmarkedIdsKey) ?? const []).toSet();
  }

  static Future<void> saveBookmarkedIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_bookmarkedIdsKey, ids.toList());
  }

  static Future<Set<String>> loadSelectedRelays() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_selectedRelaysKey);
    if (saved == null) return dummyRelays.toSet();
    return saved.toSet();
  }

  static Future<void> saveSelectedRelays(Set<String> relays) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_selectedRelaysKey, relays.toList());
  }
}
