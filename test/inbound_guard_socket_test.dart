import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/inbound_frame_guard.dart';
import 'package:sputnik/nostr/inbound_guard_socket.dart';

import 'support/raw_relay.dart';

Uint8List _reply() => Uint8List.fromList(
  'HTTP/1.1 101 Switching Protocols\r\n'
          'Upgrade: websocket\r\n'
          'Connection: Upgrade\r\n\r\n'
      .codeUnits,
);

Uint8List _joined(List<List<int>> parts) =>
    Uint8List.fromList([for (final part in parts) ...part]);

void main() {
  /// Both ends of a connection on loopback.
  Future<({Socket client, Socket server})> connected() async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(listener.close);
    final accepted = listener.first;
    final client = await Socket.connect(listener.address, listener.port);
    final server = await accepted;
    addTearDown(client.destroy);
    addTearDown(server.destroy);
    return (client: client, server: server);
  }

  /// Everything a socket delivers, and whether its stream has ended.
  ({BytesBuilder bytes, Future<void> ended, Future<void> Function(int) reached})
  collect(Stream<Uint8List> socket) {
    final bytes = BytesBuilder();
    final ended = Completer<void>();
    final waiting = <int, Completer<void>>{};
    socket.listen((chunk) {
      bytes.add(chunk);
      waiting.removeWhere((length, waiter) {
        if (bytes.length < length) return false;
        waiter.complete();
        return true;
      });
    }, onDone: ended.complete);
    Future<void> reached(int length) {
      if (bytes.length >= length) return Future.value();
      return (waiting[length] ??= Completer<void>()).future;
    }

    return (bytes: bytes, ended: ended.future, reached: reached);
  }

  group('a socket of a relay', () {
    test('delivers what the relay sends, unchanged', () async {
      final (:client, :server) = await connected();
      final violations = <InboundViolation>[];
      final guarded = InboundGuardSocket(
        client,
        InboundFrameGuard(),
        violations.add,
      );
      final received = collect(guarded);
      final sent = _joined([
        _reply(),
        webSocketText('["EOSE","a"]'),
        webSocketText('x' * 70000, frames: 3),
        webSocketFrame(9, const []),
      ]);

      server.add(sent);
      await server.close();
      await received.ended;

      expect(received.bytes.takeBytes(), sent);
      expect(violations, isEmpty);
    });

    test('reports the first violation once and hangs up', () async {
      final (:client, :server) = await connected();
      final violations = <InboundViolation>[];
      final guarded = InboundGuardSocket(
        client,
        InboundFrameGuard(),
        violations.add,
      );
      final received = collect(guarded);
      final serverSawHangup = Completer<void>();
      server.listen((_) {}, onError: (_) {}, onDone: serverSawHangup.complete);

      // The reply first, then a binary frame and more behind it.
      server.add(_reply());
      await received.reached(_reply().length);
      server.add(
        _joined([
          webSocketFrame(2, const [1, 2, 3]),
          webSocketFrame(2, const [4]),
        ]),
      );

      await received.ended.timeout(const Duration(seconds: 5));
      await serverSawHangup.future.timeout(const Duration(seconds: 5));

      expect(violations, [InboundViolation.protocol]);
      // Nothing from the chunk that broke the limit went on.
      expect(received.bytes.takeBytes(), _reply());
    });

    test('keeps checking after the data handler was replaced', () async {
      // dart:io takes over the subscription of the HTTP reply once the upgrade
      // is done and sets its own handler on it.
      final (:client, :server) = await connected();
      final violations = <InboundViolation>[];
      final guarded = InboundGuardSocket(
        client,
        InboundFrameGuard(),
        violations.add,
      );
      final bytes = BytesBuilder();
      final ended = Completer<void>();
      final subscription = guarded.listen((_) {}, onDone: ended.complete);
      addTearDown(subscription.cancel);
      subscription.onData(bytes.add);

      server.add(
        _joined([
          _reply(),
          webSocketFrame(2, const [1]),
        ]),
      );
      await ended.future.timeout(const Duration(seconds: 5));

      expect(violations, [InboundViolation.protocol]);
    });

    test('is the connection it wraps for everything else', () async {
      final (:client, :server) = await connected();
      final guarded = InboundGuardSocket(client, InboundFrameGuard(), (_) {});
      final atServer = collect(server);

      guarded.add([1, 2, 3]);
      guarded.write('ab');
      await guarded.flush();
      await guarded.close();
      await atServer.ended;

      expect(atServer.bytes.takeBytes(), [1, 2, 3, 0x61, 0x62]);
      expect(guarded.remotePort, server.port);
      expect(guarded.port, client.port);
      expect(guarded.remoteAddress.address, client.remoteAddress.address);
      expect(guarded.setOption(SocketOption.tcpNoDelay, true), isTrue);
    });
  });

  group('the connections of a relay client', () {
    Future<ConnectionTask<Socket>> Function(Uri, String?, int?) factory({
      required Future<ConnectionTask<Socket>> Function(Uri, String?, int?)
      connect,
      void Function(InboundViolation violation)? onViolation,
    }) => inboundGuardedFactory(
      connect: connect,
      onViolation: onViolation ?? (_) {},
    );

    test('wrap the socket they dial', () async {
      final (:client, server: _) = await connected();
      final connect = factory(
        connect: (_, _, _) async =>
            ConnectionTask.fromSocket(Future.value(client), () {}),
      );

      final task = await connect(Uri.parse('http://relay.example'), null, null);

      expect(await task.socket, isA<InboundGuardSocket>());
    });

    test('can be cancelled like the ones they wrap', () async {
      var cancelled = false;
      final connect = factory(
        connect: (_, _, _) async => ConnectionTask.fromSocket(
          Completer<Socket>().future,
          () => cancelled = true,
        ),
      );

      final task = await connect(Uri.parse('http://relay.example'), null, null);
      task.cancel();

      expect(cancelled, isTrue);
    });

    test('are not wrapped when they go through a proxy', () async {
      // dart:io starts TLS on that socket itself, and the proxy replies first.
      final (:client, server: _) = await connected();
      final dialled = ConnectionTask.fromSocket(Future.value(client), () {});
      final connect = factory(connect: (_, _, _) async => dialled);

      final task = await connect(
        Uri.parse('https://relay.example'),
        'proxy.example',
        3128,
      );

      expect(task, same(dialled));
    });

    test('are dialled with what the client asked for', () async {
      final (:client, server: _) = await connected();
      final asked = <(Uri, String?, int?)>[];
      final connect = factory(
        connect: (url, host, port) async {
          asked.add((url, host, port));
          return ConnectionTask.fromSocket(Future.value(client), () {});
        },
      );

      await connect(Uri.parse('https://relay.example/x'), null, null);
      await connect(Uri.parse('http://relay.example'), 'proxy', 3128);

      expect(asked, [
        (Uri.parse('https://relay.example/x'), null, null),
        (Uri.parse('http://relay.example'), 'proxy', 3128),
      ]);
    });
  });
}
