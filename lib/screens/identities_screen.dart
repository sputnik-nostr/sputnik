import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/identity.dart';
import '../models/time_format.dart';
import '../nostr/nostr.dart';
import '../widgets/placeholder_tab.dart';

Future<void> _generateIdentity(BuildContext context) async {
  try {
    final keyPair = generateNostrKeyPair();
    final identity = Identity(
      pubkeyHex: keyPair.publicKeyHex,
      privkeyHex: keyPair.privateKeyHex,
      createdAt: DateTime.now(),
    );
    identitiesNotifier.value = [...identitiesNotifier.value, identity];
    activeIdentityPubkeyNotifier.value = identity.pubkeyHex;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate a keypair: $e')),
      );
    }
  }
}

Future<void> _confirmDeleteIdentity(
  BuildContext context,
  Identity identity,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete identity?'),
      content: Text(
        'This removes the key pair for '
        '${truncateNpub(npubFromHex(identity.pubkeyHex))} from this device. '
        'Make sure you have a backup of its private key if you want to use '
        'it again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  final remaining = identitiesNotifier.value
      .where((i) => i.pubkeyHex != identity.pubkeyHex)
      .toList();
  identitiesNotifier.value = remaining;
  if (activeIdentityPubkeyNotifier.value == identity.pubkeyHex) {
    activeIdentityPubkeyNotifier.value = remaining.isEmpty
        ? null
        : remaining.first.pubkeyHex;
  }
}

Future<void> _showNsec(BuildContext context, Identity identity) async {
  final reveal = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reveal private key?'),
      content: const Text(
        'Anyone with this key can post as this identity. Only reveal it '
        'somewhere private.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Reveal'),
        ),
      ],
    ),
  );
  if (reveal != true || !context.mounted) return;

  final nsec = nsecFromHex(identity.privkeyHex);
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Private key'),
      content: SelectableText(nsec),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: nsec));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied private key to clipboard')),
            );
          },
          child: const Text('Copy'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class IdentitiesScreen extends StatelessWidget {
  const IdentitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Identities'),
        actions: [
          SizedBox(
            width: kToolbarHeight,
            child: Center(
              child: IconButton(
                key: const Key('generateIdentityButton'),
                icon: const Icon(Icons.add),
                tooltip: 'Generate new keypair',
                onPressed: () => _generateIdentity(context),
              ),
            ),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<Identity>>(
        valueListenable: identitiesNotifier,
        builder: (context, identities, _) {
          if (identities.isEmpty) {
            return const PlaceholderTab(
              icon: Icons.key_outlined,
              label: 'No identities yet',
            );
          }

          return ValueListenableBuilder<String?>(
            valueListenable: activeIdentityPubkeyNotifier,
            builder: (context, activePubkey, _) {
              return ListView(
                children: [
                  for (final identity in identities)
                    _IdentityTile(
                      identity: identity,
                      active: identity.pubkeyHex == activePubkey,
                      onSelect: () => activeIdentityPubkeyNotifier.value =
                          identity.pubkeyHex,
                      onShowNsec: () => _showNsec(context, identity),
                      onDelete: () => _confirmDeleteIdentity(context, identity),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _IdentityTile extends StatelessWidget {
  const _IdentityTile({
    required this.identity,
    required this.active,
    required this.onSelect,
    required this.onShowNsec,
    required this.onDelete,
  });

  final Identity identity;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onShowNsec;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final npub = npubFromHex(identity.pubkeyHex);
    return ListTile(
      leading: Icon(
        active ? Icons.check_circle : Icons.circle_outlined,
        color: active ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(truncateNpub(npub)),
      subtitle: Text('Created ${formatAbsoluteTime(identity.createdAt)}'),
      onTap: onSelect,
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'nsec') onShowNsec();
          if (value == 'delete') onDelete();
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'nsec', child: Text('View private key')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}
