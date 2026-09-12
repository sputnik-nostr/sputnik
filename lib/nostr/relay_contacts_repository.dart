import '../services/cache_store.dart';
import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'relay_client.dart';

final _pubkeyPattern = RegExp(r'^[0-9a-fA-F]{64}$');

List<String> _followedPubkeys(NostrEvent event) {
  return [
    for (final tag in event.tags)
      if (tag.length > 1 && tag[0] == 'p' && _pubkeyPattern.hasMatch(tag[1]))
        tag[1].toLowerCase(),
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
    if (events.isEmpty) return const <String>[];

    final author = pubkeyHex.toLowerCase();
    final own = [
      for (final event in events)
        if (event.kind == 3 && event.pubkey == author) event,
    ]..sort(compareNewestFirst);

    if (own.isEmpty) return const <String>[];

    final following = _followedPubkeys(own.first);
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
    if (events.isEmpty) return const <String>[];
    events.sort(compareNewestFirst);

    final latestByAuthor = <String, NostrEvent>{};
    for (final event in events) {
      if (event.kind != 3) continue;
      latestByAuthor.putIfAbsent(event.pubkey, () => event);
    }
    if (latestByAuthor.isEmpty) return const <String>[];

    final subject = pubkeyHex.toLowerCase();
    final followers = [
      for (final event in latestByAuthor.values)
        if (_followedPubkeys(event).contains(subject)) event.pubkey,
    ];

    if (followers.isNotEmpty) {
      await CacheStore.putFollowers(pubkeyHex, followers);
    }
    return followers;
  }
}
