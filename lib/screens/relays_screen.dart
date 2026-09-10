import 'package:flutter/material.dart';

import '../main.dart';
import '../models/relay.dart';

void _setSelected(String relay, bool selected) {
  final updated = Set<String>.from(selectedRelaysNotifier.value);
  if (selected) {
    updated.add(relay);
  } else {
    updated.remove(relay);
  }
  selectedRelaysNotifier.value = updated;
}

void _removeCustomRelay(String relay) {
  final updatedCustom = Set<String>.from(customRelaysNotifier.value)
    ..remove(relay);
  customRelaysNotifier.value = updatedCustom;

  if (selectedRelaysNotifier.value.contains(relay)) {
    _setSelected(relay, false);
  }
}

bool _isRelayUrl(String input) {
  final uri = Uri.tryParse(input);
  return uri != null && (uri.scheme == 'ws' || uri.scheme == 'wss');
}

Future<void> _addRelay(BuildContext context) async {
  final controller = TextEditingController();
  String? error;

  final url = await showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add relay'),
            content: TextField(
              key: const Key('addRelayField'),
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'wss://relay.example.com',
                errorText: error,
              ),
              onSubmitted: (_) => Navigator.pop(context, controller.text),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                key: const Key('confirmAddRelayButton'),
                onPressed: () {
                  final input = controller.text.trim();
                  if (!_isRelayUrl(input)) {
                    setState(() => error = 'Enter a valid ws:// or wss:// URL');
                    return;
                  }
                  Navigator.pop(context, input);
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      );
    },
  );
  if (url == null) return;

  final trimmed = url.trim();
  if (defaultRelays.contains(trimmed) ||
      customRelaysNotifier.value.contains(trimmed)) {
    return;
  }

  customRelaysNotifier.value = {...customRelaysNotifier.value, trimmed};
  _setSelected(trimmed, true);
}

class RelaysScreen extends StatelessWidget {
  const RelaysScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relays'),
        actions: [
          SizedBox(
            width: kToolbarHeight,
            child: Center(
              child: IconButton(
                key: const Key('addRelayButton'),
                icon: const Icon(Icons.add),
                tooltip: 'Add relay',
                onPressed: () => _addRelay(context),
              ),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          selectedRelaysNotifier,
          customRelaysNotifier,
        ]),
        builder: (context, _) {
          final selected = selectedRelaysNotifier.value;
          final customRelays = customRelaysNotifier.value.toList()..sort();

          return ListView(
            children: [
              for (final relay in defaultRelays)
                CheckboxListTile(
                  title: Text(relay),
                  value: selected.contains(relay),
                  onChanged: (checked) => _setSelected(relay, checked ?? false),
                ),
              if (customRelays.isNotEmpty) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Custom relays',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                for (final relay in customRelays)
                  CheckboxListTile(
                    title: Text(relay),
                    value: selected.contains(relay),
                    onChanged: (checked) =>
                        _setSelected(relay, checked ?? false),
                    secondary: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove relay',
                      onPressed: () => _removeCustomRelay(relay),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
