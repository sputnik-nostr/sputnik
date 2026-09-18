import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/screens/identities_screen.dart';
import 'package:sputnik/screens/profile_screen.dart';
import 'package:sputnik/widgets/compact_tab_bar.dart';
import 'package:sputnik/widgets/count_label.dart';
import 'package:sputnik/services/follow_sync.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/answering_relay_client.dart';

class _FakeSecretStore implements SecretStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

class _FakeRelayClient extends RelayClient with AnsweringRelayClient {
  _FakeRelayClient({
    this.publishOutcome = RelayPublishOutcome.accepted,
    this.paymentTargetTags = const [],
  });

  final RelayPublishOutcome publishOutcome;
  final List<List<String>> paymentTargetTags;
  NostrEvent? lastPublished;
  int queryCount = 0;

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async {
    queryCount++;
    if (filter.kinds?.contains(10133) != true) return const [];
    final author = filter.authors?.first;
    if (author == null || paymentTargetTags.isEmpty) return const [];
    return [
      NostrEvent(
        id: 'id',
        pubkey: author,
        createdAt: DateTime.now(),
        kind: 10133,
        tags: paymentTargetTags,
        content: '',
        sig: 'sig',
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
    hiddenPaymentTargetTypesNotifier.value = const {};
    profileCacheNotifier.value = const {};
    notesNotifier.value = const [];
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

  group('posts and replies tabs', () {
    final pubkeyHex = 'b' * 64;

    // Notes are shown newest first, so an id's age makes the order predictable.
    Note note(String id, String content, {required bool isReply}) => Note(
      id: id,
      pubkey: pubkeyHex,
      displayName: 'Bob',
      handle: 'bob',
      content: content,
      postedAt: '1m',
      createdAt: DateTime.now().subtract(
        Duration(minutes: int.tryParse(id) ?? 0),
      ),
      isReply: isReply,
    );

    Future<void> pumpProfile(WidgetTester tester) async {
      notesNotifier.value = [
        note('1', 'a top-level post', isReply: false),
        note('2', 'a reply to someone', isReply: true),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            pubkeyHex: pubkeyHex,
            relayClient: _FakeRelayClient(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the relays link opens their relay list', (tester) async {
      await pumpProfile(tester);

      await tester.ensureVisible(find.byKey(const Key('profileRelaysButton')));
      await tester.tap(find.byKey(const Key('profileRelaysButton')));
      await tester.pumpAndSettle();

      expect(find.text('No relay list found'), findsOneWidget);
    });

    testWidgets('the relays chip sits apart from the follow counts', (
      tester,
    ) async {
      await pumpProfile(tester);

      final chip = tester.getRect(find.byKey(const Key('profileRelaysButton')));
      final followers = tester.getRect(find.byType(CountLabel).last);

      expect(find.text('Relays'), findsOneWidget);
      expect(chip.left - followers.right, greaterThan(32));

      final icon = tester.getRect(
        find.descendant(
          of: find.byKey(const Key('profileRelaysButton')),
          matching: find.byIcon(Icons.dns_outlined),
        ),
      );
      final label = tester.getRect(find.text('Relays'));
      expect(icon.left - chip.left, closeTo(chip.right - label.right, 0.5));
    });

    testWidgets('opens on posts and hides replies', (tester) async {
      await pumpProfile(tester);

      expect(find.text('a top-level post'), findsOneWidget);
      expect(find.text('a reply to someone'), findsNothing);
    });

    testWidgets('the replies tab shows replies and hides posts', (
      tester,
    ) async {
      await pumpProfile(tester);

      await tester.tap(find.text('Replies'));
      await tester.pumpAndSettle();

      expect(find.text('a reply to someone'), findsOneWidget);
      expect(find.text('a top-level post'), findsNothing);
    });

    testWidgets('swiping moves between posts and replies', (tester) async {
      await pumpProfile(tester);

      await tester.drag(find.byType(TabBarView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('a reply to someone'), findsOneWidget);
      expect(find.text('a top-level post'), findsNothing);

      await tester.drag(find.byType(TabBarView), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.text('a top-level post'), findsOneWidget);
      expect(find.text('a reply to someone'), findsNothing);
    });

    testWidgets('scrolling a long list moves the header out of the way', (
      tester,
    ) async {
      notesNotifier.value = [
        for (var i = 0; i < 30; i++)
          note('$i', 'post number $i', isReply: false),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            pubkeyHex: pubkeyHex,
            relayClient: _FakeRelayClient(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final before = tester.getTopLeft(find.byType(CompactTabBar)).dy;
      await tester.drag(find.byType(CompactTabBar), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.byType(CompactTabBar)).dy,
        lessThan(before),
      );
      for (var i = 0; i < 4; i++) {
        await tester.drag(
          find.byType(NestedScrollView),
          const Offset(0, -1500),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('post number 29'), findsOneWidget);
    });

    testWidgets('pulling down refreshes the profile', (tester) async {
      final client = _FakeRelayClient();
      notesNotifier.value = [note('1', 'a top-level post', isReply: false)];
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(pubkeyHex: pubkeyHex, relayClient: client),
        ),
      );
      await tester.pumpAndSettle();
      final before = client.queryCount;

      await tester.fling(
        find.text('a top-level post'),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();

      expect(client.queryCount, greaterThan(before));
    });

    testWidgets('an empty tab says so', (tester) async {
      notesNotifier.value = [note('1', 'only a post', isReply: false)];
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            pubkeyHex: pubkeyHex,
            relayClient: _FakeRelayClient(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Replies'));
      await tester.pumpAndSettle();

      expect(find.text('No replies yet'), findsOneWidget);
    });
  });

  testWidgets('a hidden payment target type is not shown on a profile', (
    tester,
  ) async {
    hiddenPaymentTargetTypesNotifier.value = {'monero'};
    final fakeClient = _FakeRelayClient(
      paymentTargetTags: [
        ['payto', 'bitcoin', 'bc1qexample'],
        ['payto', 'monero', '4Aexample'],
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(pubkeyHex: 'b' * 64, relayClient: fakeClient),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('paymentTarget_bitcoin_bc1qexample')),
      findsOneWidget,
    );
    expect(find.byKey(Key('paymentTarget_monero_4Aexample')), findsNothing);
  });

  testWidgets(
    'a legacy monero field in profile metadata fills in when no payto tag '
    'covers it',
    (tester) async {
      final pubkeyHex = 'b' * 64;
      profileCacheNotifier.value = {
        pubkeyHex: const NostrMetadata(legacyMoneroAddress: '4Alegacy'),
      };
      final fakeClient = _FakeRelayClient(
        paymentTargetTags: [
          ['payto', 'bitcoin', 'bc1qexample'],
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(pubkeyHex: pubkeyHex, relayClient: fakeClient),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(Key('paymentTarget_bitcoin_bc1qexample')),
        findsOneWidget,
      );
      expect(find.byKey(Key('paymentTarget_monero_4Alegacy')), findsOneWidget);
    },
  );

  testWidgets(
    'a real payto monero tag takes priority over the legacy metadata field',
    (tester) async {
      final pubkeyHex = 'b' * 64;
      profileCacheNotifier.value = {
        pubkeyHex: const NostrMetadata(legacyMoneroAddress: '4Alegacy'),
      };
      final fakeClient = _FakeRelayClient(
        paymentTargetTags: [
          ['payto', 'monero', '4Areal'],
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(pubkeyHex: pubkeyHex, relayClient: fakeClient),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(Key('paymentTarget_monero_4Areal')), findsOneWidget);
      expect(find.byKey(Key('paymentTarget_monero_4Alegacy')), findsNothing);
    },
  );

  testWidgets(
    'hiding the monero type also hides the legacy metadata fallback',
    (tester) async {
      hiddenPaymentTargetTypesNotifier.value = {'monero'};
      final pubkeyHex = 'b' * 64;
      profileCacheNotifier.value = {
        pubkeyHex: const NostrMetadata(legacyMoneroAddress: '4Alegacy'),
      };

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            pubkeyHex: pubkeyHex,
            relayClient: _FakeRelayClient(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(Key('paymentTarget_monero_4Alegacy')), findsNothing);
    },
  );

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
        // A failed publish is retried later; don't leave that timer running.
        resetFollowSync();
      },
    );
  });
}
