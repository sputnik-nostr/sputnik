import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nip05.dart';
import 'package:sputnik/services/media_loader.dart';
import 'package:sputnik/services/nip05_verification.dart';
import 'package:sputnik/services/ssrf_guard.dart';

import 'support/connect_proxy.dart';
import 'support/eventually.dart';
import 'support/fake_connector.dart';
import 'support/guard_seams.dart';

final _pubkey = 'aa' * 32;

/// The proxy of the environment, as the tests set it.
Map<String, String> _proxied(FakeConnectProxy proxy) => {
  'http_proxy': proxy.url,
  'https_proxy': proxy.url,
};

/// A proxy, the server behind it, and two decoys that stand for the origin as
/// a direct connection would reach it.
///
/// The guard dials the public address that a name resolves to. In the rig,
/// every dial to an address that is not loopback lands on a decoy and is
/// written down, so a test can tell a direct connection without anything
/// leaving the machine.
class _Rig {
  _Rig._(this.upstream, this.proxy, this.tlsDecoy, this.plainDecoy) {
    upstream.listen((request) async {
      upstreamRequests.add('${request.method} ${request.uri}');
      final credentials = request.headers.value(
        HttpHeaders.proxyAuthorizationHeader,
      );
      if (credentials != null) upstreamCredentials.add(credentials);
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen(socket.add, onDone: socket.close);
        return;
      }
      final response = request.response;
      switch (request.uri.path) {
        case '/.well-known/nostr.json':
          response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'names': {'bob': _pubkey},
              }),
            );
        case '/to-the-lan':
          response
            ..statusCode = HttpStatus.found
            ..headers.set(HttpHeaders.locationHeader, 'https://192.168.1.5/');
        default:
          response.write('hello');
      }
      await response.close();
    });
  }

  static Future<_Rig> start() async {
    final upstream = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      SecurityContext()
        ..useCertificateChain('test/fixtures/tls.test.cert.pem')
        ..usePrivateKey('test/fixtures/tls.test.key.pem'),
    );
    return _Rig._(
      upstream,
      await FakeConnectProxy.start(tunnelPort: upstream.port),
      await FakeOrigin.start(secure: true),
      await FakeOrigin.start(),
    );
  }

  /// The server that the proxy tunnels to.
  final HttpServer upstream;
  final FakeConnectProxy proxy;

  /// Reached by a direct dial to port 443.
  final FakeOrigin tlsDecoy;

  /// Reached by a direct dial to any other port.
  final FakeOrigin plainDecoy;

  /// The requests that arrived behind the proxy, and any proxy credentials
  /// that came with them.
  final upstreamRequests = <String>[];
  final upstreamCredentials = <String>[];

  /// The public addresses that the guard dialled itself, as `address:port`.
  final directDials = <String>[];

  int get decoyConnections => tlsDecoy.connections + plainDecoy.connections;

  /// Runs [body] with [environment] as the process environment, by default
  /// the proxy of this rig for both schemes.
  Future<R> run<R>(
    Future<R> Function() body, {
    Map<String, String>? environment,
  }) {
    final outside = Zone.current; // the dials that are real run out here
    return HttpOverrides.runWithHttpOverrides(
      () => IOOverrides.runZoned(
        body,
        socketStartConnect: (host, port, {sourceAddress, sourcePort = 0}) {
          if (host is InternetAddress && host.isLoopback) {
            return outside.run(() => Socket.startConnect(host, port));
          }
          directDials.add(
            '${host is InternetAddress ? host.address : host}:$port',
          );
          final decoy = port == 443 ? tlsDecoy : plainDecoy;
          return outside.run(
            () => Socket.startConnect(InternetAddress.loopbackIPv4, decoy.port),
          );
        },
      ),
      ProxyEnvOverrides(environment ?? _proxied(proxy)),
    );
  }

  Future<void> close() async {
    await upstream.close(force: true);
    await proxy.close();
    await tlsDecoy.close();
    await plainDecoy.close();
  }
}

