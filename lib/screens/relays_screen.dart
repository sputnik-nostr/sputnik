import 'package:flutter/material.dart';

import '../main.dart';
import '../models/relay.dart';

class RelaysScreen extends StatelessWidget {
  const RelaysScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Relays')),
      body: ValueListenableBuilder<Set<String>>(
        valueListenable: selectedRelaysNotifier,
        builder: (context, selected, _) {
          return ListView(
            children: [
              for (final relay in dummyRelays)
                CheckboxListTile(
                  title: Text(relay),
                  value: selected.contains(relay),
                  onChanged: (checked) {
                    final updated = Set<String>.from(selected);
                    if (checked ?? false) {
                      updated.add(relay);
                    } else {
                      updated.remove(relay);
                    }
                    selectedRelaysNotifier.value = updated;
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
