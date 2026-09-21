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
}
