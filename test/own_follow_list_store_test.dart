import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/own_follow_list_store.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/partly_answering_relay_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final me = generateNostrKeyPair();
  final alice = 'aa' * 32;
  final bob = 'bb' * 32;
  final relays = {for (var i = 0; i < 4; i++) 'wss://r$i.example.com'};
  final at = DateTime.fromMillisecondsSinceEpoch(1760000000 * 1000);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetKnownContactLists();
  });

  Future<String?> stored() async => (await SharedPreferences.getInstance())
      .getString('seen_own_follow_lists');

  test('nothing is stored until a list has been seen', () async {
    expect(await OwnFollowListStore.load(), isNull);
  });

  test('keeps when each list was made and how many people it held', () async {
    await OwnFollowListStore.save({
      me.publicKeyHex: (createdAt: at, count: 120),
      alice: (createdAt: at.add(const Duration(days: 1)), count: 0),
    });

    final loaded = await OwnFollowListStore.load();

    expect(loaded, {
      me.publicKeyHex: (createdAt: at, count: 120),
      alice: (createdAt: at.add(const Duration(days: 1)), count: 0),
    });
  });

  test('skips what cannot be read instead of failing', () async {
    SharedPreferences.setMockInitialValues({
      'seen_own_follow_lists': jsonEncode({
        me.publicKeyHex: [1760000000, 4],
        'not-a-pubkey': [1760000000, 4],
        alice: [1760000000],
        bob: ['yesterday', 4],
        'cc' * 32: [-1, 4],
        'dd' * 32: [1760000000, -4],
        'ee' * 32: [99999999999999, 4],
      }),
    });

    expect(await OwnFollowListStore.load(), {
      me.publicKeyHex: (createdAt: at, count: 4),
    });

    SharedPreferences.setMockInitialValues({'seen_own_follow_lists': '{'});
    expect(await OwnFollowListStore.load(), isNull);
    SharedPreferences.setMockInitialValues({'seen_own_follow_lists': '[1]'});
    expect(await OwnFollowListStore.load(), isNull);
  });

  group('with the memo bound to the store, as the app does', () {
    // Once: a binding stays for as long as the app runs.
    setUpAll(() async {
      await bindPersisted(
        seenOwnContactLists,
        OwnFollowListStore.load,
        OwnFollowListStore.save,
      );
    });

    Future<FollowUpdate> follow(RelayClient client) {
      return RelayContactsRepository(client: client).applyFollowChanges(
        secretKey: SecretKey.fromHex(me.privateKeyHex),
        myPubkeyHex: me.publicKeyHex,
        changes: {bob: true},
        relayUrls: relays,
      );
    }

    NostrEvent listOf(List<String> follows, DateTime createdAt) => signEvent(
      secretKey: SecretKey.fromHex(me.privateKeyHex),
      pubkeyHex: me.publicKeyHex,
      kind: 3,
      tags: [
        for (final pubkey in follows) ['p', pubkey],
      ],
      content: '',
      createdAt: createdAt,
    );

    test(
      'a list published is kept as a time and a size, and nobody\'s name',
      () async {
        final client = PartlyAnsweringRelayClient([
          listOf([alice], DateTime.now().subtract(const Duration(days: 3))),
        ], answered: 4);

        expect(await follow(client), isA<FollowPublished>());
        // The save runs in the background after the memo changes.
        await pumpEventQueue();

        final raw = await stored();
        expect(raw, isNotNull);
        final decoded = jsonDecode(raw!) as Map<String, dynamic>;
        expect(decoded.keys, [me.publicKeyHex]);
        expect((decoded[me.publicKeyHex] as List<dynamic>)[1], 2);
        expect(raw, isNot(contains(alice)));
        expect(raw, isNot(contains(bob)));
      },
    );

    test(
      'after a restart, an older copy is asked about, not built on',
      () async {
        final client = PartlyAnsweringRelayClient([
          listOf([alice], DateTime.now().subtract(const Duration(days: 3))),
        ], answered: 4);
        await follow(client);
        await pumpEventQueue();
        final published = client.published.single;

        // A new process: nothing in memory but what the disk kept. It is read
        // first, as clearing the memo is saved too.
        final onDisk = (await OwnFollowListStore.load())!;
        resetKnownContactLists();
        seenOwnContactLists.value = onDisk;

        // The relays return the copy from before the follow, as laggards do.
        client.events
          ..clear()
          ..add(
            listOf([
              alice,
            ], published.createdAt.subtract(const Duration(days: 3))),
          );
        final update = await follow(client);

        expect(update, isA<FollowNeedsConfirmation>());
        update as FollowNeedsConfirmation;
        expect(update.risks, {FollowRisk.olderThanSeen});
        expect(update.lastSeen?.count, 2);
        expect(update.found?.count, 1);
        expect(client.published, hasLength(1));
      },
    );
  });
}
