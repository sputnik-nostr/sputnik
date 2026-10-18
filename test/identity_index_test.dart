import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/identity_index.dart';

void main() {
  final a = 'a' * 64;
  final b = 'b' * 64;
  final c = 'c' * 64;

  Map<String, dynamic> entry(String pubkeyHex, [Map<String, dynamic>? extra]) =>
      {'pubkeyHex': pubkeyHex, 'createdAt': 0, ...?extra};

  /// What `encode` stores, read back as JSON.
  List<dynamic> stored(IdentityIndex index) {
    final decoded = jsonDecode(index.encode()) as Map<String, dynamic>;
    return decoded['identities'] as List<dynamic>;
  }

  group('parse', () {
    test('reads the bare list that older versions wrote', () {
      final index = IdentityIndex.parse(jsonEncode([entry(a), entry(b)]));

      expect(index.identities.map((i) => i.pubkeyHex), [a, b]);
    });

    test('reads what encode writes', () {
      final index = IdentityIndex.empty
          .withIdentity(Identity(pubkeyHex: a, createdAt: DateTime(2026)))
          .withIdentity(Identity(pubkeyHex: b, createdAt: DateTime(2027)));

      final again = IdentityIndex.parse(index.encode());

      expect(again.identities.map((i) => i.pubkeyHex), [a, b]);
      expect(again.identities.first.createdAt, DateTime(2026));
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
          .without(c);

      expect(stored(index).take(unreadable.length), unreadable);
      expect(IdentityIndex.parse(index.encode()).identities, hasLength(1));
    });

    test('keep a private key they carry inline', () {
      final index = indexWithUnreadable().withoutInlineKey(b);

      expect(index.inlineKeys, isEmpty);
      expect(jsonEncode(stored(index)), contains('only-copy'));
    });
  });

  group('inline keys', () {
    IdentityIndex legacy() => IdentityIndex.parse(
      jsonEncode([
        entry(a, {'privkeyHex': 'key-a', 'extra': 1}),
        entry(b),
        entry(c, {'privkeyHex': 'key-c'}),
      ]),
    );

    test('are listed with the identity they belong to', () {
      expect(legacy().inlineKeys.map((k) => (k.pubkeyHex, k.privkeyHex)), [
        (a, 'key-a'),
        (c, 'key-c'),
      ]);
    });

    test('are dropped one identity at a time', () {
      final index = legacy().withoutInlineKey(a);

      expect(index.inlineKeys.map((k) => k.pubkeyHex), [c]);
      expect(index.identities.map((i) => i.pubkeyHex), [a, b, c]);
    });

    test('are kept when other entries change', () {
      final index = legacy()
          .withIdentity(Identity(pubkeyHex: 'd' * 64, createdAt: DateTime(0)))
          .without(b);

      expect(index.inlineKeys.map((k) => k.privkeyHex), ['key-a', 'key-c']);
    });

    test('leave other fields of the entry alone', () {
      final index = legacy().withoutInlineKey(a);

      expect(stored(index).first, entry(a, {'extra': 1}));
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
    original.without(a);
    original.withoutInlineKey(a);

    expect(original.encode(), before);
  });
}
