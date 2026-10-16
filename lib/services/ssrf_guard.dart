import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Whether the first [bits] bits of [bytes] match [prefix].
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

/// Suffixes that name hosts on the local network rather than the internet.
const _localHostSuffixes = ['.local', '.localhost', '.internal', '.home.arpa'];

/// IP literals and local names only; other private hosts fail at connect.
bool isLocalNetworkUrl(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase();
  if (host == null || host.isEmpty) return false;
  final address = InternetAddress.tryParse(host);
  if (address != null) return isBlockedAddress(address);
  return host == 'localhost' || _localHostSuffixes.any(host.endsWith);
}

int effectivePort(Uri url) =>
    url.port != 0 ? url.port : (url.scheme == 'https' ? 443 : 80);

/// Head start each address gets before the next one is tried too (RFC 8305).
const _connectAttemptDelay = Duration(milliseconds: 250);

/// Alternates IPv6 and IPv4, so one broken family can't stall every attempt.
List<InternetAddress> _interleaveFamilies(List<InternetAddress> addresses) {
  if (addresses.isEmpty) return addresses;
  final first = addresses.first.type;
  final preferred = [
    for (final a in addresses)
      if (a.type == first) a,
  ];
  final other = [
    for (final a in addresses)
      if (a.type != first) a,
  ];
  return [
    for (var i = 0; i < preferred.length || i < other.length; i++) ...[
      if (i < preferred.length) preferred[i],
      if (i < other.length) other[i],
    ],
  ];
}

/// Races [addresses] in staggered order, as dart:io does for a hostname.
@visibleForTesting
ConnectionTask<Socket> connectToAny(List<InternetAddress> addresses, int port) {
  final result = Completer<Socket>();
  final tasks = <ConnectionTask<Socket>>[];
  var next = 0;
  var failed = 0;
  var cancelled = false;
  Timer? stagger;

  void startNext() {
    stagger?.cancel();
    if (cancelled || result.isCompleted || next >= addresses.length) return;
    final address = addresses[next++];
    stagger = Timer(_connectAttemptDelay, startNext);

    void fail(Object error, StackTrace stack) {
      if (result.isCompleted) return;
      if (++failed == addresses.length) {
        stagger?.cancel();
        result.completeError(error, stack);
      } else {
        startNext();
      }
    }

    Socket.startConnect(address, port).then((task) {
      if (cancelled || result.isCompleted) {
        task.cancel();
        return;
      }
      tasks.add(task);
      task.socket.then((socket) {
        if (result.isCompleted) {
          socket.destroy();
          return;
        }
        stagger?.cancel();
        result.complete(socket);
        for (final other in tasks) {
          if (!identical(other, task)) other.cancel();
        }
      }, onError: fail);
    }, onError: fail);
  }

  if (addresses.isEmpty) {
    result.completeError(const SocketException('No address to connect to'));
  } else {
    startNext();
  }
  return ConnectionTask.fromSocket(result.future, () {
    cancelled = true;
    stagger?.cancel();
    for (final task in tasks) {
      task.cancel();
    }
  });
}

/// Connects only to vetted addresses so DNS can't rebind; ignores proxies.
Future<ConnectionTask<Socket>> guardedConnectionFactory(
  Uri url,
  String? proxyHost,
  int? proxyPort,
) async {
  final addresses = [
    for (final candidate in await InternetAddress.lookup(url.host))
      if (!isBlockedAddress(candidate)) candidate,
  ];
  if (addresses.isEmpty) {
    throw SocketException('No public address found for ${url.host}');
  }

  final rawTask = connectToAny(
    _interleaveFamilies(addresses),
    effectivePort(url),
  );
  if (url.scheme != 'https') return rawTask;

  // connectionFactory doesn't wrap HTTPS in TLS itself.
  final rawSocket = await rawTask.socket;
  final secureSocket = SecureSocket.secure(rawSocket, host: url.host);
  return ConnectionTask.fromSocket(secureSocket, rawTask.cancel);
}

/// An HttpClient that refuses non-public addresses.
HttpClient guardedHttpClient() =>
    HttpClient()..connectionFactory = guardedConnectionFactory;

/// Guards every HttpClient, including NetworkImage, which has no other seam.
class SsrfGuardedHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionFactory = guardedConnectionFactory;
  }
}
