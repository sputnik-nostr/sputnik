import 'dart:typed_data';

final _hexPattern = RegExp(r'^[0-9a-fA-F]*$');

String hexEncode(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List hexDecode(String hex) {
  if (hex.length.isOdd || !_hexPattern.hasMatch(hex)) {
    throw const FormatException('Invalid hex');
  }
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}
