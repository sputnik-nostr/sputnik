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

/// NIP-01's escapes only, and every other character is written as it is.
/// [jsonEncode] escapes more, changing the ID; see [_isAuthentic].
const _nip01Escapes = {
  0x08: r'\b',
  0x09: r'\t',
  0x0a: r'\n',
  0x0c: r'\f',
  0x0d: r'\r',
  0x22: r'\"',
  0x5c: r'\\',
};

/// The C0 controls without a short escape: U+0000-U+0007, U+000B and
/// U+000E-U+001F.
///
/// NIP-01 says to hash them as they are, but nostr-tools, serde_json and
/// strfry hash them as \u00xx, so software that hashes the other way than
/// the signer rejects the event.
final _unescapedControls = RegExp(r'[\x00-\x07\x0b\x0e-\x1f]');

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
String _canonicalSerialization({
  required String pubkey,
  required Object? createdAt,
  required Object? kind,
  required Object? tags,
  required Object? content,
}) {
  return _encodeJson([0, pubkey, createdAt, kind, tags, content]);
}

Uint8List _hash(String serialization) =>
    Uint8List.fromList(sha256.convert(utf8.encode(serialization)).bytes);

/// [serialization] with the controls NIP-01 leaves raw written as \u00xx.
String _withEscapedControls(String serialization) =>
    serialization.replaceAllMapped(
      _unescapedControls,
      (match) =>
          '\\u00${match[0]!.codeUnitAt(0).toRadixString(16).padLeft(2, '0')}',
    );

/// Uses the raw JSON, since the ID covers what was signed, not sanitized.
///
/// The controls NIP-01 leaves raw are hashed either as they are, as the NIP
/// says, or as \u00xx, as most JSON encoders write them, and an ID that
/// matches either is accepted. That can't admit a forgery: both are encodings
/// of the same fields, the ID commits to one byte string, which decodes to
/// exactly those fields, and the signature commits to the ID. So the key
/// holder signed these fields whichever way they were written.
bool _isAuthentic(
  Map<String, dynamic> json,
  String id,
  String pubkey,
  String sig,
) {
  final expectedId = hexDecode(id);
  final literal = _canonicalSerialization(
    pubkey: pubkey,
    createdAt: json['created_at'],
    kind: json['kind'],
    tags: json['tags'],
    content: json['content'],
  );
  var computedId = _hash(literal);
  if (!_bytesEqual(computedId, expectedId)) {
    // Without such a control there is only one way to write the event.
    if (!_unescapedControls.hasMatch(literal)) return false;
    computedId = _hash(_withEscapedControls(literal));
    if (!_bytesEqual(computedId, expectedId)) return false;
  }

  return verifySchnorrSignature(
    msg32: computedId,
    sig64: hexDecode(sig),
    pubkey32: hexDecode(pubkey),
  );
}

/// The latest `created_at`, in seconds, that a [DateTime] can hold. A later
/// one makes it throw, or wraps around once it is converted to milliseconds.
const _maxCreatedAtSeconds = 8640000000000;

/// NIP-01: "an integer between 0 and 65535".
const _maxKind = 65535;

/// [NostrEvent.fromJson] throws unless the ID and signature check out and the
/// `created_at` and `kind` are in range.
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
    // Before the signature check, so such an event costs no crypto.
    final createdAt = json['created_at'];
    final kind = json['kind'];
    if (createdAt is! int ||
        createdAt < 0 ||
        createdAt > _maxCreatedAtSeconds) {
      throw const FormatException('Malformed created_at');
    }
    if (kind is! int || kind < 0 || kind > _maxKind) {
      throw const FormatException('Malformed kind');
    }
    final tags = _tagsFromJson(json['tags']);
    if (!_isAuthentic(json, id, pubkey, sig)) {
      throw const FormatException("Event id/sig doesn't match its content");
    }

    return NostrEvent(
      id: id,
      pubkey: pubkey,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
      kind: kind,
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

/// Lone surrogates go first, so that removing a control between two halves
/// can't join them into a character the author never wrote.
String _signable(String text) =>
    sanitizeUtf16(text).replaceAll(_unescapedControls, '');

/// Builds and signs a NostrEvent with [secretKey], per NIP-01.
///
/// The controls that clients hash differently are removed from [tags] and
/// [content] and lone surrogates replaced, so the ID can be computed only one
/// way and the event holds exactly the text it commits to.
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
  final signedTags = [
    for (final tag in tags) [for (final value in tag) _signable(value)],
  ];
  final signedContent = _signable(content);

  final serialized = _canonicalSerialization(
    pubkey: pubkeyHex,
    createdAt: createdAtSeconds,
    kind: kind,
    tags: signedTags,
    content: signedContent,
  );
  final idBytes = _hash(serialized);
  final sigBytes = signSchnorrSignature(secretKey: secretKey, msg32: idBytes);

  final event = NostrEvent(
    id: hexEncode(idBytes),
    pubkey: pubkeyHex,
    createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtSeconds * 1000),
    kind: kind,
    tags: signedTags,
    content: signedContent,
    sig: hexEncode(sigBytes),
  );

  // A local event must pass the relay check too, or the binding is broken.
  if (!_isAuthentic(event.toJson(), event.id, event.pubkey, event.sig)) {
    throw StateError('Locally signed event failed its own verification');
  }

  return event;
}
