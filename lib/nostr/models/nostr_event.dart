import 'text_sanitizer.dart';

final _hexPattern = RegExp(r'^[0-9a-fA-F]+$');

bool _isHex(String value, int byteLength) =>
    value.length == byteLength * 2 && _hexPattern.hasMatch(value);

class NostrEvent {
  const NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  factory NostrEvent.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final pubkey = json['pubkey'] as String;
    final sig = json['sig'] as String;
    if (!_isHex(id, 32) || !_isHex(pubkey, 32) || !_isHex(sig, 64)) {
      throw const FormatException('Malformed event id, pubkey, or sig');
    }

    return NostrEvent(
      id: id,
      pubkey: pubkey,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['created_at'] as int) * 1000,
      ),
      kind: json['kind'] as int,
      tags: (json['tags'] as List<dynamic>)
          .map((tag) => (tag as List<dynamic>).cast<String>())
          .toList(),
      content: sanitizeUtf16(json['content'] as String),
      sig: sig,
    );
  }

  final String id;
  final String pubkey;
  final DateTime createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String sig;
}

int compareNewestFirst(NostrEvent a, NostrEvent b) {
  final byTime = b.createdAt.compareTo(a.createdAt);
  return byTime != 0 ? byTime : a.id.compareTo(b.id);
}
