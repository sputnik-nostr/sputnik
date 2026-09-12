import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/models/nostr_event.dart';
import 'package:sputnik/nostr/models/nostr_filter.dart';
import 'package:sputnik/nostr/relay_client.dart';
import 'package:sputnik/nostr/relay_contacts_repository.dart';
import 'package:sputnik/nostr/relay_payment_targets_repository.dart';
import 'package:sputnik/nostr/relay_post_repository.dart';
import 'package:sputnik/nostr/relay_reactions_repository.dart';
import 'package:sputnik/nostr/relay_thread_repository.dart';

class _RelayReturning extends RelayClient {
  const _RelayReturning(this.events);

  final List<NostrEvent> events;

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async => events;
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
  });
}
