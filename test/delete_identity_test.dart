import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/app_state.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/settings_store.dart';
import 'package:sputnik/widgets/delete_button.dart';
import 'package:sputnik/widgets/reaction_buttons.dart';

import 'support/fake_secret_store.dart';
import 'support/in_memory_relay_client.dart';

/// Counts key loads, so a test can tell that nothing was signed.
class _CountingSecretStore extends FakeSecretStore {
  var reads = 0;

  @override
  Future<String?> read(String key) {
    reads++;
    return super.read(key);
  }
}

/// A relay that hands back every event it has, whatever the filter asks for.
class _CarelessRelay extends InMemoryRelayClient {
  _CarelessRelay(super.events);

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async => [...events];
}

void main() {
  late NostrKeyPair a;
  late NostrKeyPair b;
  late NostrEvent noteEventOfA;
  late Note noteOfA;
  late InMemoryRelayClient relay;
  late _CountingSecretStore secrets;

  setUp(() async {
    confirmBeforeReactingNotifier.value = true;
    profileCacheNotifier.value = const {};
    a = generateNostrKeyPair();
    b = generateNostrKeyPair();
    secrets = _CountingSecretStore();
    SettingsStore.secretStore = secrets;
    await SettingsStore.savePrivateKey(a.publicKeyHex, a.privateKeyHex);
    await SettingsStore.savePrivateKey(b.publicKeyHex, b.privateKeyHex);
    secrets.reads = 0;
    identitiesNotifier.value = [
      Identity(pubkeyHex: a.publicKeyHex, createdAt: DateTime(2026, 1, 1)),
      Identity(pubkeyHex: b.publicKeyHex, createdAt: DateTime(2026, 1, 2)),
    ];
    activeIdentityPubkeyNotifier.value = a.publicKeyHex;
    selectedRelaysNotifier.value = {'wss://relay.example'};

    noteEventOfA = fakeEvent(
      id: 'cc',
      pubkey: a.publicKeyHex,
      content: 'written as identity A',
    );
    noteOfA = Note(
      id: noteEventOfA.id,
      pubkey: noteEventOfA.pubkey,
      displayName: 'A',
      content: noteEventOfA.content,
      createdAt: noteEventOfA.createdAt,
    );
    notesNotifier.value = [noteOfA];
    followingNotesNotifier.value = [noteOfA];
    relay = InMemoryRelayClient([noteEventOfA]);
    RelayClient.instance = relay;
  });

  tearDown(() {
    confirmBeforeReactingNotifier.value = true;
    profileCacheNotifier.value = const {};
  });

  Future<void> pumpButton(WidgetTester tester, Widget button) {
    return tester.pumpWidget(MaterialApp(home: Scaffold(body: button)));
  }

  group('deleting a note', () {
    testWidgets("refuses another identity's note, signing nothing", (
      tester,
    ) async {
      activeIdentityPubkeyNotifier.value = b.publicKeyHex;
      var deleted = false;
      await pumpButton(
        tester,
        DeleteButton(note: noteOfA, onDeleted: () => deleted = true),
      );

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Delete this note?'), findsNothing);
      expect(
        find.text('Only the identity that published this can remove it'),
        findsOneWidget,
      );
      expect(secrets.reads, 0);
      expect(relay.published, isEmpty);
      expect(deleted, isFalse);
      expect(notesNotifier.value, [noteOfA]);
      expect(followingNotesNotifier.value, [noteOfA]);
    });

    testWidgets('refuses a note when no identity is active', (tester) async {
      activeIdentityPubkeyNotifier.value = null;
      await pumpButton(tester, DeleteButton(note: noteOfA));

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(relay.published, isEmpty);
      expect(notesNotifier.value, [noteOfA]);
    });

    testWidgets('still deletes its own note, signed by the author', (
      tester,
    ) async {
      await pumpButton(tester, DeleteButton(note: noteOfA));

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      final deletion = relay.published.single;
      expect(deletion.kind, 5);
      expect(deletion.pubkey, a.publicKeyHex);
      expect(deletion.tags, [
        ['e', noteEventOfA.id],
        ['k', '1'],
      ]);
      expect(notesNotifier.value, isEmpty);
    });
  });

  group('un-liking and un-reposting', () {
    // Both publish a NIP-09 deletion of one of the active identity's own
    // events, which a relay that ignores the author filter may not return.
    Future<void> expectNothingRetracted(
      WidgetTester tester, {
      required int kind,
      required Widget button,
      required IconData icon,
      required String content,
    }) async {
      final othersReaction = fakeEvent(
        id: 'ee',
        pubkey: b.publicKeyHex,
        kind: kind,
        tags: [
          ['e', noteEventOfA.id],
        ],
        content: content,
      );
      final careless = _CarelessRelay([noteEventOfA, othersReaction]);
      RelayClient.instance = careless;
      confirmBeforeReactingNotifier.value = false;
      await pumpButton(tester, button);

      await tester.tap(find.byIcon(icon));
      await tester.pumpAndSettle();
      if (find.text('Continue').evaluate().isNotEmpty) {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }

      expect(careless.published, isEmpty);
      expect(secrets.reads, 0);
    }

    testWidgets("never retracts someone else's like", (tester) async {
      await expectNothingRetracted(
        tester,
        kind: 7,
        button: LikeButton(note: noteOfA.copyWith(likedByMe: true)),
        icon: Icons.favorite,
        content: '+',
      );
    });

    testWidgets("never retracts someone else's repost", (tester) async {
      await expectNothingRetracted(
        tester,
        kind: 6,
        button: RepostButton(note: noteOfA.copyWith(repostedByMe: true)),
        icon: Icons.repeat,
        content: '',
      );
    });
  });
}
