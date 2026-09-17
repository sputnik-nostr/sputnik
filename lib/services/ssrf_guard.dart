import 'dart:io';

// Blocks probing the device's own network via an attacker-controlled URL.
bool isBlockedAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return true;
  }
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    if (bytes[0] == 0) return true; // 0.0.0.0/8
    if (bytes[0] == 10) return true; // 10.0.0.0/8
    if (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) return true;
    if (bytes[0] == 192 && bytes[1] == 168) return true; // 192.168.0.0/16
    if (bytes[0] == 169 && bytes[1] == 254) return true; // link-local/meta
  } else if (address.type == InternetAddressType.IPv6) {
    if ((bytes[0] & 0xfe) == 0xfc) return true; // fc00::/7 unique local
  }
  return false;
}

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

  final rawTask = await Socket.startConnect(address, url.port);
  if (url.scheme != 'https') return rawTask;

  // connectionFactory doesn't wrap https in TLS itself.
  final rawSocket = await rawTask.socket;
  final secureSocket = SecureSocket.secure(rawSocket, host: url.host);
  return ConnectionTask.fromSocket(secureSocket, rawTask.cancel);
}

// Covers NetworkImage/Image.network too - they have no other injection seam.
class SsrfGuardedHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionFactory = guardedConnectionFactory;
  }
}
