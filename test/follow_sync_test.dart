import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/app_state.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/cache_store.dart';
import 'package:sputnik/services/follow_sync.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/answering_relay_client.dart';
import 'support/fake_secret_store.dart';

enum _Relays {
  // Nobody answers.
  down,

  // One relay says "nothing here"; the one holding the list is unreachable.
  partiallyDown,
  up,
}

class _FlakyRelay extends RelayClient {
  _FlakyRelay(this.me, this.followed);

  final String me;
  final List<String> followed;
  _Relays relays = _Relays.down;
  NostrEvent? lastPublished;

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async => (await queryWithStatus(relayUrls, filter)).events;

  @override
  Future<RelayQueryResult> queryWithStatus(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async {
    switch (relays) {
      case _Relays.down:
        return const RelayQueryResult(
          events: [],
          answeredRelays: 0,
          queriedRelays: 2,
        );
      case _Relays.partiallyDown:
        return const RelayQueryResult(
          events: [],
          answeredRelays: 1,
          queriedRelays: 2,
        );
      case _Relays.up:
        return RelayQueryResult(
          events: [
            NostrEvent(
              id: 'id',
              pubkey: me,
              createdAt: DateTime.now(),
              kind: 3,
              tags: [
                for (final pubkey in followed) ['p', pubkey],
              ],
              content: '',
              sig: 'sig',
            ),
          ],
          answeredRelays: 2,
          queriedRelays: 2,
        );
    }
  }

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

/// Answers each author's contact list, holding back [held]'s until released.
class _PerAuthorRelay extends RelayClient with AnsweringRelayClient {
  _PerAuthorRelay(this.followedBy, {required this.held});

  final Map<String, List<String>> followedBy;
  final String held;
  final release = Completer<void>();

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async {
    final author = filter.authors!.single;
    if (author == held) await release.future;
    return [
      NostrEvent(
        id: 'id',
        pubkey: author,
        createdAt: DateTime.now(),
        kind: 3,
        tags: [
          for (final pubkey in followedBy[author] ?? const <String>[])
            ['p', pubkey],
        ],
        content: '',
        sig: 'sig',
      ),
    ];
  }
}

// The follow-sync loop debounces before publishing.
Future<void> _waitForSync() =>
    Future<void>.delayed(const Duration(milliseconds: 800));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final alice = 'aa' * 32;
  final bob = 'bb' * 32;
  final carol = 'cc' * 32;
  late String me;

  tearDown(resetFollowSync);

  setUp(() async {
    resetFollowSync();
    await CacheStore.clearAll();
    followSyncRetryDelays = const [Duration(milliseconds: 100)];

    // A throwaway keypair, never a real saved identity.
    final keypair = generateNostrKeyPair();
    me = keypair.publicKeyHex;
    SettingsStore.secretStore = FakeSecretStore();
    await SettingsStore.savePrivateKey(me, keypair.privateKeyHex);
    identitiesNotifier.value = [
      Identity(pubkeyHex: me, createdAt: DateTime.now()),
    ];
    activeIdentityPubkeyNotifier.value = me;
    selectedRelaysNotifier.value = {'wss://relay.example'};
    myFollowingNotifier.value = null;
  });

  test('switching identity mid-load never shows the previous identity\'s '
      'follows', () async {
    final other = 'dd' * 32;
    final relay = _PerAuthorRelay({
      me: [alice],
      other: [bob, carol],
    }, held: me);
    RelayClient.instance = relay;

    final first = ensureMyFollowingLoaded({'wss://relay.example'});
    activeIdentityPubkeyNotifier.value = other;
    final second = ensureMyFollowingLoaded({'wss://relay.example'});
    relay.release.complete();
    await Future.wait([first, second]);

    expect(myFollowingNotifier.value, {bob, carol});
  });

  test('a list loaded for one identity is not reused for the next', () async {
    final other = 'dd' * 32;
    final relay = _FlakyRelay(me, [alice, bob])..relays = _Relays.up;
    RelayClient.instance = relay;
    await ensureMyFollowingLoaded({'wss://relay.example'});
    expect(myFollowingNotifier.value, {alice, bob});

    activeIdentityPubkeyNotifier.value = other;
    relay.relays = _Relays.down;
    await ensureMyFollowingLoaded({'wss://relay.example'});

    expect(myFollowingNotifier.value, isNull);
  });

  test('a failed startup load is not mistaken for "follows nobody"', () async {
    final relay = _FlakyRelay(me, [alice, bob]);
    RelayClient.instance = relay;
    Future<void> load() => ensureMyFollowingLoaded({'wss://relay.example'});

    await load();
    expect(myFollowingNotifier.value, isNull);

    relay.relays = _Relays.partiallyDown;
    await load();
    expect(myFollowingNotifier.value, isNull);

    relay.relays = _Relays.up;
    await load();
    expect(myFollowingNotifier.value, {alice, bob});
  });

  test(
    'following someone after a failed startup load keeps the real list',
    () async {
      final relay = _FlakyRelay(me, [alice, bob]);
      RelayClient.instance = relay;
      await ensureMyFollowingLoaded({'wss://relay.example'});

      // The relays recover, then the user taps Follow.
      relay.relays = _Relays.up;
      myFollowingNotifier.value = {carol};
      scheduleFollowingSync(carol, follow: true);
      await _waitForSync();

      expect([
        for (final tag in relay.lastPublished!.tags) tag[1],
      ], unorderedEquals([alice, bob, carol]));
      expect(myFollowingNotifier.value, {alice, bob, carol});
    },
  );

  test('a follow tapped while the list loads survives the load', () async {
    final relay = _PerAuthorRelay({
      me: [alice, bob],
    }, held: me);
    RelayClient.instance = relay;

    final load = ensureMyFollowingLoaded({'wss://relay.example'});
    myFollowingNotifier.value = {carol};
    scheduleFollowingSync(carol, follow: true);
    relay.release.complete();
    await load;

    expect(myFollowingNotifier.value, {alice, bob, carol});
  });

  test(
    'a follow tapped after a failed load is not cleared by a retry',
    () async {
      final relay = _FlakyRelay(me, [alice, bob]);
      RelayClient.instance = relay;
      Future<void> load() => ensureMyFollowingLoaded({'wss://relay.example'});
      await load();

      myFollowingNotifier.value = {carol};
      scheduleFollowingSync(carol, follow: true);
      await load();
      expect(myFollowingNotifier.value, {carol});

      relay.relays = _Relays.up;
      await load();
      expect(myFollowingNotifier.value, {alice, bob, carol});
    },
  );

  test('a follow made while relays are unreachable is retried until it '
      'goes through', () async {
    final relay = _FlakyRelay(me, [alice, bob]);
    RelayClient.instance = relay;

    scheduleFollowingSync(carol, follow: true);
    await _waitForSync();
    expect(relay.lastPublished, isNull);

    relay.relays = _Relays.up;
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect([
      for (final tag in relay.lastPublished!.tags) tag[1],
    ], unorderedEquals([alice, bob, carol]));
  });

  test('a relay saying "nothing here" is not trusted while another may '
      'still hold the list', () async {
    final relay = _FlakyRelay(me, [alice, bob])..relays = _Relays.partiallyDown;
    RelayClient.instance = relay;

    scheduleFollowingSync(carol, follow: true);
    await _waitForSync();
    expect(relay.lastPublished, isNull);

    relay.relays = _Relays.up;
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect([
      for (final tag in relay.lastPublished!.tags) tag[1],
    ], unorderedEquals([alice, bob, carol]));
  });

  test('changes made in a row are all applied', () async {
    final relay = _FlakyRelay(me, [alice, bob])..relays = _Relays.up;
    RelayClient.instance = relay;

    scheduleFollowingSync(carol, follow: true);
    scheduleFollowingSync(alice, follow: false);
    await _waitForSync();

    expect([
      for (final tag in relay.lastPublished!.tags) tag[1],
    ], unorderedEquals([bob, carol]));
    expect(myFollowingNotifier.value, {bob, carol});
  });
}
