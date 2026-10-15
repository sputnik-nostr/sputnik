import 'keys.dart';
import 'models/nostr_event.dart';
import 'models/nostr_payment_target.dart';
import 'relay_client.dart';
import 'replaceable_events.dart';

class RelayPaymentTargetsRepository {
  const RelayPaymentTargetsRepository({this._client});

  final RelayClient? _client;

  RelayClient get client => _client ?? RelayClient.instance;

  /// The payment targets [pubkeyHex] has published, uncached.
  Future<List<NostrPaymentTarget>> fetchPaymentTargets(
    String pubkeyHex,
    Set<String> relayUrls,
  ) async {
    final event = (await fetchOwnPaymentTargetsEvent(
      pubkeyHex,
      relayUrls,
    )).event;
    return event == null ? const [] : paymentTargetsFromEvent(event);
  }

  /// Uncached, so an edit builds on what is really published.
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

  /// Publishes [paytoTags] as the whole set; other tags carry over from [base].
  Future<({NostrEvent event, Map<String, RelayPublishResult> results})>
  publishPaymentTargets({
    required SecretKey secretKey,
    required String pubkeyHex,
    required NostrEvent? base,
    required List<List<String>> paytoTags,
    required Set<String> relayUrls,
  }) async {
    final event = signEvent(
      secretKey: secretKey,
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
