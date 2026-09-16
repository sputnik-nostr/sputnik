import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Result of checking a NIP-05 identifier against a pubkey.
enum Nip05Status {
  /// The domain confirmed this identifier maps to the pubkey.
  verified,

  /// The domain responded but does not map this identifier to the pubkey.
  mismatch,

  /// Could not be checked: malformed identifier, no response, or the
  /// target was refused as unsafe to fetch.
  unreachable,
}

typedef Nip05Identifier = ({String local, String domain});

const _fetchTimeout = Duration(seconds: 6);
const _maxResponseBytes = 64 * 1024;
const _cacheTtl = Duration(hours: 1);

final _localPartPattern = RegExp(r'^[a-z0-9-_.]+$');

/// Splits a NIP-05 identifier into local-part and domain. A bare domain
/// (no `@`) means the `_@domain` root identifier, per spec.
Nip05Identifier? parseNip05(String identifier) {
  final trimmed = identifier.trim();
  if (trimmed.isEmpty) return null;

  final atIndex = trimmed.indexOf('@');
  final local = (atIndex == -1 ? '_' : trimmed.substring(0, atIndex))
      .toLowerCase();
  final domain = atIndex == -1 ? trimmed : trimmed.substring(atIndex + 1);
  if (domain.isEmpty || !_localPartPattern.hasMatch(local)) return null;

  return (local: local, domain: domain);
}

// nip05 comes from another user's profile metadata, so the domain is
// attacker-controlled. Block loopback/private/link-local targets so it
// can't be used to probe the device's own network (e.g. cloud metadata
// endpoints like 169.254.169.254).
bool _isBlockedAddress(InternetAddress address) {
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

Future<ConnectionTask<Socket>> _guardedConnect(
  Uri url,
  String? proxyHost,
  int? proxyPort,
) async {
  final addresses = await InternetAddress.lookup(url.host);
  InternetAddress? address;
  for (final candidate in addresses) {
    if (!_isBlockedAddress(candidate)) {
      address = candidate;
      break;
    }
  }
  if (address == null) {
    throw SocketException('No public address found for ${url.host}');
  }

  final rawTask = await Socket.startConnect(address, url.port);
  if (url.scheme != 'https') return rawTask;

  // connectionFactory doesn't wrap https in TLS itself; do it here, pinned
  // to the vetted address but validated against the hostname, not the IP.
  final rawSocket = await rawTask.socket;
  final secureSocket = SecureSocket.secure(rawSocket, host: url.host);
  return ConnectionTask.fromSocket(secureSocket, rawTask.cancel);
}

Future<List<int>?> _readBounded(HttpClientResponse response) async {
  final bytes = <int>[];
  await for (final chunk in response) {
    bytes.addAll(chunk);
    if (bytes.length > _maxResponseBytes) return null;
  }
  return bytes;
}

Future<Nip05Status> _fetchAndVerify(
  Nip05Identifier parsed,
  String pubkeyHex,
) async {
  final Uri uri;
  try {
    uri = Uri.https(parsed.domain, '/.well-known/nostr.json', {
      'name': parsed.local,
    });
  } on FormatException {
    return Nip05Status.unreachable;
  }

  final client = HttpClient()..connectionFactory = _guardedConnect;
  try {
    final request = await client.getUrl(uri);
    // Per NIP-05, clients must not follow a redirect here.
    request.followRedirects = false;
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) return Nip05Status.unreachable;

    final bytes = await _readBounded(response);
    if (bytes == null) return Nip05Status.unreachable;

    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map || decoded['names'] is! Map) {
      return Nip05Status.unreachable;
    }

    final found = (decoded['names'] as Map)[parsed.local];
    if (found is! String) return Nip05Status.mismatch;

    return found.toLowerCase() == pubkeyHex.toLowerCase()
        ? Nip05Status.verified
        : Nip05Status.mismatch;
  } catch (_) {
    return Nip05Status.unreachable;
  } finally {
    client.close(force: true);
  }
}

class _CacheEntry {
  const _CacheEntry(this.status, this.checkedAt);

  final Nip05Status status;
  final DateTime checkedAt;
}

final _cache = <String, _CacheEntry>{};

/// Verifies a NIP-05 identifier against [pubkeyHex], per NIP-05. Results
/// are cached per (pubkey, identifier) pair for an hour.
Future<Nip05Status> verifyNip05({
  required String identifier,
  required String pubkeyHex,
}) async {
  final parsed = parseNip05(identifier);
  if (parsed == null) return Nip05Status.unreachable;

  final cacheKey =
      '${pubkeyHex.toLowerCase()}|${parsed.local}@${parsed.domain}';
  final cached = _cache[cacheKey];
  if (cached != null &&
      DateTime.now().difference(cached.checkedAt) < _cacheTtl) {
    return cached.status;
  }

  final status = await _fetchAndVerify(
    parsed,
    pubkeyHex,
  ).timeout(_fetchTimeout, onTimeout: () => Nip05Status.unreachable);
  _cache[cacheKey] = _CacheEntry(status, DateTime.now());
  return status;
}
