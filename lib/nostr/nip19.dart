import 'bech32.dart';
import 'hex.dart';

String? _hexFromBareEntity(
  String input,
  String expectedHrp,
  int expectedByteLength,
) {
  final decoded = bech32Decode(input);
  if (decoded == null || decoded.hrp != expectedHrp) return null;
  final bytes = convertBits(decoded.data, 5, 8, pad: false);
  if (bytes.length != expectedByteLength) return null;
  return hexEncode(bytes);
}

const _tlvSpecialByteLength = 32;

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
    if (type == 0) {
      if (length != _tlvSpecialByteLength) return null;
      return hexEncode(bytes.sublist(i + 2, valueEnd));
    }
    i = valueEnd;
  }
  return null;
}

// Encodes a hex pubkey into the canonical `npub` format.
String npubFromHex(String pubkeyHex) {
  return bech32Encode(
    'npub',
    convertBits(hexDecode(pubkeyHex), 8, 5, pad: true),
  );
}

// Decodes an `npub`-formatted pubkey into its raw hex form.
String? hexFromNpub(String npub) => _hexFromBareEntity(npub, 'npub', 32);

// Decodes an `nsec`-formatted secret key into its raw hex form.
String? hexFromNsec(String nsec) => _hexFromBareEntity(nsec, 'nsec', 32);

// Encodes a hex secret key into the canonical `nsec` format.
String nsecFromHex(String seckeyHex) {
  return bech32Encode(
    'nsec',
    convertBits(hexDecode(seckeyHex), 8, 5, pad: true),
  );
}

String noteFromHex(String eventIdHex) {
  return bech32Encode(
    'note',
    convertBits(hexDecode(eventIdHex), 8, 5, pad: true),
  );
}

String? hexFromNote(String note) => _hexFromBareEntity(note, 'note', 32);

String? hexFromNprofile(String nprofile) =>
    _hexFromTlvSpecial(nprofile, 'nprofile');

String? hexFromNevent(String nevent) => _hexFromTlvSpecial(nevent, 'nevent');

String truncateMiddle(
  String value, {
  required int totalLength,
  required int suffixLength,
}) {
  if (value.length <= totalLength) return value;
  final prefixLength = totalLength - suffixLength - 3;
  final prefix = value.substring(0, prefixLength);
  final suffix = value.substring(value.length - suffixLength);
  return '$prefix...$suffix';
}

String truncateNpub(String npub) =>
    truncateMiddle(npub, totalLength: 20, suffixLength: 5);

String shortPubkey(String pubkeyHex, [int length = 8]) =>
    pubkeyHex.length <= length ? pubkeyHex : pubkeyHex.substring(0, length);

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
