import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/identity_index.dart';

void main() {
  final a = 'a' * 64;
  final b = 'b' * 64;
  final c = 'c' * 64;

  Identity identity(String pubkeyHex) =>
      Identity(pubkeyHex: pubkeyHex, createdAt: DateTime(2026));

  Map<String, dynamic> entry(String pubkeyHex, [Map<String, dynamic>? extra]) =>
      {'pubkeyHex': pubkeyHex, 'createdAt': 0, ...?extra};

  /// What `encode` stores, read back as JSON.
  Map<String, dynamic> stored(IdentityIndex index) =>
      jsonDecode(index.encode()) as Map<String, dynamic>;

  List<dynamic> storedEntries(IdentityIndex index) =>
      stored(index)['identities'] as List<dynamic>;

  group('parse', () {
    test('reads the bare list that older versions wrote', () {
      final index = IdentityIndex.parse(jsonEncode([entry(a), entry(b)]));

      expect(index.identities.map((i) => i.pubkeyHex), [a, b]);
      expect(index.active, isNull);
    });

    test('reads what encode writes', () {
      final index = IdentityIndex.empty
          .withIdentity(
            Identity(pubkeyHex: a, createdAt: DateTime(2026)),
            slot: 'slot-a',
          )
          .withIdentity(Identity(pubkeyHex: b, createdAt: DateTime(2027)))
          .withActive(b);

      final again = IdentityIndex.parse(index.encode());

      expect(again.identities.map((i) => i.pubkeyHex), [a, b]);
      expect(again.identities.first.createdAt, DateTime(2026));
      expect(again.slotOf(a), 'slot-a');
      expect(again.slotOf(b), isNull);
      expect(again.active, b);
    });

    test('refuses what is not an identity index', () {
      for (final raw in [
        '',
        'not json',
        '42',
        '"identities"',
        '{}',
        '{"identities": []}',
        '{"version": 2}',
        '{"version": 2, "identities": {}}',
      ]) {
        expect(
          () => IdentityIndex.parse(raw),
          throwsFormatException,
          reason: raw,
        );
      }
    });

    test('refuses an index from a newer version rather than rewrite it', () {
      expect(
        () => IdentityIndex.parse('{"version": 3, "identities": []}'),
        throwsFormatException,
      );
    });

    test('ignores an active identity that is not a pubkey string', () {
      final index = IdentityIndex.parse(
        '{"version": 2, "identities": [], "active": 7}',
      );

      expect(index.active, isNull);
      expect(stored(index), isNot(contains('active')));
    });
  });

  group('entries this version cannot read', () {
    // A shape no version wrote, a damaged createdAt, and one carrying a key.
    final unreadable = <Object?>[
      'not an entry',
      42,
      {'pubkeyHex': a},
      {'pubkeyHex': b, 'createdAt': '0', 'privkeyHex': 'only-copy'},
      {'somethingNew': true},
    ];

    IdentityIndex indexWithUnreadable() =>
        IdentityIndex.parse(jsonEncode([...unreadable, entry(c)]));

    test('are not listed as identities', () {
      expect(indexWithUnreadable().identities.map((i) => i.pubkeyHex), [c]);
    });

    test('survive adding, removing and re-encoding', () {
      final index = indexWithUnreadable()
          .withIdentity(Identity(pubkeyHex: a, createdAt: DateTime(0)))
          .withSlot(c, 'slot-c')
          .withActive(c)
          .without(c);

      expect(storedEntries(index).take(unreadable.length), unreadable);
      expect(IdentityIndex.parse(index.encode()).identities, hasLength(1));
    });

    test('keep a private key they carry inline', () {
      final index = indexWithUnreadable().withoutInlineKey(b);

      expect(index.keysToMove.map((k) => k.inlineKey), [null]);
      expect(jsonEncode(storedEntries(index)), contains('only-copy'));
    });

    test('are left out of the keys to move', () {
      expect(indexWithUnreadable().keysToMove.map((k) => k.pubkeyHex), [c]);
    });
  });

  group('keys to move', () {
    IdentityIndex mixed() => IdentityIndex.parse(
      jsonEncode([
        entry(a, {'privkeyHex': 'key-a', 'extra': 1}),
        entry(b),
        entry(c, {'slot': 'slot-c'}),
        entry('d' * 64, {'slot': 'slot-d', 'privkeyHex': 'key-d'}),
      ]),
    );

    test('are the inline ones and those without a slot', () {
      expect(
        mixed().keysToMove.map((k) => (k.pubkeyHex, k.slot, k.inlineKey)),
        [(a, null, 'key-a'), (b, null, null), ('d' * 64, 'slot-d', 'key-d')],
      );
    });

    test('an inline key is dropped one identity at a time', () {
      final index = mixed().withoutInlineKey(a);

      expect(index.keysToMove.map((k) => k.inlineKey), [null, null, 'key-d']);
      expect(index.identities, hasLength(4));
    });

    test('a slot is recorded for one identity only', () {
      final index = mixed().withSlot(b, 'slot-b');

      expect(index.slotOf(b), 'slot-b');
      expect(index.slotOf(a), isNull);
      expect(index.keysToMove.map((k) => k.pubkeyHex), [a, 'd' * 64]);
    });

    test('are kept when other entries change', () {
      final index = mixed()
          .withIdentity(Identity(pubkeyHex: 'e' * 64, createdAt: DateTime(0)))
          .without(b);

      expect(index.keysToMove.map((k) => k.inlineKey), [
        'key-a',
        'key-d',
        null,
      ]);
    });

    test('leave other fields of the entry alone', () {
      final index = mixed().withoutInlineKey(a).withSlot(a, 'slot-a');

      expect(
        storedEntries(index).first,
        entry(a, {'extra': 1, 'slot': 'slot-a'}),
      );
    });
  });

  group('slots', () {
    test('are recorded with the identity they were made for', () {
      final index = IdentityIndex.empty.withIdentity(identity(a), slot: 'x1');

      expect(index.slotOf(a), 'x1');
      expect(index.slotOf(b), isNull);
      expect(storedEntries(index).single, containsPair('slot', 'x1'));
    });

    test('are not written for an identity without one', () {
      final index = IdentityIndex.empty.withIdentity(identity(a));

      expect(storedEntries(index).single, isNot(contains('slot')));
    });

    test('are read from entries that cannot be parsed as identities too', () {
      final index = IdentityIndex.parse(
        jsonEncode([
          {'pubkeyHex': a, 'slot': 'x1'},
        ]),
      );

      expect(index.identities, isEmpty);
      expect(index.slotOf(a), 'x1');
    });
  });

  group('active identity', () {
    IdentityIndex two() => IdentityIndex.empty
        .withIdentity(identity(a), slot: 'x1')
        .withIdentity(identity(b), slot: 'x2');

    test('is the one that was picked', () {
      expect(two().withActive(b).activePubkey, b);
    });

    test('is the first identity while none was picked', () {
      expect(two().activePubkey, a);
    });

    test('is the first identity when the one picked is gone', () {
      expect(two().withActive(c).activePubkey, a);
    });

    test('is nothing without identities', () {
      expect(IdentityIndex.empty.activePubkey, isNull);
      expect(IdentityIndex.empty.withActive(a).activePubkey, isNull);
    });

    test('goes unset when its identity is removed', () {
      final index = two().withActive(a).without(a);

      expect(index.active, isNull);
      expect(index.activePubkey, b);
    });

    test('stays when another identity is removed', () {
      expect(two().withActive(a).without(b).active, a);
    });

    test('can be unset', () {
      final index = two().withActive(a).withActive(null);

      expect(index.active, isNull);
      expect(stored(index), isNot(contains('active')));
    });
  });

  group('without', () {
    test('removes every entry that names the pubkey', () {
      final index = IdentityIndex.parse(
        jsonEncode([
          entry(a),
          entry(b),
          entry(a, {'privkeyHex': 'k'}),
        ]),
      );

      expect(index.without(a).identities.map((i) => i.pubkeyHex), [b]);
      expect(index.without(a).contains(a), isFalse);
    });

    test('leaves the index alone when nothing matches', () {
      final index = IdentityIndex.parse(jsonEncode([entry(a)]));

      expect(index.without(b).encode(), index.encode());
    });
  });

  test('contains also sees entries that cannot be parsed', () {
    final index = IdentityIndex.parse(
      jsonEncode([
        {'pubkeyHex': a},
      ]),
    );

    expect(index.identities, isEmpty);
    expect(index.contains(a), isTrue);
    expect(index.contains(b), isFalse);
  });

  test('changes return a new index and leave the original alone', () {
    final original = IdentityIndex.parse(jsonEncode([entry(a)]));
    final before = original.encode();

    original.withIdentity(Identity(pubkeyHex: b, createdAt: DateTime(0)));
    original.withSlot(a, 'x1');
    original.withActive(a);
    original.without(a);
    original.withoutInlineKey(a);

    expect(original.encode(), before);
  });
}
