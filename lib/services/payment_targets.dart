import '../nostr/nostr.dart';
import 'cache_store.dart';

/// [pubkeyHex]'s payment targets, from the cache while fresh and from relays
/// otherwise.
Future<List<NostrPaymentTarget>> loadPaymentTargets(
  String pubkeyHex,
  Set<String> relayUrls, {
  bool force = false,
  RelayClient client = const RelayClient(),
}) async {
  if (!force && CacheStore.isPaymentTargetsFresh(pubkeyHex)) {
    final cached = CacheStore.getPaymentTargets(pubkeyHex);
    if (cached != null) return cached;
  }

  final targets = await RelayPaymentTargetsRepository(client: client)
      .fetchPaymentTargets(pubkeyHex, relayUrls);
  // Empty may just mean the relays failed, so it is not worth keeping.
  if (targets.isNotEmpty) {
    await CacheStore.putPaymentTargets(pubkeyHex, targets);
  }
  return targets;
}
