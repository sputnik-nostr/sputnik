import 'package:flutter/foundation.dart';

/// Whether input is likely a mouse, which cannot swipe.
bool get isDesktop => switch (defaultTargetPlatform) {
  TargetPlatform.linux ||
  TargetPlatform.macOS ||
  TargetPlatform.windows => true,
  _ => false,
};
