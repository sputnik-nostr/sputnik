import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/models/nostr_event.dart';

const _signedWithAnOddTag = r'''
{"id":"f4266610520f197e532288d753da1fa2aafc63c4890c8d0b091ad985f68afe7e","pubkey":"f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9","created_at":1700000000,"kind":1,"tags":[["e","aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],["expiration",1700000000]],"content":"tolerates an odd tag","sig":"3c261831e330a76634eb915d2343f6877c3d2e6eb5e7a67d3b44bc4b7063ba7a845ce4f7039d333d2cc3fc2565cc517dacc3d0f3aed6538c648b8b7d3912aa30"}
''';

void main() {
  test('keeps an authentic event whose tags include a non-string value', () {
    final json = jsonDecode(_signedWithAnOddTag) as Map<String, dynamic>;

    final event = NostrEvent.fromJson(json);

    expect(event.content, 'tolerates an odd tag');
    expect(event.tags, [
      ['e', 'a' * 64],
    ]);
  });
}
