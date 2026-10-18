import 'package:flutter/foundation.dart';

import 'hex.dart';
import 'keys.dart';
import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'relay_client.dart';
import 'replaceable_events.dart';

/// When an identity's own follow list was made, and how many people it held.
/// Never whom: follow lists are kept off the disk.
typedef OwnListSize = ({DateTime createdAt, int count});

/// The newest own follow list seen for each identity, so that an older copy a
/// lagging relay returns is never built on without asking. The app keeps it
/// on disk, so it also holds after a restart.
final seenOwnContactLists = ValueNotifier<Map<String, OwnListSize>>(const {});

@visibleForTesting
void resetKnownContactLists() => seenOwnContactLists.value = const {};

/// Remembers [pubkeyHex]'s list unless a newer one is already known.
void noteOwnContactList(String pubkeyHex, DateTime createdAt, int count) {
  final key = pubkeyHex.toLowerCase();
  final known = seenOwnContactLists.value[key];
  if (known != null && !createdAt.isAfter(known.createdAt)) return;
  seenOwnContactLists.value = {
    ...seenOwnContactLists.value,
    key: (createdAt: createdAt, count: count),
  };
}

/// Forgets what was seen of [pubkeyHex]'s list, for an identity that is gone.
void forgetOwnContactList(String pubkeyHex) {
  seenOwnContactLists.value = {...seenOwnContactLists.value}
    ..remove(pubkeyHex.toLowerCase());
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

/// Whether the list found ([found], null for none) is older than [seen] or
/// missing though [seen] held people.
bool _isBehind(OwnListSize? found, OwnListSize seen) =>
    found == null ? seen.count > 0 : found.createdAt.isBefore(seen.createdAt);

/// What makes a follow list worth asking about before it is published.
enum FollowRisk {
  /// No list was found, but relays that did not answer may hold one.
  noListFound,

  /// The list found, or none at all, is behind one seen before.
  olderThanSeen,
}

/// Why a follow list is not published, and asking would not help.
enum FollowRefusal {
  /// Too few relays answered to tell which list is the current one.
  relaysSilent,

  /// The list would end up empty, on a list that may not be the real one.
  wouldEmptyList,
}

/// How [RelayContactsRepository.applyFollowChanges] ended.
sealed class FollowUpdate {
  const FollowUpdate();
}

/// The new list was sent; [results] says which relays took it.
class FollowPublished extends FollowUpdate {
  const FollowPublished({required this.results, required this.following});

  final Map<String, RelayPublishResult> results;

  /// Everyone on the list that was sent.
  final Set<String> following;
}

/// Nothing was sent: the list it would replace may not be the user's real one.
class FollowNeedsConfirmation extends FollowUpdate {
  const FollowNeedsConfirmation({
    required this.risks,
    required this.answeredRelays,
    required this.queriedRelays,
    required this.found,
    required this.lastSeen,
    required this.resultingCount,
  });

  /// What was found doubtful, not counting what the user agreed to already.
  final Set<FollowRisk> risks;
  final int answeredRelays;
  final int queriedRelays;

  /// The list the change would be built on; null when none was found.
  final OwnListSize? found;

  /// The newest list seen before, if any.
  final OwnListSize? lastSeen;

  /// How many people the new list would hold.
  final int resultingCount;
}

/// Nothing was sent, and asking would not help: the list could not be loaded.
class FollowRefused extends FollowUpdate {
  const FollowRefused(
    this.reason, {
    required this.answeredRelays,
    required this.queriedRelays,
  });

  final FollowRefusal reason;
  final int answeredRelays;
  final int queriedRelays;
}

class RelayContactsRepository {
  const RelayContactsRepository({this._client});

  final RelayClient? _client;

  RelayClient get client => _client ?? RelayClient.instance;

  /// Null when nothing was found and some relay may still hold a list.
  ///
  /// With [remember], a list found counts as the newest seen for [pubkeyHex],
  /// which later changes to it are checked against.
  Future<List<String>?> fetchFollowingOrNull(
    String pubkeyHex,
    Set<String> relayUrls, {
    bool remember = false,
  }) async {
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

    final following = _followedPubkeys(own.first.tags);
    if (remember) {
      noteOwnContactList(
        pubkeyHex,
        own.first.createdAt,
        following.toSet().length,
      );
    }
    return following;
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

  /// Follow (true) or unfollow (false); NIP-02 republishes the whole list.
  ///
  /// Nothing is sent while the list to build on may not be the user's real
  /// one: either the user is asked first ([FollowNeedsConfirmation], unless
  /// they already [agreedTo] those risks), or the list cannot be loaded well
  /// enough to ask ([FollowRefused]).
  Future<FollowUpdate> applyFollowChanges({
    required SecretKey secretKey,
    required String myPubkeyHex,
    required Map<String, bool> changes,
    required Set<String> relayUrls,
    Set<FollowRisk> agreedTo = const {},
  }) async {
    final own = await fetchOwnReplaceable(
      client,
      kind: 3,
      pubkeyHex: myPubkeyHex,
      relayUrls: relayUrls,
    );
    final base = own.event;
    final baseSize = base == null
        ? null
        : (
            createdAt: base.createdAt,
            count: _followedPubkeys(base.tags).toSet().length,
          );
    final seen = seenOwnContactLists.value[myPubkeyHex.toLowerCase()];
    if (baseSize != null) {
      noteOwnContactList(myPubkeyHex, baseSize.createdAt, baseSize.count);
    }

    // Publishing blind would replace the real list with just these changes.
    if (!own.mostRelaysAnswered) {
      return FollowRefused(
        FollowRefusal.relaysSilent,
        answeredRelays: own.answeredRelays,
        queriedRelays: own.queriedRelays,
      );
    }

    final tags = _withFollowChanges(base?.tags ?? const [], changes);
    final following = _followedPubkeys(tags).toSet();
    final risks = {
      if (base == null && !own.confirmedAbsent) FollowRisk.noListFound,
      // A list seen before that the relays return only in an older version,
      // or not at all, is lagging, not gone.
      if (seen != null && _isBehind(baseSize, seen)) FollowRisk.olderThanSeen,
    };
    if (risks.isNotEmpty && following.isEmpty) {
      return FollowRefused(
        FollowRefusal.wouldEmptyList,
        answeredRelays: own.answeredRelays,
        queriedRelays: own.queriedRelays,
      );
    }
    if (!agreedTo.containsAll(risks)) {
      return FollowNeedsConfirmation(
        risks: risks.difference(agreedTo),
        answeredRelays: own.answeredRelays,
        queriedRelays: own.queriedRelays,
        found: baseSize,
        lastSeen: seen,
        resultingCount: following.length,
      );
    }

    // After the newest list known, which an older base may not be.
    var after = base?.createdAt;
    if (seen != null && (after == null || seen.createdAt.isAfter(after))) {
      after = seen.createdAt;
    }
    final event = signEvent(
      secretKey: secretKey,
      pubkeyHex: myPubkeyHex,
      kind: 3,
      tags: tags,
      // NIP-02 leaves it unused, but some clients keep their relays in it.
      content: base?.content ?? '',
      createdAt: nextReplaceableTimeAfter(after),
    );
    final results = await client.publish(event, relayUrls);
    if (results.acceptedCount > 0) {
      noteOwnContactList(myPubkeyHex, event.createdAt, following.length);
    }
    return FollowPublished(results: results, following: following);
  }
}
