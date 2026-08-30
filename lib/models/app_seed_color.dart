import 'package:flutter/material.dart';

// Material seed color for the app's theme.
enum AppSeedColor {
  blue(Colors.blue, 'Blue'),
  red(Colors.red, 'Red'),
  orange(Colors.orange, 'Orange'),
  purple(Colors.purple, 'Purple'),
  green(Colors.green, 'Green');

  const AppSeedColor(this.color, this.label);

  final Color color;
  final String label;
}
