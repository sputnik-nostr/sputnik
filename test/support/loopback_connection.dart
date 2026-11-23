import 'dart:io';

/// What the pool dialled relays with before a test replaced it; the SSRF guard.
Future<ConnectionTask<Socket>> Function(Uri, String?, int?)?
productionRelayConnectionFactory;

/// Dials a relay as the app does, but without the SSRF guard, which refuses
/// the loopback relays that tests serve. A proxy is dialled instead if given.
Future<ConnectionTask<Socket>> loopbackConnectionFactory(
  Uri url,
  String? proxyHost,
  int? proxyPort,
) {
  final host = proxyHost ?? url.host;
  final port = proxyPort ?? (url.port != 0 ? url.port : 80);
  return url.scheme == 'https' && proxyHost == null
      ? SecureSocket.startConnect(host, port)
      : Socket.startConnect(host, port);
}
