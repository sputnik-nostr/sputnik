import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/keys.dart';
import 'package:sputnik/nostr/models/nostr_event.dart';

void main() {
  // A fresh, throwaway keypair generated for this test run only -- never a
  // real saved identity.
  final keypair = generateNostrKeyPair();

  test('a signed event verifies through the same path a relay event does', () {
    final event = signEvent(
      seckeyHex: keypair.privateKeyHex,
      pubkeyHex: keypair.publicKeyHex,
      kind: 1,
      content: 'hello from a test',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
    );

    final roundTripped = NostrEvent.fromJson(event.toJson());

    expect(roundTripped.id, event.id);
    expect(roundTripped.pubkey, keypair.publicKeyHex);
    expect(roundTripped.kind, 1);
    expect(roundTripped.content, 'hello from a test');
    expect(roundTripped.sig, event.sig);
  });

  test('toJson round-trips tags and created_at exactly', () {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(1700000042 * 1000);
    final event = signEvent(
      seckeyHex: keypair.privateKeyHex,
      pubkeyHex: keypair.publicKeyHex,
      kind: 1,
      tags: [
        ['e', 'a' * 64],
        ['p', 'b' * 64],
      ],
      content: 'with tags',
      createdAt: createdAt,
    );

    final json = event.toJson();
    expect(json['created_at'], 1700000042);
    expect(json['tags'], [
      ['e', 'a' * 64],
      ['p', 'b' * 64],
    ]);

    final roundTripped = NostrEvent.fromJson(json);
    expect(roundTripped.tags, [
      ['e', 'a' * 64],
      ['p', 'b' * 64],
    ]);
  });

  test('signing with a different key changes the signature', () {
    final other = generateNostrKeyPair();

    final event = signEvent(
      seckeyHex: keypair.privateKeyHex,
      pubkeyHex: keypair.publicKeyHex,
      kind: 1,
      content: 'same content',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
    );
    final otherEvent = signEvent(
      seckeyHex: other.privateKeyHex,
      pubkeyHex: other.publicKeyHex,
      kind: 1,
      content: 'same content',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
    );

    // Same content/kind/created_at but a different pubkey means a
    // different id (pubkey is part of the hashed serialization) and sig.
    expect(otherEvent.id, isNot(event.id));
    expect(otherEvent.sig, isNot(event.sig));
  });
}
