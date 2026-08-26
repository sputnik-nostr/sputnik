class NostrEvent {
  const NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.content,
  });

  factory NostrEvent.fromJson(Map<String, dynamic> json) {
    return NostrEvent(
      id: json['id'] as String,
      pubkey: json['pubkey'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['created_at'] as int) * 1000,
      ),
      kind: json['kind'] as int,
      content: json['content'] as String,
    );
  }

  final String id;
  final String pubkey;
  final DateTime createdAt;
  final int kind;
  final String content;
}
