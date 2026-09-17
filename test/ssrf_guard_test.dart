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
    bool blocked(String ip) =>
        isBlockedAddress(InternetAddress(ip, type: InternetAddressType.IPv4));

    test('blocks loopback', () => expect(blocked('127.0.0.1'), isTrue));
    test('blocks 10.0.0.0/8', () => expect(blocked('10.1.2.3'), isTrue));
    test('blocks 172.16.0.0/12', () => expect(blocked('172.20.0.1'), isTrue));
    test('blocks 192.168.0.0/16', () => expect(blocked('192.168.1.1'), isTrue));
    test(
      'blocks link-local/cloud metadata',
      () => expect(blocked('169.254.169.254'), isTrue),
    );
    test('allows a public address', () => expect(blocked('8.8.8.8'), isFalse));
  });
}
