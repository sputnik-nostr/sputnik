import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/settings_store.dart';
import 'package:sputnik/widgets/delete_button.dart';

import 'support/fake_secret_store.dart';

class _FakeRelayClient extends RelayClient {
  _FakeRelayClient(this._target, this._outcome);

  final NostrEvent _target;
  final RelayPublishOutcome _outcome;

  NostrEvent? lastPublished;
  int publishCount = 0;

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async {
    if (filter.kinds?.contains(1) == true) return [_target];
    return const [];
  }

  @override
  Future<Map<String, RelayPublishResult>> publish(
    NostrEvent event,
    Set<String> relayUrls,
  ) async {
    lastPublished = event;
    publishCount++;
    return {for (final url in relayUrls) url: RelayPublishResult(_outcome)};
  }
}

void main() {
  late Identity identity;
  late NostrEvent target;
  late Note note;

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

    SettingsStore.secretStore = FakeSecretStore();
    await SettingsStore.savePrivateKey(
      identity.pubkeyHex,
      keypair.privateKeyHex,
    );

    target = NostrEvent(
      id: 'cc' * 32,
      pubkey: identity.pubkeyHex,
      createdAt: DateTime.now(),
      kind: 1,
      tags: const [],
      content: 'hello',
      sig: 'dd' * 64,
    );
    note = Note(
      id: target.id,
      pubkey: identity.pubkeyHex,
      displayName: 'Me',
      handle: 'me',
      content: 'hello',
      postedAt: 'now',
      createdAt: target.createdAt,
    );
    notesNotifier.value = [note];
    followingNotesNotifier.value = [note];
  });

  Future<void> pumpButton(WidgetTester tester, Widget button) {
    return tester.pumpWidget(MaterialApp(home: Scaffold(body: button)));
  }

  testWidgets('tapping delete asks for confirmation and does not publish until '
      'confirmed', (tester) async {
    final fakeClient = _FakeRelayClient(target, RelayPublishOutcome.accepted);
    await pumpButton(tester, DeleteButton(note: note, relayClient: fakeClient));

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(fakeClient.publishCount, 0);
    expect(find.text('Delete this note?'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(fakeClient.publishCount, 1);
    expect(fakeClient.lastPublished!.kind, 5);
    expect(fakeClient.lastPublished!.tags, [
      ['e', target.id],
      ['k', '1'],
    ]);
  });

  testWidgets('canceling the confirmation never publishes', (tester) async {
    final fakeClient = _FakeRelayClient(target, RelayPublishOutcome.accepted);
    await pumpButton(tester, DeleteButton(note: note, relayClient: fakeClient));

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(fakeClient.publishCount, 0);
  });

  testWidgets('a successful delete drops the note from the cached feeds', (
    tester,
  ) async {
    final fakeClient = _FakeRelayClient(target, RelayPublishOutcome.accepted);
    await pumpButton(tester, DeleteButton(note: note, relayClient: fakeClient));

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(notesNotifier.value, isEmpty);
    expect(followingNotesNotifier.value, isEmpty);
  });

  testWidgets('a successful delete calls onDeleted', (tester) async {
    final fakeClient = _FakeRelayClient(target, RelayPublishOutcome.accepted);
    var deleted = false;
    await pumpButton(
      tester,
      DeleteButton(
        note: note,
        relayClient: fakeClient,
        onDeleted: () => deleted = true,
      ),
    );

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
  });

  testWidgets(
    'a rejected publish does not call onDeleted or touch the cached feeds',
    (tester) async {
      final fakeClient = _FakeRelayClient(target, RelayPublishOutcome.rejected);
      var deleted = false;
      await pumpButton(
        tester,
        DeleteButton(
          note: note,
          relayClient: fakeClient,
          onDeleted: () => deleted = true,
        ),
      );

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(deleted, isFalse);
      expect(notesNotifier.value, [note]);
      expect(followingNotesNotifier.value, [note]);
    },
  );
}