/// Everything went through the proxy, which got the credentials and which
/// asked for exactly [tunnels]; nobody else saw them and nothing was dialled
/// but the proxy.
void _expectOnlyTheProxy(
  _Rig rig, {
  required List<String> tunnels,
  required List<String> served,
}) {
  expect(rig.proxy.requests.map((r) => r.requestLine), [
    for (final tunnel in tunnels) 'CONNECT $tunnel HTTP/1.1',
  ]);
  for (final request in rig.proxy.requests) {
    expect(
      request.header('proxy-authorization'),
      FakeConnectProxy.authorization,
    );
  }
  expect(rig.upstreamRequests, served);
  expect(rig.upstreamCredentials, isEmpty);
  expect(rig.directDials, isEmpty);
  expect(rig.decoyConnections, 0);
}

/// Answers the names of the tests with fixed addresses, so no test needs DNS.
void _resolve(Map<String, List<String>> names) {
  resolveHost = (host) async {
    final known = names[host];
    if (known != null) return [for (final ip in known) InternetAddress(ip)];
    final literal = InternetAddress.tryParse(host);
    if (literal != null) return [literal];
    throw const SocketException('Failed host lookup');
  };
}

Future<String> _get(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url));
  final response = await request.close();
  return utf8.decoder.bind(response).join();
}

HttpClient _guardedClient() {
  final client = guardedHttpClient();
  addTearDown(() => client.close(force: true));
  return client;
}

Future<String> _echo(String url, {HttpClient? client}) async {
  final socket = await WebSocket.connect(url, customClient: client);
  final echoed = socket.first;
  socket.add('hello');
  final reply = await echoed;
  await socket.close();
  return reply as String;
}

/// A fresh isolate has not made dart:io's shared WebSocket client yet, so the
/// overrides installed there are in place when the first relay connects, as
/// they are in main(). The test bootstrap makes that client before a test
/// runs, without them.
Future<String> _relayInFreshIsolate(int proxyPort) {
  return Isolate.run(() async {
    HttpOverrides.global = ProxyEnvOverrides({
      'https_proxy': 'http://alice:s3cret@127.0.0.1:$proxyPort',
    });
    resolveHost = (host) async => [
      InternetAddress.tryParse(host) ?? InternetAddress('93.184.216.34'),
    ];
    SecurityContext.defaultContext.setTrustedCertificates(
      'test/fixtures/tls.test.cert.pem',
    );
    final dialled = <String>[];
    final outside = Zone.current;
    try {
      final reply = await IOOverrides.runZoned(
        () => _echo('wss://tls.test/'),
        socketStartConnect: (host, port, {sourceAddress, sourcePort = 0}) {
          if (host is InternetAddress && host.isLoopback) {
            return outside.run(() => Socket.startConnect(host, port));
          }
          dialled.add('$host:$port'); // nothing public is reachable from here
          return Future.error(const SocketException('no route'));
        },
      );
      return 'echoed $reply, dialled $dialled';
    } catch (error) {
      return 'failed with $error, dialled $dialled';
    }
  });
}

