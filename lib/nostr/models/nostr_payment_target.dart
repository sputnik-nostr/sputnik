import 'nostr_event.dart';

const _directUriSchemes = {
  'bitcoin',
  'ethereum',
  'lightning',
  'litecoin',
  'monero',
  'nano',
  'solana',
  'zcash',
};

class NostrPaymentTarget {
  const NostrPaymentTarget({required this.type, required this.address});

  factory NostrPaymentTarget.fromJson(Map<String, dynamic> json) =>
      NostrPaymentTarget(
        type: json['type'] as String,
        address: json['address'] as String,
      );

  final String type;
  final String address;

  Uri get launchUri => _directUriSchemes.contains(type)
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
        NostrPaymentTarget(type: tag[1], address: tag[2]),
  ];
}
