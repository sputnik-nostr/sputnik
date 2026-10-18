import 'dart:math';

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/models/text_limits.dart';

/// The longest prefix of [text] made of whole grapheme clusters that fits:
/// found by walking every cluster of the whole text, which is what
/// [truncateText] must reach without reading it all.
String _longestWholePrefix(String text, int maxLength) {
  var end = 0;
  for (final cluster in text.characters) {
    if (end + cluster.length > maxLength) break;
    end += cluster.length;
  }
  return text.substring(0, end);
}

void main() {
  group('truncateText', () {
    test('returns text that fits as it is', () {
      final text = 'a' * 100;

      expect(identical(truncateText(text, 100), text), isTrue);
      expect(identical(truncateText(text, 5000), text), isTrue);
      expect(truncateText('', 0), '');
    });

    test('cuts other text to the limit', () {
      expect(truncateText('a' * 101, 100), 'a' * 100);
      expect(truncateText('hello world', 5), 'hello');
      expect(truncateText('hello', 0), '');
    });

    test('never cuts inside a surrogate pair', () {
      const emoji = '\u{1F600}';

      expect(
        truncateText(
          'a$emoji'
          'b',
          2,
        ),
        'a',
      );
      expect(
        truncateText(
          'a$emoji'
          'b',
          3,
        ),
        'a$emoji',
      );
      expect(truncateText('$emoji$emoji', 3), emoji);
      expect(truncateText('$emoji$emoji', 1), '');
    });

    test('keeps a letter together with its combining marks', () {
      const accented = 'e\u{301}';

      expect(truncateText('ab${accented}cd', 3), 'ab');
      expect(truncateText('ab${accented}cd', 4), 'ab$accented');
      expect(truncateText('ae\u{301}\u{323}b', 3), 'a');
      expect(truncateText('ae\u{301}\u{323}b', 4), 'ae\u{301}\u{323}');
    });

    test('keeps emoji sequences whole', () {
      const thumbsUp = '\u{1F44D}\u{1F3FD}';
      const family = '\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}';
      const heart = '\u{2764}\u{FE0F}';

      for (final emoji in [thumbsUp, family, heart]) {
        expect(truncateText('a${emoji}b', emoji.length), 'a');
        expect(truncateText('a${emoji}b', emoji.length + 1), 'a$emoji');
      }
    });

    test('keeps a mark whose first unit is the one past the limit', () {
      // The skin tone modifier takes two units, both beyond the limit, and it
      // still belongs to the letter before it.
      expect(truncateText('${'a' * 9}e\u{1F3FB}z', 10), 'a' * 9);
    });

    test('keeps a flag, which is two regional indicators, whole', () {
      const france = '\u{1F1EB}\u{1F1F7}';

      expect(truncateText('$france$france', 2), '');
      expect(truncateText('$france$france', 4), france);
      expect(truncateText('$france$france', 6), france);
    });

    test('keeps a Hangul syllable and a line break whole', () {
      const syllable = '\u{1112}\u{1161}\u{11AB}';

      expect(truncateText('a${syllable}b', 3), 'a');
      expect(truncateText('a${syllable}b', 4), 'a$syllable');
      expect(truncateText('a\r\nb', 2), 'a');
      expect(truncateText('a\r\nb', 3), 'a\r\n');
    });

    test('drops a first cluster that is longer than the limit', () {
      final endless = 'a${'\u{301}' * 500}';

      expect(truncateText(endless, 100), '');
      expect(truncateText('x$endless', 100), 'x');
      expect(truncateText(endless, 501), endless);
    });

    test('copes with unpaired surrogates anywhere', () {
      for (final text in [
        '\u{DE00}abc',
        '\u{DE00}\u{DE00}\u{DE00}',
        'ab\u{D83D}cd',
        'ab\u{D83D}',
        'abc\u{DE00}',
        '\u{D83D}\u{D83D}\u{DE00}',
        '\u{DE00}\u{D83D}\u{DE00}\u{D83D}',
      ]) {
        for (var limit = 0; limit <= text.length; limit++) {
          final cut = truncateText(text, limit);
          expect(text.startsWith(cut), isTrue, reason: '$text at $limit');
          expect(cut.length, lessThanOrEqualTo(limit));
        }
      }
    });

    test('reads only the start of a huge text', () {
      final text = 'a' * (16 << 20);
      final watch = Stopwatch()..start();
      final cut = truncateText(text, 8000);
      watch.stop();

      expect(cut.length, 8000);
      // It takes a fraction of a millisecond.
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 100)));
    });

    test('agrees with the grapheme clusters of the whole text', () {
      const pieces = [
        ...['a', 'b', 'e', ' ', '\n', '\r', '\r\n', '.', ')', '\u{E9}'],
        ...['\u{301}', '\u{300}', '\u{308}', '\u{200D}', '\u{200C}'],
        ...['\u{FE0F}', '\u{FE0E}', '\u{1F3FB}', '\u{1F3FF}', '\u{2764}'],
        ...['\u{1F600}', '\u{1F468}', '\u{1F469}', '\u{1F467}'],
        ...['\u{1F1E6}', '\u{1F1E7}', '\u{1F1EB}', '\u{1F1F7}'],
        ...['\u{1100}', '\u{1161}', '\u{11A8}', '\u{AC00}', '\u{AC01}'],
        ...['\u{915}', '\u{94D}', '\u{937}', '\u{93F}'],
        ...['\u{628}', '\u{600}', '\u{5D0}', '\u{E01}', '\u{E33}'],
        ...['\u{D83D}', '\u{DE00}', '\u{0}', '\u{E0061}', '\u{E007F}'],
      ];
      final random = Random(7);
      for (var i = 0; i < 20000; i++) {
        final text = [
          for (var n = random.nextInt(40); n > 0; n--)
            pieces[random.nextInt(pieces.length)],
        ].join();
        final limit = random.nextInt(text.length + 3);

        final cut = truncateText(text, limit);
        final expected = _longestWholePrefix(text, limit);
        if (cut != expected) {
          fail(
            'Cut ${text.runes.map((r) => r.toRadixString(16)).toList()} '
            'at $limit to ${cut.length} units, expected ${expected.length}.',
          );
        }
      }
    });
  });
}
