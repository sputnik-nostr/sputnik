import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/main.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/follow_sync.dart';
import 'package:sputnik/services/settings_store.dart';

class _FakeSecretStore implements SecretStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

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
    followSyncRetryDelays = const [Duration(milliseconds: 100)];

    // A throwaway keypair, never a real saved identity.
    final keypair = generateNostrKeyPair();
    me = keypair.publicKeyHex;
    SettingsStore.secretStore = _FakeSecretStore();
    await SettingsStore.savePrivateKey(me, keypair.privateKeyHex);
    identitiesNotifier.value = [
      Identity(pubkeyHex: me, createdAt: DateTime.now()),
    ];
    activeIdentityPubkeyNotifier.value = me;
    selectedRelaysNotifier.value = {'wss://relay.example'};
    myFollowingNotifier.value = null;
  });

  test('a failed startup load is not mistaken for "follows nobody"', () async {
    final relay = _FlakyRelay(me, [alice, bob]);
    Future<void> load() =>
        RelayContactsRepository(client: relay)
            .ensureMyFollowingLoaded({'wss://relay.example'});

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
      await RelayContactsRepository(client: relay)
          .ensureMyFollowingLoaded({'wss://relay.example'});

      // The relays recover, then the user taps Follow.
      relay.relays = _Relays.up;
      myFollowingNotifier.value = {carol};
      scheduleFollowingSync(carol, follow: true, relayClient: relay);
      await _waitForSync();

      expect([
        for (final tag in relay.lastPublished!.tags) tag[1],
      ], unorderedEquals([alice, bob, carol]));
      expect(myFollowingNotifier.value, {alice, bob, carol});
    },
  );

  test('a follow made while relays are unreachable is retried until it '
      'goes through', () async {
    final relay = _FlakyRelay(me, [alice, bob]);

    scheduleFollowingSync(carol, follow: true, relayClient: relay);
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

    scheduleFollowingSync(carol, follow: true, relayClient: relay);
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

    scheduleFollowingSync(carol, follow: true, relayClient: relay);
    scheduleFollowingSync(alice, follow: false, relayClient: relay);
    await _waitForSync();

    expect([
      for (final tag in relay.lastPublished!.tags) tag[1],
    ], unorderedEquals([bob, carol]));
    expect(myFollowingNotifier.value, {bob, carol});
  });

  test('unfollowing removes only that person from the relay list', () async {
    final relay = _FlakyRelay(me, [alice, bob])..relays = _Relays.up;

    scheduleFollowingSync(alice, follow: false, relayClient: relay);
    await _waitForSync();

    expect([for (final tag in relay.lastPublished!.tags) tag[1]], [bob]);
    expect(myFollowingNotifier.value, {bob});
  });
}
