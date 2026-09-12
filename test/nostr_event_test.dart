import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/models/nostr_event.dart';

// Format-only checks: these mutate a field to be structurally invalid hex,
// which is rejected before NostrEvent.fromJson ever reaches signature
// verification, so a real signature isn't needed here. See
// nostr_event_verification_test.dart for authenticity checks against real
// signed events, and nostr_metadata_test.dart for content sanitization.
Map<String, dynamic> _json({
  String? id,
  String? pubkey,
  String? sig,
  Object? tags,
}) {
  return {
    'id': id ?? 'a' * 64,
    'pubkey': pubkey ?? 'b' * 64,
    'created_at': 0,
    'kind': 1,
    'tags': tags ?? <List<String>>[],
    'content': '',
    'sig': sig ?? 'c' * 128,
  };
}

void main() {
  test('rejects a wrong-length pubkey', () {
    expect(
      () => NostrEvent.fromJson(_json(pubkey: 'b' * 63)),
      throwsFormatException,
    );
  });

  test('rejects a non-hex pubkey', () {
    expect(
      () => NostrEvent.fromJson(_json(pubkey: 'z' * 64)),
      throwsFormatException,
    );
  });

  test('rejects a wrong-length id', () {
    expect(
      () => NostrEvent.fromJson(_json(id: 'a' * 63)),
      throwsFormatException,
    );
  });

  test('rejects a wrong-length sig', () {
    expect(
      () => NostrEvent.fromJson(_json(sig: 'c' * 127)),
      throwsFormatException,
    );
  });

  test('rejects tags that are not an array', () {
    expect(
      () => NostrEvent.fromJson(_json(tags: 'nope')),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'Malformed tags',
        ),
      ),
    );
  });
}
