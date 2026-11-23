import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/app_state.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/cache_store.dart';
import 'package:sputnik/services/feed_loader.dart';
import 'package:sputnik/services/follow_sync.dart';

import 'support/in_memory_relay_client.dart';

/// Answers from a list of events, but holds back the queries a test names.
class _GatedRelay extends InMemoryRelayClient {
  _GatedRelay(super.events);

  final _held =
      <({bool Function(NostrFilter) matches, Completer<void> gate})>[];

  /// Holds the answers to queries that [matches] until the result completes.
  Completer<void> hold(bool Function(NostrFilter filter) matches) {
    final gate = Completer<void>();
    _held.add((matches: matches, gate: gate));
    return gate;
  }

  void releaseAll() {
    for (final held in _held) {
      if (!held.gate.isCompleted) held.gate.complete();
    }
  }

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async {
    for (final held in _held.toList()) {
      if (held.matches(filter)) await held.gate.future;
    }
    return super.query(relayUrls, filter);
  }
}

// Identities and the people they follow are plain hex: nothing is signed here.
final _a = 'a1'.padRight(64, '0');
final _b = 'b1'.padRight(64, '0');
final _alice = 'a2'.padRight(64, '0');
final _bob = 'b2'.padRight(64, '0');
final _base = DateTime.fromMillisecondsSinceEpoch(1700000000000);

NostrEvent _note(String author, int index, String name) => fakeEvent(
  id: '${author.substring(0, 2)}${index.toRadixString(16).padLeft(4, '0')}',
  pubkey: author,
  content: '$name $index',
  createdAt: _base.subtract(Duration(minutes: index)),
);

bool _postsOf(NostrFilter filter, String author, {required bool older}) =>
    (filter.kinds?.contains(1) ?? false) &&
    (filter.authors?.contains(author) ?? false) &&
    (filter.until != null) == older;

