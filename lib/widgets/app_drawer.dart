import 'package:flutter/material.dart';

import '../main.dart';
import '../models/app_seed_color.dart';
import '../models/current_user.dart';
import '../screens/profile_screen.dart';
import '../screens/relays_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeNotifier,
          builder: (context, themeMode, _) {
            final isDark = themeMode == ThemeMode.dark;
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                InkWell(
                  key: const Key('profileCard'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Text(
                            CurrentUser.displayName[0],
                            style: TextStyle(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          CurrentUser.displayName,
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Settings',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Dark mode'),
                  secondary: Icon(
                    isDark
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                  ),
                  value: isDark,
                  onChanged: (value) {
                    themeModeNotifier.value = value
                        ? ThemeMode.dark
                        : ThemeMode.light;
                  },
                ),
                const ListTile(
                  leading: Icon(Icons.palette_outlined),
                  title: Text('Theme color'),
                ),
                ValueListenableBuilder<AppSeedColor>(
                  valueListenable: seedColorNotifier,
                  builder: (context, selected, _) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          for (final option in AppSeedColor.values) ...[
                            _ColorSwatch(
                              option: option,
                              selected: option == selected,
                              onTap: () => seedColorNotifier.value = option,
                            ),
                            const SizedBox(width: 16),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ValueListenableBuilder<Set<String>>(
                  valueListenable: selectedRelaysNotifier,
                  builder: (context, selectedRelays, _) {
                    return ListTile(
                      key: const Key('relaysCard'),
                      leading: const Icon(Icons.dns_outlined),
                      title: const Text('Relays'),
                      subtitle: Text('${selectedRelays.length} selected'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RelaysScreen(),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AppSeedColor option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: option.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: option.color,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(
                    color: Theme.of(context).colorScheme.onSurface,
                    width: 2,
                  )
                : null,
          ),
          child: selected
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}
