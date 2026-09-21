import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/blurhash.dart';

void main() {
  test('accepts a real BlurHash and rejects what would crash the decoder', () {
    expect(isValidBlurhash('LEHV6nWB2yk8pyo0adR*.7kCMdnj'), isTrue);

    for (final hash in [
      '',
      'LEHV6',
      'LEHV6nWB2yk8pyo0adR*.7kCMdn',
      'LEHV6nWB2yk8pyo0adR*.7kCMdnjj',
      'LEHV6nWB2yk8pyo0adR*.7kCMdn\u00e9',
      'LEHV6nWB2yk8pyo0adR*.7kCMdn ',
      'x' * 300,
    ]) {
      expect(isValidBlurhash(hash), isFalse, reason: hash);
    }
  });
}
