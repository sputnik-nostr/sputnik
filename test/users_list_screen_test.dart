import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/screens/users_list_screen.dart';
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

class _FakeRelayClient extends RelayClient {
  _FakeRelayClient({
    required this.seckeyHex,
    this.followingTags = const [],
    this.publishOutcome = RelayPublishOutcome.accepted,
  });

  // Used to self-sign the active identity's own kind:3 event returned from
  // query() -- must match the active identity so the event verifies.
  final String seckeyHex;

  // The active identity's own kind:3 event, as raw "p" tags.
  final List<List<String>> followingTags;
  final RelayPublishOutcome publishOutcome;
  NostrEvent? lastPublished;

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async {
    if (filter.kinds?.contains(3) != true) return const [];
    final author = filter.authors?.first;
    if (author == null) return const [];
    return [
      signEvent(
        seckeyHex: seckeyHex,
        pubkeyHex: author,
        kind: 3,
        tags: followingTags,
        content: '',
      ),
    ];
  }

  @override
  Future<Map<String, RelayPublishResult>> publish(
    NostrEvent event,
    Set<String> relayUrls,
  ) async {
    lastPublished = event;
    return {
      for (final url in relayUrls) url: RelayPublishResult(publishOutcome),
    };
  }
}

void main() {
  late Identity identity;
  late String seckeyHex;
  final followedPubkeyHex = 'b' * 64;
  final notFollowedPubkeyHex = 'c' * 64;

  setUp(() async {
    final keypair = generateNostrKeyPair();
    seckeyHex = keypair.privateKeyHex;
    identity = Identity(
      pubkeyHex: keypair.publicKeyHex,
      createdAt: DateTime.now(),
    );
    identitiesNotifier.value = [identity];
    activeIdentityPubkeyNotifier.value = identity.pubkeyHex;
    selectedRelaysNotifier.value = {'wss://relay.example'};
    profileCacheNotifier.value = const {};

    SettingsStore.secretStore = _FakeSecretStore();
    await SettingsStore.savePrivateKey(
      identity.pubkeyHex,
      keypair.privateKeyHex,
    );
  });

  testWidgets('shows Follow/Following per row, and hides it for yourself', (
    tester,
  ) async {
    final fakeClient = _FakeRelayClient(
      seckeyHex: seckeyHex,
      followingTags: [
        ['p', followedPubkeyHex],
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UsersListScreen(
          title: 'Followers',
          pubkeys: [
            followedPubkeyHex,
            notFollowedPubkeyHex,
            identity.pubkeyHex,
          ],
          relayClient: fakeClient,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Follow'), findsOneWidget);
    expect(find.byKey(const Key('followButton')), findsNWidgets(2));
  });

  testWidgets('tapping Follow in a row publishes and flips to Following', (
    tester,
  ) async {
    final fakeClient = _FakeRelayClient(seckeyHex: seckeyHex);

    await tester.pumpWidget(
      MaterialApp(
        home: UsersListScreen(
          title: 'Followers',
          pubkeys: [notFollowedPubkeyHex],
          relayClient: fakeClient,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Follow'), findsOneWidget);

    await tester.tap(find.byKey(const Key('followButton')));
    await tester.pumpAndSettle();

    expect(fakeClient.lastPublished, isNotNull);
    expect(fakeClient.lastPublished!.tags, [
      ['p', notFollowedPubkeyHex],
    ]);
    expect(find.text('Following'), findsOneWidget);
  });

  testWidgets('a rejected follow reverts the button back to Follow', (
    tester,
  ) async {
    final fakeClient = _FakeRelayClient(
      seckeyHex: seckeyHex,
      publishOutcome: RelayPublishOutcome.rejected,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UsersListScreen(
          title: 'Followers',
          pubkeys: [notFollowedPubkeyHex],
          relayClient: fakeClient,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('followButton')));
    await tester.pumpAndSettle();

    expect(fakeClient.lastPublished, isNotNull);
    expect(find.text('Follow'), findsOneWidget);
    expect(find.text('Could not update your follow list'), findsOneWidget);
  });

  testWidgets('with no active identity, no follow buttons are shown', (
    tester,
  ) async {
    activeIdentityPubkeyNotifier.value = null;
    final fakeClient = _FakeRelayClient(seckeyHex: seckeyHex);

    await tester.pumpWidget(
      MaterialApp(
        home: UsersListScreen(
          title: 'Followers',
          pubkeys: [followedPubkeyHex, notFollowedPubkeyHex],
          relayClient: fakeClient,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('followButton')), findsNothing);
  });
}
