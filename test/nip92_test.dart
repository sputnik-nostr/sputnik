import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/models/nostr_event.dart';
import 'package:sputnik/nostr/models/nostr_media.dart';
import 'package:sputnik/nostr/models/nostr_post.dart';
import 'package:sputnik/nostr/nip92.dart';

void main() {
  const image = 'https://cdn.example.com/a.jpg';

  group('noteMedia', () {
    test('finds a bare https image URL by its extension', () {
      final media = noteMedia('look $image', const []);

      expect(media.map((m) => m.url), [image]);
      expect(media.single.type, MediaType.image);
      expect(media.single.aspectRatio, isNull);
      expect(media.single.sha256, isNull);
      expect(
        noteMedia('https://cdn.example.com/a.PNG?size=large', const []),
        hasLength(1),
      );
    });

    test('leaves other links alone', () {
      final media = noteMedia(
        'https://example.com/page https://example.com/clip.txt '
        'https://example.com/a.svg https://example.com/a.avif '
        'https://example.com/${'a' * 64}',
        const [],
      );

      expect(media, isEmpty);
    });

    test('only fetchable https URLs count', () {
      for (final url in [
        'http://cdn.example.com/a.jpg',
        'http://cdn.example.com/clip.mp4',
        'https://user:pw@cdn.example.com/a.jpg',
      ]) {
        expect(noteMedia(url, const []), isEmpty, reason: url);
      }
    });

    test('trusts a declared mime type over the extension', () {
      const blob = 'https://cdn.example.com/blob';
      final webp = noteMedia(blob, [
        ['imeta', 'url $blob', 'm IMAGE/WebP; q=1'],
      ]);
      expect(webp.single.type, MediaType.image);

      final notMedia = noteMedia(image, [
        ['imeta', 'url $image', 'm application/pdf'],
      ]);
      expect(notMedia, isEmpty);

      const clip = 'https://cdn.example.com/clip.mp4';
      final png = noteMedia(clip, [
        ['imeta', 'url $clip', 'm image/png'],
      ]);
      expect(png.single.type, MediaType.image);
    });

    test('drops trailing punctuation from the URL', () {
      final media = noteMedia('see ($image).', const []);

      expect(media.single.url, image);
    });

    test('lists a repeated URL once', () {
      expect(noteMedia('$image $image', const []), hasLength(1));
    });

    test('reads dimensions and alt text from a matching imeta tag', () {
      final media = noteMedia('$image hi', [
        ['imeta', 'url $image', 'm image/jpeg', 'dim 800x600', 'alt A cat'],
      ]);

      expect(media.single.width, 800);
      expect(media.single.height, 600);
      expect(media.single.aspectRatio, closeTo(4 / 3, 0.001));
      expect(media.single.alt, 'A cat');
    });

    test('ignores an imeta tag whose URL is not in the content', () {
      final media = noteMedia('no links here', [
        ['imeta', 'url $image', 'm image/jpeg'],
      ]);

      expect(media, isEmpty);
    });

    test('drops implausible or malformed dimensions', () {
      for (final dim in ['0x0', '800', 'axb', '999999x10', '-5x10', '10x-5']) {
        final media = noteMedia(image, [
          ['imeta', 'url $image', 'dim $dim'],
        ]);

        expect(media.single.width, isNull, reason: dim);
        expect(media.single.aspectRatio, isNull, reason: dim);
      }
    });

    test('the first imeta tag for a URL wins', () {
      final media = noteMedia(image, [
        ['imeta', 'url $image', 'alt first'],
        ['imeta', 'url $image', 'alt second'],
      ]);

      expect(media.single.alt, 'first');
    });

    test('tolerates malformed imeta entries', () {
      final media = noteMedia(image, [
        ['imeta'],
        ['imeta', 'noseparator', ' leadingspace', ''],
        ['imeta', 'url $image', 'dim'],
      ]);

      expect(media, hasLength(1));
    });
  });

  group('videos', () {
    test('finds a video by its extension', () {
      for (final name in ['a.mp4', 'a.webm', 'a.MOV', 'a.m4v', 'a.mkv']) {
        final media = noteMedia('https://cdn.example.com/$name', const []);

        expect(media.single.type, MediaType.video, reason: name);
      }
    });

    test('a declared video mime type marks an extensionless URL', () {
      final media = noteMedia('https://cdn.example.com/blob', [
        ['imeta', 'url https://cdn.example.com/blob', 'm video/quicktime'],
      ]);

      expect(media.single.type, MediaType.video);
    });

    test('streaming playlists are not treated as video', () {
      expect(
        noteMedia('https://cdn.example.com/live.m3u8', [
          [
            'imeta',
            'url https://cdn.example.com/live.m3u8',
            'm application/x-mpegURL',
          ],
        ]),
        isEmpty,
      );
      expect(noteMedia('https://cdn.example.com/live.m3u8', const []), isEmpty);
    });

    test('images and videos share the per-note cap', () {
      final content = [
        for (var i = 0; i < maxNoteMedia; i++) 'https://cdn.example.com/$i.mp4',
        image,
      ].join(' ');

      expect(noteMedia(content, const []), hasLength(maxNoteMedia));
    });
  });

  group('hashes and fallbacks', () {
    final hash = 'cd' * 32;

    test('a Blossom-style URL names its own hash', () {
      final url = 'https://blossom.example/$hash.jpg';

      expect(noteMedia(url, const []).single.sha256, hash);
    });

    test('the imeta x field supplies the hash when the URL has none', () {
      final media = noteMedia(image, [
        ['imeta', 'url $image', 'x ${hash.toUpperCase()}'],
      ]);

      expect(media.single.sha256, hash);
    });

    test('the hash in the URL wins over a different x field', () {
      final url = 'https://blossom.example/$hash.jpg';
      final media = noteMedia(url, [
        ['imeta', 'url $url', 'x ${'ef' * 32}'],
      ]);

      expect(media.single.sha256, hash);
    });

    test('an x field that is not a sha256 is ignored', () {
      final media = noteMedia(image, [
        ['imeta', 'url $image', 'x nothex', 'dim 1x1'],
      ]);

      expect(media.single.sha256, isNull);
    });

    test('collects fallback URLs from repeated fields', () {
      final media = noteMedia(image, [
        [
          'imeta',
          'url $image',
          'fallback https://one.example/a.jpg',
          'fallback https://two.example/a.jpg',
        ],
      ]);

      expect(media.single.fallbackUrls, [
        'https://one.example/a.jpg',
        'https://two.example/a.jpg',
      ]);
    });

    test('drops fallbacks that are not fetchable https URLs', () {
      final media = noteMedia(image, [
        [
          'imeta',
          'url $image',
          'fallback http://plain.example/a.jpg',
          'fallback https://u:p@creds.example/a.jpg',
          'fallback nonsense',
          'fallback $image',
          'fallback https://ok.example/a.jpg',
        ],
      ]);

      expect(media.single.fallbackUrls, ['https://ok.example/a.jpg']);
    });
  });

  group('NostrMedia JSON', () {
    test('round-trips every field', () {
      final media = NostrMedia(
        url: 'https://a.example/x.mp4',
        type: MediaType.video,
        width: 10,
        height: 20,
        alt: 'clip',
        sha256: 'ab' * 32,
        fallbackUrls: const ['https://b.example/x.mp4'],
      );

      final restored = NostrMedia.fromJson(media.toJson());

      expect(restored.url, media.url);
      expect(restored.type, MediaType.video);
      expect(restored.width, 10);
      expect(restored.height, 20);
      expect(restored.alt, 'clip');
      expect(restored.sha256, media.sha256);
      expect(restored.fallbackUrls, media.fallbackUrls);
    });

    test('an entry saved before videos existed is an image', () {
      final restored = NostrMedia.fromJson({'url': 'https://a.example/x.png'});

      expect(restored.type, MediaType.image);
      expect(restored.sha256, isNull);
      expect(restored.fallbackUrls, isEmpty);
    });

    test('a corrupt hash or type is dropped rather than trusted', () {
      final restored = NostrMedia.fromJson({
        'url': 'https://a.example/x.png',
        'type': 'hologram',
        'sha256': 'NOTHEX',
        'fallbacks': ['https://b.example/x.png', 5, null],
      });

      expect(restored.type, MediaType.image);
      expect(restored.sha256, isNull);
      expect(restored.fallbackUrls, ['https://b.example/x.png']);
    });
  });

  test('a post built from an event carries its images', () {
    final event = NostrEvent(
      id: 'a' * 64,
      pubkey: 'b' * 64,
      createdAt: DateTime(2024),
      kind: 1,
      tags: [
        ['imeta', 'url $image', 'dim 10x20'],
      ],
      content: 'hello $image',
      sig: 'c' * 128,
    );

    final post = nostrPostFromEvent(event);

    expect(post.media.single.url, image);
    expect(post.media.single.height, 20);
  });
}
