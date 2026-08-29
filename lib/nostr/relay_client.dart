import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'relay_connection_pool.dart';

class RelayClient {
  const RelayClient({this.timeout = const Duration(seconds: 5)});

  final Duration timeout;

  Future<List<NostrEvent>> query(Set<String> relayUrls, NostrFilter filter) {
    return RelayConnectionPool.instance.query(
      relayUrls,
      filter,
      timeout: timeout,
    );
  }
}
