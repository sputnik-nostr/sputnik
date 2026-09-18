import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nostr.dart';

import 'support/in_memory_relay_client.dart';

void main() {
  Map<String, dynamic> edit(String? existing, Map<String, String> fields) =>
      jsonDecode(editedProfileContent(existing, fields))
          as Map<String, dynamic>;

  group('editedProfileContent', () {
    test('sets fields on an empty profile', () {
      expect(edit(null, {'name': 'a', 'about': 'b'}), {
        'name': 'a',
        'about': 'b',
      });
    });

    test('keeps keys it was not asked to change', () {
      expect(
        edit('{"name":"a","lud16":"x@y.z","birthday":{"year":1990}}', {
          'name': 'b',
        }),
        {
          'name': 'b',
          'lud16': 'x@y.z',
          'birthday': {'year': 1990},
        },
      );
    });

    test('trims values and removes empty ones', () {
      expect(edit('{"name":"a","about":"b"}', {'name': '  ', 'about': ' c '}), {
        'about': 'c',
      });
    });

    test('an edited display name replaces the deprecated spelling', () {
      expect(edit('{"displayName":"old"}', {'display_name': 'new'}), {
        'display_name': 'new',
      });
      expect(edit('{"displayName":"old"}', {'display_name': ''}), isEmpty);
    });

    test('unreadable existing content is replaced', () {
      expect(edit('not json', {'name': 'a'}), {'name': 'a'});
      expect(edit('[1,2]', {'name': 'a'}), {'name': 'a'});
    });
  });

  group('nextReplaceableTime', () {
    NostrEvent at(DateTime time) => fakeEvent(createdAt: time);

    test('is now with nothing to replace', () {
      final before = DateTime.now();
      expect(
        nextReplaceableTime(null)
            .isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('is now when the previous event is older', () {
      final previous = at(DateTime.now().subtract(const Duration(minutes: 5)));
      final next = nextReplaceableTime(previous);
      expect(
        next.millisecondsSinceEpoch ~/ 1000,
        greaterThan(previous.createdAt.millisecondsSinceEpoch ~/ 1000),
      );
    });

    test('moves one second past a previous event from this second', () {
      final previous = at(DateTime.now());
      final next = nextReplaceableTime(previous);
      expect(
        next.millisecondsSinceEpoch ~/ 1000,
        previous.createdAt.millisecondsSinceEpoch ~/ 1000 + 1,
      );
    });

    test('moves past a previous event dated in the future', () {
      final previous = at(DateTime.now().add(const Duration(hours: 2)));
      expect(nextReplaceableTime(previous).isAfter(previous.createdAt), isTrue);
    });
  });

  group('fetchOwnReplaceable', () {
    final me = 'ab' * 32;

    test('returns the newest event of the kind by the author', () async {
      final client = InMemoryRelayClient([
        fakeEvent(id: '01', pubkey: me, kind: 10002, createdAt: DateTime(2024)),
        fakeEvent(id: '02', pubkey: me, kind: 10002, createdAt: DateTime(2025)),
        fakeEvent(id: '03', pubkey: 'cd' * 32, kind: 10002),
      ]);

      final own = await fetchOwnReplaceable(
        client,
        kind: 10002,
        pubkeyHex: me,
        relayUrls: {'wss://r'},
      );

      expect(own.event!.id, startsWith('02'));
      expect(own.conclusive, isTrue);
    });

    test(
      'nothing found is conclusive only when every relay answered',
      () async {
        final client = InMemoryRelayClient();
        Future<OwnEvent> lookup() => fetchOwnReplaceable(
          client,
          kind: 0,
          pubkeyHex: me,
          relayUrls: {'wss://r'},
        );

        expect((await lookup()).conclusive, isTrue);
        client.relaysAnswer = false;
        expect((await lookup()).conclusive, isFalse);
      },
    );
  });
}
