import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _guid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

/// One WebSocket frame as a server sends it, so unmasked.
Uint8List webSocketFrame(int opcode, List<int> payload, {bool fin = true}) {
  final length = payload.length;
  final headerLength = length < 126
      ? 2
      : length < 65536
      ? 4
      : 10;
  final frame = Uint8List(headerLength + length);
  frame[0] = (fin ? 0x80 : 0) | opcode;
  if (length < 126) {
    frame[1] = length;
  } else if (length < 65536) {
    frame[1] = 126;
    ByteData.sublistView(frame).setUint16(2, length);
  } else {
    frame[1] = 127;
    ByteData.sublistView(frame).setUint64(2, length);
  }
  frame.setRange(headerLength, headerLength + length, payload);
  return frame;
}

/// A text message cut into [frames] pieces of near equal size.
Uint8List webSocketText(String text, {int frames = 1}) {
  final bytes = utf8.encode(text);
  final piece = (bytes.length / frames).ceil();
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < frames; i++) {
    final start = (i * piece).clamp(0, bytes.length);
    final end = ((i + 1) * piece).clamp(0, bytes.length);
    out.add(
      webSocketFrame(
        i == 0 ? 1 : 0,
        bytes.sublist(start, end),
        fin: i == frames - 1,
      ),
    );
  }
  return out.takeBytes();
}

/// [count] copies of [frame], in one buffer.
Uint8List repeated(Uint8List frame, int count) {
  final out = Uint8List(frame.length * count);
  for (var i = 0; i < count; i++) {
    out.setRange(i * frame.length, (i + 1) * frame.length, frame);
  }
  return out;
}

/// A relay that speaks the WebSocket handshake and then hands the raw socket
/// to the test, so it can send frames no real server would.
class RawRelay {
  RawRelay._(this._server);

  final HttpServer _server;

  /// Every connection accepted so far.
  final connections = <RawConnection>[];

  String get url => 'ws://127.0.0.1:${_server.port}';

  /// Runs [onConnection] for each client, once the upgrade is done. It listens
  /// on [port], or on one the system picks if that is 0.
  static Future<RawRelay> start(
    FutureOr<void> Function(RawConnection connection) onConnection, {
    int port = 0,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final relay = RawRelay._(server);
    server.listen((request) async {
      final key = request.headers.value('sec-websocket-key')!;
      final accept = base64.encode(
        sha1.convert(utf8.encode('$key$_guid')).bytes,
      );
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.add(
        utf8.encode(
          'HTTP/1.1 101 Switching Protocols\r\n'
          'Upgrade: websocket\r\n'
          'Connection: Upgrade\r\n'
          'Sec-WebSocket-Accept: $accept\r\n\r\n',
        ),
      );
      final connection = RawConnection._(socket, request.headers);
      relay.connections.add(connection);
      try {
        await onConnection(connection);
      } catch (_) {
        // The client hanging up mid-write is what most tests are about.
      }
    });
    return relay;
  }

  Future<void> close() async {
    for (final connection in connections) {
      connection.socket.destroy();
    }
    await _server.close(force: true);
  }
}

/// The server side of one connection to a [RawRelay].
class RawConnection {
  RawConnection._(this.socket, this.requestHeaders) {
    socket.listen(
      _onData,
      onError: (_) => _end(),
      onDone: _end,
      cancelOnError: true,
    );
  }

  final Socket socket;

  /// The headers of the request that was upgraded to this connection.
  final HttpHeaders requestHeaders;

  /// The JSON messages the client has sent, oldest first.
  final received = <List<dynamic>>[];

  /// Pong frames the client has sent, e.g. in answer to our pings.
  int pongs = 0;

  final _ended = Completer<void>();
  final _buffer = BytesBuilder();
  final _waiting = <Completer<void>>[];

  /// Completes once the client has closed or dropped its end.
  Future<void> get closed => _ended.future;

  bool get isClosed => _ended.isCompleted;

  /// Messages the client sent that start with [verb], e.g. `REQ`.
  List<List<dynamic>> messagesOf(String verb) => [
    for (final message in received)
      if (message.first == verb) message,
  ];

  /// Waits for the client's [index]th message that starts with [verb].
  Future<List<dynamic>> next(String verb, {int index = 0}) async {
    while (messagesOf(verb).length <= index) {
      if (_ended.isCompleted) throw StateError('closed before a $verb');
      final wake = Completer<void>();
      _waiting.add(wake);
      await wake.future;
    }
    return messagesOf(verb)[index];
  }

  /// Raw bytes; [flush] after a large write to wait for it to leave.
  void send(List<int> bytes) => socket.add(bytes);

  void sendText(String text, {int frames = 1}) =>
      send(webSocketText(text, frames: frames));

  Future<void> flush() => socket.flush();

  void _end() {
    if (!_ended.isCompleted) _ended.complete();
    _wakeAll();
  }

  void _wakeAll() {
    final waiting = List.of(_waiting);
    _waiting.clear();
    for (final wake in waiting) {
      if (!wake.isCompleted) wake.complete();
    }
  }

  void _onData(Uint8List data) {
    _buffer.add(data);
    final bytes = _buffer.takeBytes();
    var at = 0;
    while (bytes.length - at >= 2) {
      final opcode = bytes[at] & 0x0f;
      var length = bytes[at + 1] & 0x7f;
      var header = 2;
      if (length == 126) {
        if (bytes.length - at < 4) break;
        length = ByteData.sublistView(bytes).getUint16(at + 2);
        header = 4;
      } else if (length == 127) {
        if (bytes.length - at < 10) break;
        length = ByteData.sublistView(bytes).getUint64(at + 2);
        header = 10;
      }
      final masked = bytes[at + 1] & 0x80 != 0;
      final maskAt = at + header;
      final payloadAt = maskAt + (masked ? 4 : 0);
      if (bytes.length - payloadAt < length) break;
      final payload = Uint8List.fromList(
        bytes.sublist(payloadAt, payloadAt + length),
      );
      if (masked) {
        for (var i = 0; i < length; i++) {
          payload[i] ^= bytes[maskAt + (i % 4)];
        }
      }
      if (opcode == 1) {
        received.add(jsonDecode(utf8.decode(payload)) as List<dynamic>);
      } else if (opcode == 10) {
        pongs++;
      }
      at = payloadAt + length;
    }
    if (at < bytes.length) _buffer.add(bytes.sublist(at));
    _wakeAll();
  }
}
