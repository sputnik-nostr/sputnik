import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nostr.dart';

class _RecordingRelay extends RelayClient {
  _RecordingRelay({this.toReturn = const []});

  final List<NostrEvent> toReturn;
  NostrEvent? lastPublished;

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async => toReturn;

  @override
  Future<Map<String, RelayPublishResult>> publish(
    NostrEvent event,
    Set<String> relayUrls,
  ) async {
    lastPublished = event;
    return {
      for (final url in relayUrls)
        url: const RelayPublishResult(RelayPublishOutcome.accepted),
    };
  }
}

class _FilterRecordingRelay extends RelayClient {
  final filters = <NostrFilter>[];

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async {
    filters.add(filter);
    return const [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a page of posts is split so one popular post cannot use up the '
      'reaction limit for the rest', () async {
    final relay = _FilterRecordingRelay();
    final postIds = [
      for (var i = 0; i < 25; i++) i.toRadixString(16).padLeft(64, '0'),
    ];

    final reactions = await RelayReactionsRepository(client: relay)
        .fetchReactions(postIds, {'wss://relay.example'});

    expect(reactions.keys, unorderedEquals(postIds));
    for (final kind in [6, 7]) {
      final chunks = [
        for (final filter in relay.filters)
          if (filter.kinds!.single == kind) filter.tags!['e']!,
      ];
      expect(chunks.every((chunk) => chunk.length <= 10), isTrue);
      expect(chunks.expand((chunk) => chunk), unorderedEquals(postIds));
    }
  });

  late String me;
  late String seckeyHex;
  late NostrEvent target;

  setUp(() {
    // A fresh, throwaway keypair generated for this test run only -- never
    // a real saved identity.
    final keypair = generateNostrKeyPair();
    me = keypair.publicKeyHex;
    seckeyHex = keypair.privateKeyHex;
    target = NostrEvent(
      id: 'cc' * 32,
      pubkey: 'bb' * 32,
      createdAt: DateTime.now(),
      kind: 1,
      tags: const [],
      content: 'hello',
      sig: 'dd' * 64,
    );
  });

  test(
    'publishLike signs a NIP-25 kind 7 like referencing the target',
    () async {
      final relay = _RecordingRelay();
      await RelayReactionsRepository(client: relay).publishLike(
        secretKey: SecretKey.fromHex(seckeyHex),
        myPubkeyHex: me,
        target: target,
        relayHint: 'wss://hint.example',
        relayUrls: {'wss://relay.example'},
      );

      final event = relay.lastPublished!;
      expect(event.kind, 7);
      expect(event.pubkey, me);
      expect(event.content, '+');
      expect(
        event.tags,
        contains(equals(['e', target.id, 'wss://hint.example', target.pubkey])),
      );
      expect(event.tags, contains(equals(['p', target.pubkey, ''])));
      expect(event.tags, contains(equals(['k', '1'])));
    },
  );

  test(
    'publishRepost signs a NIP-18 kind 6 repost with the note as content',
    () async {
      final relay = _RecordingRelay();
      await RelayReactionsRepository(client: relay).publishRepost(
        secretKey: SecretKey.fromHex(seckeyHex),
        myPubkeyHex: me,
        target: target,
        relayHint: 'wss://hint.example',
        relayUrls: {'wss://relay.example'},
      );

      final event = relay.lastPublished!;
      expect(event.kind, 6);
      expect(event.pubkey, me);
      expect(
        event.tags,
        contains(equals(['e', target.id, 'wss://hint.example'])),
      );
      expect(event.tags, contains(equals(['p', target.pubkey, ''])));
      expect(
        (jsonDecode(event.content) as Map<String, dynamic>)['id'],
        target.id,
      );
    },
  );

  test(
    'fetchOwnReaction finds the newest matching like by me, ignoring '
    "someone else's like, a dislike, and a like for a different note",
    () async {
      final someoneElsesLike = NostrEvent(
        id: 'e1' * 32,
        pubkey: 'ff' * 32,
        createdAt: DateTime.now(),
        kind: 7,
        tags: [
          ['e', target.id],
        ],
        content: '+',
        sig: 'sig',
      );
      final myDislike = NostrEvent(
        id: 'e2' * 32,
        pubkey: me,
        createdAt: DateTime.now(),
        kind: 7,
        tags: [
          ['e', target.id],
        ],
        content: '-',
        sig: 'sig',
      );
      final myLikeOfAnotherNote = NostrEvent(
        id: 'e3' * 32,
        pubkey: me,
        createdAt: DateTime.now(),
        kind: 7,
        tags: [
          ['e', 'aa' * 32],
        ],
        content: '+',
        sig: 'sig',
      );
      final myOlderLike = NostrEvent(
        id: 'e4' * 32,
        pubkey: me,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        kind: 7,
        tags: [
          ['e', target.id],
        ],
        content: '+',
        sig: 'sig',
      );
      final myNewerLike = NostrEvent(
        id: 'e5' * 32,
        pubkey: me,
        createdAt: DateTime.now(),
        kind: 7,
        tags: [
          ['e', target.id],
        ],
        content: '+',
        sig: 'sig',
      );

      final relay = _RecordingRelay(
        toReturn: [
          someoneElsesLike,
          myDislike,
          myLikeOfAnotherNote,
          myOlderLike,
          myNewerLike,
        ],
      );

      final found = await RelayReactionsRepository(client: relay)
          .fetchOwnReaction(
            myPubkeyHex: me,
            noteId: target.id,
            kind: 7,
            relayUrls: {'wss://relay.example'},
          );

      expect(found?.id, myNewerLike.id);
    },
  );

  test('publishRetraction signs a NIP-09 kind 5 deletion request', () async {
    final relay = _RecordingRelay();
    final myLike = NostrEvent(
      id: 'e6' * 32,
      pubkey: me,
      createdAt: DateTime.now(),
      kind: 7,
      tags: [
        ['e', target.id],
      ],
      content: '+',
      sig: 'sig',
    );

    await RelayReactionsRepository(client: relay).publishRetraction(
      secretKey: SecretKey.fromHex(seckeyHex),
      myPubkeyHex: me,
      target: myLike,
      relayUrls: {'wss://relay.example'},
    );

    final event = relay.lastPublished!;
    expect(event.kind, 5);
    expect(event.pubkey, me);
    expect(event.tags, [
      ['e', myLike.id],
      ['k', '7'],
    ]);
  });
}
