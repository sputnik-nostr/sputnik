import 'package:flutter/foundation.dart';

import '../main.dart';
import '../services/cache_store.dart';
import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'relay_client.dart';
import 'replaceable_events.dart';

final _pubkeyPattern = RegExp(r'^[0-9a-fA-F]{64}$');

// Newest own contact list seen or published; older copies are not built on.
final _newestOwnContactList = <String, DateTime>{};

@visibleForTesting
void resetKnownContactLists() => _newestOwnContactList.clear();

void _noteContactList(String pubkeyHex, DateTime createdAt) {
  final key = pubkeyHex.toLowerCase();
  final known = _newestOwnContactList[key];
  if (known == null || createdAt.isAfter(known)) {
    _newestOwnContactList[key] = createdAt;
  }
}

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

  Future<({List<List<String>> tags, NostrEvent? event})?> _fetchOwnContactList(
    String pubkeyHex,
    Set<String> relayUrls,
  ) async {
    final own = await fetchOwnReplaceable(
      client,
      kind: 3,
      pubkeyHex: pubkeyHex,
      relayUrls: relayUrls,
    );
    if (!own.conclusive) return null;

    final known = _newestOwnContactList[pubkeyHex.toLowerCase()];
    final event = own.event;
    if (event == null) {
      // A list we saw before that no relay returns now is lagging, not gone.
      if (known != null) return null;
      return (tags: const <List<String>>[], event: null);
    }
    if (known != null && event.createdAt.isBefore(known)) return null;
    _noteContactList(pubkeyHex, event.createdAt);

    return (
      tags: [
        for (final tag in event.tags)
          if (tag.isNotEmpty && tag[0] == 'p') tag,
      ],
      event: event,
    );
  }

  // Applies follow (true) / unfollow (false) changes to the relays' list,
  // which NIP-02 has us republish in full each time.
  Future<({Map<String, RelayPublishResult> results, Set<String> following})>
  applyFollowChanges({
    required String seckeyHex,
    required String myPubkeyHex,
    required Map<String, bool> changes,
    required Set<String> relayUrls,
  }) async {
    final current = await _fetchOwnContactList(myPubkeyHex, relayUrls);
    // Publishing blind would replace the real list with just these changes.
    if (current == null) {
      return (
        results: const <String, RelayPublishResult>{},
        following: const <String>{},
      );
    }

    final desired = {
      for (final tag in current.tags)
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
      currentTags: current.tags,
      previous: current.event,
      desiredFollowing: desired,
      relayUrls: relayUrls,
    );
    return (results: results, following: desired);
  }

  Future<Map<String, RelayPublishResult>> _publishFollowing({
    required String seckeyHex,
    required String myPubkeyHex,
    required List<List<String>> currentTags,
    required NostrEvent? previous,
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
      createdAt: nextReplaceableTime(previous),
    );
    final results = await client.publish(event, relayUrls);

    final accepted = results.values.any(
      (result) => result.outcome == RelayPublishOutcome.accepted,
    );
    if (accepted) {
      _noteContactList(myPubkeyHex, event.createdAt);
      await CacheStore.putFollowing(myPubkeyHex, desiredFollowing.toList());
    }
    return results;
  }
}
