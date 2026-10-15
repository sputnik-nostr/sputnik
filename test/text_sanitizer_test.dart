import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/models/text_sanitizer.dart';

void main() {
  test('returns text without surrogates unchanged', () {
    const text = 'plain text, accents e\u00e9 and CJK \u4e2d';
    expect(identical(sanitizeUtf16(text), text), isTrue);
  });

  test('keeps a valid surrogate pair', () {
    expect(sanitizeUtf16('hi \u{1F600}!'), 'hi \u{1F600}!');
  });

  test('replaces a lone high surrogate, including at the end', () {
    expect(sanitizeUtf16('ab\uD83D'), 'ab\uFFFD');
    expect(sanitizeUtf16('a\uD83Db'), 'a\uFFFDb');
  });

  test('replaces a lone low surrogate after valid text', () {
    expect(sanitizeUtf16('ok \u{1F600} \uDE00 end'), 'ok \u{1F600} \uFFFD end');
  });
}
