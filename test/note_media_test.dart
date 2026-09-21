import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/nostr/models/nostr_media.dart';

Note _note({List<NostrMedia> media = const []}) => Note(
  id: 'a' * 64,
  pubkey: 'b' * 64,
  displayName: 'Name',
  handle: 'h',
  content: 'hello',
  postedAt: '1m',
  createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  media: media,
);

void main() {
  test('media survives a JSON round trip, as bookmarks need', () {
    final note = _note(
      media: [
        const NostrMedia(
          url: 'https://a.example/1.jpg',
          width: 640,
          height: 480,
          alt: 'cat',
        ),
        const NostrMedia(url: 'https://a.example/2.png'),
      ],
    );

    final restored = Note.fromJson(note.toJson());

    expect(restored.media.map((m) => m.url), [
      'https://a.example/1.jpg',
      'https://a.example/2.png',
    ]);
    expect(restored.media.first.width, 640);
    expect(restored.media.first.height, 480);
    expect(restored.media.first.alt, 'cat');
    expect(restored.media.last.width, isNull);
  });

  test('a bookmark saved before media existed still loads', () {
    final json = _note().toJson();

    expect(Note.fromJson(json).media, isEmpty);
  });

  test('malformed saved media is skipped rather than failing the load', () {
    final json = _note().toJson()
      ..['media'] = [
        {'url': 'https://a.example/ok.jpg'},
        {'url': 5},
        {'width': 10},
        'nonsense',
        null,
        {'url': 'https://a.example/bad.jpg', 'width': -1, 'height': 'x'},
      ];

    final media = Note.fromJson(json).media;

    expect(media.map((m) => m.url), [
      'https://a.example/ok.jpg',
      'https://a.example/bad.jpg',
    ]);
    expect(media.last.width, isNull);
    expect(media.last.height, isNull);
  });

  test('copyWith keeps the media, so reaction updates do not drop images', () {
    final note = _note(
      media: [const NostrMedia(url: 'https://a.example/1.jpg')],
    );

    expect(note.copyWith(likeCount: 3).media, hasLength(1));
    expect(note.copyWith(displayName: 'New').media, hasLength(1));
  });
}
