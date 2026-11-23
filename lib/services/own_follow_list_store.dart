import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../nostr/hex.dart';
import '../nostr/nostr.dart';

/// Keeps [seenOwnContactLists] across restarts. Per identity it holds only
/// when the follow list was made and how many people it held, never who they
/// were: follow lists stay off the disk.
class OwnFollowListStore {
  OwnFollowListStore._();

  static const _key = 'seen_own_follow_lists';

  /// Largest second count a [DateTime] can hold.
  static const _maxSeconds = 8640000000000;

  static Future<Map<String, OwnListSize>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final sizes = <String, OwnListSize>{};
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (!isHex(entry.key, 32) || value is! List || value.length != 2) {
        continue;
      }
      final [seconds, count] = value;
      if (seconds is! int || count is! int) continue;
      if (seconds < 0 || seconds > _maxSeconds || count < 0) continue;
      sizes[entry.key.toLowerCase()] = (
        createdAt: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
        count: count,
      );
    }
    return sizes;
  }

  static Future<void> save(Map<String, OwnListSize> sizes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        for (final entry in sizes.entries)
          entry.key: [
            entry.value.createdAt.millisecondsSinceEpoch ~/ 1000,
            entry.value.count,
          ],
      }),
    );
  }
}