bool _contactsOf(NostrFilter filter, String author) =>
    (filter.kinds?.contains(3) ?? false) &&
    (filter.authors?.contains(author) ?? false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _GatedRelay relay;
  late VoidCallback followingListener;

  List<String> shown() => [
    for (final note in followingNotesNotifier.value ?? const <Note>[])
      note.pubkey,
  ];

  setUp(() async {
    resetFollowSync();
    await CacheStore.clearAll();
    selectedRelaysNotifier.value = {'wss://relay.example'};
    profileCacheNotifier.value = const {};
    followingNotesNotifier.value = null;
    myFollowingNotifier.value = null;
    activeIdentityPubkeyNotifier.value = _a;
    // A's follow list is fresh in memory, as after browsing as A.
    CacheStore.putFollowing(_a, [_alice]);
    relay = _GatedRelay([
      for (var i = 0; i < 40; i++) _note(_alice, i, 'alice'),
      for (var i = 0; i < 3; i++) _note(_bob, i, 'bob'),
      fakeEvent(
        id: 'cc01',
        pubkey: _b,
        kind: 3,
        tags: [
          ['p', _bob],
        ],
      ),
    ]);
    RelayClient.instance = relay;

    // What main() does when the identity changes.
    followingListener = () {
      followingNotesNotifier.value = null;
      runFeedLoad(loadFollowingFeed, 'loading the following feed');
    };
    activeIdentityPubkeyNotifier.addListener(followingListener);
  });

  tearDown(() async {
    activeIdentityPubkeyNotifier.removeListener(followingListener);
    relay.releaseAll();
    await pumpEventQueue();
    resetFollowSync();
    followingNotesNotifier.value = null;
  });

  test('B\'s feed is not A\'s first page when it arrives late', () async {
    final alicePosts = relay.hold((f) => _postsOf(f, _alice, older: false));
    final bobContacts = relay.hold((f) => _contactsOf(f, _b));
    final loadA = loadFollowingFeed();
    await pumpEventQueue();

    activeIdentityPubkeyNotifier.value = _b;
    alicePosts.complete();
    await loadA;
    await pumpEventQueue();

    expect(activeIdentityPubkeyNotifier.value, _b);
    expect(
      followingNotesNotifier.value,
      isNull,
      reason: "B's Following tab is still loading, and must not show A's",
    );

    bobContacts.complete();
    await pumpEventQueue(times: 100);
    expect(shown(), everyElement(_bob));
    expect(shown(), isNotEmpty);
  });

  test(
    'B\'s feed does not grow by A\'s older page when it arrives late',
    () async {
      await loadFollowingFeed();
      expect(followingFeedHasMore.value, isTrue);
      final aliceOlder = relay.hold((f) => _postsOf(f, _alice, older: true));
      final bobContacts = relay.hold((f) => _contactsOf(f, _b));
      final moreA = loadMoreFollowingFeed();
      await pumpEventQueue();

      activeIdentityPubkeyNotifier.value = _b;
      aliceOlder.complete();
      await moreA;
      await pumpEventQueue();

      expect(followingNotesNotifier.value, isNull);

      bobContacts.complete();
      await pumpEventQueue(times: 100);
      expect(shown(), everyElement(_bob));
      expect(followingFeedHasMore.value, isFalse);
    },
  );

  test(
    'B\'s loading feed is not replaced when A\'s hydration finishes',
    () async {
      final reactions = relay.hold(
        (f) =>
            (f.kinds?.contains(7) ?? false) || (f.kinds?.contains(6) ?? false),
      );
      final bobContacts = relay.hold((f) => _contactsOf(f, _b));
      final loadA = loadFollowingFeed();
      await pumpEventQueue();
      expect(shown(), everyElement(_alice), reason: 'A\'s page is on screen');

      activeIdentityPubkeyNotifier.value = _b;
      expect(followingNotesNotifier.value, isNull);
      reactions.complete();
      await loadA;
      await pumpEventQueue();

      expect(
        followingNotesNotifier.value,
        isNull,
        reason:
            'a feed that is still loading stays a spinner, not an empty list',
      );
      bobContacts.complete();
      await pumpEventQueue(times: 100);
      expect(shown(), everyElement(_bob));
    },
  );

  test(
    'a page for an identity that is gone is dropped, with no reload',
    () async {
      // Nothing is told that the identity changed, so only the load can notice.
      activeIdentityPubkeyNotifier.removeListener(followingListener);
      final alicePosts = relay.hold((f) => _postsOf(f, _alice, older: false));
      final loadA = loadFollowingFeed();
      await pumpEventQueue();

      activeIdentityPubkeyNotifier.value = _b;
      alicePosts.complete();
      await loadA;
      await pumpEventQueue();

      expect(followingNotesNotifier.value, isNull);
    },
  );

  test('losing the identity is not undone by a page for the old one', () async {
    final alicePosts = relay.hold((f) => _postsOf(f, _alice, older: false));
    final loadA = loadFollowingFeed();
    await pumpEventQueue();

    activeIdentityPubkeyNotifier.value = null;
    alicePosts.complete();
    await loadA;
    await pumpEventQueue();

    expect(followingNotesNotifier.value, isEmpty);
    expect(followingFeedHasMore.value, isFalse);
  });

  test('an older page from before a round trip to B does not land', () async {
    await loadFollowingFeed();
    final aliceOlder = relay.hold((f) => _postsOf(f, _alice, older: true));
    final moreA = loadMoreFollowingFeed();
    await pumpEventQueue();
    // A's follow list has to be asked for again when A is back.
    await CacheStore.clearAll();
    relay.hold((f) => _contactsOf(f, _a));
    relay.hold((f) => _contactsOf(f, _b));

    activeIdentityPubkeyNotifier.value = _b;
    activeIdentityPubkeyNotifier.value = _a;
    aliceOlder.complete();
    await moreA;
    await pumpEventQueue();

    expect(activeIdentityPubkeyNotifier.value, _a);
    expect(
      followingNotesNotifier.value,
      isNull,
      reason: 'the feed is loading again, from the newest post',
    );
  });

  test('switching away and back shows the feed once', () async {
    final alicePosts = relay.hold((f) => _postsOf(f, _alice, older: false));
    final bobContacts = relay.hold((f) => _contactsOf(f, _b));
    final firstLoad = loadFollowingFeed();
    await pumpEventQueue();

    activeIdentityPubkeyNotifier.value = _b;
    activeIdentityPubkeyNotifier.value = _a;
    alicePosts.complete();
    await firstLoad;
    await pumpEventQueue(times: 100);
    bobContacts.complete();
    await pumpEventQueue(times: 100);

    expect(activeIdentityPubkeyNotifier.value, _a);
    final ids = [for (final note in followingNotesNotifier.value!) note.id];
    expect(ids.toSet(), hasLength(ids.length));
    expect(shown(), everyElement(_alice));
    expect(ids, isNotEmpty);
  });

  test('control: once B reaches its first page, A\'s is discarded', () async {
    CacheStore.putFollowing(_b, [_bob]);
    final alicePosts = relay.hold((f) => _postsOf(f, _alice, older: false));
    final loadA = loadFollowingFeed();
    await pumpEventQueue();

    activeIdentityPubkeyNotifier.value = _b;
    await pumpEventQueue(times: 100);
    alicePosts.complete();
    await loadA;
    await pumpEventQueue();

    expect(shown(), everyElement(_bob));
    expect(shown(), isNotEmpty);
  });
}
