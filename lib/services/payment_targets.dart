import '../nostr/nostr.dart';
import 'cache_store.dart';

/// [pubkeyHex]'s payment targets, from the cache while fresh.
Future<List<NostrPaymentTarget>> loadPaymentTargets(
  String pubkeyHex,
  Set<String> relayUrls, {
  bool force = false,
}) async {
  final cached = force ? null : CacheStore.freshPaymentTargets(pubkeyHex);
  if (cached != null) return cached;

  final targets = await RelayPaymentTargetsRepository().fetchPaymentTargets(
    pubkeyHex,
    relayUrls,
  );
  // Empty may just mean the relays failed, so it is not worth keeping.
  if (targets.isNotEmpty) {
    await CacheStore.putPaymentTargets(pubkeyHex, targets);
  }
  return targets;
}
