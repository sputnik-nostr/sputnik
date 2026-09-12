import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/models/nostr_event.dart';

const _pubkey =
    'f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9';
const _id = '5ce1d827a8c89d926b6fb5668cc7d0eb33bda4821ff2cdb14d5c58b9797a8bd4';
const _sig =
    '4d88c14a099ab5cead3e07d86e573425d8d1187cdc83cb6925c73ef64eb195b9'
    '84e63519b0f27f8380efa28675441a616f4f4f2c53b6fd98f7f863ac3f5fcebc';
const _content = 'hello from a golden fixture';

Map<String, dynamic> _golden() => jsonDecode(
  jsonEncode({
    'id': _id,
    'pubkey': _pubkey,
    'created_at': 1700000000,
    'kind': 1,
    'tags': [
      ['e', 'a' * 64],
      ['p', 'b' * 64],
    ],
    'content': _content,
    'sig': _sig,
  }),
) as Map<String, dynamic>;

void main() {
  test('accepts a correctly signed event', () {
    final event = NostrEvent.fromJson(_golden());

    expect(event.id, _id);
    expect(event.pubkey, _pubkey);
    expect(event.kind, 1);
    expect(event.content, _content);
    expect(event.sig, _sig);
    expect(
      event.createdAt,
      DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
    );
    expect(event.tags, [
      ['e', 'a' * 64],
      ['p', 'b' * 64],
    ]);
  });

  test('rejects tampered content', () {
    final json = _golden()..['content'] = 'hello from a golden fixturE';

    expect(() => NostrEvent.fromJson(json), throwsFormatException);
  });

  test('rejects a tampered signature', () {
    final json = _golden()..['sig'] = 'f${_sig.substring(1)}';

    expect(() => NostrEvent.fromJson(json), throwsFormatException);
  });

  test('rejects a substituted pubkey', () {
    final json = _golden()..['pubkey'] = 'd' * 64;

    expect(() => NostrEvent.fromJson(json), throwsFormatException);
  });

  test('rejects a tampered created_at', () {
    final json = _golden()..['created_at'] = 1700000001;

    expect(() => NostrEvent.fromJson(json), throwsFormatException);
  });

  test('rejects tampered tags', () {
    final json = _golden()
      ..['tags'] = [
        ['e', 'c' * 64],
      ];

    expect(() => NostrEvent.fromJson(json), throwsFormatException);
  });

  test('rejects forged content whose id was recomputed to match', () {
    final json = _golden()
      ..['content'] = 'hello from a FORGED fixture'
      ..['id'] =
          '42770d73a82659ca564bb2f2c0791049e74a3536806f526c0fc8d73ad77b5eff';

    expect(() => NostrEvent.fromJson(json), throwsFormatException);
  });

  test('rejects an id that is not the hash of the event', () {
    final json = _golden()..['id'] = 'e' * 64;

    expect(() => NostrEvent.fromJson(json), throwsFormatException);
  });

  test('rejects a tampered kind', () {
    final json = _golden()..['kind'] = 7;

    expect(() => NostrEvent.fromJson(json), throwsFormatException);
  });

  test('rejects an event signed by a key other than its pubkey', () {
    final json = _golden()
      ..['pubkey'] =
          'e493dbf1c10d80f3581e4904930b1404cc6c13900ee0758474fa94abe8c4cd13'
      ..['id'] =
          '179fcace1056f67d66e67c367982e1608ac699c7444ccf02ddca271f6ea04574'
      ..['sig'] =
          '9583fd3e1c375411c80d21e03ed56f44d4cf63623db7ad893108ae227de91e18'
          'e695bc2baaf103892a2ebb11de843af24f9e140031b1e329b11fe0cf85e0004a';

    expect(() => NostrEvent.fromJson(json), throwsFormatException);
  });
}
