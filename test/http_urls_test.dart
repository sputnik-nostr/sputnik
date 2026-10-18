import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/http_urls.dart';

const _punctuation = '.,;:!?\'*';
const _closers = {')': '(', ']': '[', '}': '{'};

/// The original `trimUrlEnd`. Every trailing closer rescans the whole URL, so
/// it is quadratic, but it is plainly right: the linear one is held to it.
String _spec(String url) {
  int count(int end, String char) {
    var found = 0;
    for (var i = 0; i < end; i++) {
      if (url[i] == char) found++;
    }
    return found;
  }

  var end = url.length;
  while (end > 0) {
    final last = url[end - 1];
    final opener = _closers[last];
    final trailing =
        _punctuation.contains(last) ||
        (opener != null && count(end, last) > count(end, opener));
    if (!trailing) break;
    end--;
  }
  return url.substring(0, end);
}

/// A linear `trimUrlEnd` with the rules open to getting wrong as parameters.
/// The defaults must agree with [_spec]; each other setting is a plausible
/// partial fix that must not.
String _linear(
  String url, {
  Map<String, String> closers = _closers,
  String punctuation = _punctuation,
  bool decrement = true,
}) {
  final counts = <String, int>{};
  for (var i = 0; i < url.length; i++) {
    counts[url[i]] = (counts[url[i]] ?? 0) + 1;
  }
  var end = url.length;
  while (end > 0) {
    final last = url[end - 1];
    final opener = closers[last];
    if (opener != null) {
      if (counts[last]! <= (counts[opener] ?? 0)) break;
      if (decrement) counts[last] = counts[last]! - 1;
    } else if (!punctuation.contains(last)) {
      break;
    }
    end--;
  }
  return url.substring(0, end);
}

final _flawed = <String, String Function(String)>{
  'only parentheses are brackets': (url) =>
      _linear(url, closers: const {')': '('}),
  'closers are never uncounted': (url) => _linear(url, decrement: false),
  'a colon and an asterisk are text': (url) =>
      _linear(url, punctuation: '.,;!?\''),
};

/// Every input of the shapes a URL's end takes in practice.
Iterable<String> _inputs() sync* {
  const symbols = ['(', ')', '[', ']', '{', '}', '.', ':', '*', 'a'];
  // Every string of up to five of them.
  var layer = [''];
  for (var length = 0; length <= 5; length++) {
    yield* layer;
    layer = [
      for (final prefix in layer)
        for (final symbol in symbols) prefix + symbol,
    ];
  }

  // Nested brackets with too many or too few closers, then trailing text.
  const tails = ['', '.', ')', '.)', ',]', '}.', ':', '*', '!?', '\'"'];
  for (final MapEntry(key: closer, value: opener) in _closers.entries) {
    for (var opened = 0; opened <= 5; opened++) {
      for (var closed = 0; closed <= 7; closed++) {
        for (final tail in tails) {
          yield 'https://a.example/x${opener * opened}y${closer * closed}$tail';
        }
      }
    }
  }

  // Long mixed strings, with characters that take two code units.
  const alphabet = [
    ...['(', ')', '[', ']', '{', '}', '.', ',', ';', ':', '!', '?', '\''],
    ...['*', '/', '%', '=', '&', 'a', 'b', '\u{1F600}', '\u{e9}', '\u{200d}'],
  ];
  final random = Random(1);
  for (var i = 0; i < 20000; i++) {
    final tail = StringBuffer();
    for (var n = random.nextInt(60); n > 0; n--) {
      tail.write(alphabet[random.nextInt(alphabet.length)]);
    }
    yield 'https://a.example/$tail';
  }
}

/// [text] with anything but printable ASCII spelled out, for failure messages.
String _escaped(String text) => [
  for (final unit in text.codeUnits)
    unit < 0x20 || unit > 0x7e
        ? '\\u${unit.toRadixString(16)}'
        : String.fromCharCode(unit),
].join();

