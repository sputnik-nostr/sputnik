import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/keys.dart';
import 'package:sputnik/nostr/models/nostr_event.dart';

void main() {
  // A fresh, throwaway keypair generated for this test run only -- never a
  // real saved identity.
  final keypair = generateNostrKeyPair();

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
}
