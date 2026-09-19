import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/screens/edit_profile_screen.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/fake_secret_store.dart';
import 'support/in_memory_relay_client.dart';

void main() {
  late Identity identity;
  late InMemoryRelayClient client;
  late NostrEvent published0;

  Map<String, dynamic> contentOf(NostrEvent event) =>
      jsonDecode(event.content) as Map<String, dynamic>;

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
      identity.pubkeyHex: const NostrMetadata(displayName: 'Cached name'),
    };

    // What the relays hold, including fields this app has no form for.
    published0 = fakeEvent(
      id: '0a',
      pubkey: identity.pubkeyHex,
      kind: 0,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      tags: [
        ['client', 'other'],
      ],
      content: jsonEncode({
        'display_name': 'Old Name',
        'name': 'old',
        'about': 'Old bio',
        'picture': 'https://example.com/pic.png',
        'lud16': 'me@wallet.example',
        'bot': false,
      }),
    );
    client = InMemoryRelayClient([published0]);

    SettingsStore.secretStore = FakeSecretStore();
    await SettingsStore.savePrivateKey(
      identity.pubkeyHex,
      keypair.privateKeyHex,
    );
  });

  Future<void> openEditProfileScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: EditProfileScreen(relayClient: client)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmSaveProfileButton')));
    // Bounded pumps, so the snack bar is still up for assertions.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('seeds the fields from the published profile, not the cache', (
    tester,
  ) async {
    await openEditProfileScreen(tester);

    expect(find.widgetWithText(TextField, 'Old Name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'old'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Old bio'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'https://example.com/pic.png'),
      findsOneWidget,
    );
    expect(find.text('Cached name'), findsNothing);
  });

  testWidgets('falls back to the cached profile when none is published', (
    tester,
  ) async {
    client.events.clear();

    await openEditProfileScreen(tester);

    expect(find.widgetWithText(TextField, 'Cached name'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('the bio starts as one line like the other fields', (
    tester,
  ) async {
    await openEditProfileScreen(tester);

    final bio = tester.getSize(find.byKey(const Key('editBioField')));
    final name = tester.getSize(find.byKey(const Key('editNameField')));
    expect(bio.height, name.height);
  });

  testWidgets('the payment targets row spans the full width', (tester) async {
    await openEditProfileScreen(tester);

    await tester.scrollUntilVisible(
      find.byKey(const Key('editPaymentTargetsTile')),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.byType(Divider), findsNothing);
    final screenWidth = tester.getSize(find.byType(MaterialApp)).width;
    expect(
      tester.getSize(find.byKey(const Key('editPaymentTargetsTile'))).width,
      screenWidth,
    );
  });

  testWidgets('saving asks for confirmation before publishing', (tester) async {
    await openEditProfileScreen(tester);

    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pumpAndSettle();

    expect(find.text('Update profile?'), findsOneWidget);
    expect(client.published, isEmpty);
  });

  testWidgets('publishes every edited field and keeps the ones it does not '
      'know about', (tester) async {
    await openEditProfileScreen(tester);

    Future<void> enter(String key, String text) =>
        tester.enterText(find.byKey(Key(key)), text);
    await enter('editNameField', 'New Name');
    await enter('editUsernameField', 'newname');
    await enter('editBioField', 'New bio');
    await enter('editPictureField', 'https://example.com/new.png');
    await enter('editBannerField', 'https://example.com/banner.png');
    await enter('editNip05Field', 'me@example.com');
    await enter('editWebsiteField', 'https://example.com');
    await save(tester);

    final event = client.published.single;
    expect(event.kind, 0);
    expect(contentOf(event), {
      'display_name': 'New Name',
      'name': 'newname',
      'about': 'New bio',
      'picture': 'https://example.com/new.png',
      'banner': 'https://example.com/banner.png',
      'nip05': 'me@example.com',
      'website': 'https://example.com',
      'lud16': 'me@wallet.example',
      'bot': false,
    });
    expect(event.tags, [
      ['client', 'other'],
    ]);
    expect(
      profileCacheNotifier.value[identity.pubkeyHex]?.displayName,
      'New Name',
    );
    expect(
      profileCacheNotifier.value[identity.pubkeyHex]?.nip05,
      'me@example.com',
    );

    await tester.pumpAndSettle();
    expect(find.byType(EditProfileScreen), findsNothing);
  });

  testWidgets('an invalid URL blocks saving', (tester) async {
    await openEditProfileScreen(tester);

    await tester.enterText(find.byKey(const Key('editWebsiteField')), 'nope');
    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid http:// or https:// URL'), findsOneWidget);
    expect(find.text('Update profile?'), findsNothing);
    expect(client.published, isEmpty);
  });

  testWidgets('an invalid NIP-05 address blocks saving', (tester) async {
    await openEditProfileScreen(tester);

    await tester.enterText(find.byKey(const Key('editNip05Field')), 'a b@c');
    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pumpAndSettle();

    expect(find.text('Enter an address like name@example.com'), findsOneWidget);
    expect(client.published, isEmpty);
  });

  testWidgets('warns when the current profile could not be checked', (
    tester,
  ) async {
    client.events.clear();
    client.relaysAnswer = false;
    await openEditProfileScreen(tester);

    expect(find.byKey(const Key('retryLoadProfileButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('could not be checked'), findsWidgets);
    expect(client.published, isEmpty);
  });

  testWidgets('retrying picks up the published profile without losing edits', (
    tester,
  ) async {
    client.relaysAnswer = false;
    final held = [...client.events];
    client.events.clear();
    await openEditProfileScreen(tester);
    await tester.enterText(find.byKey(const Key('editBioField')), 'typed bio');

    client.events.addAll(held);
    client.relaysAnswer = true;
    await tester.tap(find.byKey(const Key('retryLoadProfileButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('retryLoadProfileButton')), findsNothing);

    await save(tester);

    final content = contentOf(client.published.single);
    expect(content['about'], 'typed bio');
    expect(content['lud16'], 'me@wallet.example');
  });

  testWidgets('a rejected publish keeps the screen open', (tester) async {
    client.publishOutcome = RelayPublishOutcome.rejected;
    await openEditProfileScreen(tester);

    await save(tester);
    await tester.pumpAndSettle();

    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(
      find.text('Could not publish this profile update to any relay'),
      findsOneWidget,
    );
  });
}
