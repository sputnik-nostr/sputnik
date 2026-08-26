import 'bech32.dart';

// Encodes a hex pubkey into the canonical `npub` format.
String npubFromHex(String pubkeyHex) {
  final bytes = [
    for (var i = 0; i < pubkeyHex.length; i += 2)
      int.parse(pubkeyHex.substring(i, i + 2), radix: 16),
  ];
  return bech32Encode('npub', convertBits(bytes, 8, 5, pad: true));
}

// Decodes an `npub`-formatted pubkey into its raw hex form.
String? hexFromNpub(String npub) {
  final decoded = bech32Decode(npub);
  if (decoded == null || decoded.hrp != 'npub') return null;
  final bytes = convertBits(decoded.data, 5, 8, pad: false);
  if (bytes.isEmpty) return null;
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// Truncates an `npub` for display purposes.
String truncateNpub(String npub) {
  const totalLength = 20;
  const suffixLength = 5;
  if (npub.length <= totalLength) return npub;
  final prefixLength = totalLength - suffixLength - 3;
  final prefix = npub.substring(0, prefixLength);
  final suffix = npub.substring(npub.length - suffixLength);
  return '$prefix...$suffix';
}
