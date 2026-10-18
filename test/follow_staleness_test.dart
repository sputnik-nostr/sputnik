import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nostr.dart';

import 'support/partly_answering_relay_client.dart';

void main() {
  final me = generateNostrKeyPair();
  final alice = 'aa' * 32;
  final bob = 'bb' * 32;
  final relays = {for (var i = 0; i < 4; i++) 'wss://r$i.example.com'};

  setUp(resetKnownContactLists);

  NostrEvent contactList(List<String> follows, {required Duration age}) {
    return signEvent(
      secretKey: SecretKey.fromHex(me.privateKeyHex),
      pubkeyHex: me.publicKeyHex,
      kind: 3,
      tags: [
        for (final pubkey in follows) ['p', pubkey],
      ],
      content: '',
      createdAt: DateTime.now().subtract(age),
    );
  }

  Future<FollowUpdate> change(
    RelayClient client,
    String target, {
    bool follow = true,
    Set<FollowRisk> agreedTo = const {},
  }) {
    return RelayContactsRepository(client: client).applyFollowChanges(
      secretKey: SecretKey.fromHex(me.privateKeyHex),
      myPubkeyHex: me.publicKeyHex,
      changes: {target: follow},
      relayUrls: relays,
      agreedTo: agreedTo,
    );
  }

  /// What the relays took of a follow; nothing when it was not sent.
  Future<Map<String, RelayPublishResult>> follow(
    RelayClient client,
    String target,
  ) async {
    final update = await change(client, target);
    return update is FollowPublished ? update.results : const {};
  }

  test('one relay of four answering is not enough to publish', () async {
    final client = PartlyAnsweringRelayClient([
      contactList([alice], age: const Duration(days: 30)),
    ], answered: 1);

    final results = await follow(client, bob);

    expect(results, isEmpty);
    expect(client.published, isEmpty);
  });

  test('exactly half of the relays answering is not enough', () async {
    final client = PartlyAnsweringRelayClient([
      contactList([alice], age: const Duration(days: 30)),
    ], answered: 2);

    await follow(client, bob);

    expect(client.published, isEmpty);
  });

  test('a majority answering with a list is enough', () async {
    final client = PartlyAnsweringRelayClient([
      contactList([alice], age: const Duration(days: 30)),
    ], answered: 3);

    await follow(client, bob);

    expect(client.published.single.tags, [
      ['p', alice],
      ['p', bob],
    ]);
  });

  test('no relay answering never publishes a fresh list', () async {
    final client = PartlyAnsweringRelayClient([], answered: 0);

    await follow(client, bob);

    expect(client.published, isEmpty);
  });

  test('every relay answering with nothing starts a fresh list', () async {
    final client = PartlyAnsweringRelayClient([], answered: 4);

    await follow(client, bob);

    expect(client.published.single.tags, [
      ['p', bob],
    ]);
  });

  test('a lagging relay cannot roll back a list published earlier', () async {
    final older = contactList([alice], age: const Duration(days: 30));
    final client = PartlyAnsweringRelayClient([older], answered: 4);

    await follow(client, bob);
    expect(client.published, hasLength(1));

    // The relays now answer with the pre-follow copy, as a laggard would.
    client.events
      ..clear()
      ..add(older);
    final update = await change(client, 'cc' * 32);

    expect(update, isA<FollowNeedsConfirmation>());
    update as FollowNeedsConfirmation;
    expect(update.risks, {FollowRisk.olderThanSeen});
    expect(update.found?.count, 1);
    expect(update.lastSeen?.count, 2);
    expect(client.published, hasLength(1));
  });

  test(
    'a list published earlier that no relay returns is not dropped',
    () async {
      final client = PartlyAnsweringRelayClient([
        contactList([alice], age: const Duration(days: 30)),
      ], answered: 4);

      await follow(client, bob);
      client.events.clear();
      final update = await change(client, 'cc' * 32);

      expect(update, isA<FollowNeedsConfirmation>());
      update as FollowNeedsConfirmation;
      expect(update.risks, {FollowRisk.olderThanSeen});
      expect(update.found, isNull);
      expect(update.lastSeen?.count, 2);
      expect(client.published, hasLength(1));
    },
  );

  test('once the relays catch up the next change goes through', () async {
    final client = PartlyAnsweringRelayClient([
      contactList([alice], age: const Duration(days: 30)),
    ], answered: 4);

    await follow(client, bob);
    await follow(client, 'cc' * 32);

    expect(client.published, hasLength(2));
    expect(client.published.last.tags.map((t) => t[1]), [
      alice,
      bob,
      'cc' * 32,
    ]);
  });

  group('asks before building on a list that may not be the real one', () {
    test(
      'a majority answering with nothing is asked about, not trusted',
      () async {
        final client = PartlyAnsweringRelayClient([], answered: 3);

        final update = await change(client, bob);

        expect(update, isA<FollowNeedsConfirmation>());
        update as FollowNeedsConfirmation;
        expect(update.risks, {FollowRisk.noListFound});
        expect(update.answeredRelays, 3);
        expect(update.queriedRelays, 4);
        expect(update.found, isNull);
        expect(update.resultingCount, 1);
        expect(client.published, isEmpty);
      },
    );

    test('once the user agrees, the fresh list is published', () async {
      final client = PartlyAnsweringRelayClient([], answered: 3);

      final update = await change(
        client,
        bob,
        agreedTo: {FollowRisk.noListFound},
      );

      expect(update, isA<FollowPublished>());
      expect(client.published.single.tags, [
        ['p', bob],
      ]);
    });

    test('too few relays answering is refused, not asked about', () async {
      final client = PartlyAnsweringRelayClient([], answered: 2);

      final update = await change(client, bob);

      expect(update, isA<FollowRefused>());
      update as FollowRefused;
      expect(update.reason, FollowRefusal.relaysSilent);
      expect(update.answeredRelays, 2);
      expect(update.queriedRelays, 4);
      expect(client.published, isEmpty);
    });

    test('an unfollow never publishes an empty list on a doubtful base, even '
        'if the user agreed', () async {
      final client = PartlyAnsweringRelayClient([], answered: 3);

      for (final agreedTo in [
        const <FollowRisk>{},
        {FollowRisk.noListFound},
      ]) {
        final update = await change(
          client,
          alice,
          follow: false,
          agreedTo: agreedTo,
        );

        expect(update, isA<FollowRefused>());
        expect((update as FollowRefused).reason, FollowRefusal.wouldEmptyList);
      }
      expect(client.published, isEmpty);
    });

    test(
      'a list from after the last one seen is built on without asking',
      () async {
        final client = PartlyAnsweringRelayClient([
          contactList([alice], age: const Duration(days: 30)),
        ], answered: 4);
        noteOwnContactList(
          me.publicKeyHex,
          DateTime.now().subtract(const Duration(days: 90)),
          10,
        );

        final update = await change(client, bob);

        // Another client may have shortened the list since; that is its news.
        expect(update, isA<FollowPublished>());
      },
    );

    test(
      'the change is dated after a newer list than the one built on',
      () async {
        final client = PartlyAnsweringRelayClient([
          contactList([alice], age: const Duration(days: 30)),
        ], answered: 4);
        final future = DateTime.now().add(const Duration(hours: 2));
        noteOwnContactList(me.publicKeyHex, future, 5);

        await change(client, bob, agreedTo: {FollowRisk.olderThanSeen});

        expect(client.published.single.createdAt.isAfter(future), isTrue);
      },
    );
  });

  group('the list shown for an identity', () {
    Future<List<String>?> shown(RelayClient client) =>
        RelayContactsRepository(client: client)
            .fetchFollowingOrNull(me.publicKeyHex, relays);

    test(
      'is unknown while a relay that may hold it has not answered',
      () async {
        for (final answered in [0, 1, 2, 3]) {
          final client = PartlyAnsweringRelayClient([], answered: answered);

          expect(
            await shown(client),
            isNull,
            reason: '$answered of 4 answered',
          );
        }
      },
    );

    test('is empty only when every relay said there is none', () async {
      expect(
        await shown(PartlyAnsweringRelayClient([], answered: 4)),
        <String>[],
      );
    });

    test('is the list that was found, however few relays answered', () async {
      final client = PartlyAnsweringRelayClient([
        contactList([alice], age: const Duration(days: 30)),
      ], answered: 1);

      expect(await shown(client), [alice]);
    });
  });
}
