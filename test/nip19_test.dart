import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nip19.dart';

void main() {
  const hex1 =
      '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';
  const npub1 =
      'npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6';
  const hex2 =
      '7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e';
  const npub2 =
      'npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg';

  test('encodes a hex pubkey to the matching npub', () {
    expect(npubFromHex(hex1), npub1);
    expect(npubFromHex(hex2), npub2);
  });

  test('decodes an npub to the matching hex pubkey', () {
    expect(hexFromNpub(npub1), hex1);
    expect(hexFromNpub(npub2), hex2);
  });

  test('rejects a non-npub bech32 string', () {
    expect(
      hexFromNpub(
        'nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5',
      ),
      isNull,
    );
  });

  test('rejects garbage input', () {
    expect(hexFromNpub('not a bech32 string'), isNull);
  });
}
