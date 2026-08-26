import '../services/cache_store.dart';
import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'relay_client.dart';

List<String> _followedPubkeys(NostrEvent event) {
  return [
    for (final tag in event.tags)
      if (tag.length > 1 && tag[0] == 'p') tag[1],
  ];
}

class RelayContactsRepository {
  const RelayContactsRepository({this.client = const RelayClient()});

  final RelayClient client;

  // The pubkeys a person follows, read from their own kind:3 contact list.
  Future<List<String>> fetchFollowing(
    String pubkeyHex,
    Set<String> relayUrls,
  ) async {
    if (CacheStore.isFollowingFresh(pubkeyHex)) {
      final cached = CacheStore.getFollowing(pubkeyHex);
      if (cached != null) return cached;
    }

    final events = await client.query(
      relayUrls,
      NostrFilter(kinds: const [3], authors: [pubkeyHex], limit: 1),
    );

    final following = events.isEmpty
        ? const <String>[]
        : _followedPubkeys((events..sort(compareNewestFirst)).first);

    await CacheStore.putFollowing(pubkeyHex, following);
    return following;
  }

  // The pubkeys of people whose own contact list currently includes this
  // pubkey.
  Future<List<String>> fetchFollowers(
    String pubkeyHex,
    Set<String> relayUrls,
  ) async {
    if (CacheStore.isFollowersFresh(pubkeyHex)) {
      final cached = CacheStore.getFollowers(pubkeyHex);
      if (cached != null) return cached;
    }

    final events = await client.query(
      relayUrls,
      NostrFilter(
        kinds: const [3],
        tags: {
          'p': [pubkeyHex],
        },
        limit: 500,
      ),
    );
    events.sort(compareNewestFirst);

    final latestByAuthor = <String, NostrEvent>{};
    for (final event in events) {
      latestByAuthor.putIfAbsent(event.pubkey, () => event);
    }

    final followers = [
      for (final event in latestByAuthor.values)
        if (_followedPubkeys(event).contains(pubkeyHex)) event.pubkey,
    ];

    await CacheStore.putFollowers(pubkeyHex, followers);
    return followers;
  }
}
