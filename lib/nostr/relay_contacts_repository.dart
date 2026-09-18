import '../main.dart';
import '../services/cache_store.dart';
import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'relay_client.dart';

final _pubkeyPattern = RegExp(r'^[0-9a-fA-F]{64}$');

// Which identity myFollowingNotifier holds data for, and its load future.
String? _myFollowingLoadedForPubkeyHex;
Future<void>? _myFollowingLoadingFuture;

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
    Set<String> relayUrls, {
    bool force = false,
  }) async =>
      await _fetchFollowingOrNull(pubkeyHex, relayUrls, force: force) ??
      const <String>[];

  // Null when nothing was found and some relay may still hold a list.
  Future<List<String>?> _fetchFollowingOrNull(
    String pubkeyHex,
    Set<String> relayUrls, {
    bool force = false,
  }) async {
    if (!force && CacheStore.isFollowingFresh(pubkeyHex)) {
      final cached = CacheStore.getFollowing(pubkeyHex);
      if (cached != null) return cached;
    }

    final result = await client.queryWithStatus(
      relayUrls,
      NostrFilter(kinds: const [3], authors: [pubkeyHex], limit: 1),
    );

    final author = pubkeyHex.toLowerCase();
    final own = [
      for (final event in result.events)
        if (event.kind == 3 && event.pubkey == author) event,
    ]..sort(compareNewestFirst);

    if (own.isEmpty) {
      return result.allRelaysAnswered ? const <String>[] : null;
    }

    final following = _followedPubkeys(own.first);
    await CacheStore.putFollowing(pubkeyHex, following);
    return following;
  }

  // The pubkeys of people whose own contact list currently includes this
  // pubkey.
  Future<List<String>> fetchFollowers(
    String pubkeyHex,
    Set<String> relayUrls, {
    bool force = false,
  }) async {
    if (!force && CacheStore.isFollowersFresh(pubkeyHex)) {
      final cached = CacheStore.getFollowers(pubkeyHex);
      if (cached != null) return cached;
    }

    final tagged = await client.query(
      relayUrls,
      NostrFilter(
        kinds: const [3],
        tags: {
          'p': [pubkeyHex],
        },
        limit: 500,
      ),
    );
    if (tagged.isEmpty) return const <String>[];

    final candidates = {
      for (final event in tagged)
        if (event.kind == 3) event.pubkey,
    };
    if (candidates.isEmpty) return const <String>[];

    final latestEventsByChunk = await Future.wait(
      chunkedAuthors(candidates.toList()).map(
        (chunk) => client.query(
          relayUrls,
          NostrFilter(kinds: const [3], authors: chunk),
        ),
      ),
    );
    final latestEvents = latestEventsByChunk.expand((events) => events).toList()
      ..sort(compareNewestFirst);

    final latestByAuthor = <String, NostrEvent>{};
    for (final event in latestEvents) {
      if (event.kind != 3) continue;
      latestByAuthor.putIfAbsent(event.pubkey, () => event);
    }

    final subject = pubkeyHex.toLowerCase();
    final followers = [
      for (final event in latestByAuthor.values)
        if (_followedPubkeys(event).contains(subject)) event.pubkey,
    ];

    await CacheStore.putFollowers(pubkeyHex, followers);
    return followers;
  }

  // Populates myFollowingNotifier for the active identity, once per identity.
  Future<void> ensureMyFollowingLoaded(Set<String> relayUrls) {
    final myPubkeyHex = activeIdentityPubkeyNotifier.value;
    if (myPubkeyHex == null) {
      myFollowingNotifier.value = null;
      _myFollowingLoadedForPubkeyHex = null;
      return Future.value();
    }
    if (_myFollowingLoadedForPubkeyHex == myPubkeyHex &&
        myFollowingNotifier.value != null) {
      return Future.value();
    }
    return _myFollowingLoadingFuture ??=
        _fetchFollowingOrNull(myPubkeyHex, relayUrls)
            .then((following) {
              // Left unloaded on failure so the next call retries.
              if (following == null) return;
              myFollowingNotifier.value = following.toSet();
              _myFollowingLoadedForPubkeyHex = myPubkeyHex;
            })
            .whenComplete(() => _myFollowingLoadingFuture = null);
  }

  // Raw "p" tags, kept verbatim (unlike fetchFollowing) so a republish
  // doesn't drop others' relay/petname fields. Always fresh, not cached.
  // Null when nothing was found and some relay may still hold a list.
  Future<List<List<String>>?> fetchOwnContactTags(
    String pubkeyHex,
    Set<String> relayUrls,
  ) async {
    final result = await client.queryWithStatus(
      relayUrls,
      NostrFilter(kinds: const [3], authors: [pubkeyHex], limit: 1),
    );
    final author = pubkeyHex.toLowerCase();
    final own = [
      for (final event in result.events)
        if (event.kind == 3 && event.pubkey == author) event,
    ]..sort(compareNewestFirst);
    if (own.isEmpty) return result.allRelaysAnswered ? const [] : null;

    return [
      for (final tag in own.first.tags)
        if (tag.isNotEmpty && tag[0] == 'p') tag,
    ];
  }

  // Adds/removes targetPubkeyHex and republishes the full list (NIP-02:
  // fully replaced each time; content unused).
  Future<Map<String, RelayPublishResult>> setFollowing({
    required String seckeyHex,
    required String myPubkeyHex,
    required String targetPubkeyHex,
    required bool follow,
    required Set<String> relayUrls,
  }) async {
    final outcome = await applyFollowChanges(
      seckeyHex: seckeyHex,
      myPubkeyHex: myPubkeyHex,
      changes: {targetPubkeyHex: follow},
      relayUrls: relayUrls,
    );
    return outcome.results;
  }

  // Applies follow (true) / unfollow (false) changes to the relays' list.
  Future<({Map<String, RelayPublishResult> results, Set<String> following})>
  applyFollowChanges({
    required String seckeyHex,
    required String myPubkeyHex,
    required Map<String, bool> changes,
    required Set<String> relayUrls,
  }) async {
    final currentTags = await fetchOwnContactTags(myPubkeyHex, relayUrls);
    // Publishing blind would replace the real list with just these changes.
    if (currentTags == null) {
      return (
        results: const <String, RelayPublishResult>{},
        following: const <String>{},
      );
    }

    final desired = {
      for (final tag in currentTags)
        if (tag.length > 1) tag[1].toLowerCase(),
    };
    for (final change in changes.entries) {
      final target = change.key.toLowerCase();
      if (change.value) {
        desired.add(target);
      } else {
        desired.remove(target);
      }
    }

    final results = await _publishFollowing(
      seckeyHex: seckeyHex,
      myPubkeyHex: myPubkeyHex,
      currentTags: currentTags,
      desiredFollowing: desired,
      relayUrls: relayUrls,
    );
    return (results: results, following: desired);
  }

  Future<Map<String, RelayPublishResult>> _publishFollowing({
    required String seckeyHex,
    required String myPubkeyHex,
    required List<List<String>> currentTags,
    required Set<String> desiredFollowing,
    required Set<String> relayUrls,
  }) async {
    final kept = [
      for (final tag in currentTags)
        if (tag.length > 1 && desiredFollowing.contains(tag[1].toLowerCase()))
          tag,
    ];
    final keptPubkeys = {for (final tag in kept) tag[1].toLowerCase()};
    final newTags = [
      ...kept,
      for (final pubkey in desiredFollowing)
        if (!keptPubkeys.contains(pubkey)) ['p', pubkey],
    ];

    final event = signEvent(
      seckeyHex: seckeyHex,
      pubkeyHex: myPubkeyHex,
      kind: 3,
      tags: newTags,
      content: '',
    );
    final results = await client.publish(event, relayUrls);

    final accepted = results.values.any(
      (result) => result.outcome == RelayPublishOutcome.accepted,
    );
    if (accepted) {
      await CacheStore.putFollowing(myPubkeyHex, desiredFollowing.toList());
    }
    return results;
  }
}
