import 'package:flutter/material.dart';

import '../screens/identities_screen.dart';
import 'placeholder_tab.dart';

/// Says there is no identity yet, with a button to create or import one.
class NoIdentityPrompt extends StatelessWidget {
  const NoIdentityPrompt({
    super.key,
    required this.icon,
    required this.buttonKey,
  });

  final IconData icon;
  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlaceholderTab(icon: icon, label: 'No identity yet'),
          const SizedBox(height: 16),
          FilledButton(
            key: buttonKey,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const IdentitiesScreen()),
            ),
            child: const Text('Create or import an identity'),
          ),
        ],
      ),
    );
  }
}
