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

/// Most addresses raced for one connection. A hostile name can return
/// hundreds, and every attempt that gets no answer holds a socket.
const _maxRacedAddresses = 6;

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
///
/// Like any [ConnectionTask], cancelling it closes every attempt and fails
/// its socket with a [SocketException].
@visibleForTesting
ConnectionTask<Socket> connectToAny(List<InternetAddress> addresses, int port) {
  final result = Completer<Socket>();
  final tasks = <ConnectionTask<Socket>>[];
  var next = 0;
  var failed = 0;
  Timer? stagger;

  void startNext() {
    stagger?.cancel();
    if (result.isCompleted || next >= addresses.length) return;
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

    // An error thrown straight away fails this attempt like any other.
    Future<ConnectionTask<Socket>> started;
    try {
      started = Socket.startConnect(address, port);
    } catch (error, stack) {
      started = Future.error(error, stack);
    }
    started.then((task) {
      if (result.isCompleted) {
        // Nobody wants it any more: close whatever it still manages to open.
        task.socket.then((socket) => socket.destroy(), onError: (_) {});
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
    if (result.isCompleted) return;
    stagger?.cancel();
    for (final task in tasks) {
      task.cancel();
    }
    result.completeError(const SocketException('Connection attempt cancelled'));
  });
}

/// The IPv4 address behind an IPv4-mapped IPv6 address (::ffff:a.b.c.d).
List<int>? _mappedV4(List<int> bytes) {
  final mapped =
      bytes.length == 16 &&
      bytes.take(10).every((byte) => byte == 0) &&
      bytes[10] == 0xff &&
      bytes[11] == 0xff;
  return mapped ? bytes.sublist(12) : null;
}

/// Whether [address] is one of [own] or shares a /64 with one of them.
///
/// A public address of this machine passes [isBlockedAddress], and so does a
/// neighbour on its IPv6 LAN, but a request to either reaches a service on or
/// next to the machine. Interfaces don't report their prefix length, so IPv6
/// neighbours are the addresses of the same /64, the size of a LAN subnet;
/// for IPv4 only the address itself counts.
@visibleForTesting
bool isOwnNetworkAddress(
  InternetAddress address,
  Iterable<InternetAddress> own,
) {
  // The OS connects to ::ffff:a.b.c.d over IPv4.
  final bytes = address.rawAddress;
  final comparable = _mappedV4(bytes) ?? bytes;
  final bits = comparable.length == 4 ? 32 : 64;
  for (final mine in own) {
    final theirs = mine.rawAddress;
    if (theirs.length == comparable.length &&
        _inCidr(comparable, theirs, bits)) {
      return true;
    }
  }
  return false;
}

Future<List<InternetAddress>> _listInterfaceAddresses() async => [
  // Loopback too: a public address can be assigned to it.
  for (final interface in await NetworkInterface.list(includeLoopback: true))
    ...interface.addresses,
];

/// The addresses of this host's own network interfaces.
///
/// A burst of connections shares one listing, and a changed network is picked
/// up once [maxAge] has passed. If the interfaces can't be listed there is
/// nothing to compare with, and the blocklist alone applies as it always did.
@visibleForTesting
class OwnAddresses {
  OwnAddresses({
    Future<List<InternetAddress>> Function()? list,
    this.maxAge = const Duration(seconds: 60),
  }) : _list = list ?? _listInterfaceAddresses;

  final Future<List<InternetAddress>> Function() _list;
  final Duration maxAge;
  Future<List<InternetAddress>>? _addresses;
  final _age = Stopwatch();

  Future<List<InternetAddress>> get addresses {
    final current = _addresses;
    if (current != null && _age.elapsed < maxAge) return current;
    _age
      ..reset()
      ..start();
    return _addresses = _load();
  }

  Future<List<InternetAddress>> _load() async {
    try {
      return await _list();
    } catch (_) {
      return const [];
    }
  }
}

/// The interfaces the guard compares addresses with; replaced in tests.
@visibleForTesting
OwnAddresses ownAddresses = OwnAddresses();

/// Looks up the addresses of a host name; replaced in tests.
@visibleForTesting
Future<List<InternetAddress>> Function(String host) resolveHost =
    InternetAddress.lookup;

/// The addresses of [host] that are public and off this host's own network, in
/// the order they are tried.
Future<List<InternetAddress>> _vettedAddresses(String host) async {
  final resolved = await resolveHost(host);
  final own = await ownAddresses.addresses;
  final addresses = [
    for (final candidate in resolved)
      if (!isBlockedAddress(candidate) && !isOwnNetworkAddress(candidate, own))
        candidate,
  ];
  if (addresses.isEmpty) {
    throw SocketException('No public address found for $host');
  }
  return _interleaveFamilies(addresses).take(_maxRacedAddresses).toList();
}

/// Connects only to vetted addresses so DNS can't rebind; ignores proxies.
///
/// The task is handed back at once, with the lookup, the connect and the TLS
/// handshake still ahead of it: dart:io applies connectionTimeout and
/// close(force: true) only to a task it holds. Cancelling fails it at once.
Future<ConnectionTask<Socket>> guardedConnectionFactory(
  Uri url,
  String? proxyHost,
  int? proxyPort,
) {
  final result = Completer<Socket>();
  ConnectionTask<Socket>? racing;

  Future<void> connect() async {
    final addresses = await _vettedAddresses(url.host);
    if (result.isCompleted) return; // cancelled during the lookup
    final task = racing = connectToAny(addresses, effectivePort(url));
    var socket = await task.socket;
    // connectionFactory doesn't wrap HTTPS in TLS itself. A handshake under
    // way can't be aborted, so after a cancel its socket is closed once it ends.
    if (url.scheme == 'https' && !result.isCompleted) {
      socket = await SecureSocket.secure(socket, host: url.host);
    }
    if (result.isCompleted) {
      socket.destroy(); // cancelled while connecting
    } else {
      result.complete(socket);
    }
  }

  connect().catchError((Object error, StackTrace stack) {
    if (!result.isCompleted) result.completeError(error, stack);
  }).ignore();
  return Future.value(
    ConnectionTask.fromSocket(result.future, () {
      if (result.isCompleted) return;
      racing?.cancel();
      result.completeError(
        const SocketException('Connection attempt cancelled'),
      );
    }),
  );
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
