import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/keys.dart';
import 'package:sputnik/nostr/models/nostr_event.dart';
import 'package:sputnik/nostr/models/nostr_filter.dart';
import 'package:sputnik/nostr/relay_client.dart';
import 'package:sputnik/nostr/relay_contacts_repository.dart';
import 'package:sputnik/nostr/relay_payment_targets_repository.dart';
import 'package:sputnik/nostr/relay_post_repository.dart';
import 'package:sputnik/nostr/relay_reactions_repository.dart';
import 'package:sputnik/nostr/relay_thread_repository.dart';

import 'support/answering_relay_client.dart';

class _RelayReturning extends RelayClient with AnsweringRelayClient {
  const _RelayReturning(this.events);

  final List<NostrEvent> events;

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async => events;
}

// A mutable sibling of _RelayReturning for tests that also publish -- kept
// separate since _RelayReturning's const constructor is relied on elsewhere
// (e.g. the top-level _noReactions below).
class _RelayReturningAndPublishing extends RelayClient
    with AnsweringRelayClient {
  _RelayReturningAndPublishing(
    this.events, {
    this.publishOutcome = RelayPublishOutcome.accepted,
  });

  final List<NostrEvent> events;
  final RelayPublishOutcome publishOutcome;
  NostrEvent? lastPublished;

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async => events;

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

// A client whose relays did not all answer a query: empty results.
class _UnreachableRelay extends RelayClient {
  _UnreachableRelay({this.answered = 0});

  final int answered;
  final published = <NostrEvent>[];

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async => const [];

  @override
  Future<RelayQueryResult> queryWithStatus(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async => RelayQueryResult(
    events: const [],
    answeredRelays: answered,
    queriedRelays: 2,
  );

  @override
  Future<Map<String, RelayPublishResult>> publish(
    NostrEvent event,
    Set<String> relayUrls,
  ) async {
    published.add(event);
    return {
      for (final url in relayUrls)
        url: const RelayPublishResult(RelayPublishOutcome.accepted),
    };
  }
}

const _noReactions = RelayReactionsRepository(client: _RelayReturning([]));

void main() {
  final victim = 'aa' * 32;
  final attacker = 'bb' * 32;
  final other = 'cc' * 32;
  final wantedId = '11' * 32;
  final otherId = '22' * 32;
  final recent = DateTime.now().add(const Duration(days: 3650));
  final older = recent.subtract(const Duration(days: 1));

  NostrEvent event({
    required String pubkey,
    required int kind,
    String id = '33',
    List<List<String>> tags = const [],
    String content = '',
    DateTime? createdAt,
  }) {
    return NostrEvent(
      id: id,
      pubkey: pubkey,
      createdAt: createdAt ?? recent,
      kind: kind,
      tags: tags,
      content: content,
      sig: 'sig',
    );
  }

  group('payment targets', () {
    test('ignores an event authored by someone else', () async {
      final repository = RelayPaymentTargetsRepository(
        client: _RelayReturning([
          event(
            pubkey: attacker,
            kind: 10133,
            tags: [
              ['payto', 'bitcoin', 'attacker-address'],
            ],
          ),
        ]),
      );

      expect(
        await repository.fetchPaymentTargets(victim, {'wss://r'}),
        isEmpty,
      );
    });

    test('ignores an event of the wrong kind', () async {
      final repository = RelayPaymentTargetsRepository(
        client: _RelayReturning([
          event(
            pubkey: victim,
            kind: 1,
            tags: [
              ['payto', 'bitcoin', 'wrong-kind'],
            ],
          ),
        ]),
      );

      expect(
        await repository.fetchPaymentTargets(victim, {'wss://r'}),
        isEmpty,
      );
    });

    test('keeps the targets the profile owner signed', () async {
      final repository = RelayPaymentTargetsRepository(
        client: _RelayReturning([
          event(
            pubkey: victim,
            kind: 10133,
            tags: [
              ['payto', 'bitcoin', 'real-address'],
            ],
          ),
        ]),
      );

      final targets = await repository.fetchPaymentTargets(victim, {'wss://r'});
      expect(targets, hasLength(1));
      expect(targets.single.address, 'real-address');
    });
  });

  group('posts', () {
    test('drops posts authored by anyone but the requested author', () async {
      final repository = RelayPostRepository(
        relayUrls: const {'wss://r'},
        client: _RelayReturning([
          event(pubkey: attacker, kind: 1, id: otherId, content: 'not theirs'),
        ]),
      );

      expect(await repository.fetchPostsByAuthor(victim), isEmpty);
    });

    test('keeps posts actually authored by the requested author', () async {
      final repository = RelayPostRepository(
        relayUrls: const {'wss://r'},
        client: _RelayReturning([
          event(pubkey: victim, kind: 1, id: otherId, content: 'theirs'),
        ]),
      );

      final posts = await repository.fetchPostsByAuthor(victim);
      expect(posts, hasLength(1));
      expect(posts.single.content, 'theirs');
    });

    test('fetchPostById rejects an event with a different id', () async {
      final repository = RelayPostRepository(
        relayUrls: const {'wss://r'},
        client: _RelayReturning([
          event(pubkey: attacker, kind: 1, id: otherId, content: 'substituted'),
        ]),
      );

      expect(await repository.fetchPostById(wantedId), isNull);
    });

    test('fetchPostById returns the post whose id was asked for', () async {
      final repository = RelayPostRepository(
        relayUrls: const {'wss://r'},
        client: _RelayReturning([
          event(pubkey: attacker, kind: 1, id: otherId, content: 'decoy'),
          event(pubkey: victim, kind: 1, id: wantedId, content: 'wanted'),
        ]),
      );

      expect((await repository.fetchPostById(wantedId))?.content, 'wanted');
    });
  });

  group('contacts', () {
    test('ignores a contact list authored by someone else', () async {
      final repository = RelayContactsRepository(
        client: _RelayReturning([
          event(
            pubkey: attacker,
            kind: 3,
            tags: [
              ['p', other],
            ],
          ),
        ]),
      );

      expect(await repository.fetchFollowing(victim, {'wss://r'}), isEmpty);
    });

    test('keeps the contact list the author signed themselves', () async {
      final repository = RelayContactsRepository(
        client: _RelayReturning([
          event(
            pubkey: victim,
            kind: 3,
            tags: [
              ['p', other],
            ],
          ),
        ]),
      );

      expect(await repository.fetchFollowing(victim, {'wss://r'}), [other]);
    });

    test('drops p tags that are not 32-byte hex', () async {
      final repository = RelayContactsRepository(
        client: _RelayReturning([
          event(
            pubkey: victim,
            kind: 3,
            tags: [
              ['p', 'not-hex'],
              ['p', 'abc'],
              ['p', ''],
              ['p', other],
            ],
          ),
        ]),
      );

      expect(await repository.fetchFollowing(victim, {'wss://r'}), [other]);
    });

    test('a mention in a note does not make someone a follower', () async {
      final repository = RelayContactsRepository(
        client: _RelayReturning([
          event(
            pubkey: attacker,
            kind: 1,
            tags: [
              ['p', victim],
            ],
          ),
        ]),
      );

      expect(await repository.fetchFollowers(victim, {'wss://r'}), isEmpty);
    });
  });

  group('follow publishing', () {
    // A fresh, throwaway keypair generated for this test run only -- never
    // a real saved identity.
    final me = generateNostrKeyPair();

    test('fetchOwnContactTags keeps only "p" tags, verbatim', () async {
      final client = _RelayReturningAndPublishing([
        event(
          pubkey: me.publicKeyHex,
          kind: 3,
          tags: [
            ['p', other, 'wss://their-relay', 'petname'],
            ['not-p', 'ignored'],
          ],
        ),
      ]);
      final repository = RelayContactsRepository(client: client);

      final tags = await repository.fetchOwnContactTags(me.publicKeyHex, {
        'wss://r',
      });

      expect(tags, [
        ['p', other, 'wss://their-relay', 'petname'],
      ]);
    });

    test(
      'following someone adds them while preserving everyone else\'s tags',
      () async {
        final client = _RelayReturningAndPublishing([
          event(
            pubkey: me.publicKeyHex,
            kind: 3,
            tags: [
              ['p', other, 'wss://their-relay', 'petname'],
            ],
          ),
        ]);
        final repository = RelayContactsRepository(client: client);

        final results = await repository.setFollowing(
          seckeyHex: me.privateKeyHex,
          myPubkeyHex: me.publicKeyHex,
          targetPubkeyHex: victim,
          follow: true,
          relayUrls: {'wss://r'},
        );

        expect(
          results.values.every(
            (r) => r.outcome == RelayPublishOutcome.accepted,
          ),
          isTrue,
        );
        final published = client.lastPublished!;
        expect(published.kind, 3);
        expect(published.content, '');
        expect(published.tags, [
          ['p', other, 'wss://their-relay', 'petname'],
          ['p', victim],
        ]);
      },
    );

    test('unfollowing someone removes only their tag', () async {
      final client = _RelayReturningAndPublishing([
        event(
          pubkey: me.publicKeyHex,
          kind: 3,
          tags: [
            ['p', other, 'wss://their-relay', 'petname'],
            ['p', victim],
          ],
        ),
      ]);
      final repository = RelayContactsRepository(client: client);

      await repository.setFollowing(
        seckeyHex: me.privateKeyHex,
        myPubkeyHex: me.publicKeyHex,
        targetPubkeyHex: victim,
        follow: false,
        relayUrls: {'wss://r'},
      );

      expect(client.lastPublished!.tags, [
        ['p', other, 'wss://their-relay', 'petname'],
      ]);
    });

    test('following with no prior contact list starts a fresh one', () async {
      final client = _RelayReturningAndPublishing([]);
      final repository = RelayContactsRepository(client: client);

      await repository.setFollowing(
        seckeyHex: me.privateKeyHex,
        myPubkeyHex: me.publicKeyHex,
        targetPubkeyHex: victim,
        follow: true,
        relayUrls: {'wss://r'},
      );

      expect(client.lastPublished!.tags, [
        ['p', victim],
      ]);
    });

    test('a rejected publish is reported, not silently swallowed', () async {
      final client = _RelayReturningAndPublishing(
        [],
        publishOutcome: RelayPublishOutcome.rejected,
      );
      final repository = RelayContactsRepository(client: client);

      final results = await repository.setFollowing(
        seckeyHex: me.privateKeyHex,
        myPubkeyHex: me.publicKeyHex,
        targetPubkeyHex: victim,
        follow: true,
        relayUrls: {'wss://r'},
      );

      expect(
        results.values.every((r) => r.outcome == RelayPublishOutcome.rejected),
        isTrue,
      );
    });
  });

  group('follow-list changes', () {
    final me = generateNostrKeyPair();

    Future<({Map<String, RelayPublishResult> results, Set<String> following})>
    apply(RelayClient client, Map<String, bool> changes) {
      return RelayContactsRepository(client: client).applyFollowChanges(
        seckeyHex: me.privateKeyHex,
        myPubkeyHex: me.publicKeyHex,
        changes: changes,
        relayUrls: {'wss://r'},
      );
    }

    test('applies changes on top of the relay list, preserving kept tags and '
        'adding bare tags for new ones', () async {
      final client = _RelayReturningAndPublishing([
        event(
          pubkey: me.publicKeyHex,
          kind: 3,
          tags: [
            ['p', other, 'wss://their-relay', 'petname'],
            ['p', victim],
          ],
        ),
      ]);

      // Drop victim, keep other, add attacker.
      final outcome = await apply(client, {victim: false, attacker: true});

      expect(
        outcome.results.values.every(
          (r) => r.outcome == RelayPublishOutcome.accepted,
        ),
        isTrue,
      );
      expect(outcome.following, {other, attacker});
      expect(client.lastPublished!.tags, [
        ['p', other, 'wss://their-relay', 'petname'],
        ['p', attacker],
      ]);
    });

    test('an unchanged list is republished as it was', () async {
      final client = _RelayReturningAndPublishing([
        event(
          pubkey: me.publicKeyHex,
          kind: 3,
          tags: [
            ['p', other],
          ],
        ),
      ]);

      await apply(client, {other: true});

      expect(client.lastPublished!.tags, [
        ['p', other],
      ]);
    });

    test('starts a new list when the relays answered and have none', () async {
      final client = _RelayReturningAndPublishing(const []);

      final outcome = await apply(client, {other: true});

      expect(outcome.following, {other});
      expect(client.lastPublished!.tags, [
        ['p', other],
      ]);
    });

    test('publishes nothing when no relay answered the list query', () async {
      final client = _UnreachableRelay();

      final outcome = await apply(client, {other: true});

      expect(outcome.results, isEmpty);
      expect(client.published, isEmpty);
    });

    test(
      'publishes nothing when only some relays answered "no list"',
      () async {
        final client = _UnreachableRelay(answered: 1);

        final outcome = await apply(client, {other: true});

        expect(outcome.results, isEmpty);
        expect(client.published, isEmpty);
      },
    );
  });

  group('thread replies', () {
    test('drops events that do not reference the post', () async {
      final repository = RelayThreadRepository(
        reactionsRepository: _noReactions,
        client: _RelayReturning([
          event(
            pubkey: attacker,
            kind: 1,
            id: otherId,
            content: 'unrelated',
            tags: [
              ['e', 'dd' * 32],
            ],
          ),
        ]),
      );

      final thread = await repository.fetchThread(wantedId, {'wss://r'});
      expect(thread.replies, isEmpty);
    });

    test('drops events of the wrong kind', () async {
      final repository = RelayThreadRepository(
        reactionsRepository: _noReactions,
        client: _RelayReturning([
          event(
            pubkey: attacker,
            kind: 7,
            id: otherId,
            tags: [
              ['e', wantedId],
            ],
          ),
        ]),
      );

      final thread = await repository.fetchThread(wantedId, {'wss://r'});
      expect(thread.replies, isEmpty);
    });

    test('keeps a genuine reply', () async {
      final repository = RelayThreadRepository(
        reactionsRepository: _noReactions,
        client: _RelayReturning([
          event(
            pubkey: attacker,
            kind: 1,
            id: otherId,
            content: 'a real reply',
            tags: [
              ['e', wantedId],
            ],
          ),
        ]),
      );

      final thread = await repository.fetchThread(wantedId, {'wss://r'});
      expect(thread.replies, hasLength(1));
      expect(thread.replies.single.content, 'a real reply');
    });

    test('a marked "mention" tag does not make a note a reply', () async {
      final repository = RelayThreadRepository(
        reactionsRepository: _noReactions,
        client: _RelayReturning([
          event(
            pubkey: attacker,
            kind: 1,
            id: otherId,
            content: 'just citing it',
            tags: [
              ['e', wantedId, '', 'mention'],
              ['e', otherId, '', 'root'],
            ],
          ),
        ]),
      );

      final thread = await repository.fetchThread(wantedId, {'wss://r'});
      expect(thread.replies, isEmpty);
    });

    test('a marked "reply" tag takes priority over "root"', () async {
      final repository = RelayThreadRepository(
        reactionsRepository: _noReactions,
        client: _RelayReturning([
          event(
            pubkey: attacker,
            kind: 1,
            id: otherId,
            content: 'a reply deep in the thread',
            tags: [
              ['e', otherId, '', 'root'],
              ['e', wantedId, '', 'reply'],
            ],
          ),
        ]),
      );

      final thread = await repository.fetchThread(wantedId, {'wss://r'});
      expect(thread.replies, hasLength(1));
    });

    test('in the deprecated positional scheme, only the last e tag is the '
        'direct parent, not an earlier citation', () async {
      final repository = RelayThreadRepository(
        reactionsRepository: _noReactions,
        client: _RelayReturning([
          event(
            pubkey: attacker,
            kind: 1,
            id: otherId,
            content: 'root is wanted, but replying to something else',
            tags: [
              ['e', wantedId],
              ['e', otherId],
            ],
          ),
        ]),
      );

      final thread = await repository.fetchThread(wantedId, {'wss://r'});
      expect(thread.replies, isEmpty);
    });
  });

  group('followers', () {
    test('counts an author whose own list includes the subject', () async {
      final repository = RelayContactsRepository(
        client: _RelayReturning([
          event(
            pubkey: attacker,
            kind: 3,
            tags: [
              ['p', victim],
            ],
          ),
        ]),
      );

      expect(await repository.fetchFollowers(victim, {'wss://r'}), [attacker]);
    });

    test('keeps the newest contact list per author', () async {
      final repository = RelayContactsRepository(
        client: _RelayReturning([
          event(
            pubkey: attacker,
            kind: 3,
            createdAt: older,
            tags: [
              ['p', victim],
            ],
          ),
          event(pubkey: attacker, kind: 3, createdAt: recent, tags: const []),
        ]),
      );

      expect(await repository.fetchFollowers(victim, {'wss://r'}), isEmpty);
    });
  });

  group('reactions', () {
    test('a kind-1 note tagging the post is not a like', () async {
      final repository = RelayReactionsRepository(
        client: _RelayReturning([
          event(
            pubkey: attacker,
            kind: 1,
            tags: [
              ['e', wantedId],
            ],
          ),
        ]),
      );

      final reactions = await repository.fetchReactions(
        [wantedId],
        {'wss://r'},
      );
      expect(reactions[wantedId]!.likerPubkeys, isEmpty);
      expect(reactions[wantedId]!.reposterPubkeys, isEmpty);
    });

    test('a like is counted as a like and not as a repost', () async {
      final repository = RelayReactionsRepository(
        client: _RelayReturning([
          event(
            pubkey: attacker,
            kind: 7,
            tags: [
              ['e', wantedId],
            ],
          ),
        ]),
      );

      final reactions = await repository.fetchReactions(
        [wantedId],
        {'wss://r'},
      );
      expect(reactions[wantedId]!.likerPubkeys, [attacker]);
      expect(reactions[wantedId]!.reposterPubkeys, isEmpty);
    });

    test('a dislike ("-") is not counted as a like', () async {
      final repository = RelayReactionsRepository(
        client: _RelayReturning([
          event(
            pubkey: attacker,
            kind: 7,
            content: '-',
            tags: [
              ['e', wantedId],
            ],
          ),
        ]),
      );

      final reactions = await repository.fetchReactions(
        [wantedId],
        {'wss://r'},
      );
      expect(reactions[wantedId]!.likerPubkeys, isEmpty);
    });

    test('a custom emoji reaction is not counted as a like', () async {
      final repository = RelayReactionsRepository(
        client: _RelayReturning([
          event(
            pubkey: attacker,
            kind: 7,
            content: ':shortcode:',
            tags: [
              ['e', wantedId],
            ],
          ),
        ]),
      );

      final reactions = await repository.fetchReactions(
        [wantedId],
        {'wss://r'},
      );
      expect(reactions[wantedId]!.likerPubkeys, isEmpty);
    });

    test('only the last e tag is treated as the reaction target', () async {
      final repository = RelayReactionsRepository(
        client: _RelayReturning([
          event(
            pubkey: attacker,
            kind: 7,
            tags: [
              ['e', otherId],
              ['e', wantedId],
            ],
          ),
        ]),
      );

      final reactions = await repository.fetchReactions(
        [wantedId, otherId],
        {'wss://r'},
      );
      expect(reactions[wantedId]!.likerPubkeys, [attacker]);
      expect(reactions[otherId]!.likerPubkeys, isEmpty);
    });
  });
}
