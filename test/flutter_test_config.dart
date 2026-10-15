import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/relay_client.dart';

/// Puts back the real relay client after each test, so a fake never leaks.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  tearDown(() => RelayClient.instance = const RelayClient());
  await testMain();
}
