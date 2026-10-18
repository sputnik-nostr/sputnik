import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sputnik/services/ssrf_guard.dart';

/// What a [FakeConnectProxy] was asked for.
class ProxyRequest {
  const ProxyRequest(this.requestLine, this.headers);

  /// The first line, like `CONNECT relay.test:443 HTTP/1.1`.
  final String requestLine;

  /// The headers, with lower-case names.
  final Map<String, String> headers;

  String get method => requestLine.split(' ').first;

  String? header(String name) => headers[name.toLowerCase()];
}

int _endOfHead(List<int> bytes) {
  for (var i = 3; i < bytes.length; i++) {
    if (bytes[i - 3] == 13 &&
        bytes[i - 2] == 10 &&
        bytes[i - 1] == 13 &&
        bytes[i] == 10) {
      return i + 1;
    }
  }
  return -1;
}

/// Reads the head of an HTTP request off [socket] and passes it to [onHead],
/// which says where the bytes that follow the head are to go, or answers null
/// to drop them. Those bytes are held back until it has answered.
void _readHead(
  Socket socket,
  Future<void Function(Uint8List)?> Function(String head) onHead,
) {
  final held = BytesBuilder(copy: false);
  void Function(Uint8List)? forward;
  var headRead = false;
  socket.listen(
    (chunk) {
      final next = forward;
      if (next != null) return next(chunk);
      held.add(chunk);
      if (headRead) return;
      final bytes = held.toBytes();
      final end = _endOfHead(bytes);
      if (end < 0) return;
      headRead = true;
      held
        ..clear()
        ..add(Uint8List.sublistView(bytes, end));
      onHead(latin1.decode(bytes.sublist(0, end - 4))).then((target) {
        forward = target ?? (_) {};
        final rest = held.takeBytes();
        if (rest.isNotEmpty) forward!(rest);
      });
    },
    onError: (_) {},
    onDone: socket.destroy,
  );
}

void _tryAdd(Socket socket, List<int> data) {
  try {
    socket.add(data);
  } catch (_) {
    // The other end is already gone.
  }
}

/// An HTTP proxy on the loopback interface that records its requests and
/// answers every CONNECT by tunnelling to one local port, the way a proxy
/// makes the last hop to the server. Anything else is answered with a 501.
class FakeConnectProxy {
  FakeConnectProxy._(this._server, this._tunnelPort) {
    _server.listen(_serve);
  }

  static Future<FakeConnectProxy> start({required int tunnelPort}) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return FakeConnectProxy._(server, tunnelPort);
  }

  final ServerSocket _server;
  final int _tunnelPort;
  final _open = <Socket>{};

  /// The requests, in the order they arrived.
  final requests = <ProxyRequest>[];

  /// How many TCP connections were accepted, whether or not they sent a request.
  int connections = 0;

  /// A status line like `403 Forbidden` to answer every CONNECT with, or null
  /// to tunnel it.
  String? refuseWith;

  int get port => _server.port;

  /// A proxy setting as the environment would carry it.
  String get url => 'http://alice:s3cret@127.0.0.1:$port';

  /// The Proxy-Authorization header HttpClient makes of [url].
  static const authorization = 'Basic YWxpY2U6czNjcmV0';

  void _serve(Socket client) {
    connections++;
    _open.add(client);
    _readHead(client, (head) async {
      final lines = head.split('\r\n');
      final request = ProxyRequest(lines.first, {
        for (final line in lines.skip(1))
          if (line.contains(':'))
            line.substring(0, line.indexOf(':')).toLowerCase(): line
                .substring(line.indexOf(':') + 1)
                .trim(),
      });
      requests.add(request);

      Future<void Function(Uint8List)?> answer(String status) async {
        _tryAdd(
          client,
          latin1.encode(
            'HTTP/1.1 $status\r\nContent-Length: 0\r\nConnection: close\r\n\r\n',
          ),
        );
        await client.flush().catchError((Object _) => null);
        client.destroy();
        return null;
      }

      if (request.method != 'CONNECT') return answer('501 Not Implemented');
      final refusal = refuseWith;
      if (refusal != null) return answer(refusal);
      final Socket tunnel;
      try {
        tunnel = await Socket.connect(
          InternetAddress.loopbackIPv4,
          _tunnelPort,
        );
      } catch (_) {
        return answer('502 Bad Gateway');
      }
      _open.add(tunnel);
      _tryAdd(
        client,
        latin1.encode('HTTP/1.1 200 Connection established\r\n\r\n'),
      );
      tunnel.listen(
        (data) => _tryAdd(client, data),
        onDone: client.destroy,
        onError: (_) => client.destroy(),
      );
      unawaited(
        client.done.then(
          (_) => tunnel.destroy(),
          onError: (_) => tunnel.destroy(),
        ),
      );
      return (data) => _tryAdd(tunnel, data);
    });
  }

  Future<void> close() async {
    await _server.close();
    for (final socket in _open) {
      socket.destroy();
    }
  }
}

/// A stand-in for the server that only a direct connection reaches. It counts
/// the connections and keeps the heads of the requests it could read, so a test
/// can tell what such a connection sent, or that there was none.
class FakeOrigin {
  FakeOrigin._(this._server, this._context) {
    _server.listen(_serve);
  }

  /// With [secure], a TLS server for tls.test, as the tests of the guard use.
  static Future<FakeOrigin> start({bool secure = false}) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final context = secure
        ? (SecurityContext()
            ..useCertificateChain('test/fixtures/tls.test.cert.pem')
            ..usePrivateKey('test/fixtures/tls.test.key.pem'))
        : null;
    return FakeOrigin._(server, context);
  }

  final ServerSocket _server;
  final SecurityContext? _context;
  final _open = <Socket>{};

  int connections = 0;

  /// The heads of the requests, as the server read them.
  final heads = <String>[];

  int get port => _server.port;

  /// What a client that reaches this server reads back.
  static const greeting = 'the origin itself';

  Future<void> _serve(Socket accepted) async {
    connections++;
    _open.add(accepted);
    final Socket socket;
    try {
      final context = _context;
      socket = context == null
          ? accepted
          : await SecureSocket.secureServer(accepted, context);
    } catch (_) {
      return; // the client did not like the certificate
    }
    _open.add(socket);
    _readHead(socket, (head) async {
      heads.add(head);
      final refuse = head.startsWith('CONNECT ');
      final body = refuse ? '' : greeting;
      _tryAdd(
        socket,
        latin1.encode(
          'HTTP/1.1 ${refuse ? '400 Bad Request' : '200 OK'}\r\n'
          'Content-Length: ${body.length}\r\nConnection: close\r\n\r\n$body',
        ),
      );
      await socket.flush().catchError((Object _) => null);
      socket.destroy();
      return null;
    });
  }

  Future<void> close() async {
    await _server.close();
    for (final socket in _open) {
      socket.destroy();
    }
  }
}

/// The overrides of the app, reading [environment] where dart:io would read
/// the process environment (http_proxy, https_proxy, no_proxy).
class ProxyEnvOverrides extends SsrfGuardedHttpOverrides {
  ProxyEnvOverrides(this.environment);

  final Map<String, String> environment;

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? _) =>
      super.findProxyFromEnvironment(url, environment);
}
