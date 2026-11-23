import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/bech32.dart';
import 'package:sputnik/nostr/hex.dart';
import 'package:sputnik/nostr/nip19.dart';
import 'package:sputnik/nostr/nip27.dart';

void main() {
  final id = 'c' * 64;
  final note = noteFromHex(id);
  final nevent = bech32Encode(
    'nevent',
    convertBits([0, 32, ...hexDecode(id)], 8, 5, pad: true),
  );

  test('finds a note and an nevent, with or without nostr:', () {
    final text = 'a nostr:$note b $nevent';
    final refs = noteReferences(text);

    expect(refs.map((r) => r.eventIdHex), [id, id]);
    expect(text.substring(refs[0].start, refs[0].end), 'nostr:$note');
    expect(text.substring(refs[1].start, refs[1].end), nevent);
  });

  test('finds a note and an nevent written in uppercase', () {
    final text = 'a NOSTR:${note.toUpperCase()} b ${nevent.toUpperCase()}';
    final refs = noteReferences(text);

    expect(refs.map((r) => r.eventIdHex), [id, id]);
    expect(
      text.substring(refs[0].start, refs[0].end),
      'NOSTR:${note.toUpperCase()}',
    );
    expect(text.substring(refs[1].start, refs[1].end), nevent.toUpperCase());
  });

  test('ignores a reference that mixes cases', () {
    final mixed = note.substring(0, 20) + note.substring(20).toUpperCase();

    expect(noteReferences('nostr:$mixed $mixed'), isEmpty);
  });

  test('ignores profiles, invalid ids and plain words', () {
    final npub = npubFromHex('a' * 64);
    expect(
      noteReferences('nostr:$npub note1 nostr:note1qqqq event1abc'),
      isEmpty,
    );
  });

  test('ignores an id inside a web address', () {
    expect(noteReferences('https://njump.me/$note'), isEmpty);
  });
}
