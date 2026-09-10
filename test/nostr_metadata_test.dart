import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/models/nostr_metadata.dart';

void main() {
  test('parses well-formed metadata content', () {
    final metadata = NostrMetadata.fromContent(
      '{"name": "alice", "about": "hello"}',
    );
    expect(metadata.name, 'alice');
    expect(metadata.about, 'hello');
  });

  test('sanitizes a lone surrogate in name so Text can render it', () {
    final metadata = NostrMetadata.fromContent('{"name": "bad\\ud800name"}');
    expect(metadata.name, 'bad�name');
  });

  test('sanitizes a lone surrogate in about', () {
    final metadata = NostrMetadata.fromContent('{"about": "oops\\udc00!"}');
    expect(metadata.about, 'oops�!');
  });

  test('keeps a valid surrogate pair (emoji) intact', () {
    final metadata = NostrMetadata.fromContent('{"name": "hi \\ud83d\\ude00"}');
    expect(metadata.name, 'hi 😀');
  });
}
