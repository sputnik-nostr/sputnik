import 'nostr_event.dart';
import 'payment_target_types.dart';

String _canonicalPaymentTargetType(String type) {
  final lower = type.toLowerCase();
  return paymentTargetTypeAliases[lower] ?? lower;
}

class NostrPaymentTarget {
  const NostrPaymentTarget({required this.type, required this.address});

  factory NostrPaymentTarget.fromJson(Map<String, dynamic> json) =>
      NostrPaymentTarget(
        type: _canonicalPaymentTargetType(json['type'] as String),
        address: json['address'] as String,
      );

  final String type;
  final String address;

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

List<NostrPaymentTarget> paymentTargetsFromEvent(NostrEvent event) {
  return [
    for (final tag in event.tags)
      if (tag.length > 2 && tag[0] == 'payto')
        NostrPaymentTarget(
          type: _canonicalPaymentTargetType(tag[1]),
          address: tag[2],
        ),
  ];
}
