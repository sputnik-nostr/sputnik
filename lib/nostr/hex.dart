import 'dart:typed_data';

const _digits = '0123456789abcdef';

/// The value of the hex digit [codeUnit], or -1 if it is not one.
int hexDigitValue(int codeUnit) {
  if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30;
  final lower = codeUnit | 0x20;
  if (lower >= 0x61 && lower <= 0x66) return lower - 0x61 + 10;
  return -1;
}

/// Whether [value] is exactly [byteLength] bytes written as hex.
bool isHex(String value, int byteLength) {
  if (value.length != byteLength * 2) return false;
  for (var i = 0; i < value.length; i++) {
    if (hexDigitValue(value.codeUnitAt(i)) < 0) return false;
  }
  return true;
}

String hexEncode(List<int> bytes) {
  final codeUnits = Uint8List(bytes.length * 2);
  for (var i = 0; i < bytes.length; i++) {
    codeUnits[i * 2] = _digits.codeUnitAt(bytes[i] >> 4);
    codeUnits[i * 2 + 1] = _digits.codeUnitAt(bytes[i] & 0x0f);
  }
  return String.fromCharCodes(codeUnits);
}

Uint8List hexDecode(String hex) {
  if (hex.length.isOdd) throw const FormatException('Invalid hex');
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    final high = hexDigitValue(hex.codeUnitAt(i * 2));
    final low = hexDigitValue(hex.codeUnitAt(i * 2 + 1));
    if (high < 0 || low < 0) throw const FormatException('Invalid hex');
    bytes[i] = high << 4 | low;
  }
  return bytes;
}
