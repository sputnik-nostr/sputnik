import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/models/relay.dart';

void main() {
  test('accepts wss URLs with a real domain', () {
    expect(isRelayUrl('wss://relay.damus.io'), isTrue);
    expect(isRelayUrl('wss://relay.example.com:4848'), isTrue);
    expect(isRelayUrl('wss://relay.example.com/path'), isTrue);
  });

  test('accepts ws URLs', () {
    expect(isRelayUrl('ws://relay.example.com'), isTrue);
  });

  test('accepts IPv4 and IPv6 hosts', () {
    expect(isRelayUrl('wss://192.168.1.1'), isTrue);
    expect(isRelayUrl('wss://[::1]'), isTrue);
    expect(isRelayUrl('wss://[2001:db8::1]'), isTrue);
  });

  test('rejects schemes other than ws/wss', () {
    expect(isRelayUrl('https://relay.example.com'), isFalse);
    expect(isRelayUrl('w://relay.example.com'), isFalse);
  });

  test('rejects a single-label host', () {
    expect(isRelayUrl('wss://a'), isFalse);
    expect(isRelayUrl('wss://localhost'), isFalse);
  });

  test('rejects malformed IPv4 addresses', () {
    expect(isRelayUrl('wss://256.256.256.256'), isFalse);
    expect(isRelayUrl('wss://1.2.3'), isFalse);
  });

  test('rejects malformed domains', () {
    expect(isRelayUrl('wss://a..b'), isFalse);
    expect(isRelayUrl('wss://-invalid-.com'), isFalse);
    expect(isRelayUrl('wss://foo bar.com'), isFalse);
  });

  test('rejects a missing or empty host', () {
    expect(isRelayUrl('wss://'), isFalse);
    expect(isRelayUrl('wss:relay'), isFalse);
  });

  test('rejects garbage input', () {
    expect(isRelayUrl('not a url'), isFalse);
    expect(isRelayUrl(''), isFalse);
  });

  test('canonicalRelayUrl lowercases scheme and host', () {
    expect(
      canonicalRelayUrl('WSS://Relay.Example.COM'),
      'wss://relay.example.com',
    );
  });

  test('canonicalRelayUrl drops a bare root path', () {
    expect(
      canonicalRelayUrl('wss://relay.example.com/'),
      'wss://relay.example.com',
    );
  });

  test('canonicalRelayUrl keeps a non-root path as-is', () {
    expect(
      canonicalRelayUrl('wss://relay.example.com/path'),
      'wss://relay.example.com/path',
    );
  });

  test('canonicalRelayUrl makes case/trailing-slash variants match', () {
    expect(
      canonicalRelayUrl('WSS://Relay.Example.COM/'),
      canonicalRelayUrl('wss://relay.example.com'),
    );
  });

  test('rejects an authority that carries userinfo', () {
    expect(isRelayUrl('wss://relay.damus.io@158.51.42.7'), isFalse);
    expect(isRelayUrl('wss://relay.damus.io@evil.example.com'), isFalse);
    expect(isRelayUrl('wss://user:pass@relay.example.com'), isFalse);
    expect(isRelayUrl('wss://relay.example.com'), isTrue);
  });

  test('anything accepted stays accepted once canonicalised', () {
    const inputs = [
      'wss://relay.example.com',
      'WSS://Relay.Example.COM/',
      'wss://relay.example.com:8080',
      'ws://192.0.2.1',
      'wss://[2001:db8::1]',
    ];

    for (final input in inputs) {
      expect(isRelayUrl(input), isTrue, reason: input);
      final canonical = canonicalRelayUrl(input);
      expect(isRelayUrl(canonical), isTrue, reason: canonical);
      expect(canonicalRelayUrl(canonical), canonical, reason: canonical);
    }
  });
}
