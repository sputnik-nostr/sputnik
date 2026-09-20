import 'nostr_event.dart';
import 'payment_target_types.dart';

/// Lowercases [type] and maps known aliases to their canonical name.
String canonicalPaymentTargetType(String type) {
  final lower = type.toLowerCase();
  return paymentTargetTypeAliases[lower] ?? lower;
}

/// A `payto` tag from a kind 10133 event, per NIP-A3.
class NostrPaymentTarget {
  const NostrPaymentTarget({required this.type, required this.address});

  factory NostrPaymentTarget.fromJson(Map<String, dynamic> json) =>
      NostrPaymentTarget(
        type: canonicalPaymentTargetType(json['type'] as String),
        address: json['address'] as String,
      );

  final String type;
  final String address;

  /// A `<type>:<address>` URI when the type has its own scheme, otherwise
  /// `payto://<type>/<address>` (RFC 8905), per NIP-A3.
  Uri get launchUri => (paymentTargetTypes[type]?.hasDirectUriScheme ?? false)
      ? Uri(scheme: type, path: address)
      : Uri(scheme: 'payto', host: type, pathSegments: [address]);

  Map<String, dynamic> toJson() => {'type': type, 'address': address};

  @override
  bool operator ==(Object other) =>
      other is NostrPaymentTarget &&
      other.type == type &&
      other.address == address;

  @override
  int get hashCode => Object.hash(type, address);
}

/// The well-formed `payto` tags of [event]; the kind is not checked.
List<NostrPaymentTarget> paymentTargetsFromEvent(NostrEvent event) {
  return [
    for (final tag in event.tags)
      if (tag.length > 2 && tag[0] == 'payto')
        NostrPaymentTarget(
          type: canonicalPaymentTargetType(tag[1]),
          address: tag[2],
        ),
  ];
}
