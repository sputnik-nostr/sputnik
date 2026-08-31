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
}
