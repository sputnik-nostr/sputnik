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
    final events = await client.query(
      relayUrls,
      NostrFilter(kinds: const [3], authors: [pubkeyHex], limit: 1),
    );
    if (events.isEmpty) return [];

    events.sort(compareNewestFirst);
    return _followedPubkeys(events.first);
  }

  // The pubkeys of people whose own contact list currently includes this
  // pubkey.
  Future<List<String>> fetchFollowers(
    String pubkeyHex,
    Set<String> relayUrls,
  ) async {
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

    return [
      for (final event in latestByAuthor.values)
        if (_followedPubkeys(event).contains(pubkeyHex)) event.pubkey,
    ];
  }
}
