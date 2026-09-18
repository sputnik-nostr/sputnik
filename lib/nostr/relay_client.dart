import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'relay_connection_pool.dart';

export 'relay_connection_pool.dart'
    show RelayPublishOutcome, RelayPublishResult, RelayQueryResult;

const authorsChunkSize = 100;

List<List<String>> chunkedAuthors(List<String> authors) {
  return [
    for (var i = 0; i < authors.length; i += authorsChunkSize)
      authors.sublist(
        i,
        i + authorsChunkSize > authors.length
            ? authors.length
            : i + authorsChunkSize,
      ),
  ];
}

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

  // Like [query], but also says how many relays actually answered.
  Future<RelayQueryResult> queryWithStatus(
    Set<String> relayUrls,
    NostrFilter filter,
  ) {
    return RelayConnectionPool.instance.queryWithStatus(
      relayUrls,
      filter,
      timeout: timeout,
    );
  }

  Future<Map<String, RelayPublishResult>> publish(
    NostrEvent event,
    Set<String> relayUrls,
  ) {
    return RelayConnectionPool.instance.publishToAll(
      event,
      relayUrls,
      timeout: timeout,
    );
  }
}
