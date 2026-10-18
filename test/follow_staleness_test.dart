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

  Future<Map<String, RelayPublishResult>> follow(
    RelayClient client,
    String target,
  ) async {
    final outcome = await RelayContactsRepository(client: client)
        .applyFollowChanges(
          secretKey: SecretKey.fromHex(me.privateKeyHex),
          myPubkeyHex: me.publicKeyHex,
          changes: {target: true},
          relayUrls: relays,
        );
    return outcome.results;
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
    final results = await follow(client, 'cc' * 32);

    expect(results, isEmpty);
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
      final results = await follow(client, 'cc' * 32);

      expect(results, isEmpty);
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
