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
  _FakeRelayClient({this.publishOutcome = RelayPublishOutcome.accepted});

  final RelayPublishOutcome publishOutcome;
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
    lastPublished = event;
    return {
      for (final url in relayUrls) url: RelayPublishResult(publishOutcome),
    };
  }
}

// The follow-sync background loop debounces before publishing.
Future<void> _settleFollowSync(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    identitiesNotifier.value = const [];
    activeIdentityPubkeyNotifier.value = null;
    selectedRelaysNotifier.value = {'wss://relay.example'};
    myFollowingNotifier.value = null;
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

  testWidgets("viewing someone else's profile with no active identity shows no "
      'follow button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          pubkeyHex: 'b' * 64,
          relayClient: _FakeRelayClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('followButton')), findsNothing);
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
      'the button flips instantly and stays clickable through a rapid '
      'double-tap, with no confirm dialog',
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

        // Flips instantly, no network call yet, no confirm dialog.
        expect(find.text('Following'), findsOneWidget);
        expect(fakeClient.lastPublished, isNull);
        expect(find.byType(AlertDialog), findsNothing);

        // Immediately tappable again -- no disabled/pending state.
        await tester.tap(find.byKey(const Key('followButton')));
        await tester.pump();
        expect(find.text('Follow'), findsOneWidget);
        expect(fakeClient.lastPublished, isNull);

        // The two taps collapse into a single publish of the final state.
        await _settleFollowSync(tester);
        expect(fakeClient.lastPublished, isNotNull);
        expect(find.text('Follow'), findsOneWidget);
      },
    );

    testWidgets('tapping Follow publishes the new state after a short delay', (
      tester,
    ) async {
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

      await tester.tap(find.byKey(const Key('followButton')));
      await _settleFollowSync(tester);

      final published = fakeClient.lastPublished;
      expect(published, isNotNull);
      expect(published!.pubkey, identity.pubkeyHex);
      expect(published.kind, 3);
      expect(published.content, '');
      expect(published.tags, [
        ['p', targetPubkeyHex],
      ]);
      expect(find.text('Following'), findsOneWidget);
    });

    testWidgets(
      'a rejected follow shows an error but does not revert the button',
      (tester) async {
        final fakeClient = _FakeRelayClient(
          publishOutcome: RelayPublishOutcome.rejected,
        );
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            home: ProfileScreen(
              pubkeyHex: targetPubkeyHex,
              relayClient: fakeClient,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('followButton')));
        await _settleFollowSync(tester);

        expect(fakeClient.lastPublished, isNotNull);
        // Not reverted, even though the background publish failed.
        expect(find.text('Following'), findsOneWidget);
        expect(find.text('Could not update your follow list'), findsOneWidget);
      },
    );
  });
}
