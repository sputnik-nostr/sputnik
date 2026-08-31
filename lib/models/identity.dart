class Identity {
  const Identity({
    required this.pubkeyHex,
    required this.privkeyHex,
    required this.createdAt,
  });

  factory Identity.fromJson(Map<String, dynamic> json) => Identity(
    pubkeyHex: json['pubkeyHex'] as String,
    privkeyHex: json['privkeyHex'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
  );

  final String pubkeyHex;
  final String privkeyHex;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'pubkeyHex': pubkeyHex,
    'privkeyHex': privkeyHex,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };
}
