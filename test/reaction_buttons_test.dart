import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/settings_store.dart';
import 'package:sputnik/widgets/reaction_buttons.dart';

import 'support/fake_secret_store.dart';

class _FakeRelayClient extends RelayClient {
  _FakeRelayClient(this._target, this._outcome, {this._ownReaction});

  final NostrEvent _target;
  final RelayPublishOutcome _outcome;

  /// The caller's own like/repost of [_target], if any -- what a "fetch my
  /// own reaction" query should find, and what a retraction removes.
  NostrEvent? _ownReaction;

  NostrEvent? lastPublished;
  int publishCount = 0;

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async {
    if (filter.kinds?.contains(1) == true) return [_target];
    final own = _ownReaction;
    if (own != null && filter.kinds?.contains(own.kind) == true) return [own];
    return const [];
  }

  @override
  Future<Map<String, RelayPublishResult>> publish(
    NostrEvent event,
    Set<String> relayUrls,
  ) async {
    lastPublished = event;
    publishCount++;
    if (event.kind == 6 || event.kind == 7) _ownReaction = event;
    if (event.kind == 5) _ownReaction = null;
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

    final author = 'bb' * 32;
    target = NostrEvent(
      id: 'cc' * 32,
      pubkey: author,
      createdAt: DateTime.now(),
      kind: 1,
      tags: const [],
      content: 'hello',
      sig: 'dd' * 64,
    );
    note = Note(
      id: target.id,
      pubkey: author,
      displayName: 'Bob',
      handle: 'bob',
      content: 'hello',
      postedAt: 'now',
      createdAt: target.createdAt,
    );
  });

  tearDown(() => confirmBeforeReactingNotifier.value = false);

  Future<void> pumpButton(WidgetTester tester, Widget button) {
    return tester.pumpWidget(MaterialApp(home: Scaffold(body: button)));
  }

  testWidgets('with confirmation off (the default), tapping like publishes '
      'immediately with no dialog', (tester) async {
    final fakeClient = _FakeRelayClient(target, RelayPublishOutcome.accepted);
    await pumpButton(tester, LikeButton(note: note, relayClient: fakeClient));

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(fakeClient.publishCount, 1);
    expect(fakeClient.lastPublished!.kind, 7);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('tapping like asks for confirmation and does not publish until '
      'confirmed', (tester) async {
    confirmBeforeReactingNotifier.value = true;
    final fakeClient = _FakeRelayClient(target, RelayPublishOutcome.accepted);
    await pumpButton(tester, LikeButton(note: note, relayClient: fakeClient));

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();

    expect(fakeClient.publishCount, 0);
    expect(find.text('Like this note?'), findsOneWidget);
  });

  testWidgets('canceling the like confirmation never publishes', (
    tester,
  ) async {
    confirmBeforeReactingNotifier.value = true;
    final fakeClient = _FakeRelayClient(target, RelayPublishOutcome.accepted);
    await pumpButton(tester, LikeButton(note: note, relayClient: fakeClient));

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(fakeClient.publishCount, 0);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
  });

  testWidgets('confirming publishes exactly one signed kind 7 like', (
    tester,
  ) async {
    confirmBeforeReactingNotifier.value = true;
    final fakeClient = _FakeRelayClient(target, RelayPublishOutcome.accepted);
    await pumpButton(tester, LikeButton(note: note, relayClient: fakeClient));

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(fakeClient.publishCount, 1);
    expect(fakeClient.lastPublished!.kind, 7);
    expect(fakeClient.lastPublished!.content, '+');
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets(
    'liking then tapping again un-likes it, via a NIP-09 deletion request',
    (tester) async {
      final fakeClient = _FakeRelayClient(target, RelayPublishOutcome.accepted);
      await pumpButton(tester, LikeButton(note: note, relayClient: fakeClient));

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();
      expect(fakeClient.publishCount, 1);
      expect(fakeClient.lastPublished!.kind, 7);
      final likeEventId = fakeClient.lastPublished!.id;
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();

      expect(fakeClient.publishCount, 2);
      expect(fakeClient.lastPublished!.kind, 5);
      expect(fakeClient.lastPublished!.tags, [
        ['e', likeEventId],
        ['k', '7'],
      ]);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    },
  );

  testWidgets('a note already liked in a previous session can be un-liked, by '
      'fetching the reaction to delete from relays first', (tester) async {
    final myLike = NostrEvent(
      id: 'ee' * 32,
      pubkey: identity.pubkeyHex,
      createdAt: DateTime.now(),
      kind: 7,
      tags: [
        ['e', target.id],
      ],
      content: '+',
      sig: 'ff' * 64,
    );
    final fakeClient = _FakeRelayClient(
      target,
      RelayPublishOutcome.accepted,
      ownReaction: myLike,
    );
    final likedNote = note.copyWith(likeCount: 1, likedByMe: true);
    await pumpButton(
      tester,
      LikeButton(note: likedNote, relayClient: fakeClient),
    );
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pumpAndSettle();

    expect(fakeClient.publishCount, 1);
    expect(fakeClient.lastPublished!.kind, 5);
    expect(fakeClient.lastPublished!.tags, [
      ['e', myLike.id],
      ['k', '7'],
    ]);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
  });

  testWidgets(
    "un-liking when no relay has the reaction shows an error and doesn't "
    'change anything',
    (tester) async {
      final fakeClient = _FakeRelayClient(target, RelayPublishOutcome.accepted);
      final likedNote = note.copyWith(likeCount: 1, likedByMe: true);
      await pumpButton(
        tester,
        LikeButton(note: likedNote, relayClient: fakeClient),
      );

      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();

      expect(fakeClient.publishCount, 0);
      expect(
        find.text('Could not find that on any of your relays'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    },
  );

  testWidgets('tapping repost asks for confirmation and does not publish until '
      'confirmed, even though confirmation-before-reacting is off (repost '
      'always confirms)', (tester) async {
    final fakeClient = _FakeRelayClient(target, RelayPublishOutcome.accepted);
    await pumpButton(tester, RepostButton(note: note, relayClient: fakeClient));

    await tester.tap(find.byIcon(Icons.repeat));
    await tester.pumpAndSettle();

    expect(fakeClient.publishCount, 0);
    expect(find.text('Repost this note?'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(fakeClient.publishCount, 1);
    expect(fakeClient.lastPublished!.kind, 6);
  });

  testWidgets(
    'reposting then tapping again un-reposts it, confirming both times '
    'since repost always asks',
    (tester) async {
      final fakeClient = _FakeRelayClient(target, RelayPublishOutcome.accepted);
      await pumpButton(
        tester,
        RepostButton(note: note, relayClient: fakeClient),
      );

      await tester.tap(find.byIcon(Icons.repeat));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(fakeClient.publishCount, 1);
      expect(fakeClient.lastPublished!.kind, 6);
      final repostEventId = fakeClient.lastPublished!.id;

      await tester.tap(find.byIcon(Icons.repeat));
      await tester.pumpAndSettle();
      expect(find.text('Remove your repost?'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(fakeClient.publishCount, 2);
      expect(fakeClient.lastPublished!.kind, 5);
      expect(fakeClient.lastPublished!.tags, [
        ['e', repostEventId],
        ['k', '6'],
      ]);
    },
  );
}
