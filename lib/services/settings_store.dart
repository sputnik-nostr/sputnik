import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_seed_color.dart';

class SettingsStore {
  SettingsStore._();

  static const _themeModeKey = 'theme_mode';
  static const _seedColorKey = 'seed_color';

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
}
