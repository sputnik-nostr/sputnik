import 'package:flutter/foundation.dart';

import 'hex.dart';
import 'keys.dart';
import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'relay_client.dart';
import 'replaceable_events.dart';

/// So a lagging relay's older copy is never republished over the newest.
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

bool _isPTag(List<String> tag) => tag.length > 1 && tag[0] == 'p';

List<String> _followedPubkeys(List<List<String>> tags) {
  return [
    for (final tag in tags)
      if (_isPTag(tag) && isHex(tag[1], 32)) tag[1].toLowerCase(),
  ];
}

/// [tags] without the p tags of those unfollowed and with a bare p tag added
/// for each new follow. Every other tag stays as it was, where it was.
List<List<String>> _withFollowChanges(
  List<List<String>> tags,
  Map<String, bool> changes,
) {
  final unfollowed = {
    for (final change in changes.entries)
      if (!change.value) change.key.toLowerCase(),
  };
  final result = <List<String>>[];
  final followed = <String>{};
  for (final tag in tags) {
    if (_isPTag(tag)) {
      final pubkey = tag[1].toLowerCase();
      if (unfollowed.contains(pubkey)) continue;
      followed.add(pubkey);
    }
    result.add(tag);
  }
  for (final change in changes.entries) {
    final pubkey = change.key.toLowerCase();
    if (change.value && followed.add(pubkey)) result.add(['p', pubkey]);
  }
  return result;
}

class RelayContactsRepository {
  const RelayContactsRepository({this._client});

  final RelayClient? _client;

  RelayClient get client => _client ?? RelayClient.instance;

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
      // A silent relay may hold it, and an empty answer stays for the session.
      return result.allRelaysAnswered ? const <String>[] : null;
    }

    return _followedPubkeys(own.first.tags);
  }

  /// People whose current contact list includes [pubkeyHex].
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
    if (!own.mostRelaysAnswered) return null;

    final known = _newestOwnContactList[pubkeyHex.toLowerCase()];
    final event = own.event;
    if (event == null) {
      // A list we saw before that no relay returns now is lagging, not gone.
      if (known != null) return null;
      return (tags: const <List<String>>[], event: null);
    }
    if (known != null && event.createdAt.isBefore(known)) return null;
    _noteContactList(pubkeyHex, event.createdAt);

    return (tags: event.tags, event: event);
  }

  /// Follow (true) or unfollow (false); NIP-02 republishes the whole list.
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

    final tags = _withFollowChanges(current.tags, changes);
    final results = await _publishFollowing(
      secretKey: secretKey,
      myPubkeyHex: myPubkeyHex,
      tags: tags,
      previous: current.event,
      relayUrls: relayUrls,
    );
    return (results: results, following: _followedPubkeys(tags).toSet());
  }

  Future<Map<String, RelayPublishResult>> _publishFollowing({
    required SecretKey secretKey,
    required String myPubkeyHex,
    required List<List<String>> tags,
    required NostrEvent? previous,
    required Set<String> relayUrls,
  }) async {
    final event = signEvent(
      secretKey: secretKey,
      pubkeyHex: myPubkeyHex,
      kind: 3,
      tags: tags,
      // NIP-02 leaves it unused, but some clients keep their relays in it.
      content: previous?.content ?? '',
      createdAt: nextReplaceableTime(previous),
    );
    final results = await client.publish(event, relayUrls);
    if (results.acceptedCount > 0) {
      _noteContactList(myPubkeyHex, event.createdAt);
    }
    return results;
  }
}
