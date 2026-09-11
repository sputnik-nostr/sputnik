import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../nostr/models/nostr_metadata.dart';
import '../nostr/models/nostr_payment_target.dart';

/// Local Hive-backed cache for data fetched from relays. Each entry is
/// stored with a fetch timestamp so callers can decide whether it's fresh
/// enough to skip a relay round-trip.
class CacheStore {
  CacheStore._();

  static const staleAfter = Duration(hours: 1);

  static late final Box<Map> _profiles;
  static late final Box<Map> _contacts;
  static late final Box<Map> _paymentTargets;

  static bool _ready = false;

  static Future<void> init() async {
    try {
      await Hive.initFlutter();
      final boxes = await Future.wait([
        Hive.openBox<Map>('profiles'),
        Hive.openBox<Map>('contacts'),
        Hive.openBox<Map>('paymentTargets'),
      ]);
      _profiles = boxes[0];
      _contacts = boxes[1];
      _paymentTargets = boxes[2];
      _ready = true;
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

  static bool _isFresh(int? fetchedAtMillis) {
    if (fetchedAtMillis == null) return false;
    final fetchedAt = DateTime.fromMillisecondsSinceEpoch(fetchedAtMillis);
    return DateTime.now().difference(fetchedAt) < staleAfter;
  }

  // --- Profiles (kind 0) ---

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

  static Future<void> clearProfiles() async {
    if (!_ready) return;
    await _profiles.clear();
  }

  // --- Contacts (kind 3 following/followers) ---

  static List<String>? getFollowing(String pubkeyHex) =>
      _getList('$pubkeyHex:following');

  static List<String>? getFollowers(String pubkeyHex) =>
      _getList('$pubkeyHex:followers');

  static bool isFollowingFresh(String pubkeyHex) =>
      _ready &&
      _isFresh(_contacts.get('$pubkeyHex:following')?['fetchedAt'] as int?);

  static bool isFollowersFresh(String pubkeyHex) =>
      _ready &&
      _isFresh(_contacts.get('$pubkeyHex:followers')?['fetchedAt'] as int?);

  static Future<void> putFollowing(String pubkeyHex, List<String> pubkeys) =>
      _putList('$pubkeyHex:following', pubkeys);

  static Future<void> putFollowers(String pubkeyHex, List<String> pubkeys) =>
      _putList('$pubkeyHex:followers', pubkeys);

  static List<String>? _getList(String key) {
    if (!_ready) return null;
    final entry = _contacts.get(key);
    if (entry == null) return null;
    return List<String>.from(entry['pubkeys'] as List? ?? const []);
  }

  static Future<void> _putList(String key, List<String> pubkeys) {
    if (!_ready) return Future.value();
    return _contacts.put(key, {
      'pubkeys': pubkeys,
      'fetchedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // --- Payment targets (kind 10133) ---

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
