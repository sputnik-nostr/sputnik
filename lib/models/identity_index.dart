import 'dart:convert';

import 'identity.dart';

/// An identity whose private key may still be where an older version kept it:
/// inside its index entry ([inlineKey]), or in an entry named after its pubkey
/// because it has no [slot] yet.
typedef KeyToMove = ({String pubkeyHex, String? slot, String? inlineKey});

/// The identities this device holds, as kept in secure storage, and which of
/// them is active.
///
/// Each identity's private key lives in an entry of its own, named after the
/// identity's random [slotOf], so that entry names say nothing about whose key
/// they hold.
///
/// Entries stay the JSON they were read as, so a rewrite never drops what this
/// version cannot interpret: an entry it cannot parse, or a private key that
/// an older version stored inline and that has not been moved out yet.
class IdentityIndex {
  const IdentityIndex._(this._entries, [this.active]);

  static const empty = IdentityIndex._([]);

  static const _version = 2;

  /// Reads the current format and the bare list that older versions wrote.
  ///
  /// Throws [FormatException] for anything else, including an index from a
  /// newer version, which this one must not rewrite.
  factory IdentityIndex.parse(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is List<dynamic>) return IdentityIndex._(decoded);
    if (decoded is Map<String, dynamic> && decoded['version'] == _version) {
      final entries = decoded['identities'];
      final active = decoded['active'];
      if (entries is List<dynamic>) {
        return IdentityIndex._(entries, active is String ? active : null);
      }
    }
    throw const FormatException('unreadable identity index');
  }

  final List<Object?> _entries;

  /// The pubkey the user picked as the active identity, if any. It may name an
  /// identity that is gone: use [activePubkey].
  final String? active;

  /// The identities this version can read, in the order they were added.
  List<Identity> get identities => [
    for (final entry in _entries) ?_identityOf(entry),
  ];

  /// The active identity: the one [active] names, or else the first one, as
  /// something is active whenever there are identities.
  String? get activePubkey {
    final pubkeyHex = active;
    if (pubkeyHex != null && identities.any((i) => i.pubkeyHex == pubkeyHex)) {
      return pubkeyHex;
    }
    return identities.isEmpty ? null : identities.first.pubkeyHex;
  }

  /// Whether an entry, even an unreadable one, names [pubkeyHex].
  bool contains(String pubkeyHex) =>
      _entries.any((entry) => _pubkeyOf(entry) == pubkeyHex);

  /// The name of the entry that holds the private key of [pubkeyHex], if it
  /// has been given one.
  String? slotOf(String pubkeyHex) {
    for (final entry in _entries) {
      if (_pubkeyOf(entry) != pubkeyHex) continue;
      final slot = (entry as Map<String, dynamic>)['slot'];
      if (slot is String) return slot;
    }
    return null;
  }

  /// Whether the index accounts for the key entry [name]: it is the slot of an
  /// identity, or it is named after the pubkey of one that has no slot yet.
  bool refersTo(String name) {
    for (final entry in _entries) {
      if (entry is! Map<String, dynamic>) continue;
      final slot = entry['slot'];
      if (slot is String ? slot == name : entry['pubkeyHex'] == name) {
        return true;
      }
    }
    return false;
  }

  /// Identities whose private key is not in a slot yet, or is still inline.
  Iterable<KeyToMove> get keysToMove sync* {
    for (final entry in _entries) {
      final identity = _identityOf(entry);
      if (identity == null) continue;
      final map = entry as Map<String, dynamic>;
      final slot = map['slot'];
      final inlineKey = map['privkeyHex'];
      if (slot is String && inlineKey is! String) continue;
      yield (
        pubkeyHex: identity.pubkeyHex,
        slot: slot is String ? slot : null,
        inlineKey: inlineKey is String ? inlineKey : null,
      );
    }
  }

  /// Lists [identity], whose private key is in [slot] if that is given.
  IdentityIndex withIdentity(Identity identity, {String? slot}) =>
      IdentityIndex._([
        ..._entries,
        {...identity.toJson(), 'slot': ?slot},
      ], active);

  /// Records that the private key of [pubkeyHex] is in [slot].
  IdentityIndex withSlot(String pubkeyHex, String slot) =>
      _withEntry(pubkeyHex, (entry) => {...entry, 'slot': slot});

  /// Drops the inline private key of [pubkeyHex], once it is stored elsewhere.
  IdentityIndex withoutInlineKey(String pubkeyHex) =>
      _withEntry(pubkeyHex, (entry) => {...entry}..remove('privkeyHex'));

  IdentityIndex withActive(String? pubkeyHex) =>
      IdentityIndex._(_entries, pubkeyHex);

  /// Unlists [pubkeyHex]; if it was the active identity, nothing is.
  IdentityIndex without(String pubkeyHex) => IdentityIndex._([
    for (final entry in _entries)
      if (_pubkeyOf(entry) != pubkeyHex) entry,
  ], active == pubkeyHex ? null : active);

  String encode() => jsonEncode({
    'version': _version,
    'identities': _entries,
    'active': ?active,
  });

  IdentityIndex _withEntry(
    String pubkeyHex,
    Map<String, dynamic> Function(Map<String, dynamic> entry) change,
  ) => IdentityIndex._([
    for (final entry in _entries)
      if (_identityOf(entry)?.pubkeyHex == pubkeyHex)
        change(entry as Map<String, dynamic>)
      else
        entry,
  ], active);

  static Identity? _identityOf(Object? entry) {
    try {
      return Identity.fromJson(entry as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static String? _pubkeyOf(Object? entry) {
    if (entry is! Map<String, dynamic>) return null;
    final pubkeyHex = entry['pubkeyHex'];
    return pubkeyHex is String ? pubkeyHex : null;
  }
}
