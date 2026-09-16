import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/screens/identities_screen.dart';
import 'package:sputnik/screens/profile_screen.dart';
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
    this.publishOutcome = RelayPublishOutcome.accepted,
    this.gate,
  });

  final RelayPublishOutcome publishOutcome;
  // When set, publish() waits on this before resolving -- lets a test
  // observe UI state that should already be settled before the network
  // call completes (i.e. an optimistic update).
  final Completer<void>? gate;
  NostrEvent? lastPublished;

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async => const [];

  @override
  Future<Map<String, RelayPublishResult>> publish(
    NostrEvent event,
    Set<String> relayUrls,
  ) async {
    if (gate != null) await gate!.future;
    lastPublished = event;
    return {
      for (final url in relayUrls) url: RelayPublishResult(publishOutcome),
    };
  }
}

void main() {
  setUp(() {
    identitiesNotifier.value = const [];
    activeIdentityPubkeyNotifier.value = null;
    selectedRelaysNotifier.value = {'wss://relay.example'};
  });

  testWidgets('with no active identity, shows a prompt instead of a profile', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();

    expect(find.text('No identity yet'), findsOneWidget);
    expect(
      find.byKey(const Key('createIdentityFromProfileButton')),
      findsOneWidget,
    );
  });

  testWidgets('the prompt leads to the identities screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('createIdentityFromProfileButton')));
    await tester.pumpAndSettle();

    expect(find.byType(IdentitiesScreen), findsOneWidget);
  });

  group('follow button', () {
    late Identity identity;
    final targetPubkeyHex = 'b' * 64;

    setUp(() async {
      // A fresh, throwaway keypair generated for this test run only -- never
      // a real saved identity.
      final keypair = generateNostrKeyPair();
      identity = Identity(
        pubkeyHex: keypair.publicKeyHex,
        createdAt: DateTime.now(),
      );
      identitiesNotifier.value = [identity];
      activeIdentityPubkeyNotifier.value = identity.pubkeyHex;

      SettingsStore.secretStore = _FakeSecretStore();
      await SettingsStore.savePrivateKey(
        identity.pubkeyHex,
        keypair.privateKeyHex,
      );
    });

    testWidgets(
      'the button flips to Following instantly, before the publish resolves',
      (tester) async {
        final gate = Completer<void>();
        final fakeClient = _FakeRelayClient(gate: gate);
        await tester.pumpWidget(
          MaterialApp(
            home: ProfileScreen(
              pubkeyHex: targetPubkeyHex,
              relayClient: fakeClient,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('followButton')));
        await tester.pump();

        // The publish hasn't resolved yet (the gate is still closed), but
        // the button should already reflect the new state.
        expect(find.text('Following'), findsOneWidget);
        expect(fakeClient.lastPublished, isNull);

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.text('Following'), findsOneWidget);
        expect(fakeClient.lastPublished, isNotNull);
      },
    );

    testWidgets(
      'tapping Follow publishes immediately, with no confirm dialog',
      (tester) async {
        final fakeClient = _FakeRelayClient();
        await tester.pumpWidget(
          MaterialApp(
            home: ProfileScreen(
              pubkeyHex: targetPubkeyHex,
              relayClient: fakeClient,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Follow'), findsOneWidget);

        await tester.tap(find.byKey(const Key('followButton')));
        await tester.pump();

        // No confirm dialog -- unlike posting/editing a profile, following
        // is reversible and carries no content.
        expect(find.byType(AlertDialog), findsNothing);

        await tester.pumpAndSettle();

        final published = fakeClient.lastPublished;
        expect(published, isNotNull);
        expect(published!.pubkey, identity.pubkeyHex);
        expect(published.kind, 3);
        expect(published.content, '');
        expect(published.tags, [
          ['p', targetPubkeyHex],
        ]);
        expect(find.text('Following'), findsOneWidget);
      },
    );

    testWidgets('a rejected follow leaves the button as Follow', (
      tester,
    ) async {
      final fakeClient = _FakeRelayClient(
        publishOutcome: RelayPublishOutcome.rejected,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            pubkeyHex: targetPubkeyHex,
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
  });
}
