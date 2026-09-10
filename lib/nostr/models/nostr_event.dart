import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../keys.dart';
import 'text_sanitizer.dart';

final _hexPattern = RegExp(r'^[0-9a-fA-F]+$');

bool _isHex(String value, int byteLength) =>
    value.length == byteLength * 2 && _hexPattern.hasMatch(value);

Uint8List _bytesFromHex(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _isAuthentic(
  Map<String, dynamic> json,
  String id,
  String pubkey,
  String sig,
) {
  final serialized = utf8.encode(
    jsonEncode([
      0,
      pubkey,
      json['created_at'],
      json['kind'],
      json['tags'],
      json['content'],
    ]),
  );
  final computedId = Uint8List.fromList(sha256.convert(serialized).bytes);
  if (!_bytesEqual(computedId, _bytesFromHex(id))) return false;

  return verifySchnorrSignature(
    msg32: computedId,
    sig64: _bytesFromHex(sig),
    pubkey32: _bytesFromHex(pubkey),
  );
}

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
    final id = (json['id'] as String).toLowerCase();
    final pubkey = (json['pubkey'] as String).toLowerCase();
    final sig = (json['sig'] as String).toLowerCase();
    if (!_isHex(id, 32) || !_isHex(pubkey, 32) || !_isHex(sig, 64)) {
      throw const FormatException('Malformed event id, pubkey, or sig');
    }
    if (!_isAuthentic(json, id, pubkey, sig)) {
      throw const FormatException("Event id/sig doesn't match its content");
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
