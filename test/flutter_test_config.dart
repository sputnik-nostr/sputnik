import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/relay_client.dart';
import 'package:sputnik/nostr/relay_connection_pool.dart';

import 'support/loopback_connection.dart';

/// Puts back the real relay client and an empty relay pool after each test, so
/// a fake or a relay that failed never leaks, and lets tests reach the relays
/// they serve on loopback.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  productionRelayConnectionFactory = relayConnectionFactory;
  relayConnectionFactory = loopbackConnectionFactory;
  tearDown(() async {
    RelayClient.instance = const RelayClient();
    await RelayConnectionPool.instance.reset();
  });
  await testMain();
}
