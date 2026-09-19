import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/screens/users_list_screen.dart';
import 'package:sputnik/services/settings_store.dart';
import 'package:sputnik/widgets/follow_button.dart';

import 'support/answering_relay_client.dart';
import 'support/fake_secret_store.dart';

class _FakeRelayClient extends RelayClient with AnsweringRelayClient {
  _FakeRelayClient({
    required this.seckeyHex,
    this.followingTags = const [],
    this.followingQueryGate,
  });

  // Used to self-sign the active identity's own kind:3 event returned from
  // query() -- must match the active identity so the event verifies.
  final String seckeyHex;

  // The active identity's own kind:3 event, as raw "p" tags.
  final List<List<String>> followingTags;
  NostrEvent? lastPublished;

  // When set, delays the kind:3 query until this completes.
  final Completer<void>? followingQueryGate;

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async {
    if (filter.kinds?.contains(3) != true) return const [];
    final author = filter.authors?.first;
    if (author == null) return const [];
    if (followingQueryGate != null) await followingQueryGate!.future;
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
      for (final url in relayUrls)
        url: const RelayPublishResult(RelayPublishOutcome.accepted),
    };
  }
}

// The follow-sync background loop debounces before publishing.
Future<void> _settleFollowSync(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
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
    myFollowingNotifier.value = null;

    SettingsStore.secretStore = FakeSecretStore();
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

  testWidgets('a follow made in a list is immediately visible to a fresh '
      'FollowButton for the same person elsewhere, with no extra fetch', (
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

    await tester.tap(find.byKey(const Key('followButton')));
    await _settleFollowSync(tester);
    expect(find.text('Following'), findsOneWidget);

    // A fresh FollowButton for the same person, as on a new profile page.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FollowButton(
            targetPubkeyHex: notFollowedPubkeyHex,
            relayClient: fakeClient,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Following'), findsOneWidget);
  });

  testWidgets('follow buttons show as Follow immediately, before the '
      'my-following fetch resolves', (tester) async {
    final gate = Completer<void>();
    final fakeClient = _FakeRelayClient(
      seckeyHex: seckeyHex,
      followingQueryGate: gate,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UsersListScreen(
          title: 'Followers',
          pubkeys: [followedPubkeyHex, notFollowedPubkeyHex],
          relayClient: fakeClient,
        ),
      ),
    );
    await tester.pump();

    // Visible immediately, defaulting to Follow, not hidden.
    expect(find.byKey(const Key('followButton')), findsNWidgets(2));
    expect(find.text('Follow'), findsNWidgets(2));

    gate.complete();
    await tester.pumpAndSettle();
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
