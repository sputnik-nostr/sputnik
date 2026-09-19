import 'dart:convert';

import 'package:crypto/crypto.dart';
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

  test(
    'serializes only the NIP-01 escapes; other characters stay verbatim',
    () {
      final event = signEvent(
        seckeyHex: keypair.privateKeyHex,
        pubkeyHex: keypair.publicKeyHex,
        kind: 1,
        tags: [
          ['t', 'x\u0001y'],
        ],
        content: 'a\u0001b\u001fc\u007fd\ne\tf\\"g\u2028',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
      );

      // Written out by hand from the NIP-01 rules, not via jsonEncode.
      final expected =
          '[0,"${keypair.publicKeyHex}",1700000000,1,[["t","x\u0001y"]],'
          '"a\u0001b\u001fc\u007fd'
          r'\n'
          'e'
          r'\t'
          'f'
          r'\\'
          r'\"'
          'g\u2028"]';
      expect(event.id, sha256.convert(utf8.encode(expected)).toString());
      expect(NostrEvent.fromJson(event.toJson()).content, event.content);
    },
  );
}
