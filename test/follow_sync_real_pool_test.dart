import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/app_state.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/nostr/relay_connection_pool.dart';
import 'package:sputnik/services/cache_store.dart';
import 'package:sputnik/services/follow_sync.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/fake_secret_store.dart';
import 'support/follow_questions.dart';
import 'support/mock_relay.dart';
import 'support/relay_states.dart';

// A follow tap as the app handles it, from the sync loop to local relays over
// the real pool: the first follow of a session while the relay that holds the
// user's list does not answer.

void main() {
  // Reporting a failure looks for the navigator, which needs the binding. The
  // binding swaps in an HTTP client that answers 400 to everything, and the
  // relays here are real.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  final alice = 'aa' * 32;
  final newcomer = 'ee' * 32;
  late String me;
  late List<MockRelay> relays;

  /// Two relays that say they hold no list, and a third that holds the real
  /// one but does not answer.
  setUp(() async {
    resetFollowSync();
    resetKnownContactLists();
    await CacheStore.clearAll();
    followSyncRetryDelays = const [Duration(milliseconds: 200)];

    final keypair = generateNostrKeyPair();
    me = keypair.publicKeyHex;
    SettingsStore.secretStore = FakeSecretStore();
    await SettingsStore.savePrivateKey(me, keypair.privateKeyHex);
    identitiesNotifier.value = [
      Identity(pubkeyHex: me, createdAt: DateTime.now()),
    ];
    activeIdentityPubkeyNotifier.value = me;
    myFollowingNotifier.value = null;

    final real = signEvent(
      secretKey: SecretKey.fromHex(keypair.privateKeyHex),
      pubkeyHex: me,
      kind: 3,
      tags: [
        for (final person in realFollows) ['p', person * 32],
      ],
      content: '',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    relays = [
      await MockRelay.start(RelayState.empty, const []),
      await MockRelay.start(RelayState.empty, const []),
      await MockRelay.start(RelayState.slow, [real]),
    ];
    selectedRelaysNotifier.value = {for (final relay in relays) relay.url};
  });

  tearDown(() async {
    resetFollowSync();
    await RelayConnectionPool.instance.retainOnly(const {});
    await Future.wait([
      for (final relay in relays) relay.server.close(force: true),
    ]);
  });

  /// Waits for something that happens by itself, in real time.
  Future<void> until(bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  int sent() => relays.fold(0, (sum, relay) => sum + relay.received.length);

  test('the first follow asks before it replaces a list it could not find, '
      'and publishes what the user agreed to', () async {
    FollowNeedsConfirmation? asked;
    int? sentWhenAsked;
    answerFollowQuestions((update) {
      asked = update;
      sentWhenAsked = sent();
      return true;
    });

    myFollowingNotifier.value = {newcomer};
    scheduleFollowingSync(newcomer, follow: true);
    // Published: the sync loop keeps the list it sent.
    await until(() => CacheStore.freshFollowing(me) != null);

    expect(asked!.risks, {FollowRisk.noListFound});
    expect((asked!.answeredRelays, asked!.queriedRelays), (2, 3));
    expect(sentWhenAsked, 0);
    final published = NostrEvent.fromJson(relays.first.received.single);
    expect(published.tags, [
      ['p', newcomer],
    ]);
    // What was published is what this device knows of the list from now on.
    expect(seenOwnContactLists.value[me]?.count, 1);
    expect(myFollowingNotifier.value, {newcomer});
  });

  test('turning the question down sends nothing and undoes the tap', () async {
    final answered = Completer<void>();
    confirmFollowUpdate = (update) async {
      answered.complete();
      return false;
    };

    myFollowingNotifier.value = {alice, newcomer};
    scheduleFollowingSync(newcomer, follow: true);
    await answered.future;
    await until(() => myFollowingNotifier.value?.length == 1);

    expect(myFollowingNotifier.value, {alice});
    expect(sent(), 0);
  });

  test('an unfollow that would leave an empty list is not sent, and is '
      'tried again', () async {
    confirmFollowUpdate = (update) async => fail('there is nothing to ask');

    myFollowingNotifier.value = {};
    scheduleFollowingSync(alice, follow: false);
    // Two rounds at the relays that answer: the change is still queued.
    await until(() => relays.first.requests >= 2);

    expect(sent(), 0);
  });
}
