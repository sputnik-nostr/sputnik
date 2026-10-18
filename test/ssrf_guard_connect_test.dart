import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/services/ssrf_guard.dart';

import 'support/black_hole.dart';
import 'support/eventually.dart';
import 'support/fake_connector.dart';
import 'support/guard_seams.dart';

void main() {
  restoreGuardSeams();

  /// A name with a hundred addresses, none of which ever answers.
  void resolveToBlackHoles() {
    resolveHost = (_) async => [
      for (var i = 1; i <= 100; i++) InternetAddress('12.0.0.$i'),
    ];
  }

  HttpClient guardedClient([Duration? connectionTimeout]) {
    final client = HttpClient()
      ..connectionFactory = guardedConnectionFactory
      ..connectionTimeout = connectionTimeout
      // Whatever http_proxy says on the machine that runs the tests.
      ..findProxy = (_) => 'DIRECT';
    addTearDown(() => client.close(force: true));
    return client;
  }

  /// Fails, rather than hangs, when [request] never ends.
  Future<void> expectEnds(Future<Object?> request, Matcher error) {
    return expectLater(
      request.timeout(const Duration(seconds: 3)),
      throwsA(error),
    );
  }

  final timedOut = isA<SocketException>().having(
    (error) => error.message,
    'message',
    contains('timed out'),
  );

  // Redirects what the guard dials to a real listener on this machine. The
  // connect runs in the zone of the test: futures from another error zone,
  // like the root one, would report their errors as unhandled.
  Future<ConnectionTask<Socket>> Function(
    dynamic,
    int, {
    dynamic sourceAddress,
    int sourcePort,
  })
  dialLoopback(int port) {
    final testZone = Zone.current;
    return (host, _, {sourceAddress, sourcePort = 0}) => testZone.run(
      () => Socket.startConnect(InternetAddress.loopbackIPv4, port),
    );
  }

  for (final scheme in ['http', 'https']) {
    group('$scheme to a name that never answers', () {
      test('ends at the connection timeout and closes every attempt', () async {
        resolveToBlackHoles();
        final connector = FakeConnector();
        await connector.run(() async {
          final client = guardedClient(const Duration(milliseconds: 300));

          await expectEnds(
            client.getUrl(Uri.parse('$scheme://hostile.test/')),
            timedOut,
          );

          expect(connector.attempts, isNotEmpty);
          expect(connector.open, isEmpty);
        });
      });

      test('ends when the client is closed forcibly', () async {
        resolveToBlackHoles();
        final connector = FakeConnector();
        await connector.run(() async {
          final client = guardedClient();
          final ended = expectEnds(
            client.getUrl(Uri.parse('$scheme://hostile.test/')),
            isA<SocketException>(),
          );
          await eventually(() => connector.attempts.isNotEmpty);

          client.close(force: true);
          await ended;

          expect(connector.open, isEmpty);
        });
      });
    });

    group('$scheme to a name whose lookup never answers', () {
      setUp(
        () => resolveHost = (_) => Completer<List<InternetAddress>>().future,
      );

      test('ends at the connection timeout', () async {
        final connector = FakeConnector();
        await connector.run(() async {
          final client = guardedClient(const Duration(milliseconds: 300));

          await expectEnds(
            client.getUrl(Uri.parse('$scheme://silent-dns.test/')),
            timedOut,
          );

          expect(connector.attempts, isEmpty);
        });
      });

      test('ends when the client is closed forcibly', () async {
        final client = guardedClient();
        final ended = expectEnds(
          client.getUrl(Uri.parse('$scheme://silent-dns.test/')),
          isA<SocketException>(),
        );
        await pumpEventQueue();

        client.close(force: true);

        await ended;
      });
    });
  }

  group('guardedConnectionFactory task', () {
    Future<ConnectionTask<Socket>> open(String url) =>
        guardedConnectionFactory(Uri.parse(url), null, null).timeout(
          const Duration(seconds: 3),
        ); // it is handed back before the lookup

    test('hands over the socket of the address that answers', () async {
      final answered = FakeSocket();
      resolveHost = (_) async => [InternetAddress('8.8.8.8')];
      final connector = FakeConnector()
        ..onAttempt = (attempt) => attempt.connect(answered);
      await connector.run(() async {
        final task = await open('http://ok.test/');

        expect(await task.socket, same(answered));

        task.cancel(); // too late: the socket belongs to the caller now
        await pumpEventQueue();
        expect(answered.destroyed, isFalse);
      });
    });

    test('does not dial once cancelled during the lookup', () async {
      final lookup = Completer<List<InternetAddress>>();
      resolveHost = (_) => lookup.future;
      final connector = FakeConnector();
      await connector.run(() async {
        final task = await open('http://slow.test/');
        final ended = expectLater(task.socket, throwsA(isA<SocketException>()));

        task.cancel();
        lookup.complete([InternetAddress('8.8.8.8')]);
        await ended;
        await pumpEventQueue();

        expect(connector.attempts, isEmpty);
      });
    });
  });

  group('TLS over the guarded connection', () {
    SecurityContext serverContext() => SecurityContext()
      ..useCertificateChain('test/fixtures/tls.test.cert.pem')
      ..usePrivateKey('test/fixtures/tls.test.key.pem');

    // The guard dials the public address the resolver returns, which these
    // tests send on to a server of their own.
    setUp(() => resolveHost = (_) async => [InternetAddress('93.184.216.34')]);

    setUpAll(() {
      SecurityContext.defaultContext.setTrustedCertificates(
        'test/fixtures/tls.test.cert.pem',
      );
    });

    Future<HttpServer> serveHello() async {
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverContext(),
      );
      addTearDown(() => server.close(force: true));
      server.listen(
        (request) => request.response
          ..write('hello')
          ..close(),
      );
      return server;
    }

    test('completes the handshake for the host of the url', () async {
      final server = await serveHello();

      await IOOverrides.runZoned(() async {
        final request = await guardedClient().getUrl(
          Uri.parse('https://tls.test:${server.port}/'),
        );
        final response = await request.close();

        expect(await response.transform(utf8.decoder).join(), 'hello');
      }, socketStartConnect: dialLoopback(server.port));
    });

    test('refuses a certificate that is not for the host of the url', () async {
      final server = await serveHello();

      await IOOverrides.runZoned(() async {
        await expectLater(
          guardedClient().getUrl(
            Uri.parse('https://other.test:${server.port}/'),
          ),
          throwsA(isA<HandshakeException>()),
        );
      }, socketStartConnect: dialLoopback(server.port));
    });

    test('ends a handshake that never finishes at the connection timeout and '
        'closes it if it finishes later', () async {
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(raw.close);
      final accepted = raw.first; // held: the server stays silent for now

      await IOOverrides.runZoned(() async {
        await expectEnds(
          guardedClient(const Duration(milliseconds: 300))
              .getUrl(Uri.parse('https://tls.test:${raw.port}/')),
          timedOut,
        );
      }, socketStartConnect: dialLoopback(raw.port));

      // Only now does the server answer, after the client gave up.
      final secured = await SecureSocket.secureServer(
        await accepted,
        serverContext(),
      );
      final closed = Completer<void>();
      secured.listen(
        (_) {},
        onError: (_) => closed.complete(),
        onDone: closed.complete,
      );
      await closed.future.timeout(const Duration(seconds: 3));
    });
  });

  test(
    'https to a black-holed name leaves no connect pending once it ends',
    () async {
      final hole = await BlackHole.bind();
      addTearDown(hole.close);
      resolveToBlackHoles();

      await IOOverrides.runZoned(() async {
        final client = guardedClient(const Duration(milliseconds: 600));

        await expectEnds(
          client.getUrl(Uri.parse('https://hostile.test/')),
          timedOut,
        );

        await eventually(() => hole.pendingConnects == 0);
      }, socketStartConnect: dialLoopback(hole.port));
    },
    skip: BlackHole.isSupported ? false : 'needs /proc/net/tcp',
  );
}
