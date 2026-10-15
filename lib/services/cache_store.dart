import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../nostr/models/nostr_metadata.dart';
import '../nostr/models/nostr_payment_target.dart';

/// Relay data with fetch times, so a fresh entry can skip a relay round trip.
class CacheStore {
  CacheStore._();

  static const staleAfter = Duration(hours: 1);

  /// Entries not refreshed within this long are dropped when the cache opens.
  static const maxAge = Duration(days: 30);

  static late final Box<Map> _profiles;
  static late final Box<Map> _paymentTargets;

  /// Memory only: follow lists on disk would hint at whose profiles were
  /// viewed.
  static final _contacts = <String, ({List<String> pubkeys, int fetchedAt})>{};

  static bool _ready = false;

  /// Not the documents folder, which is user-visible and often synced.
  static Future<Directory> _cacheDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/relay_cache').create(recursive: true);
  }

  static Future<void> init({@visibleForTesting Directory? directory}) async {
    try {
      Hive.init((directory ?? await _cacheDirectory()).path);
      final boxes = await Future.wait([
        Hive.openBox<Map>('profiles'),
        Hive.openBox<Map>('paymentTargets'),
      ]);
      _profiles = boxes[0];
      _paymentTargets = boxes[1];
      _ready = true;
      await Future.wait([
        ...boxes.map(pruneExpired),
        // Left behind by versions that kept follow lists on disk.
        Hive.deleteBoxFromDisk('contacts'),
      ]);
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'sputnik',
          context: ErrorDescription('opening the relay data cache'),
        ),
      );
    }
  }

  /// Deletes entries whose `fetchedAt` is older than [maxAge].
  @visibleForTesting
  static Future<void> pruneExpired(Box<Map> box, {DateTime? now}) {
    final cutoff = (now ?? DateTime.now())
        .subtract(maxAge)
        .millisecondsSinceEpoch;
    return box.deleteAll([
      for (final key in box.keys)
        if (((box.get(key)?['fetchedAt'] as int?) ?? 0) < cutoff) key,
    ]);
  }

  static bool _isFresh(int? fetchedAtMillis) {
    if (fetchedAtMillis == null) return false;
    final fetchedAt = DateTime.fromMillisecondsSinceEpoch(fetchedAtMillis);
    return DateTime.now().difference(fetchedAt) < staleAfter;
  }

  static Map<String, NostrMetadata> loadAllProfiles() {
    if (!_ready) return const <String, NostrMetadata>{};
    final result = <String, NostrMetadata>{};
    for (final key in _profiles.keys) {
      final data = _profiles.get(key)?['data'];
      if (data == null) continue;
      try {
        result[key as String] = NostrMetadata.fromJson(
          Map<String, dynamic>.from(data as Map),
        );
      } catch (_) {
        // Skip malformed cache entries.
      }
    }
    return result;
  }

  static bool isProfileFresh(String pubkeyHex) {
    if (!_ready) return false;
    return _isFresh(_profiles.get(pubkeyHex)?['fetchedAt'] as int?);
  }

  static Future<void> putProfiles(Map<String, NostrMetadata> profiles) async {
    if (!_ready) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _profiles.putAll({
      for (final entry in profiles.entries)
        entry.key: {'data': entry.value.toJson(), 'fetchedAt': now},
    });
  }

  /// Empties every cache, including the follow lists that hint at who was
  /// viewed.
  static Future<void> clearAll() async {
    _contacts.clear();
    if (!_ready) return;
    await Future.wait([_profiles.clear(), _paymentTargets.clear()]);
  }

  static List<String>? getFollowing(String pubkeyHex) =>
      _getList('$pubkeyHex:following');

  static List<String>? getFollowers(String pubkeyHex) =>
      _getList('$pubkeyHex:followers');

  static bool isFollowingFresh(String pubkeyHex) =>
      _isFresh(_contacts['$pubkeyHex:following']?.fetchedAt);

  static bool isFollowersFresh(String pubkeyHex) =>
      _isFresh(_contacts['$pubkeyHex:followers']?.fetchedAt);

  static void putFollowing(String pubkeyHex, List<String> pubkeys) =>
      _putList('$pubkeyHex:following', pubkeys);

  static void putFollowers(String pubkeyHex, List<String> pubkeys) =>
      _putList('$pubkeyHex:followers', pubkeys);

  static List<String>? _getList(String key) {
    final pubkeys = _contacts[key]?.pubkeys;
    return pubkeys == null ? null : List.of(pubkeys);
  }

  static void _putList(String key, List<String> pubkeys) {
    // Stale lists are never read, so dropping them bounds memory.
    _contacts.removeWhere((_, entry) => !_isFresh(entry.fetchedAt));
    _contacts[key] = (
      pubkeys: List.unmodifiable(pubkeys),
      fetchedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static List<NostrPaymentTarget>? getPaymentTargets(String pubkeyHex) {
    if (!_ready) return null;
    final data = _paymentTargets.get(pubkeyHex)?['data'] as List?;
    if (data == null) return null;
    return [
      for (final item in data)
        NostrPaymentTarget.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  static bool isPaymentTargetsFresh(String pubkeyHex) {
    if (!_ready) return false;
    return _isFresh(_paymentTargets.get(pubkeyHex)?['fetchedAt'] as int?);
  }

  static Future<void> putPaymentTargets(
    String pubkeyHex,
    List<NostrPaymentTarget> targets,
  ) {
    if (!_ready) return Future.value();
    return _paymentTargets.put(pubkeyHex, {
      'data': [for (final target in targets) target.toJson()],
      'fetchedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
