import 'package:flutter/material.dart';

import '../main.dart';
import '../models/app_seed_color.dart';
import '../services/cache_store.dart';
import 'relays_screen.dart';

Future<void> _confirmClearCache(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Clear cached data?'),
      content: const Text(
        'This removes cached profile names, pictures, and banners. '
        'They will be re-fetched from relays as needed.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Clear'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  await CacheStore.clearProfiles();
  profileCacheNotifier.value = {};

  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Cleared cached data')));
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeModeNotifier,
        builder: (context, themeMode, _) {
          final isDark = themeMode == ThemeMode.dark;
          return ListView(
            children: [
              SwitchListTile(
                title: const Text('Dark mode'),
                secondary: Icon(
                  isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
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
              ListTile(
                key: const Key('clearCacheCard'),
                leading: const Icon(Icons.delete_outline),
                title: const Text('Clear cached data'),
                subtitle: const Text('Cached profile info'),
                onTap: () => _confirmClearCache(context),
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RelaysScreen()),
                      );
                    },
                  );
                },
              ),
            ],
          );
        },
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
