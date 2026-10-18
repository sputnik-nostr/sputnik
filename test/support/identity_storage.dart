import 'dart:convert';

import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/identity_index.dart';
import 'package:sputnik/nostr/nostr.dart';

/// An identity and its real private key.
typedef HeldIdentity = ({Identity identity, String privkeyHex});

HeldIdentity newHeldIdentity() {
  final keyPair = generateNostrKeyPair();
  return (
    identity: Identity(pubkeyHex: keyPair.publicKeyHex, createdAt: DateTime(1)),
    privkeyHex: keyPair.privateKeyHex,
  );
}

extension HeldIdentityPubkey on HeldIdentity {
  String get pubkeyHex => identity.pubkeyHex;
}

/// Secure storage as this version leaves it: every key in a slot of its own,
/// named by the index.
Map<String, String> currentStorage(List<HeldIdentity> held, {String? active}) {
  var index = IdentityIndex.empty;
  for (var i = 0; i < held.length; i++) {
    index = index.withIdentity(held[i].identity, slot: 'slot$i');
  }
  return {
    'identities': index.withActive(active).encode(),
    for (var i = 0; i < held.length; i++)
      'identity_secret_slot$i': held[i].privkeyHex,
  };
}

/// Secure storage as versions before slots left it: a bare list for an index,
/// and each key in an entry named after its pubkey.
Map<String, String> legacyStorage(List<HeldIdentity> held) => {
  'identities': jsonEncode([for (final h in held) h.identity.toJson()]),
  for (final h in held) 'identity_secret_${h.pubkeyHex}': h.privkeyHex,
};

/// Secure storage as the versions that kept each key inside the index left it.
Map<String, String> inlineStorage(List<HeldIdentity> held) => {
  'identities': jsonEncode([
    for (final h in held) {...h.identity.toJson(), 'privkeyHex': h.privkeyHex},
  ]),
};

/// The index in [storage], as the next start finds it.
IdentityIndex storedIndex(Map<String, String> storage) =>
    IdentityIndex.parse(storage['identities']!);

/// Whether [value] is stored anywhere in [storage], under any name.
bool isStored(Map<String, String> storage, String value) =>
    storage.values.any((stored) => stored.contains(value));
