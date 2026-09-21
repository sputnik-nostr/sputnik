import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/services/media_loader.dart';
import 'package:sputnik/services/video_store.dart';

class _RealHttp extends HttpOverrides {}

HttpClient _realClient() =>
    HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());

void main() {
  late HttpServer server;
  late Directory temp;
  late Uri base;
  late VideoStore store;
  var requests = 0;

  VideoStore newStore({int? cacheBytes}) => VideoStore(
    tempDirectory: () async => temp,
    clientFactory: _realClient,
    cacheBytes: cacheBytes ?? videoCacheBytes,
  );

  setUp(() async {
    requests = 0;
    temp = await Directory.systemTemp.createTemp('video_store_test_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    store = newStore();
  });

  tearDown(() async {
    await server.close(force: true);
    await temp.delete(recursive: true);
  });

  void serve(List<int> Function(HttpRequest request) body) {
    server.listen((request) {
      requests++;
      request.response
        ..add(body(request))
        ..close();
    });
  }

  // Files the store left in its session folder.
  List<File> filesOnDisk() => [
    for (final dir in temp.listSync().whereType<Directory>())
      ...dir.listSync().whereType<File>(),
  ];

  test('downloads a video to a file with the same bytes', () async {
    final video = List.generate(1000, (i) => i % 251);
    serve((_) => video);

    final file = await store.fetch(
      MediaSource(url: base.resolve('/v.mp4').toString()),
    );

    expect(await file.readAsBytes(), video);
    expect(file.path, endsWith('.mp4'));
  });

  test(
    'keeps videos in a folder of its own inside the temp directory',
    () async {
      serve((_) => [1, 2, 3]);

      final file = await store.fetch(
        MediaSource(url: base.resolve('/v.mp4').toString()),
      );

      expect(file.parent.parent.path, temp.path);
      expect(file.parent.path.split('/').last, startsWith('sputnik_media_'));
    },
  );

  test('plays the same URL again without downloading twice', () async {
    serve((_) => [1, 2, 3]);
    final source = MediaSource(url: base.resolve('/v.mp4').toString());

    final first = await store.fetch(source);
    final second = await store.fetch(source);

    expect(second.path, first.path);
    expect(requests, 1);
  });

  test('checks the hash and deletes a file that does not match', () async {
    serve((_) => [1, 2, 3]);

    await expectLater(
      store.fetch(
        MediaSource(url: base.resolve('/v.mp4').toString(), sha256: 'ab' * 32),
      ),
      throwsA(
        isA<HttpException>().having(
          (e) => e.message,
          'message',
          contains('Hash mismatch'),
        ),
      ),
    );

    expect(filesOnDisk(), isEmpty);
  });

  test('cancelling stops the download and removes the partial file', () async {
    server.listen((request) {
      request.response
        ..contentLength = 100
        ..add([0])
        ..flush();
    });
    final canceller = DownloadCanceller();
    final done = store.fetch(
      MediaSource(url: base.resolve('/v.mp4').toString()),
      canceller: canceller,
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));
    canceller.cancel();

    await expectLater(done, throwsA(isA<DownloadCancelled>()));
    expect(filesOnDisk(), isEmpty);
  });

  test('ignores an unsafe file extension from the URL', () async {
    serve((_) => [1]);

    final file = await store.fetch(
      MediaSource(url: base.resolve('/v.mp4%2F..%2Fx').toString()),
    );

    expect(file.parent.parent.path, temp.path);
    expect(file.path.split('/').last, matches(RegExp(r'^\d+(\.\w{1,5})?$')));
  });

  test('drops the oldest videos once over the cache budget', () async {
    serve((request) => Uint8List(600));
    final small = newStore(cacheBytes: 1000);

    final a = await small.fetch(
      MediaSource(url: base.resolve('/a.mp4').toString()),
    );
    final b = await small.fetch(
      MediaSource(url: base.resolve('/b.mp4').toString()),
    );

    expect(a.existsSync(), isFalse);
    expect(b.existsSync(), isTrue);
    expect(small.cachedCount, 1);
  });

  test('never evicts the video that was just fetched', () async {
    serve((request) => Uint8List(600));
    final tiny = newStore(cacheBytes: 10);

    final file = await tiny.fetch(
      MediaSource(url: base.resolve('/a.mp4').toString()),
    );

    expect(file.existsSync(), isTrue);
  });

  group('sweepStale', () {
    test('removes folders left by earlier runs, and only those', () async {
      final stale = await Directory('${temp.path}/sputnik_media_old').create();
      await File('${stale.path}/0.mp4').writeAsBytes([1]);
      final unrelated = await Directory('${temp.path}/other').create();

      await store.sweepStale();

      expect(stale.existsSync(), isFalse);
      expect(unrelated.existsSync(), isTrue);
    });

    test('leaves the current session alone', () async {
      serve((_) => [1, 2, 3]);
      final file = await store.fetch(
        MediaSource(url: base.resolve('/v.mp4').toString()),
      );

      await store.sweepStale();

      expect(file.existsSync(), isTrue);
    });
  });
}
