import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nip05.dart';

void main() {
  final pubkey = 'aa' * 32;

  group('parseNip05', () {
    test('splits local-part and domain on @', () {
      final parsed = parseNip05('Bob@example.com');
      expect(parsed, isNotNull);
      expect(parsed!.local, 'bob');
      expect(parsed.domain, 'example.com');
    });

    test('a bare domain is shorthand for the _@domain root identifier', () {
      final parsed = parseNip05('example.com');
      expect(parsed, isNotNull);
      expect(parsed!.local, '_');
      expect(parsed.domain, 'example.com');
    });

    test('rejects an empty identifier', () {
      expect(parseNip05(''), isNull);
      expect(parseNip05('   '), isNull);
    });

    test('rejects a local-part with disallowed characters', () {
      expect(parseNip05('bo b@example.com'), isNull);
      expect(parseNip05(r'bo$b@example.com'), isNull);
    });

    test('rejects an identifier with no domain', () {
      expect(parseNip05('bob@'), isNull);
    });
  });

  group('verifyNip05', () {
    test('an unparseable identifier is unreachable, not a crash', () async {
      final status = await verifyNip05(identifier: '', pubkeyHex: pubkey);
      expect(status, Nip05Status.unreachable);
    });

    // Regression test: connectionFactory must actually complete a real
    // TLS handshake, which fakes can't catch.
    test('completes a real TLS handshake and verifies a known identifier', () async {
      final verified = await verifyNip05(
        identifier: 'jb55@damus.io',
        pubkeyHex:
            '32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245',
      );
      expect(verified, Nip05Status.verified);

      final mismatch = await verifyNip05(
        identifier: 'jb55@damus.io',
        pubkeyHex: pubkey,
      );
      expect(mismatch, Nip05Status.mismatch);
    });
  });
}
