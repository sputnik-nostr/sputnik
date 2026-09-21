import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sputnik/widgets/media_kit_player.dart';

// Files that are not videos, but tell a player to open another URL.
Map<String, String> _hostileFiles(String url) => {
  'hls.mp4':
      '#EXTM3U\n#EXT-X-VERSION:3\n#EXTINF:1,\n$url/hls\n#EXT-X-ENDLIST\n',
  'edl.mp4': '# mpv EDL v0\n$url/edl\n',
  'm3u.mp4': '#EXTM3U\n$url/m3u\n',
};

/// A silent mono 8 kHz WAV, so a normal playable file needs no fixtures.
List<int> _silentWav(int seconds) {
  const rate = 8000;
  final data = rate * 2 * seconds;
  final header = ByteData(44)
    ..setUint32(4, 36 + data, Endian.little)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(40, data, Endian.little);
  final bytes = header.buffer.asUint8List();
  bytes.setAll(0, 'RIFF'.codeUnits);
  bytes.setAll(8, 'WAVEfmt '.codeUnits);
  bytes.setAll(36, 'data'.codeUnits);
  return [...bytes, ...Uint8List(data)];
}

void main() {
  late bool libmpv;
  late HttpServer server;
  late Directory dir;
  final requests = <String>[];

  setUpAll(() {
    try {
      MediaKit.ensureInitialized();
      libmpv = true;
    } catch (_) {
      libmpv = false;
    }
  });

  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      requests.add(request.uri.path);
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
    });
    dir = await Directory.systemTemp.createTemp('sputnik_lockdown_');
    final url = 'http://127.0.0.1:${server.port}';
    for (final entry in _hostileFiles(url).entries) {
      await File('${dir.path}/${entry.key}').writeAsString(entry.value);
    }
  });

  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  Future<Player> newPlayer() async {
    final player = Player();
    // No sound card is needed to check what a file makes the player fetch.
    await (player.platform as NativePlayer).setProperty('ao', 'null');
    return player;
  }

  Future<void> waitForRequest(Duration limit) async {
    final deadline = DateTime.now().add(limit);
    while (requests.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  for (final name in _hostileFiles('').keys) {
    test('unlocked, $name makes the player fetch its URL', () async {
      if (!libmpv) return markTestSkipped('libmpv is not installed');
      final player = await newPlayer();
      try {
        await player.open(Media('${dir.path}/$name'));
        await waitForRequest(const Duration(seconds: 5));

        // Proves the check below can see a fetch when there is one.
        expect(requests, isNotEmpty);
      } finally {
        await player.dispose();
      }
    });

    test('locked down, $name fetches nothing', () async {
      if (!libmpv) return markTestSkipped('libmpv is not installed');
      final player = await newPlayer();
      try {
        await lockDownPlayer(player);
        await player.open(Media('${dir.path}/$name'));
        await waitForRequest(const Duration(seconds: 2));

        expect(requests, isEmpty);
      } finally {
        await player.dispose();
      }
    });
  }

  test('a normal file still plays with the lockdown applied', () async {
    if (!libmpv) return markTestSkipped('libmpv is not installed');
    await File('${dir.path}/good.wav').writeAsBytes(_silentWav(5));
    final player = await newPlayer();
    try {
      await lockDownPlayer(player);
      await player.open(Media('${dir.path}/good.wav'));

      // Without this, "fetches nothing" also passes for a player that
      // refuses to open anything at all.
      final duration = await player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 5));
      expect(duration.inSeconds, 5);
      final position = await player.stream.position
          .firstWhere((p) => p > Duration.zero)
          .timeout(const Duration(seconds: 5));
      expect(position, greaterThan(Duration.zero));
      expect(player.state.playing, isTrue);
    } finally {
      await player.dispose();
    }
  });

  test('every lockdown option is applied and reads back', () async {
    if (!libmpv) return markTestSkipped('libmpv is not installed');
    final player = await newPlayer();
    try {
      await lockDownPlayer(player);

      final platform = player.platform as NativePlayer;
      for (final option in videoPlayerOptions.entries) {
        expect(await platform.getProperty(option.key), option.value);
      }
    } finally {
      await player.dispose();
    }
  });
}
