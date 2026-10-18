import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/services/image_saver.dart';
import 'package:sputnik/services/media_loader.dart';

Uint8List _png() => Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);

/// Bytes whose length cannot be read, so that writing them fails half way.
class _Unwritable extends ListBase<int> {
  @override
  int get length => throw StateError('disk full');

  @override
  set length(int _) {}

  @override
  int operator [](int index) => 0;

  @override
  void operator []=(int index, int value) {}
}

const _executable = 0x49; // The owner, group and other execute bits.

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
    },
  );

  test('takes no part of the extension from the URL', () {
    // Bytes that are not an image have no name: there is nothing to save.
    expect(imageFileName('https://a.example/run.sh.x', [1, 2, 3]), isNull);
    expect(imageFileName('https://a.example/a.gif', [1, 2]), isNull);
    expect(imageFileName('https://a.example/a.exe', const []), isNull);
    // And an image only ever ends in its own extension.
    expect(imageFileName('https://a.example/run.sh.x', _png()), 'run_sh.png');
  });

  test('names are plain whatever the URL holds', () {
    final plain = RegExp(
      r'^[A-Za-z0-9][A-Za-z0-9_-]*\.(png|jpg|gif|webp|bmp)$',
    );
    for (final name in [
      'run.sh.x',
      'evil.desktop',
      'a.tar.gz',
      'x.AppImage',
      '-rf',
      '--help',
      '.bashrc',
      '..',
      '...',
      'con',
      'a b',
      'a%00b',
      'a%0Ab',
      '%E2%80%AEgpj.exe',
      'caf%C3%A9',
      '%FF',
      '_',
      '-',
      '',
      'a' * 300,
    ]) {
      expect(
        imageFileName('https://a.example/$name', _png()),
        matches(plain),
        reason: name,
      );
    }
  });

  test('cannot be steered out of the folder or made unwieldy by the URL', () {
    expect(
      imageFileName('https://a.example/..%2F..%2Fetc%2Fpasswd', _png()),
      isNot(contains('/')),
    );
    expect(imageFileName('https://a.example/.hidden', _png()), 'hidden.png');
    expect(imageFileName('https://a.example/', _png()), 'image.png');
    expect(
      imageFileName('https://a.example/${'a' * 200}.png', _png())!.length,
      lessThanOrEqualTo(64),
    );
  });

  test('a URL that is not valid UTF-8 still gives a plain name', () {
    final name = imageFileName('https://a.example/Caf%E9.jpg', _png());

    expect(name, isNot(contains('%')));
    expect(name, endsWith('.png'));
  });

  test('saves nothing that is not an image', () async {
    var asked = 0;

    final result = await saveImage(
      MediaSource(url: 'https://a.example/run.sh.x'),
      backend: (bytes, name) async {
        asked++;
        return '/home/me/$name';
      },
      fetchBytes: (_) async => Uint8List.fromList('#!/bin/sh\n'.codeUnits),
    );

    expect(result.outcome, SaveOutcome.failed);
    expect(asked, 0);
  });

  group('saving to a file the user picked', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('image_saver_test_');
    });

    tearDown(() => dir.delete(recursive: true));

    Future<String?> save(String name, {String? pick}) {
      return saveToDevice(
        _png(),
        name,
        pickLocation: (_) async => pick == null ? null : '${dir.path}/$pick',
      );
    }

    test('writes the bytes to a new file that is not executable', () async {
      final suggested = <String>[];

      final path = await saveToDevice(
        _png(),
        'cat.png',
        pickLocation: (name) async {
          suggested.add(name);
          return '${dir.path}/$name';
        },
      );

      expect(suggested, ['cat.png']);
      expect(path, '${dir.path}/cat.png');
      expect(File(path!).readAsBytesSync(), _png());
      expect(File(path).statSync().mode & _executable, 0);
    });

    test('writes nothing when the user cancels', () async {
      expect(await save('cat.png'), isNull);
      expect(dir.listSync(), isEmpty);
    });

    test('never replaces a file that exists, nor changes its mode', () async {
      final target = File('${dir.path}/run.sh')
        ..writeAsStringSync('#!/bin/sh\necho precious\n');
      await Process.run('chmod', ['755', target.path]);

      await expectLater(
        save('cat.png', pick: 'run.sh'),
        throwsA(isA<PathExistsException>()),
      );

      expect(target.readAsStringSync(), '#!/bin/sh\necho precious\n');
      expect(target.statSync().mode & _executable, _executable);
    });

    test('does not write through a link', () async {
      final victim = File('${dir.path}/victim.txt')..writeAsStringSync('keep');
      Link('${dir.path}/live.png').createSync(victim.path);
      Link('${dir.path}/dangling.png').createSync('${dir.path}/nowhere');

      for (final name in ['live.png', 'dangling.png']) {
        await expectLater(
          save('cat.png', pick: name),
          throwsA(isA<PathExistsException>()),
          reason: name,
        );
      }

      expect(victim.readAsStringSync(), 'keep');
      expect(File('${dir.path}/nowhere').existsSync(), isFalse);
    });

    test('takes back the file it made if the write fails', () async {
      final path = '${dir.path}/half.png';

      await expectLater(
        writeNewFile(path, _Unwritable()),
        throwsA(isA<StateError>()),
      );

      expect(File(path).existsSync(), isFalse);
    });

    test('tells the user a file with that name exists', () async {
      File('${dir.path}/cat.png').writeAsStringSync('mine');

      final result = await saveImage(
        MediaSource(url: 'https://a.example/cat.png'),
        backend: (bytes, name) => save(name, pick: name),
        fetchBytes: (_) async => _png(),
      );

      expect(result.outcome, SaveOutcome.exists);
      expect(saveMessage(result), 'A file with that name already exists');
      expect(File('${dir.path}/cat.png').readAsStringSync(), 'mine');
    });
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
