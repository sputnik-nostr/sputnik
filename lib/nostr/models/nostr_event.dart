import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../hex.dart';
import '../keys.dart';
import 'text_sanitizer.dart';

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Sanitizes each tag, dropping any that contain a non-string value.
List<List<String>> _tagsFromJson(Object? raw) {
  if (raw is! List) throw const FormatException('Malformed tags');
  final tags = <List<String>>[];
  for (final tag in raw) {
    if (tag is! List) continue;
    final values = <String>[];
    var wellFormed = true;
    for (final value in tag) {
      if (value is! String) {
        wellFormed = false;
        break;
      }
      values.add(sanitizeUtf16(value));
    }
    if (wellFormed) tags.add(values);
  }
  return tags;
}

final _needsEscape = RegExp(r'[\x00-\x1f"\\]');

/// NIP-01's escapes only; [jsonEncode] escapes more, changing the ID.
const _nip01Escapes = {
  0x08: r'\b',
  0x09: r'\t',
  0x0a: r'\n',
  0x0c: r'\f',
  0x0d: r'\r',
  0x22: r'\"',
  0x5c: r'\\',
};

String _encodeString(String value) {
  if (!_needsEscape.hasMatch(value)) return '"$value"';
  final buffer = StringBuffer('"');
  for (final unit in value.codeUnits) {
    final escape = _nip01Escapes[unit];
    if (escape == null) {
      buffer.writeCharCode(unit);
    } else {
      buffer.write(escape);
    }
  }
  return (buffer..write('"')).toString();
}

String _encodeJson(Object? value) => switch (value) {
  String() => _encodeString(value),
  List() => '[${value.map(_encodeJson).join(',')}]',
  Map() =>
    '{${value.entries.map((e) => '${_encodeString('${e.key}')}:${_encodeJson(e.value)}').join(',')}}',
  _ => jsonEncode(value),
};

/// Shared by signing and verification so the two can't drift apart.
Uint8List _canonicalSerialization({
  required String pubkey,
  required Object? createdAt,
  required Object? kind,
  required Object? tags,
  required Object? content,
}) {
  return utf8.encode(_encodeJson([0, pubkey, createdAt, kind, tags, content]));
}

/// Uses the raw JSON, since the ID covers what was signed, not sanitized.
bool _isAuthentic(
  Map<String, dynamic> json,
  String id,
  String pubkey,
  String sig,
) {
  final serialized = _canonicalSerialization(
    pubkey: pubkey,
    createdAt: json['created_at'],
    kind: json['kind'],
    tags: json['tags'],
    content: json['content'],
  );
  final computedId = Uint8List.fromList(sha256.convert(serialized).bytes);
  if (!_bytesEqual(computedId, hexDecode(id))) return false;

  return verifySchnorrSignature(
    msg32: computedId,
    sig64: hexDecode(sig),
    pubkey32: hexDecode(pubkey),
  );
}

/// [NostrEvent.fromJson] throws unless the ID and signature check out.
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
    if (!isHex(id, 32) || !isHex(pubkey, 32) || !isHex(sig, 64)) {
      throw const FormatException('Malformed event ID, pubkey, or sig');
    }
    final tags = _tagsFromJson(json['tags']);
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
      tags: tags,
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'pubkey': pubkey,
    'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
    'kind': kind,
    'tags': tags,
    'content': content,
    'sig': sig,
  };
}

/// Newest first, with ties broken by ID so the order is deterministic.
int compareNewestFirst(NostrEvent a, NostrEvent b) {
  final byTime = b.createdAt.compareTo(a.createdAt);
  return byTime != 0 ? byTime : a.id.compareTo(b.id);
}

/// Builds and signs a NostrEvent with [secretKey], per NIP-01.
NostrEvent signEvent({
  required SecretKey secretKey,
  required String pubkeyHex,
  required int kind,
  List<List<String>> tags = const [],
  required String content,
  DateTime? createdAt,
}) {
  final createdAtSeconds =
      (createdAt ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;

  final serialized = _canonicalSerialization(
    pubkey: pubkeyHex,
    createdAt: createdAtSeconds,
    kind: kind,
    tags: tags,
    content: content,
  );
  final idBytes = Uint8List.fromList(sha256.convert(serialized).bytes);
  final sigBytes = signSchnorrSignature(secretKey: secretKey, msg32: idBytes);

  final event = NostrEvent(
    id: hexEncode(idBytes),
    pubkey: pubkeyHex,
    createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtSeconds * 1000),
    kind: kind,
    tags: tags,
    content: content,
    sig: hexEncode(sigBytes),
  );

  // A local event must pass the relay check too, or the binding is broken.
  if (!_isAuthentic(event.toJson(), event.id, event.pubkey, event.sig)) {
    throw StateError('Locally signed event failed its own verification');
  }

  return event;
}
