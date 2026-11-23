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

String _bareEntityFromHex(String hrp, String hex) =>
    bech32Encode(hrp, convertBits(hexDecode(hex), 8, 5, pad: true));

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

String npubFromHex(String pubkeyHex) => _bareEntityFromHex('npub', pubkeyHex);

String? hexFromNpub(String npub) => _hexFromBareEntity(npub, 'npub', 32);

String? hexFromNsec(String nsec) => _hexFromBareEntity(nsec, 'nsec', 32);

String nsecFromHex(String seckeyHex) => _bareEntityFromHex('nsec', seckeyHex);

String noteFromHex(String eventIdHex) => _bareEntityFromHex('note', eventIdHex);

String? hexFromNote(String note) => _hexFromBareEntity(note, 'note', 32);

/// Decodes an `nprofile` into its pubkey hex, ignoring relay hints.
String? hexFromNprofile(String nprofile) =>
    _hexFromTlvSpecial(nprofile, 'nprofile');

/// Decodes an `nevent` into its event ID hex, ignoring its other fields.
String? hexFromNevent(String nevent) => _hexFromTlvSpecial(nevent, 'nevent');

/// Encodes a hex event ID, and optionally its author, into an `nevent`.
String neventFromHex(String eventIdHex, {String? authorPubkeyHex}) {
  final bytes = [
    0,
    _tlvSpecialByteLength,
    ...hexDecode(eventIdHex),
    if (authorPubkeyHex != null) ...[2, 32, ...hexDecode(authorPubkeyHex)],
  ];
  return bech32Encode('nevent', convertBits(bytes, 8, 5, pad: true));
}

/// Elides the middle of [value] with "..." to fit [totalLength].
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

/// Matches a `nostr:` URI, or a bare npub, nprofile, note or nevent.
const nostrEntityPattern =
    r'nostr:\w+|\bn(?:pub|profile|ote|event)1[02-9ac-hj-np-z]+';

typedef NostrUriTarget = ({String? pubkeyHex, String? eventIdHex});

bool _startsWithIgnoringCase(String text, String lowerCasePrefix) =>
    text.length >= lowerCasePrefix.length &&
    text.substring(0, lowerCasePrefix.length).toLowerCase() == lowerCasePrefix;

/// An npub, nprofile, note or nevent, with or without `nostr:`; else null.
///
/// A QR code may carry the URI in uppercase, which BIP-173 allows for a whole
/// entity but never mixed with lowercase; the bech32 decoders enforce that.
/// The scheme is case-insensitive.
NostrUriTarget? decodeNostrUri(String text) {
  final value = _startsWithIgnoringCase(text, 'nostr:')
      ? text.substring(6)
      : text;

  if (_startsWithIgnoringCase(value, 'npub1')) {
    final hex = hexFromNpub(value);
    return hex == null ? null : (pubkeyHex: hex, eventIdHex: null);
  }
  if (_startsWithIgnoringCase(value, 'nprofile1')) {
    final hex = hexFromNprofile(value);
    return hex == null ? null : (pubkeyHex: hex, eventIdHex: null);
  }
  if (_startsWithIgnoringCase(value, 'note1')) {
    final hex = hexFromNote(value);
    return hex == null ? null : (pubkeyHex: null, eventIdHex: hex);
  }
  if (_startsWithIgnoringCase(value, 'nevent1')) {
    final hex = hexFromNevent(value);
    return hex == null ? null : (pubkeyHex: null, eventIdHex: hex);
  }
  return null;
}
