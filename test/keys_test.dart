import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/keys.dart';

void main() {
  test('derives the BIP-340 x-only pubkey for a known test vector', () {
    const seckeyHex =
        '0000000000000000000000000000000000000000000000000000000000000003';
    const expectedPubkeyHex =
        'F9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9';

    final pubkeyHex = xonlyPubkeyHexFromSeckeyHex(seckeyHex);

    expect(pubkeyHex.toUpperCase(), expectedPubkeyHex);
  });

  test('generates a fresh, internally-consistent keypair', () {
    final keypair = generateNostrKeyPair();

    expect(keypair.privateKeyHex, hasLength(64));
    expect(keypair.publicKeyHex, hasLength(64));
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(keypair.privateKeyHex), isTrue);
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(keypair.publicKeyHex), isTrue);

    expect(
      xonlyPubkeyHexFromSeckeyHex(keypair.privateKeyHex),
      keypair.publicKeyHex,
    );

    final other = generateNostrKeyPair();
    expect(other.privateKeyHex, isNot(keypair.privateKeyHex));
  });

  test('a signature from a fixed test-only key verifies against it', () {
    // Same seckey as the BIP-340 test vector above -- public, well-known,
    // and not anyone's real identity.
    const seckeyHex =
        '0000000000000000000000000000000000000000000000000000000000000003';
    final pubkeyHex = xonlyPubkeyHexFromSeckeyHex(seckeyHex);
    final pubkeyBytes = Uint8List.fromList(
      List.generate(
        32,
        (i) => int.parse(pubkeyHex.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );
    final msg = Uint8List(32)..fillRange(0, 32, 0x42);

    final sig = signSchnorrSignature(seckeyHex: seckeyHex, msg32: msg);

    expect(sig, hasLength(64));
    expect(
      verifySchnorrSignature(msg32: msg, sig64: sig, pubkey32: pubkeyBytes),
      isTrue,
    );
  });

  test('a signature does not verify against a different message', () {
    const seckeyHex =
        '0000000000000000000000000000000000000000000000000000000000000003';
    final pubkeyHex = xonlyPubkeyHexFromSeckeyHex(seckeyHex);
    final pubkeyBytes = Uint8List.fromList(
      List.generate(
        32,
        (i) => int.parse(pubkeyHex.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );
    final msg = Uint8List(32)..fillRange(0, 32, 0x42);
    final otherMsg = Uint8List(32)..fillRange(0, 32, 0x43);

    final sig = signSchnorrSignature(seckeyHex: seckeyHex, msg32: msg);

    expect(
      verifySchnorrSignature(
        msg32: otherMsg,
        sig64: sig,
        pubkey32: pubkeyBytes,
      ),
      isFalse,
    );
  });

  group('secret key hex input', () {
    final valid = '${'00' * 31}03';

    test(
      'a key longer than 32 bytes is rejected, not copied past the buffer',
      () {
        expect(
          () => xonlyPubkeyHexFromSeckeyHex('${valid}00'),
          throwsArgumentError,
        );
        expect(
          () =>
              signSchnorrSignature(seckeyHex: valid * 4, msg32: Uint8List(32)),
          throwsArgumentError,
        );
      },
    );

    test('a key shorter than 32 bytes is rejected', () {
      expect(() => xonlyPubkeyHexFromSeckeyHex('03'), throwsArgumentError);
      expect(() => xonlyPubkeyHexFromSeckeyHex(''), throwsArgumentError);
    });

    test('only well-formed hex digits are accepted', () {
      // int.parse alone would accept a sign or whitespace in a pair.
      for (final bad in ['-f', '+f', ' f', 'f ', '0x']) {
        final key = (bad * 32).substring(0, 64);
        expect(
          () => xonlyPubkeyHexFromSeckeyHex(key),
          throwsArgumentError,
          reason: bad,
        );
      }
    });

    test('the error does not echo the secret', () {
      final secret = 'zz${'00' * 31}';
      try {
        xonlyPubkeyHexFromSeckeyHex(secret);
        fail('expected an error');
      } on ArgumentError catch (e) {
        expect(e.toString(), isNot(contains('zz')));
      }
    });
  });
}