void main() {
  group('withoutUrls', () {
    const url = 'https://a.example/1.jpg';

    test('removes a URL at the end of a line', () {
      expect(withoutUrls('look at this $url', {url}), 'look at this');
    });

    test('removes a line that held only the URL', () {
      expect(withoutUrls('first\n$url\nlast', {url}), 'first\nlast');
    });

    test('returns nothing when the text was only the URL', () {
      expect(withoutUrls(url, {url}), '');
      expect(withoutUrls('$url\n$url', {url}), '');
    });

    test('keeps the punctuation that followed the URL', () {
      expect(withoutUrls('wow $url.', {url}), 'wow .');
    });

    test('leaves other URLs and untouched lines exactly as written', () {
      const other = 'https://b.example/page';
      expect(withoutUrls('  a  \n$other\n$url', {url}), '  a  \n$other');
    });

    test('does not remove a URL that merely starts with a listed one', () {
      const longer = 'https://a.example/1.jpg.html';
      expect(withoutUrls(longer, {url}), longer);
    });
  });

  group('trimUrlEnd', () {
    const base = 'https://a.example/x';

    test('drops sentence punctuation and unmatched closers', () {
      expect(trimUrlEnd('https://a.example/x).'), 'https://a.example/x');
      expect(trimUrlEnd('https://a.example/(x)'), 'https://a.example/(x)');
    });

    for (final char in _punctuation.split('')) {
      test('drops $char, alone and repeated', () {
        expect(trimUrlEnd('$base$char'), base);
        expect(trimUrlEnd('$base${char * 5}'), base);
        expect(trimUrlEnd('$base$char.$char'), base);
      });

      test('keeps $char inside a URL', () {
        expect(trimUrlEnd('$base${char}y'), '$base${char}y');
      });
    }

    for (final MapEntry(key: closer, value: opener) in _closers.entries) {
      test('keeps $closer only where the URL opened it with $opener', () {
        expect(trimUrlEnd('$base$closer'), base);
        expect(trimUrlEnd('$base$closer$closer.'), base);
        expect(trimUrlEnd('$base$opener$closer'), '$base$opener$closer');
        expect(trimUrlEnd('$base$opener$closer$closer'), '$base$opener$closer');
        expect(
          trimUrlEnd('$base$opener$opener$closer$closer$closer'),
          '$base$opener$opener$closer$closer',
        );
        expect(trimUrlEnd('$base$opener${closer}y.'), '$base$opener${closer}y');
      });
    }

    test('treats each kind of bracket on its own', () {
      expect(trimUrlEnd('$base(]'), '$base(');
      expect(trimUrlEnd('$base[)'), '$base[');
      expect(trimUrlEnd('$base{)}'), '$base{)}');
    });

    group('on a long run', () {
      // A trim that rescans the URL for each closer needs seconds for a run
      // this long. The linear one needs a few milliseconds.
      const length = 100000;
      const generous = Duration(milliseconds: 300);

      final runs = {
        for (final char in [..._closers.keys, '.', ',']) char: char,
        'closers of every kind': ')]}',
        'closers and punctuation': ').]}',
        'punctuation of every kind': _punctuation,
      };
      for (final MapEntry(key: name, value: unit) in runs.entries) {
        test('of $name takes linear time', () {
          final url = '$base${unit * (length ~/ unit.length)}';
          final watch = Stopwatch()..start();
          final trimmed = trimUrlEnd(url);
          watch.stop();

          expect(trimmed, base);
          expect(watch.elapsed, lessThan(generous));
        });
      }

      test('of closers the URL opened only some of takes linear time', () {
        final url = '$base${'(a)' * (length ~/ 3)})))';
        final watch = Stopwatch()..start();
        final trimmed = trimUrlEnd(url);
        watch.stop();

        expect(trimmed, '$base${'(a)' * (length ~/ 3)}');
        expect(watch.elapsed, lessThan(generous));
      });

      test('of closers in text of two-byte characters takes linear time', () {
        final url = 'https://a.example/\u{20ac}${')' * length}';
        final watch = Stopwatch()..start();
        final trimmed = trimUrlEnd(url);
        watch.stop();

        expect(trimmed, 'https://a.example/\u{20ac}');
        expect(watch.elapsed, lessThan(generous));
      });

      test('does not slow the removal of a URL from a note', () {
        final note = 'look $base${')' * length}';
        final watch = Stopwatch()..start();
        final matches = httpUrlPattern.allMatches(note).toList();
        final without = withoutUrls(note, {base});
        watch.stop();

        expect(matches, hasLength(1));
        expect(without, 'look ${')' * length}');
        expect(watch.elapsed, lessThan(generous));
      });

      test('is far faster than the original, however fast the machine', () {
        // The original is the slowest on a run like this, and the two are
        // timed one after the other, so no bound in milliseconds is needed.
        final url = '$base${')' * 20000}';
        Duration time(String Function(String) trim) {
          final watch = Stopwatch()..start();
          trim(url);
          return watch.elapsed;
        }

        final original = time(_spec);
        final linear = [for (var i = 0; i < 3; i++) time(trimUrlEnd)]
            .reduce((a, b) => a < b ? a : b);

        expect(linear * 10, lessThan(original));
      });
    });

    group('against the quadratic original', () {
      test('agrees on short, nested and random URLs', () {
        var checked = 0;
        for (final url in _inputs()) {
          final expected = _spec(url);
          if (trimUrlEnd(url) != expected) {
            fail('trimUrlEnd(${_escaped(url)}) != ${_escaped(expected)}');
          }
          checked++;
        }
        expect(checked, greaterThan(100000));
      });

      test(
        'is matched by the linear sketch the flawed variants start from',
        () {
          for (final url in _inputs()) {
            expect(_linear(url), _spec(url), reason: _escaped(url));
          }
        },
      );

      for (final MapEntry(key: flaw, value: variant) in _flawed.entries) {
        test('would catch a variant where $flaw', () {
          final tells = _inputs().any((url) => variant(url) != _spec(url));
          expect(tells, isTrue);
        });
      }
    });
  });
}
