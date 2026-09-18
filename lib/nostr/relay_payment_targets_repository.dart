import '../services/cache_store.dart';
import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'models/nostr_payment_target.dart';
import 'relay_client.dart';
import 'replaceable_events.dart';

class RelayPaymentTargetsRepository {
  const RelayPaymentTargetsRepository({this.client = const RelayClient()});

  final RelayClient client;

  Future<List<NostrPaymentTarget>> fetchPaymentTargets(
    String pubkeyHex,
    Set<String> relayUrls, {
    bool force = false,
  }) async {
    if (!force && CacheStore.isPaymentTargetsFresh(pubkeyHex)) {
      final cached = CacheStore.getPaymentTargets(pubkeyHex);
      if (cached != null) return cached;
    }

    final events = await client.query(
      relayUrls,
      NostrFilter(kinds: const [10133], authors: [pubkeyHex], limit: 1),
    );

    if (events.isEmpty) return const <NostrPaymentTarget>[];

    final author = pubkeyHex.toLowerCase();
    final own = [
      for (final event in events)
        if (event.kind == 10133 && event.pubkey == author) event,
    ]..sort(compareNewestFirst);

    if (own.isEmpty) return const <NostrPaymentTarget>[];

    final targets = paymentTargetsFromEvent(own.first);
    await CacheStore.putPaymentTargets(pubkeyHex, targets);
    return targets;
  }

  // Uncached, so an edit builds on what is really published.
  Future<OwnEvent> fetchOwnPaymentTargetsEvent(
    String pubkeyHex,
    Set<String> relayUrls,
  ) {
    return fetchOwnReplaceable(
      client,
      kind: 10133,
      pubkeyHex: pubkeyHex,
      relayUrls: relayUrls,
    );
  }

  // Publishes [paytoTags] as the whole set; other tags carry over from [base].
  Future<({NostrEvent event, Map<String, RelayPublishResult> results})>
  publishPaymentTargets({
    required String seckeyHex,
    required String pubkeyHex,
    required NostrEvent? base,
    required List<List<String>> paytoTags,
    required Set<String> relayUrls,
  }) async {
    final event = signEvent(
      seckeyHex: seckeyHex,
      pubkeyHex: pubkeyHex,
      kind: 10133,
      tags: [
        for (final tag in base?.tags ?? const <List<String>>[])
          if (tag.isEmpty || tag[0] != 'payto') tag,
        ...paytoTags,
      ],
      content: '',
      createdAt: nextReplaceableTime(base),
    );
    final results = await client.publish(event, relayUrls);
    return (event: event, results: results);
  }
}
