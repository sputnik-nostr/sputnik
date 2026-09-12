import 'dart:io';

// List of hardcoded default relays.
const defaultRelays = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.primal.net',
  'wss://relay.snort.social',
];

// Maximum number of user-added relays.
const maxCustomRelays = 20;

// RFC 1035-ish hostname label.
final _hostLabelPattern = RegExp(
  r'^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$',
);
final _tldPattern = RegExp(r'^[a-zA-Z]{2,}$');

bool _isValidDomain(String host) {
  if (host.isEmpty || host.length > 253) return false;

  final labels = host.split('.');
  if (labels.length < 2) return false;
  if (!_tldPattern.hasMatch(labels.last)) return false;
  return labels.every(_hostLabelPattern.hasMatch);
}

bool _isValidHost(String host) =>
    InternetAddress.tryParse(host) != null || _isValidDomain(host);

// Whether [input] is a valid WebSocket URL with a real domain, or IP as host.
bool isRelayUrl(String input) {
  final uri = Uri.tryParse(input);
  if (uri == null || !uri.hasAuthority) return false;
  if (uri.scheme != 'ws' && uri.scheme != 'wss') return false;
  if (uri.userInfo.isNotEmpty) return false;
  return _isValidHost(uri.host);
}

// Normalizes case and a bare "/" path so equivalent URLs deduplicate correctly.
String canonicalRelayUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null) return input.trim();
  return uri.replace(path: uri.path == '/' ? '' : uri.path).toString();
}
