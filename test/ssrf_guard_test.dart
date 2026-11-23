import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/services/ssrf_guard.dart';

import 'support/fake_connector.dart';
import 'support/guard_seams.dart';

void main() {
  restoreGuardSeams();

  group('effectivePort', () {
    // Mirrors how dart:io's WebSocket.connect rewrites a wss/ws url.
    Uri rewriteLikeWebSocketConnect(String url) {
      final uri = Uri.parse(url);
      return Uri(
        scheme: uri.isScheme('wss') ? 'https' : 'http',
        host: uri.host,
        port: uri.port,
      );
    }

    test('a ws-origin uri rewritten to https with no port is not port 0', () {
      final rewritten = rewriteLikeWebSocketConnect('wss://relay.example');
      expect(rewritten.port, 0); // confirms the Uri quirk still exists
      expect(effectivePort(rewritten), 443);
    });

    test('a ws-origin uri rewritten to http with no port is not port 0', () {
      final rewritten = rewriteLikeWebSocketConnect('ws://relay.example');
      expect(effectivePort(rewritten), 80);
    });

    test('an explicit port is preserved', () {
      expect(effectivePort(Uri.parse('https://relay.example:8443')), 8443);
    });
  });

  group('isBlockedAddress', () {
    bool blocked(String ip) => isBlockedAddress(InternetAddress(ip));

    test('blocks the IPv4 private and special-use ranges', () {
      for (final ip in [
        '0.0.0.0',
        '10.1.2.3',
        '100.64.0.1',
        '100.127.255.254',
        '127.0.0.1',
        '127.9.9.9',
        '169.254.169.254',
        '172.16.0.1',
        '172.31.255.255',
        '192.0.0.1',
        '192.0.2.1',
        '192.168.1.1',
        '198.18.0.1',
        '198.19.255.255',
        '198.51.100.1',
        '203.0.113.1',
        '224.0.0.1',
        '240.0.0.1',
        '255.255.255.255',
      ]) {
        expect(blocked(ip), isTrue, reason: ip);
      }
    });

    test('allows public IPv4 addresses next to the blocked ranges', () {
      for (final ip in [
        '8.8.8.8',
        '1.1.1.1',
        '100.63.255.255',
        '100.128.0.1',
        '172.15.255.255',
        '172.32.0.1',
        '198.17.255.255',
        '198.20.0.1',
        '223.255.255.255',
      ]) {
        expect(blocked(ip), isFalse, reason: ip);
      }
    });

    test('blocks IPv4 addresses carried inside IPv6', () {
      for (final ip in [
        '::ffff:127.0.0.1',
        '::ffff:7f00:1',
        '::ffff:10.0.0.1',
        '::ffff:192.168.1.1',
        '::ffff:169.254.169.254',
        '64:ff9b::7f00:1',
        '64:ff9b::a9fe:a9fe',
        '2002:7f00:1::',
        '2002:c0a8:101::1',
      ]) {
        expect(blocked(ip), isTrue, reason: ip);
      }
    });

    test('allows a public IPv4 address carried inside IPv6', () {
      expect(blocked('::ffff:8.8.8.8'), isFalse);
      expect(blocked('64:ff9b::808:808'), isFalse);
      expect(blocked('2002:808:808::1'), isFalse);
    });

    test('blocks IPv6 loopback, unspecified and local ranges', () {
      for (final ip in [
        '::',
        '::1',
        '::2',
        '::7f00:1',
        'fc00::1',
        'fd12:3456::1',
        'fe80::1',
        'fec0::1',
        'ff02::1',
        '100::1',
        '2001::1',
        '2001:db8::1',
        '3fff::1',
      ]) {
        expect(blocked(ip), isTrue, reason: ip);
      }
    });

    test('allows public IPv6 unicast addresses', () {
      for (final ip in [
        '2606:4700:4700::1111',
        '2001:4860:4860::8888',
        '2a00:1450:4001:81b::200e',
      ]) {
        expect(blocked(ip), isFalse, reason: ip);
      }
    });
  });

  group('guardedConnectionFactory', () {
    test('cannot reach a loopback service through a mapped address', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var served = 0;
      server.listen((request) {
        served++;
        request.response.close();
      });

      for (final host in [
        '127.0.0.1',
        '[::ffff:127.0.0.1]',
        '[::ffff:7f00:1]',
      ]) {
        final client = HttpClient()
          ..connectionFactory = guardedConnectionFactory
          // Whatever http_proxy says on the machine that runs the tests.
          ..findProxy = (_) => 'DIRECT';
        addTearDown(() => client.close(force: true));
        await expectLater(
          client.getUrl(Uri.parse('http://$host:${server.port}/')),
          throwsA(isA<SocketException>()),
          reason: host,
        );
      }
      expect(served, 0);
    });

    group('with a replaced resolver', () {
      /// Opens a connection that must fail, however the failure is reported.
      Future<void> dial(FakeConnector connector, String url) {
        return connector.run(
          () => expectLater(
            guardedConnectionFactory(
              Uri.parse(url),
              null,
              null,
            ).then((task) => task.socket),
            throwsA(isA<SocketException>()),
          ),
        );
      }

      test(
        'dials only the public addresses of a name with private ones',
        () async {
          resolveHost = (_) async => [
            InternetAddress('10.0.0.5'),
            InternetAddress('8.8.8.8'),
            InternetAddress('::ffff:192.168.1.5'),
            InternetAddress('127.0.0.1'),
            InternetAddress('2606:4700:4700::1111'),
            InternetAddress('fd00::5'),
          ];
          final connector = FakeConnector()
            ..onAttempt = (attempt) => attempt.fail();

          await dial(connector, 'http://mixed.test:8080/');

          expect(
            connector.attempts.map((attempt) => attempt.address.address),
            unorderedEquals(['8.8.8.8', '2606:4700:4700::1111']),
          );
          expect(
            connector.attempts.map((attempt) => attempt.port),
            everyElement(8080),
          );
        },
      );

      test('does not dial a name that only has private addresses', () async {
        resolveHost = (_) async => [
          InternetAddress('10.0.0.5'),
          InternetAddress('169.254.169.254'),
          InternetAddress('::1'),
        ];
        final connector = FakeConnector();

        await dial(connector, 'http://internal.test/');

        expect(connector.attempts, isEmpty);
      });

      group('on a machine with a public address of its own', () {
        // A public IPv4 address, and an IPv6 one from a /64 shared with the
        // rest of the LAN.
        setUp(() {
          ownAddresses = OwnAddresses(
            list: () async => [
              InternetAddress('93.184.216.34'),
              InternetAddress('2606:4700:4700:a1:4278:3bff:1d0f:7b0d'),
            ],
          );
        });

        test('does not dial its own addresses or its LAN neighbours', () async {
          resolveHost = (_) async => [
            InternetAddress('2606:4700:4700:a1::1'),
            InternetAddress('93.184.216.34'),
            InternetAddress('::ffff:93.184.216.34'),
            InternetAddress('2606:4700:4700:a2::1'),
            InternetAddress('93.184.216.35'),
          ];
          final connector = FakeConnector()
            ..onAttempt = (attempt) => attempt.fail();

          await dial(connector, 'http://neighbours.test/');

          expect(
            connector.attempts.map((attempt) => attempt.address.address),
            unorderedEquals(['2606:4700:4700:a2::1', '93.184.216.35']),
          );
        });

        test(
          'does not dial a name that only leads to its own network',
          () async {
            resolveHost = (_) async => [
              InternetAddress('2606:4700:4700:a1::1'),
              InternetAddress('::ffff:93.184.216.34'),
            ];
            final connector = FakeConnector();

            await dial(connector, 'http://neighbours.test/');

            expect(connector.attempts, isEmpty);
          },
        );

        test('does not dial an address literal on its own network', () async {
          final connector = FakeConnector();

          await dial(connector, 'https://[2606:4700:4700:a1::1]:8443/');
          await dial(connector, 'http://93.184.216.34:8080/');

          expect(connector.attempts, isEmpty);
        });

        test('looks past a long run of addresses on its own network', () async {
          resolveHost = (_) async => [
            for (var i = 1; i <= 10; i++)
              InternetAddress('2606:4700:4700:a1::$i'),
            InternetAddress('2606:4700:4700:a2::1'),
          ];
          final connector = FakeConnector()
            ..onAttempt = (attempt) => attempt.fail();

          await dial(connector, 'http://neighbours.test/');

          expect(connector.attempts.map((attempt) => attempt.address.address), [
            '2606:4700:4700:a2::1',
          ]);
        });

        test('dials as before when the interfaces cannot be listed', () async {
          ownAddresses = OwnAddresses(
            list: () async => throw const OSError('not allowed', 13),
          );
          resolveHost = (_) async => [InternetAddress('2606:4700:4700:a1::1')];
          final connector = FakeConnector()
            ..onAttempt = (attempt) => attempt.fail();

          await dial(connector, 'http://neighbours.test/');

          expect(connector.attempts.map((attempt) => attempt.address.address), [
            '2606:4700:4700:a1::1',
          ]);
        });
      });
    });
  });

  group('isLocalNetworkUrl', () {
    test('flags private and loopback IP literals', () {
      expect(isLocalNetworkUrl('ws://192.168.1.5:7777'), isTrue);
      expect(isLocalNetworkUrl('ws://127.0.0.1'), isTrue);
      expect(isLocalNetworkUrl('wss://[::1]'), isTrue);
      expect(isLocalNetworkUrl('ws://10.0.0.2'), isTrue);
    });

    test('flags local-only host names', () {
      expect(isLocalNetworkUrl('ws://relay.local'), isTrue);
      expect(isLocalNetworkUrl('ws://nas.home.arpa'), isTrue);
      expect(isLocalNetworkUrl('ws://localhost:4848'), isTrue);
    });

    test('leaves public hosts alone', () {
      expect(isLocalNetworkUrl('wss://relay.damus.io'), isFalse);
      expect(isLocalNetworkUrl('wss://8.8.8.8'), isFalse);
      expect(isLocalNetworkUrl('wss://localhost.example.com'), isFalse);
    });
  });
  group('connectToAny', () {
    test('falls back to the next address when one refuses', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final refusing = InternetAddress('127.0.0.2');

      final socket = await connectToAny([
        refusing,
        InternetAddress.loopbackIPv4,
      ], server.port).socket.timeout(const Duration(seconds: 5));
      addTearDown(socket.destroy);

      expect(socket.remoteAddress, InternetAddress.loopbackIPv4);
    });

    test('fails once every address has failed', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();

      await expectLater(
        connectToAny([
          InternetAddress('127.0.0.2'),
          InternetAddress.loopbackIPv4,
        ], port).socket.timeout(const Duration(seconds: 5)),
        throwsA(isA<SocketException>()),
      );
    });
  });
}
