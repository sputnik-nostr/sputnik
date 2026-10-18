import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/services/ssrf_guard.dart';

/// Puts the guard's replaceable parts back after each test, so that a fake
/// can't leak into the next one.
void restoreGuardSeams() {
  final realResolver = resolveHost;
  tearDown(() => resolveHost = realResolver);
}
