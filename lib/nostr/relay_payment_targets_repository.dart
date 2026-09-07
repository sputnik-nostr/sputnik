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

    final targets = events.isEmpty
        ? const <NostrPaymentTarget>[]
        : paymentTargetsFromEvent((events..sort(compareNewestFirst)).first);

    await CacheStore.putPaymentTargets(pubkeyHex, targets);
    return targets;
  }
}
