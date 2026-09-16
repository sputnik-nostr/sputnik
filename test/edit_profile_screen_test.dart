import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/screens/edit_profile_screen.dart';
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
  _FakeRelayClient(this._outcome, {this.message});

  final RelayPublishOutcome _outcome;
  final String? message;
  NostrEvent? lastPublished;

  @override
  Future<Map<String, RelayPublishResult>> publish(
    NostrEvent event,
    Set<String> relayUrls,
  ) async {
    lastPublished = event;
    return {
      for (final url in relayUrls)
        url: RelayPublishResult(_outcome, message: message),
    };
  }
}

void main() {
  late Identity identity;

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
    selectedRelaysNotifier.value = {'wss://relay.example'};
    profileCacheNotifier.value = {
      identity.pubkeyHex: const NostrMetadata(
        displayName: 'Old Name',
        about: 'Old bio',
        picture: 'https://example.com/pic.png',
      ),
    };

    SettingsStore.secretStore = _FakeSecretStore();
    await SettingsStore.savePrivateKey(
      identity.pubkeyHex,
      keypair.privateKeyHex,
    );
  });

  Future<void> openEditProfileScreen(
    WidgetTester tester,
    RelayClient relayClient,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: EditProfileScreen(relayClient: relayClient)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('seeds the fields from the cached profile metadata', (
    tester,
  ) async {
    await openEditProfileScreen(tester, const RelayClient());

    expect(find.widgetWithText(TextField, 'Old Name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Old bio'), findsOneWidget);
  });

  testWidgets('saving asks for confirmation before publishing', (tester) async {
    final fakeClient = _FakeRelayClient(RelayPublishOutcome.accepted);
    await openEditProfileScreen(tester, fakeClient);

    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pumpAndSettle();

    expect(find.text('Update profile?'), findsOneWidget);
    expect(fakeClient.lastPublished, isNull);
  });

  testWidgets(
    'confirming signs and publishes a kind:0 event, preserving other fields',
    (tester) async {
      final fakeClient = _FakeRelayClient(RelayPublishOutcome.accepted);
      await openEditProfileScreen(tester, fakeClient);

      await tester.enterText(
        find.byKey(const Key('editNameField')),
        'New Name',
      );
      await tester.enterText(find.byKey(const Key('editBioField')), 'New bio');
      await tester.tap(find.byKey(const Key('saveProfileButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmSaveProfileButton')));
      // Bounded pumps rather than pumpAndSettle, so the SnackBar assertion
      // below runs before its auto-dismiss timer would clear it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final published = fakeClient.lastPublished;
      expect(published, isNotNull);
      expect(published!.kind, 0);
      final content = jsonDecode(published.content) as Map<String, dynamic>;
      expect(content['display_name'], 'New Name');
      expect(content['about'], 'New bio');
      // Not exposed by this form -- must survive the update untouched.
      expect(content['picture'], 'https://example.com/pic.png');

      expect(
        profileCacheNotifier.value[identity.pubkeyHex]?.displayName,
        'New Name',
      );

      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsNothing);
    },
  );

  testWidgets('a rejected publish keeps the screen open', (tester) async {
    final fakeClient = _FakeRelayClient(
      RelayPublishOutcome.rejected,
      message: 'blocked',
    );
    await openEditProfileScreen(tester, fakeClient);

    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmSaveProfileButton')));
    await tester.pumpAndSettle();

    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(
      find.text('Could not publish this profile update to any relay'),
      findsOneWidget,
    );
  });
}
