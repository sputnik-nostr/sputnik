import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/services/ssrf_guard.dart';

/// Puts the guard's replaceable parts back after each test, so that a fake
/// can't leak into the next one. Until a test says otherwise, the machine
/// looks like it has no addresses of its own.
void restoreGuardSeams() {
  final realResolver = resolveHost;
  final realOwnAddresses = ownAddresses;
  setUp(() => ownAddresses = OwnAddresses(list: () async => const []));
  tearDown(() {
    resolveHost = realResolver;
    ownAddresses = realOwnAddresses;
  });
}
