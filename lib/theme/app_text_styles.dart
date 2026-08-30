import 'package:flutter/material.dart';

extension AppTextStyles on ThemeData {
  TextStyle? get avatarName =>
      textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold);

  TextStyle? get metadata =>
      textTheme.bodySmall?.copyWith(color: colorScheme.outline);

  TextStyle get avatarFallback => TextStyle(
    color: colorScheme.onPrimaryContainer,
    fontWeight: FontWeight.bold,
  );
}
