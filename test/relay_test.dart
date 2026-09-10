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
}
