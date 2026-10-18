import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/app_state.dart';
import 'package:sputnik/main.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/feed_loader.dart';
import 'package:sputnik/services/follow_sync.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/fake_secret_store.dart';
import 'support/identity_storage.dart';
import 'support/in_memory_relay_client.dart';

// The whole way there, as a user reaches it: A's note is on screen in a tab,
// the identity is changed in Settings > Identities, and the user goes back.
void main() {
  late NostrKeyPair a;
  late NostrKeyPair b;
  late NostrEvent eventOfA;
  late Note noteOfA;
  late InMemoryRelayClient relay;
  late VoidCallback followingListener;

  final delete = find.byIcon(Icons.delete_outline);

  setUp(() {
    resetFollowSync();
    a = generateNostrKeyPair();
    b = generateNostrKeyPair();
    final held = [
      (
        identity: Identity(
          pubkeyHex: a.publicKeyHex,
          createdAt: DateTime(2026, 1, 1),
        ),
        privkeyHex: a.privateKeyHex,
      ),
      (
        identity: Identity(
          pubkeyHex: b.publicKeyHex,
          createdAt: DateTime(2026, 1, 2),
        ),
        privkeyHex: b.privateKeyHex,
      ),
    ];
    // Generating, importing and deleting an identity change the index in
    // secure storage and the list follows it, so the index must list the same.
    SettingsStore.secretStore = FakeSecretStore(
      currentStorage(held, active: a.publicKeyHex),
    );
    identitiesNotifier.value = [for (final h in held) h.identity];
    activeIdentityPubkeyNotifier.value = a.publicKeyHex;
    selectedRelaysNotifier.value = {'wss://relay.example'};
    profileCacheNotifier.value = const {};
    myFollowingNotifier.value = const {};
    confirmBeforeReactingNotifier.value = true;

    eventOfA = fakeEvent(
      id: 'cc',
      pubkey: a.publicKeyHex,
      content: 'written as identity A',
    );
    noteOfA = Note(
      id: eventOfA.id,
      pubkey: eventOfA.pubkey,
      displayName: 'A',
      content: eventOfA.content,
      createdAt: eventOfA.createdAt,
    );
    notesNotifier.value = [noteOfA];
    followingNotesNotifier.value = const [];
    bookmarkedNotesNotifier.value = const {};
    relay = InMemoryRelayClient([eventOfA]);
    RelayClient.instance = relay;

    // What main() does when the identity changes.
    followingListener = () {
      followingNotesNotifier.value = null;
      runFeedLoad(loadFollowingFeed, 'loading the following feed');
    };
    activeIdentityPubkeyNotifier.addListener(followingListener);
  });

  tearDown(() {
    activeIdentityPubkeyNotifier.removeListener(followingListener);
    resetFollowSync();
    notesNotifier.value = null;
    followingNotesNotifier.value = null;
    bookmarkedNotesNotifier.value = const {};
    myFollowingNotifier.value = null;
  });

  Future<void> openIdentities(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('profileAvatarButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settingsCard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identitiesCard')));
    await tester.pumpAndSettle();
  }

  Future<void> backToTabs(WidgetTester tester) async {
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
  }

  Future<void> switchTo(WidgetTester tester, NostrKeyPair keys) async {
    await openIdentities(tester);
    await tester.tap(find.text(truncateNpub(npubFromHex(keys.publicKeyHex))));
    await tester.pumpAndSettle();
    expect(activeIdentityPubkeyNotifier.value, keys.publicKeyHex);
    await backToTabs(tester);
  }

  testWidgets('Global: B is not offered a deletion of A\'s note', (
    tester,
  ) async {
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Global'));
    await tester.pumpAndSettle();
    expect(delete, findsOneWidget, reason: 'A is active and wrote the note');

    await switchTo(tester, b);
    await tester.tap(find.text('Global'));
    await tester.pumpAndSettle();

    expect(find.text('written as identity A'), findsOneWidget);
    expect(delete, findsNothing);
    expect(relay.published, isEmpty);
  });

  testWidgets('Bookmarks, already open: B is not offered it', (tester) async {
    bookmarkedNotesNotifier.value = {noteOfA.id: noteOfA};
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bookmarks'));
    await tester.pumpAndSettle();
    expect(delete, findsOneWidget, reason: 'A is active and wrote the note');

    await switchTo(tester, b);

    expect(find.text('written as identity A'), findsOneWidget);
    expect(delete, findsNothing);
    expect(relay.published, isEmpty);
  });

  testWidgets('Bookmarks, first opened after the switch: nor is it', (
    tester,
  ) async {
    bookmarkedNotesNotifier.value = {noteOfA.id: noteOfA};
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();

    await switchTo(tester, b);
    await tester.tap(find.text('Bookmarks'));
    await tester.pumpAndSettle();

    expect(find.text('written as identity A'), findsOneWidget);
    expect(delete, findsNothing);
  });

  testWidgets('a generated identity is not offered it either', (tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Global'));
    await tester.pumpAndSettle();
    expect(delete, findsOneWidget);

    await openIdentities(tester);
    await tester.tap(find.byKey(const Key('generateIdentityButton')));
    await tester.pumpAndSettle();
    expect(activeIdentityPubkeyNotifier.value, isNot(a.publicKeyHex));
    await backToTabs(tester);

    expect(find.text('written as identity A'), findsOneWidget);
    expect(delete, findsNothing);
  });

  testWidgets('an imported identity is not offered it either', (tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Global'));
    await tester.pumpAndSettle();
    expect(delete, findsOneWidget);

    await openIdentities(tester);
    await tester.tap(find.byKey(const Key('importIdentityButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      'nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5',
    );
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(identitiesNotifier.value, hasLength(3));
    expect(activeIdentityPubkeyNotifier.value, isNot(a.publicKeyHex));
    await backToTabs(tester);

    expect(find.text('written as identity A'), findsOneWidget);
    expect(delete, findsNothing);
  });

  testWidgets('nor is the identity that takes over from a deleted one', (
    tester,
  ) async {
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Global'));
    await tester.pumpAndSettle();
    expect(delete, findsOneWidget);

    await openIdentities(tester);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(identitiesNotifier.value.map((i) => i.pubkeyHex), [b.publicKeyHex]);
    expect(activeIdentityPubkeyNotifier.value, b.publicKeyHex);
    await backToTabs(tester);

    expect(find.text('written as identity A'), findsOneWidget);
    expect(delete, findsNothing);
  });

  testWidgets('switching back to A brings Delete back', (tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Global'));
    await tester.pumpAndSettle();

    await switchTo(tester, b);
    expect(delete, findsNothing);
    await switchTo(tester, a);

    expect(delete, findsOneWidget);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(relay.published.single.kind, 5);
    expect(relay.published.single.pubkey, a.publicKeyHex);
  });
}
