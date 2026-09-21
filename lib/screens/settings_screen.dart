import 'package:flutter/material.dart';

import '../main.dart';
import '../models/app_seed_color.dart';
import '../models/identity.dart';
import '../models/relay.dart';
import '../services/cache_store.dart';
import 'identities_screen.dart';
import 'payment_target_types_screen.dart';
import 'relays_screen.dart';

Future<void> _confirmClearCache(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Clear cached data?'),
      content: const Text(
        'This removes cached profiles, follow lists, and payment targets. '
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

  await CacheStore.clearAll();
  profileCacheNotifier.value = {};

  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Cleared cached data')));
  }
}

Future<void> _confirmResetPreferences(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reset preferences?'),
      content: const Text(
        'This resets the theme, theme color, relay selection, media '
        'loading, and payment target visibility back to their defaults. '
        'Identities and bookmarks are not affected.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Reset'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  themeModeNotifier.value = ThemeMode.system;
  seedColorNotifier.value = AppSeedColor.blue;
  selectedRelaysNotifier.value = defaultRelays.toSet();
  loadMediaNotifier.value = false;
  loadNoteImagesNotifier.value = false;
  hiddenPaymentTargetTypesNotifier.value = const {};

  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Preferences reset')));
  }
}

InputDecorationTheme _dropdownDecoration(BuildContext context) {
  return InputDecorationTheme(
    filled: true,
    fillColor: WidgetStateColor.resolveWith((states) {
      final colorScheme = Theme.of(context).colorScheme;
      final base = colorScheme.surfaceContainerHighest;
      if (states.contains(WidgetState.hovered)) {
        return Color.alphaBlend(
          colorScheme.onSurface.withValues(alpha: 0.08),
          base,
        );
      }
      return base;
    }),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
  );
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
          return ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: const Text('Theme'),
                trailing: DropdownMenu<ThemeMode>(
                  initialSelection: themeMode,
                  requestFocusOnTap: false,
                  width: 160,
                  textStyle: Theme.of(context).textTheme.bodyMedium,
                  inputDecorationTheme: _dropdownDecoration(context),
                  onSelected: (mode) {
                    if (mode != null) themeModeNotifier.value = mode;
                  },
                  dropdownMenuEntries: const [
                    DropdownMenuEntry(value: ThemeMode.system, label: 'System'),
                    DropdownMenuEntry(value: ThemeMode.light, label: 'Light'),
                    DropdownMenuEntry(value: ThemeMode.dark, label: 'Dark'),
                  ],
                ),
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
              ValueListenableBuilder<List<Identity>>(
                valueListenable: identitiesNotifier,
                builder: (context, identities, _) {
                  return ListTile(
                    key: const Key('identitiesCard'),
                    leading: const Icon(Icons.key_outlined),
                    title: const Text('Identities'),
                    subtitle: Text('${identities.length} saved'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const IdentitiesScreen(),
                        ),
                      );
                    },
                  );
                },
              ),
              const Divider(height: 1),
              ValueListenableBuilder<bool>(
                valueListenable: loadMediaNotifier,
                builder: (context, loadMedia, _) {
                  return SwitchListTile(
                    key: const Key('loadMediaSwitch'),
                    secondary: const Icon(Icons.image_outlined),
                    title: const Text('Load profile images automatically'),
                    subtitle: const Text(
                      "Can reveal your IP to a profile's image host.",
                    ),
                    value: loadMedia,
                    onChanged: (value) => loadMediaNotifier.value = value,
                  );
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: loadNoteImagesNotifier,
                builder: (context, loadNoteImages, _) {
                  return SwitchListTile(
                    key: const Key('loadNoteImagesSwitch'),
                    secondary: const Icon(Icons.photo_library_outlined),
                    title: const Text('Load images in notes automatically'),
                    subtitle: const Text(
                      'Can reveal your IP to an image host. '
                      'Videos always wait for a tap.',
                    ),
                    value: loadNoteImages,
                    onChanged: (value) => loadNoteImagesNotifier.value = value,
                  );
                },
              ),
              ValueListenableBuilder<Set<String>>(
                valueListenable: hiddenPaymentTargetTypesNotifier,
                builder: (context, hidden, _) {
                  return ListTile(
                    key: const Key('paymentTargetTypesCard'),
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: const Text('Payment targets'),
                    subtitle: Text(
                      hidden.isEmpty
                          ? 'All types shown'
                          : '${hidden.length} type'
                                '${hidden.length == 1 ? '' : 's'} hidden',
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PaymentTargetTypesScreen(),
                        ),
                      );
                    },
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('clearCacheCard'),
                leading: const Icon(Icons.delete_outline),
                title: const Text('Clear cached data'),
                subtitle: const Text(
                  'Profiles, follow lists, and payment targets',
                ),
                onTap: () => _confirmClearCache(context),
              ),
              ListTile(
                key: const Key('resetPreferencesCard'),
                leading: const Icon(Icons.restore_outlined),
                title: const Text('Reset preferences'),
                subtitle: const Text('Theme, color, and relays'),
                onTap: () => _confirmResetPreferences(context),
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
