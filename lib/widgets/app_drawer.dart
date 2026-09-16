import 'package:flutter/material.dart';

import '../main.dart';
import '../nostr/nip19.dart';
import '../screens/profile_screen.dart';
import '../screens/settings_screen.dart';
import '../theme/app_text_styles.dart';

// A short label for whichever identity is active - a resolved profile name,
// a short pubkey if none is cached yet, or a prompt when there's no
// identity at all.
String _activeIdentityLabel() {
  final pubkeyHex = activeIdentityPubkeyNotifier.value;
  if (pubkeyHex == null) return 'No identity yet';
  final resolvedName = profileCacheNotifier.value[pubkeyHex]?.resolvedName
      ?.trim();
  if (resolvedName != null && resolvedName.isNotEmpty) return resolvedName;
  return shortPubkey(pubkeyHex);
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            InkWell(
              key: const Key('profileCard'),
              onTap: () {
                FocusScope.of(context).unfocus();
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    activeIdentityPubkeyNotifier,
                    profileCacheNotifier,
                  ]),
                  builder: (context, _) {
                    final label = _activeIdentityLabel();
                    return Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Text(
                            label[0].toUpperCase(),
                            style: theme.avatarFallback,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(label, style: theme.avatarName),
                      ],
                    );
                  },
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              key: const Key('settingsCard'),
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
