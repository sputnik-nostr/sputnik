import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Collects what `reportError` sends to Flutter's handler instead of letting it
/// fail the test; call it in the test or its setUp.
List<FlutterErrorDetails> captureReportedErrors() {
  final reported = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reported.add;
  addTearDown(() => FlutterError.onError = previous);
  return reported;
}
