import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/bech32.dart';
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

  test('encodes a hex seckey to the matching nsec', () {
    const seckeyHex =
        '67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa';
    const nsec =
        'nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5';
    expect(nsecFromHex(seckeyHex), nsec);
  });

  test('encodes and decodes a hex event id as note', () {
    final note = noteFromHex(hex1);
    expect(hexFromNote(note), hex1);
  });

  test('decodes an nprofile TLV payload to its pubkey', () {
    const nprofile =
        'nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p';
    expect(hexFromNprofile(nprofile), hex1);
  });

  test('decodes a nevent TLV payload to its event id', () {
    final data = <int>[0, hex1.length ~/ 2];
    final idBytes = [
      for (var i = 0; i < hex1.length; i += 2)
        int.parse(hex1.substring(i, i + 2), radix: 16),
    ];
    data.addAll(idBytes);
    final nevent = bech32Encode('nevent', convertBits(data, 8, 5, pad: true));
    expect(hexFromNevent(nevent), hex1);
  });

  test('decodeNostrUri resolves npub and nostr:npub the same way', () {
    expect(decodeNostrUri(npub1), (pubkeyHex: hex1, eventIdHex: null));
    expect(decodeNostrUri('nostr:$npub1'), (pubkeyHex: hex1, eventIdHex: null));
  });

  test('decodeNostrUri resolves a bare note to an event target', () {
    final note = noteFromHex(hex1);
    expect(decodeNostrUri(note), (pubkeyHex: null, eventIdHex: hex1));
  });

  test('decodeNostrUri returns null for unsupported entities', () {
    expect(
      decodeNostrUri(
        'nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5',
      ),
      isNull,
    );
    expect(decodeNostrUri('not a nostr identifier'), isNull);
  });
}
