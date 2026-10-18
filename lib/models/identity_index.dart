import 'dart:convert';

import 'identity.dart';

/// The identities this device holds, as kept in secure storage.
///
/// Entries stay the JSON they were read as, so a rewrite never drops what this
/// version cannot interpret: an entry it cannot parse, or a private key that
/// an older version stored inline and that has not been moved out yet.
class IdentityIndex {
  const IdentityIndex._(this._entries);

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
      if (entries is List<dynamic>) return IdentityIndex._(entries);
    }
    throw const FormatException('unreadable identity index');
  }

  final List<Object?> _entries;

  /// The identities this version can read, in the order they were added.
  List<Identity> get identities => [
    for (final entry in _entries) ?_identityOf(entry),
  ];

  /// Whether an entry, even an unreadable one, names [pubkeyHex].
  bool contains(String pubkeyHex) =>
      _entries.any((entry) => _pubkeyOf(entry) == pubkeyHex);

  /// Private keys that an older version stored inside their identity entry.
  Iterable<({String pubkeyHex, String privkeyHex})> get inlineKeys sync* {
    for (final entry in _entries) {
      if (_identityOf(entry) == null) continue;
      final map = entry as Map<String, dynamic>;
      final privkeyHex = map['privkeyHex'];
      if (privkeyHex is String) {
        yield (pubkeyHex: map['pubkeyHex'] as String, privkeyHex: privkeyHex);
      }
    }
  }

  IdentityIndex withIdentity(Identity identity) =>
      IdentityIndex._([..._entries, identity.toJson()]);

  /// Drops the inline private key of [pubkeyHex], once it is stored elsewhere.
  IdentityIndex withoutInlineKey(String pubkeyHex) => IdentityIndex._([
    for (final entry in _entries)
      if (_identityOf(entry)?.pubkeyHex == pubkeyHex)
        Map<String, dynamic>.of(entry as Map<String, dynamic>)
          ..remove('privkeyHex')
      else
        entry,
  ]);

  IdentityIndex without(String pubkeyHex) => IdentityIndex._([
    for (final entry in _entries)
      if (_pubkeyOf(entry) != pubkeyHex) entry,
  ]);

  String encode() => jsonEncode({'version': _version, 'identities': _entries});

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
