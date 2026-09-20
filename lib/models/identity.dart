/// A Nostr identity added to this app, identified by its hex public key.
class Identity {
  const Identity({required this.pubkeyHex, required this.createdAt});

  factory Identity.fromJson(Map<String, dynamic> json) => Identity(
    pubkeyHex: json['pubkeyHex'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
  );

  final String pubkeyHex;

  /// When the identity was added to this app.
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'pubkeyHex': pubkeyHex,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };
}

Identity? identityWithPubkey(List<Identity> identities, String pubkeyHex) {
  for (final identity in identities) {
    if (identity.pubkeyHex == pubkeyHex) return identity;
  }
  return null;
}
