import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/services/ssrf_guard.dart';

void main() {
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
          ..connectionFactory = guardedConnectionFactory;
        addTearDown(() => client.close(force: true));
        await expectLater(
          client.getUrl(Uri.parse('http://$host:${server.port}/')),
          throwsA(isA<SocketException>()),
          reason: host,
        );
      }
      expect(served, 0);
    });
  });
}
