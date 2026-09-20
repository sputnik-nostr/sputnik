import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'relay_connection_pool.dart';

export 'relay_connection_pool.dart'
    show RelayPublishOutcome, RelayPublishResult, RelayQueryResult;

/// Authors per filter, to stay within typical relay limits.
const authorsChunkSize = 100;

/// Splits [authors] into chunks of at most [authorsChunkSize].
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

/// Queries and publishes through the shared [RelayConnectionPool].
class RelayClient {
  const RelayClient({this.timeout = const Duration(seconds: 5)});

  /// How long each call waits for relay responses before giving up.
  final Duration timeout;

  /// Events matching [filter] from every relay, deduplicated by id.
  Future<List<NostrEvent>> query(Set<String> relayUrls, NostrFilter filter) {
    return RelayConnectionPool.instance.query(
      relayUrls,
      filter,
      timeout: timeout,
    );
  }

  /// Like [query], but also says how many relays actually answered.
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

  /// Publishes [event] to every relay, keyed by relay URL.
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
