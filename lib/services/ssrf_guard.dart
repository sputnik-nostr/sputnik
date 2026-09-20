import 'dart:io';

/// Whether the first [bits] bits of [bytes] match [prefix], which may be
/// shorter than [bytes].
bool _inCidr(List<int> bytes, List<int> prefix, int bits) {
  final whole = bits ~/ 8;
  for (var i = 0; i < whole; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  final rest = bits % 8;
  if (rest == 0) return true;
  final mask = (0xff << (8 - rest)) & 0xff;
  return (bytes[whole] & mask) == (prefix[whole] & mask);
}

bool _isBlockedV4(List<int> b) {
  return _inCidr(b, [0], 8) || // 0.0.0.0/8
      _inCidr(b, [10], 8) || // private
      _inCidr(b, [100, 64], 10) || // carrier-grade NAT
      _inCidr(b, [127], 8) || // loopback
      _inCidr(b, [169, 254], 16) || // link-local, cloud metadata
      _inCidr(b, [172, 16], 12) || // private
      _inCidr(b, [192, 0, 0], 24) || // IETF protocol assignments
      _inCidr(b, [192, 0, 2], 24) || // documentation
      _inCidr(b, [192, 88, 99], 24) || // deprecated 6to4 relay
      _inCidr(b, [192, 168], 16) || // private
      _inCidr(b, [198, 18], 15) || // benchmarking
      _inCidr(b, [198, 51, 100], 24) || // documentation
      _inCidr(b, [203, 0, 113], 24) || // documentation
      b[0] >= 224; // multicast, reserved, broadcast
}

bool _isBlockedV6(List<int> b) {
  final zeroPrefix = b.take(10).every((byte) => byte == 0);
  if (zeroPrefix) {
    // ::ffff:a.b.c.d reaches the IPv4 host; every other ::/80 form is local.
    if (b[10] == 0xff && b[11] == 0xff) return _isBlockedV4(b.sublist(12));
    return true;
  }
  // 64:ff9b::/96 NAT64 embeds an IPv4 address.
  if (_inCidr(b, [0x00, 0x64, 0xff, 0x9b, 0, 0, 0, 0, 0, 0, 0, 0], 96)) {
    return _isBlockedV4(b.sublist(12));
  }
  // Only 2000::/3 is global unicast; the rest is ULA, link-local, multicast.
  if ((b[0] & 0xe0) != 0x20) return true;
  if (_inCidr(b, [0x20, 0x01, 0x00], 23)) return true; // 2001::/23
  if (_inCidr(b, [0x20, 0x01, 0x0d, 0xb8], 32)) return true; // docs
  if (_inCidr(b, [0x3f, 0xff, 0x00], 20)) return true; // docs
  // 2002::/16 6to4 embeds an IPv4 address.
  if (b[0] == 0x20 && b[1] == 0x02) return _isBlockedV4(b.sublist(2, 6));
  return false;
}

/// Whether [address] is loopback, private, link-local, or otherwise non-public.
bool isBlockedAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  return switch (address.type) {
    InternetAddressType.IPv4 => _isBlockedV4(bytes),
    InternetAddressType.IPv6 => _isBlockedV6(bytes),
    _ => true,
  };
}

int effectivePort(Uri url) =>
    url.port != 0 ? url.port : (url.scheme == 'https' ? 443 : 80);

/// Connects to the address it vetted, so DNS can't rebind after the check.
///
/// Ignores [proxyHost] and [proxyPort].
Future<ConnectionTask<Socket>> guardedConnectionFactory(
  Uri url,
  String? proxyHost,
  int? proxyPort,
) async {
  final addresses = await InternetAddress.lookup(url.host);
  InternetAddress? address;
  for (final candidate in addresses) {
    if (!isBlockedAddress(candidate)) {
      address = candidate;
      break;
    }
  }
  if (address == null) {
    throw SocketException('No public address found for ${url.host}');
  }

  final rawTask = await Socket.startConnect(address, effectivePort(url));
  if (url.scheme != 'https') return rawTask;

  // connectionFactory doesn't wrap https in TLS itself.
  final rawSocket = await rawTask.socket;
  final secureSocket = SecureSocket.secure(rawSocket, host: url.host);
  return ConnectionTask.fromSocket(secureSocket, rawTask.cancel);
}

/// Guards every HttpClient, including NetworkImage, which has no other seam.
class SsrfGuardedHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionFactory = guardedConnectionFactory;
  }
}
