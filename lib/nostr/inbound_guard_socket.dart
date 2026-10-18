import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'inbound_frame_guard.dart';

/// A relay's socket that closes itself, and says why, when what the relay sends
/// breaks the limits of [InboundFrameGuard].
class InboundGuardSocket extends Stream<Uint8List> implements Socket {
  InboundGuardSocket(this._inner, this._guard, this._onViolation);

  final Socket _inner;
  final InboundFrameGuard _guard;
  final void Function(InboundViolation violation) _onViolation;
  bool _reported = false;

  Uint8List _check(Uint8List chunk) {
    if (_guard.accept(chunk)) return chunk;
    if (!_reported) {
      _reported = true;
      _onViolation(_guard.violation!);
      _inner.destroy();
    }
    return Uint8List(0);
  }

  // A mapped stream, not a closure on the socket's own subscription: dart:io
  // takes over the subscription it listened with once the upgrade is done and
  // replaces its data handler, which would silently drop the check.
  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _inner
      .map(_check)
      .listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  Encoding get encoding => _inner.encoding;

  @override
  set encoding(Encoding value) => _inner.encoding = value;

  @override
  void add(List<int> data) => _inner.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) =>
      _inner.addStream(stream);

  @override
  Future<dynamic> close() => _inner.close();

  @override
  Future<dynamic> get done => _inner.done;

  @override
  Future<dynamic> flush() => _inner.flush();

  @override
  void write(Object? object) => _inner.write(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _inner.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _inner.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => _inner.writeln(object);

  @override
  InternetAddress get address => _inner.address;

  @override
  InternetAddress get remoteAddress => _inner.remoteAddress;

  @override
  int get port => _inner.port;

  @override
  int get remotePort => _inner.remotePort;

  @override
  void destroy() => _inner.destroy();

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _inner.setOption(option, enabled);

  @override
  Uint8List getRawOption(RawSocketOption option) => _inner.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _inner.setRawOption(option);
}

/// The connection factory of [inboundGuardedHttpClient].
Future<ConnectionTask<Socket>> Function(
  Uri url,
  String? proxyHost,
  int? proxyPort,
)
inboundGuardedFactory({
  required Future<ConnectionTask<Socket>> Function(
    Uri url,
    String? proxyHost,
    int? proxyPort,
  )
  connect,
  required void Function(InboundViolation violation) onViolation,
  int maxMessageBytes = 1 << 20,
}) {
  return (url, proxyHost, proxyPort) async {
    final task = await connect(url, proxyHost, proxyPort);
    if (proxyHost != null) return task;
    return ConnectionTask.fromSocket(
      task.socket.then<Socket>(
        (socket) => InboundGuardSocket(
          socket,
          InboundFrameGuard(maxMessageBytes: maxMessageBytes),
          onViolation,
        ),
      ),
      task.cancel,
    );
  };
}

/// An [HttpClient] for opening relay WebSockets: it dials with [connect] and
/// every connection it opens is watched by an [InboundFrameGuard] that calls
/// [onViolation] and closes the connection once the relay breaks a limit.
///
/// Through a proxy nothing is watched: for wss, dart:io opens a tunnel and
/// starts the TLS session itself on this socket, which a wrapper cannot take
/// part in, and for ws the proxy may answer with replies of its own. The limits
/// of the connection pool still apply there.
HttpClient inboundGuardedHttpClient({
  required Future<ConnectionTask<Socket>> Function(
    Uri url,
    String? proxyHost,
    int? proxyPort,
  )
  connect,
  required void Function(InboundViolation violation) onViolation,
  int maxMessageBytes = 1 << 20,
}) {
  return HttpClient()
    ..connectionFactory = inboundGuardedFactory(
      connect: connect,
      onViolation: onViolation,
      maxMessageBytes: maxMessageBytes,
    );
}
