import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_seed_color.dart';
import '../models/note.dart';
import '../models/relay.dart';

// Loads a notifier's persisted value and wires it to save on every change.
// Used to bind each of the app's settings notifiers without repeating the
// "load, assign, add a saving listener" sequence for each one.
Future<void> bindPersisted<T>(
  ValueNotifier<T> notifier,
  Future<T> Function() load,
  Future<void> Function(T value) save,
) async {
  notifier.value = await load();
  notifier.addListener(() => save(notifier.value));
}

class SettingsStore {
  SettingsStore._();

  static const _themeModeKey = 'theme_mode';
  static const _seedColorKey = 'seed_color';
  static const _bookmarkedNotesKey = 'bookmarked_notes';
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

  static Future<Map<String, Note>> loadBookmarkedNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_bookmarkedNotesKey);
    if (raw == null) return {};

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          entry.key: Note.fromJson(entry.value as Map<String, dynamic>),
      };
    } catch (_) {
      // Cached bookmark data is malformed; start with an empty set.
      return {};
    }
  }

  static Future<void> saveBookmarkedNotes(Map<String, Note> notes) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = {
      for (final entry in notes.entries) entry.key: entry.value.toJson(),
    };
    await prefs.setString(_bookmarkedNotesKey, jsonEncode(encoded));
  }

  static Future<Set<String>> loadSelectedRelays() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_selectedRelaysKey);
    if (saved == null) return defaultRelays.toSet();

    final stillKnown = saved.toSet().intersection(defaultRelays.toSet());
    if (stillKnown.isEmpty) {
      await saveSelectedRelays(defaultRelays.toSet());
      return defaultRelays.toSet();
    }
    return stillKnown;
  }

  static Future<void> saveSelectedRelays(Set<String> relays) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_selectedRelaysKey, relays.toList());
  }
}
