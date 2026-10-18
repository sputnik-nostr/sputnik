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

  const seckeyHex =
      '67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa';
  const nsec =
      'nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5';

  test('encodes a hex seckey to the matching nsec', () {
    expect(nsecFromHex(seckeyHex), nsec);
  });

  test('decodes an nsec to the matching hex seckey', () {
    expect(hexFromNsec(nsec), seckeyHex);
  });

  test('rejects a non-nsec bech32 string', () {
    expect(hexFromNsec(npub1), isNull);
  });

  test('rejects a bech32 payload with the wrong byte length', () {
    final shortHex = hex1.substring(0, 40);
    final shortBytes = [
      for (var i = 0; i < shortHex.length; i += 2)
        int.parse(shortHex.substring(i, i + 2), radix: 16),
    ];
    final shortPayload = bech32Encode(
      'nsec',
      convertBits(shortBytes, 8, 5, pad: true),
    );
    expect(hexFromNsec(shortPayload), isNull);
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

  test('encodes and decodes a hex event id as nevent', () {
    final nevent = neventFromHex(hex1);
    expect(hexFromNevent(nevent), hex1);
  });

  test('encoding an nevent with an author still decodes to the event id', () {
    final nevent = neventFromHex(hex1, authorPubkeyHex: hex2);
    expect(hexFromNevent(nevent), hex1);
  });

  test('rejects a TLV special value that is not 32 bytes', () {
    final idBytes = [
      for (var i = 0; i < hex1.length; i += 2)
        int.parse(hex1.substring(i, i + 2), radix: 16),
    ];
    final truncated = idBytes.sublist(0, 16);
    final data = <int>[0, truncated.length, ...truncated];
    final payload = convertBits(data, 8, 5, pad: true);

    expect(hexFromNevent(bech32Encode('nevent', payload)), isNull);
    expect(hexFromNprofile(bech32Encode('nprofile', payload)), isNull);
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

  group('decodeNostrUri with uppercase', () {
    // QR codes carry URIs in uppercase; BIP-173 allows an entity in all
    // lowercase or all uppercase, never a mix of the two.
    const nprofile =
        'nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p';
    final entities = {
      'npub': (npub1, (pubkeyHex: hex1, eventIdHex: null)),
      'nprofile': (nprofile, (pubkeyHex: hex1, eventIdHex: null)),
      'note': (noteFromHex(hex1), (pubkeyHex: null, eventIdHex: hex1)),
      'nevent': (
        neventFromHex(hex1, authorPubkeyHex: hex2),
        (pubkeyHex: null, eventIdHex: hex1),
      ),
    };

    /// [entity] with its last lowercase letter in uppercase.
    String oneUppercase(String entity) {
      final letter = entity.lastIndexOf(RegExp('[a-z]'));
      return entity.substring(0, letter) +
          entity[letter].toUpperCase() +
          entity.substring(letter + 1);
    }

    for (final MapEntry(key: kind, value: (entity, target))
        in entities.entries) {
      group(kind, () {
        test('decodes the lowercase form', () {
          expect(decodeNostrUri(entity), target);
          expect(decodeNostrUri('nostr:$entity'), target);
        });

        test('decodes the uppercase form', () {
          expect(decodeNostrUri(entity.toUpperCase()), target);
          expect(decodeNostrUri('nostr:${entity.toUpperCase()}'), target);
          expect(decodeNostrUri('NOSTR:${entity.toUpperCase()}'), target);
        });

        test('decodes a scheme in any case before a whole entity', () {
          expect(decodeNostrUri('NOSTR:$entity'), target);
          expect(decodeNostrUri('Nostr:$entity'), target);
        });

        test('rejects an entity that mixes cases', () {
          final upper = entity.toUpperCase();
          final firstCapital = entity[0].toUpperCase() + entity.substring(1);
          final lowercasePrefix = entity.substring(0, entity.indexOf('1') + 1);
          final upperPrefix = lowercasePrefix.toUpperCase();

          for (final mixed in [
            oneUppercase(entity),
            firstCapital,
            // Only the prefix, or only the rest, in uppercase.
            upperPrefix + entity.substring(lowercasePrefix.length),
            lowercasePrefix + upper.substring(lowercasePrefix.length),
          ]) {
            expect(decodeNostrUri(mixed), isNull, reason: mixed);
            expect(decodeNostrUri('nostr:$mixed'), isNull, reason: mixed);
            expect(decodeNostrUri('NOSTR:$mixed'), isNull, reason: mixed);
          }
        });

        test('still checks the checksum of the uppercase form', () {
          final upper = entity.toUpperCase();
          // The last character is part of the checksum; "Q" is 0 and "P" is 1.
          final last = upper.endsWith('Q') ? 'P' : 'Q';

          expect(
            decodeNostrUri(upper.substring(0, upper.length - 1) + last),
            isNull,
          );
        });
      });
    }

    test('never decodes an nsec, in any case', () {
      const nsec =
          'nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5';

      expect(decodeNostrUri(nsec.toUpperCase()), isNull);
      expect(decodeNostrUri('NOSTR:${nsec.toUpperCase()}'), isNull);
    });

    test('returns null for text too short to be an entity', () {
      for (final text in ['', 'n', 'NOSTR', 'nostr:', 'NOSTR:', 'NPUB1']) {
        expect(decodeNostrUri(text), isNull, reason: text);
      }
    });

    test('hexFromNpub decodes the uppercase form too', () {
      expect(hexFromNpub(npub1.toUpperCase()), hex1);
    });
  });
}
