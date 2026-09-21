const _base83 =
    r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    r'abcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~';

/// Whether [hash] is a well-formed BlurHash; the decoder throws on others.
bool isValidBlurhash(String hash) {
  if (hash.length < 6 || hash.length > 4 + 2 * 9 * 10) return false;
  for (final unit in hash.codeUnits) {
    if (!_base83.codeUnits.contains(unit)) return false;
  }
  final sizeFlag = _base83.indexOf(hash[0]);
  final numY = sizeFlag ~/ 9 + 1;
  final numX = sizeFlag % 9 + 1;
  return hash.length == 4 + 2 * numX * numY;
}