void main() {
  restoreGuardSeams();

  setUpAll(() {
    SecurityContext.defaultContext.setTrustedCertificates(
      'test/fixtures/tls.test.cert.pem',
    );
  });

  setUp(() {
    clearNip05Cache();
    _resolve({
      'tls.test': ['93.184.216.34'],
      'other.test': ['93.184.216.34'],
      'direct.test': ['93.184.216.35'],
      'proxy.test': ['127.0.0.1'],
      'localhost': ['127.0.0.1', '::1'],
      'internal.test': ['10.0.0.5'],
    });
  });

  Future<_Rig> startRig() async {
    final rig = await _Rig.start();
    addTearDown(rig.close);
    return rig;
  }

  final refusedByTheGuard = isA<SocketException>().having(
    (error) => error.message,
    'message',
    contains('No public address'),
  );

  group('https through a proxy', () {
    test(
      'goes to the proxy, which gets the credentials and nobody else',
      () async {
        final rig = await startRig();

        final body = await rig.run(
          () => _get(_guardedClient(), 'https://tls.test/hello'),
        );

        expect(body, 'hello');
        _expectOnlyTheProxy(
          rig,
          tunnels: ['tls.test:443'],
          served: ['GET /hello'],
        );
      },
    );

    test('hands HttpClient the socket of the proxy, without TLS', () async {
      final rig = await startRig();

      final socket = await rig.run(() async {
        final task = await guardedConnectionFactory(
          Uri.parse('https://tls.test/'),
          '127.0.0.1',
          rig.proxy.port,
        );
        return task.socket;
      });
      addTearDown(socket.destroy);

      expect(socket, isNot(isA<SecureSocket>()));
      expect(socket.remotePort, rig.proxy.port);
      expect(rig.proxy.requests, isEmpty); // HttpClient asks for the tunnel
      expect(rig.directDials, isEmpty);
    });

    test('reaches a proxy that is given by name', () async {
      final rig = await startRig();

      final body = await rig.run(
        () => _get(_guardedClient(), 'https://tls.test/hello'),
        environment: {
          'https_proxy': 'http://alice:s3cret@proxy.test:${rig.proxy.port}',
        },
      );

      expect(body, 'hello');
      _expectOnlyTheProxy(
        rig,
        tunnels: ['tls.test:443'],
        served: ['GET /hello'],
      );
    });

    test('falls back to the next address of a proxy name', () async {
      // Nothing listens on the first address of the proxy.
      _resolve({
        'proxy.test': ['127.0.0.2', '127.0.0.1'],
        'tls.test': ['93.184.216.34'],
      });
      final rig = await startRig();

      final body = await rig.run(
        () => _get(_guardedClient(), 'https://tls.test/hello'),
        environment: {
          'https_proxy': 'http://alice:s3cret@proxy.test:${rig.proxy.port}',
        },
      );

      expect(body, 'hello');
      _expectOnlyTheProxy(
        rig,
        tunnels: ['tls.test:443'],
        served: ['GET /hello'],
      );
    });

    test('checks the certificate of the host, not of the proxy', () async {
      final rig = await startRig();

      await rig.run(
        () => expectLater(
          _get(_guardedClient(), 'https://other.test/'),
          throwsA(isA<HandshakeException>()),
        ),
      );

      expect(rig.proxy.requests.map((r) => r.requestLine), [
        'CONNECT other.test:443 HTTP/1.1',
      ]);
    });

    test('vets the host again for every request', () async {
      final rig = await startRig();

      await rig.run(() async {
        final client = _guardedClient();
        expect(await _get(client, 'https://tls.test/hello'), 'hello');

        _resolve({
          'tls.test': ['10.0.0.5'], // the name now leads inside
        });
        await expectLater(
          _get(client, 'https://tls.test/hello'),
          throwsA(refusedByTheGuard),
        );
      });

      expect(rig.proxy.requests, hasLength(1));
      expect(rig.decoyConnections, 0);
    });

    test('vets the target of a redirect too', () async {
      final rig = await startRig();

      await rig.run(
        () => expectLater(
          _get(_guardedClient(), 'https://tls.test/to-the-lan'),
          throwsA(refusedByTheGuard),
        ),
      );

      expect(rig.upstreamRequests, ['GET /to-the-lan']);
      expect(rig.proxy.requests, hasLength(1)); // none for the redirect
      expect(rig.directDials, isEmpty);
      expect(rig.decoyConnections, 0);
    });

    test('passes on a name with a public address among private ones', () async {
      // The proxy chooses the address that it connects to, so all that the
      // guard asks of a name is that it leads to the public internet.
      _resolve({
        'tls.test': ['10.0.0.5', '93.184.216.34'],
      });
      final rig = await startRig();

      final body = await rig.run(
        () => _get(_guardedClient(), 'https://tls.test/hello'),
      );

      expect(body, 'hello');
    });

    test('reaches a wss relay with a guarded client of its own', () async {
      final rig = await startRig();

      final reply = await rig.run(
        () => _echo('wss://tls.test/', client: _guardedClient()),
      );

      expect(reply, 'hello');
      _expectOnlyTheProxy(rig, tunnels: ['tls.test:443'], served: ['GET /']);
    });

    test('reaches a wss relay with the overrides of the app', () async {
      final rig = await startRig();

      final outcome = await _relayInFreshIsolate(rig.proxy.port);

      expect(outcome, 'echoed hello, dialled []');
      _expectOnlyTheProxy(rig, tunnels: ['tls.test:443'], served: ['GET /']);
    });

    test('verifies a NIP-05 identifier', () async {
      final rig = await startRig();

      final status = await rig.run(
        () => verifyNip05(identifier: 'bob@tls.test', pubkeyHex: _pubkey),
      );

      expect(status, Nip05Status.verified);
      _expectOnlyTheProxy(
        rig,
        tunnels: ['tls.test:443'],
        served: ['GET /.well-known/nostr.json?name=bob'],
      );
    });
  });

  group('through a proxy, the guard still refuses', () {
    /// The guard looks at the target before it so much as connects to the
    /// proxy, so the proxy never hears of it.
    Future<void> expectRefused(_Rig rig, String url, Matcher error) async {
      await rig.run(
        () => expectLater(_get(_guardedClient(), url), throwsA(error)),
      );
      expect(rig.proxy.connections, 0, reason: url);
      expect(rig.directDials, isEmpty, reason: url);
      expect(rig.decoyConnections, 0, reason: url);
    }

    test('a host without a public address', () async {
      final rig = await startRig();

      for (final url in [
        'https://localhost/',
        'https://127.0.0.1:8443/',
        'https://192.168.1.5/',
        'https://10.1.2.3:8443/',
        'https://169.254.169.254/latest/meta-data/',
        'https://[fd00::1]/',
        'https://[::ffff:192.168.1.5]/',
        'https://internal.test/',
      ]) {
        await expectRefused(rig, url, refusedByTheGuard);
      }
    });

    test('a host that leads to this machine itself', () async {
      ownAddresses = OwnAddresses(
        list: () async => [InternetAddress('93.184.216.34')],
      );
      final rig = await startRig();

      await expectRefused(rig, 'https://tls.test/', refusedByTheGuard);
    });

    test('a host that cannot be looked up', () async {
      final rig = await startRig();

      await expectRefused(rig, 'https://unknown.test/', isA<SocketException>());
    });

    test('plain http, also for a relay', () async {
      final rig = await startRig();
      final refusedHere = isA<SocketException>().having(
        (error) => error.message,
        'message',
        contains('through a proxy'),
      );

      await rig.run(() async {
        await expectLater(
          _get(_guardedClient(), 'http://tls.test:8080/'),
          throwsA(refusedHere),
        );
        // A ws:// relay is plain http until it upgrades.
        await expectLater(
          _echo('ws://tls.test:7777/', client: _guardedClient()),
          throwsA(refusedHere),
        );
      });

      expect(rig.proxy.connections, 0);
      expect(rig.directDials, isEmpty);
      expect(rig.decoyConnections, 0);
    });
  });

  group('no_proxy', () {
    test(
      'names a host that is dialled directly, without credentials',
      () async {
        final rig = await startRig();

        final body = await rig.run(
          () => _get(_guardedClient(), 'https://tls.test/hello'),
          environment: {..._proxied(rig.proxy), 'no_proxy': 'tls.test'},
        );

        expect(body, FakeOrigin.greeting);
        expect(rig.directDials, ['93.184.216.34:443']);
        expect(rig.proxy.connections, 0);
        expect(rig.tlsDecoy.heads.single, startsWith('GET /hello '));
        expect(
          rig.tlsDecoy.heads.single.toLowerCase(),
          isNot(contains('proxy-')),
        );
      },
    );

    test('splits one client between the proxy and a direct host', () async {
      final rig = await startRig();

      final bodies = await rig.run(() async {
        final client = _guardedClient();
        return [
          await _get(client, 'https://tls.test/hello'),
          await _get(client, 'http://direct.test:8080/'),
          await _get(client, 'https://tls.test/hello'),
        ];
      }, environment: {..._proxied(rig.proxy), 'no_proxy': 'direct.test'});

      expect(bodies, ['hello', FakeOrigin.greeting, 'hello']);
      // Each request through the proxy gets a tunnel of its own.
      expect(rig.proxy.requests.map((r) => r.requestLine), [
        'CONNECT tls.test:443 HTTP/1.1',
        'CONNECT tls.test:443 HTTP/1.1',
      ]);
      for (final request in rig.proxy.requests) {
        expect(
          request.header('proxy-authorization'),
          FakeConnectProxy.authorization,
        );
      }
      expect(rig.upstreamRequests, ['GET /hello', 'GET /hello']);
      expect(rig.upstreamCredentials, isEmpty);
      expect(rig.directDials, ['93.184.216.35:8080']);
      expect(rig.plainDecoy.heads.single, startsWith('GET / '));
      expect(
        rig.plainDecoy.heads.single.toLowerCase(),
        isNot(contains('proxy-')),
      );
      expect(rig.tlsDecoy.connections, 0);
    });

    test('names a ws relay that is not held to the rule for http', () async {
      final rig = await startRig();

      // The decoy is no relay, so the upgrade fails, but not before the relay
      // was dialled directly and without credentials.
      await rig.run(
        () => expectLater(
          _echo('ws://direct.test:8080/', client: _guardedClient()),
          throwsA(isA<WebSocketException>()),
        ),
        environment: {..._proxied(rig.proxy), 'no_proxy': 'direct.test'},
      );

      expect(rig.directDials, ['93.184.216.35:8080']);
      expect(rig.proxy.connections, 0);
      expect(
        rig.plainDecoy.heads.single.toLowerCase(),
        isNot(contains('proxy-')),
      );
    });
  });

  group('a proxy that does not do its part', () {
    test('is not replaced by a direct connection when it is SOCKS', () async {
      final rig = await startRig();
      final socks = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(socks.close);
      final received = <String>[];
      socks.listen(
        (client) => client.listen((data) {
          // A SOCKS server hangs up on a first byte that is no SOCKS version.
          received.add(latin1.decode(data));
          client.destroy();
        }, onError: (_) {}),
      );

      await rig.run(
        () => expectLater(
          _get(_guardedClient(), 'https://tls.test/hello'),
          throwsA(isA<HttpException>()),
        ),
        environment: {'https_proxy': 'socks5h://127.0.0.1:${socks.port}'},
      );

      expect(received.single, startsWith('CONNECT tls.test:443 '));
      expect(rig.directDials, isEmpty);
      expect(rig.decoyConnections, 0);
    });

    test('is not replaced by a direct connection when it refuses', () async {
      final rig = await startRig();
      rig.proxy.refuseWith = '403 Forbidden';

      await rig.run(
        () => expectLater(
          _get(_guardedClient(), 'https://tls.test/hello'),
          throwsA(
            isA<HttpException>().having(
              (error) => error.message,
              'message',
              contains('403'),
            ),
          ),
        ),
      );

      expect(rig.proxy.requests, hasLength(1));
      expect(rig.directDials, isEmpty);
      expect(rig.decoyConnections, 0);
    });

    test('is not replaced by a direct connection when it is down', () async {
      final rig = await startRig();
      final gone = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = gone.port;
      await gone.close();

      await rig.run(
        () => expectLater(
          _get(_guardedClient(), 'https://tls.test/hello'),
          throwsA(isA<SocketException>()),
        ),
        environment: {'https_proxy': 'http://alice:s3cret@127.0.0.1:$port'},
      );

      expect(rig.directDials, isEmpty);
      expect(rig.decoyConnections, 0);
    });

    test(
      'is not replaced by a direct connection when its name is lost',
      () async {
        final rig = await startRig();

        await rig.run(
          () => expectLater(
            _get(_guardedClient(), 'https://tls.test/hello'),
            throwsA(isA<SocketException>()),
          ),
          environment: {'https_proxy': 'http://alice:s3cret@lost.test:3128'},
        );

        expect(rig.directDials, isEmpty);
        expect(rig.decoyConnections, 0);
      },
    );
  });

  group('dialling the proxy', () {
    final timedOut = isA<SocketException>().having(
      (error) => error.message,
      'message',
      contains('timed out'),
    );

    /// Runs [body] with a proxy on the discard port that never answers.
    Future<R> withSilentProxy<R>(
      FakeConnector connector,
      Future<R> Function() body,
    ) {
      return HttpOverrides.runWithHttpOverrides(
        () => connector.run(body),
        ProxyEnvOverrides({'https_proxy': 'http://127.0.0.1:9'}),
      );
    }

    test('ends at the connection timeout', () async {
      final connector = FakeConnector();
      await withSilentProxy(connector, () async {
        final client = _guardedClient()
          ..connectionTimeout = const Duration(milliseconds: 300);

        await expectLater(
          _get(client, 'https://tls.test/').timeout(const Duration(seconds: 3)),
          throwsA(timedOut),
        );

        expect(
          connector.attempts.map((a) => '${a.address.address}:${a.port}'),
          ['127.0.0.1:9'],
        );
        expect(connector.open, isEmpty);
      });
    });

    test('ends when the client is closed forcibly', () async {
      final connector = FakeConnector();
      await withSilentProxy(connector, () async {
        final client = _guardedClient();
        final ended = expectLater(
          _get(client, 'https://tls.test/').timeout(const Duration(seconds: 3)),
          throwsA(isA<SocketException>()),
        );
        await eventually(() => connector.attempts.isNotEmpty);

        client.close(force: true);
        await ended;

        expect(connector.open, isEmpty);
      });
    });

    test('is left out when cancelled while the target is looked up', () async {
      final lookup = Completer<List<InternetAddress>>();
      final looked = <String>[];
      resolveHost = (host) {
        looked.add(host);
        return lookup.future;
      };
      final connector = FakeConnector();
      await connector.run(() async {
        final task = await guardedConnectionFactory(
          Uri.parse('https://slow.test/'),
          'proxy.test',
          8118,
        );
        final ended = expectLater(task.socket, throwsA(isA<SocketException>()));

        task.cancel();
        lookup.complete([InternetAddress('8.8.8.8')]);
        await ended;
        await pumpEventQueue();

        expect(looked, ['slow.test']); // the proxy was not even looked up
        expect(connector.attempts, isEmpty);
      });
    });

    test('is left out when cancelled while the proxy is looked up', () async {
      final lookup = Completer<List<InternetAddress>>();
      resolveHost = (host) {
        if (host == 'proxy.test') return lookup.future;
        return Future.value([InternetAddress('93.184.216.34')]);
      };
      final connector = FakeConnector();
      await connector.run(() async {
        final task = await guardedConnectionFactory(
          Uri.parse('https://tls.test/'),
          'proxy.test',
          8118,
        );
        final ended = expectLater(task.socket, throwsA(isA<SocketException>()));
        await pumpEventQueue(); // the target is vetted, the proxy not yet found

        task.cancel();
        lookup.complete([InternetAddress('127.0.0.1')]);
        await ended;
        await pumpEventQueue();

        expect(connector.attempts, isEmpty);
      });
    });

    test('is closed when cancelled while it is dialled', () async {
      final connector = FakeConnector();
      await connector.run(() async {
        final task = await guardedConnectionFactory(
          Uri.parse('https://tls.test/'),
          '127.0.0.1',
          8118,
        );
        final ended = expectLater(task.socket, throwsA(isA<SocketException>()));
        await eventually(() => connector.attempts.isNotEmpty);

        task.cancel();
        await ended;

        expect(connector.attempts.single.cancelled, isTrue);
      });
    });
  });

  group('the shared image client through a proxy', () {
    setUp(() => replaceSharedImageClient(null));
    tearDown(() => replaceSharedImageClient(null));

    /// More requests at once than the client's limit per host.
    Future<void> expectBurstToFinish({String? noProxy}) async {
      final rig = await startRig();

      final bodies = await rig.run(
        () => Future.wait([
          for (var i = 0; i < 20; i++)
            fetchImageBytes(Uri.parse('https://tls.test/hello')),
        ]).timeout(const Duration(seconds: 10)),
        environment: {'https_proxy': rig.proxy.url, 'no_proxy': ?noProxy},
      );

      expect(bodies, everyElement(utf8.encode('hello')));
      _expectOnlyTheProxy(
        rig,
        tunnels: List.filled(20, 'tls.test:443'),
        served: List.filled(20, 'GET /hello'),
      );
    }

    test(
      'finishes more requests at once than its limit per host',
      expectBurstToFinish,
    );

    test('is not limited again by no_proxy entries for other hosts', () {
      return expectBurstToFinish(noProxy: 'org,example.com');
    });
  });
}
