import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/http_urls.dart';

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
    test('drops sentence punctuation and unmatched closers', () {
      expect(trimUrlEnd('https://a.example/x).'), 'https://a.example/x');
      expect(trimUrlEnd('https://a.example/(x)'), 'https://a.example/(x)');
    });

    test('handles a long run of closers quickly', () {
      final watch = Stopwatch()..start();
      final url = 'https://a.example/${')' * 200000}';
      expect(trimUrlEnd(url), 'https://a.example/');
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });
  });
}
