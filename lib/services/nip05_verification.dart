import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../nostr/nip05.dart';
import 'ssrf_guard.dart';

const _fetchTimeout = Duration(seconds: 6);
const _maxResponseBytes = 64 * 1024;
const _cacheTtl = Duration(hours: 1);

Future<List<int>?> _readBounded(HttpClientResponse response) async {
  final bytes = <int>[];
  await for (final chunk in response) {
    bytes.addAll(chunk);
    if (bytes.length > _maxResponseBytes) return null;
  }
  return bytes;
}

Future<Nip05Status> _fetchAndVerify(
  HttpClient client,
  Uri uri,
  Nip05Identifier parsed,
  String pubkeyHex,
) async {
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
  }
}

/// Fetches and checks [parsed], always closing the client, even on timeout.
Future<Nip05Status> _check(Nip05Identifier parsed, String pubkeyHex) async {
  final Uri uri;
  try {
    uri = Uri.https(parsed.domain, '/.well-known/nostr.json', {
      'name': parsed.local,
    });
  } on FormatException {
    return Nip05Status.unreachable;
  }

  final client = guardedHttpClient()..connectionTimeout = _fetchTimeout;
  try {
    return await _fetchAndVerify(
      client,
      uri,
      parsed,
      pubkeyHex,
    ).timeout(_fetchTimeout, onTimeout: () => Nip05Status.unreachable);
  } finally {
    // Aborts a request the timeout gave up on, rather than leaving it open.
    client.close(force: true);
  }
}

class _CacheEntry {
  const _CacheEntry(this.status, this.checkedAt);

  final Nip05Status status;
  final DateTime checkedAt;
}

final _cache = <String, _CacheEntry>{};

void clearNip05Cache() => _cache.clear();

/// Checks that [identifier] maps to [pubkeyHex] via its domain's
/// `.well-known/nostr.json`. Results are cached per (pubkey, identifier) pair
/// for an hour.
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

  final status = await _check(parsed, pubkeyHex);
  _cache[cacheKey] = _CacheEntry(status, DateTime.now());
  return status;
}
