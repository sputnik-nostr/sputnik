import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/services/image_saver.dart';
import 'package:sputnik/services/media_loader.dart';

Uint8List _png() => Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);

void main() {
  test(
    'names the file from the URL but trusts the bytes for the extension',
    () {
      expect(imageFileName('https://a.example/dir/cat.jpg', _png()), 'cat.png');
      expect(
        imageFileName('https://a.example/a.png', [0xff, 0xd8, 0xff, 0]),
        'a.jpg',
      );
      expect(
        imageFileName('https://a.example/a', [
          ...'RIFF'.codeUnits,
          0,
          0,
          0,
          0,
          ...'WEBP'.codeUnits,
        ]),
        'a.webp',
      );
      // Unrecognized bytes fall back to a plausible URL extension, else none.
      expect(imageFileName('https://a.example/a.gif', [1, 2]), 'a.gif');
      expect(imageFileName('https://a.example/a.exe', [1, 2]), 'a');
    },
  );

  test('cannot be steered out of the folder or made unwieldy by the URL', () {
    expect(
      imageFileName('https://a.example/..%2F..%2Fetc%2Fpasswd', _png()),
      isNot(contains('/')),
    );
    expect(imageFileName('https://a.example/.hidden', _png()), 'hidden.png');
    expect(imageFileName('https://a.example/', _png()), 'image.png');
    expect(
      imageFileName('https://a.example/${'a' * 200}.png', _png()).length,
      lessThanOrEqualTo(64),
    );
  });

  test('reports each way saving can end', () async {
    final source = MediaSource(url: 'https://a.example/cat.png');
    Future<Uint8List> fetch(MediaSource _) async => _png();

    Future<SaveResult> run(SaveBackend backend) =>
        saveImage(source, backend: backend, fetchBytes: fetch);

    final names = <String>[];
    final saved = await run((bytes, name) async {
      names.add(name);
      return '/home/me/cat.png';
    });
    expect(saved.outcome, SaveOutcome.saved);
    expect(saveMessage(saved), 'Saved to /home/me/cat.png');
    expect(names, ['cat.png']);

    final cancelled = await run((bytes, name) async => null);
    expect(cancelled.outcome, SaveOutcome.cancelled);
    expect(saveMessage(cancelled), isNull);

    final denied = await run((bytes, name) async => throw const SaveDenied());
    expect(denied.outcome, SaveOutcome.denied);

    final failed = await run((bytes, name) async => throw StateError('disk'));
    expect(failed.outcome, SaveOutcome.failed);

    final noDownload = await saveImage(
      source,
      backend: (bytes, name) async => 'never',
      fetchBytes: (_) async => throw StateError('offline'),
    );
    expect(noDownload.outcome, SaveOutcome.failed);
  });
}
