import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/models/nostr_metadata.dart';

void main() {
  test('parses well-formed metadata content', () {
    final metadata = NostrMetadata.fromContent(
      '{"name": "alice", "about": "hello"}',
    );
    expect(metadata.name, 'alice');
    expect(metadata.about, 'hello');
  });

  test('sanitizes a lone surrogate in name so Text can render it', () {
    final metadata = NostrMetadata.fromContent('{"name": "bad\\ud800name"}');
    expect(metadata.name, 'bad�name');
  });

  test('keeps a valid surrogate pair (emoji) intact', () {
    final metadata = NostrMetadata.fromContent('{"name": "hi \\ud83d\\ude00"}');
    expect(metadata.name, 'hi 😀');
  });

  test('keeps the rest of a profile when one field is not a string', () {
    final metadata = NostrMetadata.fromContent(
      '{"name": "alice", "nip05": 12345, "about": []}',
    );

    expect(metadata.name, 'alice');
    expect(metadata.nip05, isNull);
    expect(metadata.about, isNull);
  });

  group('legacyMoneroAddress (non-standard, not part of any NIP)', () {
    test('falls back to "monero_address" when "xmr" is absent', () {
      final metadata = NostrMetadata.fromContent(
        '{"monero_address": "4Baddress"}',
      );
      expect(metadata.legacyMoneroAddress, '4Baddress');
    });

    test('falls back to cryptocurrency_addresses.monero last', () {
      final metadata = NostrMetadata.fromContent(
        '{"cryptocurrency_addresses": {"monero": "4Caddress"}}',
      );
      expect(metadata.legacyMoneroAddress, '4Caddress');
    });

    test('prefers "xmr" over the other two when several are present', () {
      final metadata = NostrMetadata.fromContent(
        '{"xmr": "4Aaddress", "monero_address": "4Baddress", '
        '"cryptocurrency_addresses": {"monero": "4Caddress"}}',
      );
      expect(metadata.legacyMoneroAddress, '4Aaddress');
    });

    test('is null when none of the fields are present', () {
      final metadata = NostrMetadata.fromContent('{"name": "alice"}');
      expect(metadata.legacyMoneroAddress, isNull);
    });

    test('round-trips through the local cache format', () {
      final metadata = NostrMetadata.fromContent('{"xmr": "4Aaddress"}');
      final restored = NostrMetadata.fromJson(metadata.toJson());
      expect(restored.legacyMoneroAddress, '4Aaddress');
    });
  });
}
