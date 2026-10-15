import 'package:flutter/foundation.dart';

/// Reports a non-fatal [error] to Flutter's error handler.
void reportError(String description, Object error, StackTrace stack) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'sputnik',
      context: ErrorDescription(description),
    ),
  );
}
