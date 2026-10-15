import 'package:flutter/foundation.dart';

import 'hex.dart';
import 'keys.dart';
import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'relay_client.dart';
import 'replaceable_events.dart';

/// Newest own contact list seen or published, per pubkey, so a lagging relay's
/// older copy is never republished over it.
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

List<String> _followedPubkeys(NostrEvent event) {
  return [
    for (final tag in event.tags)
      if (tag.length > 1 && tag[0] == 'p' && isHex(tag[1], 32))
        tag[1].toLowerCase(),
  ];
}

class RelayContactsRepository {
  const RelayContactsRepository({this.client = const RelayClient()});

  final RelayClient client;

  /// The pubkeys a person follows, read from their own kind:3 contact list.
  Future<List<String>> fetchFollowing(
    String pubkeyHex,
    Set<String> relayUrls,
  ) async =>
      await fetchFollowingOrNull(pubkeyHex, relayUrls) ?? const <String>[];

  /// Null when nothing was found and some relay may still hold a list.
  Future<List<String>?> fetchFollowingOrNull(
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

    if (own.isEmpty) {
      return result.allRelaysAnswered ? const <String>[] : null;
    }

    return _followedPubkeys(own.first);
  }

  /// The pubkeys of people whose own contact list currently includes this
  /// pubkey.
  Future<List<String>> fetchFollowers(
    String pubkeyHex,
    Set<String> relayUrls,
  ) async {
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

    // A lagging relay may still tag us from a list its author has replaced.
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
    return [
      for (final event in latestByAuthor.values)
        if (event.tags.any(
          (tag) =>
              tag.length > 1 &&
              tag[0] == 'p' &&
              tag[1].toLowerCase() == subject,
        ))
          event.pubkey,
    ];
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

  /// Applies follow (true) / unfollow (false) changes to the relays' list,
  /// which NIP-02 has us republish in full each time.
  Future<({Map<String, RelayPublishResult> results, Set<String> following})>
  applyFollowChanges({
    required SecretKey secretKey,
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
      secretKey: secretKey,
      myPubkeyHex: myPubkeyHex,
      currentTags: current.tags,
      previous: current.event,
      desiredFollowing: desired,
      relayUrls: relayUrls,
    );
    return (results: results, following: desired);
  }

  Future<Map<String, RelayPublishResult>> _publishFollowing({
    required SecretKey secretKey,
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
      secretKey: secretKey,
      pubkeyHex: myPubkeyHex,
      kind: 3,
      tags: newTags,
      content: '',
      createdAt: nextReplaceableTime(previous),
    );
    final results = await client.publish(event, relayUrls);
    if (results.acceptedCount > 0) {
      _noteContactList(myPubkeyHex, event.createdAt);
    }
    return results;
  }
}
