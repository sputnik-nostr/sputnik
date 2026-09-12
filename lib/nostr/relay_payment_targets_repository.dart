import '../services/cache_store.dart';
import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'models/nostr_payment_target.dart';
import 'relay_client.dart';

class RelayPaymentTargetsRepository {
  const RelayPaymentTargetsRepository({this.client = const RelayClient()});

  final RelayClient client;

  Future<List<NostrPaymentTarget>> fetchPaymentTargets(
    String pubkeyHex,
    Set<String> relayUrls,
  ) async {
    if (CacheStore.isPaymentTargetsFresh(pubkeyHex)) {
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
}
