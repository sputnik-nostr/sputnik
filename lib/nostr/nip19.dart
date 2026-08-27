import 'bech32.dart';

String _hexFromBytes(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _bytesFromHex(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

String? _hexFromBareEntity(String input, String expectedHrp) {
  final decoded = bech32Decode(input);
  if (decoded == null || decoded.hrp != expectedHrp) return null;
  final bytes = convertBits(decoded.data, 5, 8, pad: false);
  if (bytes.isEmpty) return null;
  return _hexFromBytes(bytes);
}

String? _hexFromTlvSpecial(String input, String expectedHrp) {
  final decoded = bech32Decode(input);
  if (decoded == null || decoded.hrp != expectedHrp) return null;
  final bytes = convertBits(decoded.data, 5, 8, pad: false);

  var i = 0;
  while (i + 2 <= bytes.length) {
    final type = bytes[i];
    final length = bytes[i + 1];
    final valueEnd = i + 2 + length;
    if (valueEnd > bytes.length) return null;
    if (type == 0) return _hexFromBytes(bytes.sublist(i + 2, valueEnd));
    i = valueEnd;
  }
  return null;
}

// Encodes a hex pubkey into the canonical `npub` format.
String npubFromHex(String pubkeyHex) {
  return bech32Encode(
    'npub',
    convertBits(_bytesFromHex(pubkeyHex), 8, 5, pad: true),
  );
}

// Decodes an `npub`-formatted pubkey into its raw hex form.
String? hexFromNpub(String npub) => _hexFromBareEntity(npub, 'npub');

String noteFromHex(String eventIdHex) {
  return bech32Encode(
    'note',
    convertBits(_bytesFromHex(eventIdHex), 8, 5, pad: true),
  );
}

String? hexFromNote(String note) => _hexFromBareEntity(note, 'note');

String? hexFromNprofile(String nprofile) =>
    _hexFromTlvSpecial(nprofile, 'nprofile');

String? hexFromNevent(String nevent) => _hexFromTlvSpecial(nevent, 'nevent');

String truncateNpub(String npub) {
  const totalLength = 20;
  const suffixLength = 5;
  if (npub.length <= totalLength) return npub;
  final prefixLength = totalLength - suffixLength - 3;
  final prefix = npub.substring(0, prefixLength);
  final suffix = npub.substring(npub.length - suffixLength);
  return '$prefix...$suffix';
}

typedef NostrUriTarget = ({String? pubkeyHex, String? eventIdHex});

NostrUriTarget? decodeNostrUri(String text) {
  final value = text.startsWith('nostr:') ? text.substring(6) : text;

  if (value.startsWith('npub1')) {
    final hex = hexFromNpub(value);
    return hex == null ? null : (pubkeyHex: hex, eventIdHex: null);
  }
  if (value.startsWith('nprofile1')) {
    final hex = hexFromNprofile(value);
    return hex == null ? null : (pubkeyHex: hex, eventIdHex: null);
  }
  if (value.startsWith('note1')) {
    final hex = hexFromNote(value);
    return hex == null ? null : (pubkeyHex: null, eventIdHex: hex);
  }
  if (value.startsWith('nevent1')) {
    final hex = hexFromNevent(value);
    return hex == null ? null : (pubkeyHex: null, eventIdHex: hex);
  }
  return null;
}
