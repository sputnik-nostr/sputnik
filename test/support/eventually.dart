import 'package:flutter_test/flutter_test.dart';

/// Polls [condition], for state that something outside the test changes.
Future<void> eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition never held');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
