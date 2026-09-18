import 'package:flutter/material.dart';

// Shorter than the default 48px, which is a lot for two text-only tabs.
const compactTabHeight = 36.0;

class CompactTabBar extends StatelessWidget {
  const CompactTabBar({
    super.key,
    required this.controller,
    required this.labels,
  });

  final TabController controller;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      tabs: [
        for (final label in labels) Tab(text: label, height: compactTabHeight),
      ],
    );
  }
}
