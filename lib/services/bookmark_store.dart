import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/note.dart';

/// Bookmarks are user data, so they live apart from the prunable relay cache.
class BookmarkStore {
  BookmarkStore._();

  /// Where earlier versions kept every bookmark, as one JSON object.
  static const _legacyKey = 'bookmarked_notes';

  static Box<String>? _box;

  /// IDs last loaded or saved, so an unreadable entry is never deleted.
  static final _known = <String>{};

  static Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/bookmarks').create(recursive: true);
  }

  static Future<Box<String>> _open(Directory? directory) async {
    return _box ??= await Hive.openBox<String>(
      'bookmarks',
      path: (directory ?? await _directory()).path,
    );
  }

  /// Every readable bookmark, after moving over any kept by an older version.
  static Future<Map<String, Note>> load({
    @visibleForTesting Directory? directory,
  }) async {
    final box = await _open(directory);
    await _migrateLegacy(box);

    final notes = <String, Note>{};
    for (final key in box.keys) {
      try {
        final json = jsonDecode(box.get(key)!) as Map<String, dynamic>;
        notes[key as String] = Note.fromJson(json);
      } catch (_) {
        // Left in the box as it is, in case a later version can read it.
      }
    }
    _known
      ..clear()
      ..addAll(notes.keys);
    return notes;
  }

  /// Writes only what changed since the last load or save.
  static Future<void> save(Map<String, Note> notes) async {
    final box = await _open(null);
    final removed = _known.difference(notes.keys.toSet());
    final added = {
      for (final entry in notes.entries)
        if (!_known.contains(entry.key))
          entry.key: jsonEncode(entry.value.toJson()),
    };
    await box.deleteAll(removed);
    await box.putAll(added);
    _known
      ..removeAll(removed)
      ..addAll(added.keys);
  }

  /// Imports the old single-blob bookmarks once, then forgets them.
  static Future<void> _migrateLegacy(Box<String> box) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_legacyKey);
    if (raw == null) return;

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // Unparseable as a whole: keep it, since nothing else holds the data.
      return;
    }

    final imported = <String, String>{};
    final unreadable = <String, dynamic>{};
    for (final entry in decoded.entries) {
      try {
        final note = Note.fromJson(entry.value as Map<String, dynamic>);
        if (!box.containsKey(entry.key)) {
          imported[entry.key] = jsonEncode(note.toJson());
        }
      } catch (_) {
        unreadable[entry.key] = entry.value;
      }
    }
    await box.putAll(imported);

    // Anything left behind must not bring back a bookmark removed later.
    if (unreadable.isEmpty) {
      await prefs.remove(_legacyKey);
    } else {
      await prefs.setString(_legacyKey, jsonEncode(unreadable));
    }
  }

  @visibleForTesting
  static Future<void> close() async {
    await _box?.close();
    _box = null;
    _known.clear();
  }
}
