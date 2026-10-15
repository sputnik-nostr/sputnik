import 'blossom.dart';
import 'relay_client.dart';
import 'replaceable_events.dart';

class RelayBlossomListRepository {
  const RelayBlossomListRepository({this._client});

  final RelayClient? _client;

  RelayClient get client => _client ?? RelayClient.instance;

  /// The HTTPS servers in [pubkeyHex]'s kind:10063 list, or none.
  Future<List<String>> fetchServers(
    String pubkeyHex,
    Set<String> relayUrls,
  ) async {
    final own = await fetchOwnReplaceable(
      client,
      kind: 10063,
      pubkeyHex: pubkeyHex,
      relayUrls: relayUrls,
    );
    final event = own.event;
    return event == null ? const [] : blossomServersFromEvent(event);
  }
}
