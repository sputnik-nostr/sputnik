import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/hex.dart';

void main() {
  test('round-trips bytes', () {
    expect(hexEncode(hexDecode('00ff10Ab')), '00ff10ab');
  });

  test('rejects odd length, signs, whitespace and non-hex', () {
    for (final bad in ['abc', '-f', '+f', ' f', 'f ', '0x', 'zz', 'g0']) {
      expect(() => hexDecode(bad), throwsFormatException, reason: bad);
    }
  });

  test('an empty string decodes to no bytes', () {
    expect(hexDecode(''), isEmpty);
  });
}
