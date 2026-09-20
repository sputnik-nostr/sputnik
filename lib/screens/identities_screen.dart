import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/identity.dart';
import '../models/time_format.dart';
import '../nostr/nostr.dart';
import '../services/settings_store.dart';
import '../widgets/placeholder_tab.dart';

/// How long a copied nsec is left on the clipboard before it's cleared.
const nsecClipboardClearDelay = Duration(seconds: 30);

/// Clears the clipboard after [nsecClipboardClearDelay], but only if it
/// still holds the value we copied. If the user copied something else in
/// the meantime, that is left alone.
void _scheduleClipboardClear(String copiedValue) {
  Future.delayed(nsecClipboardClearDelay, () async {
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == copiedValue) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {
      // Best-effort: if the clipboard can't be read or cleared, leave it.
    }
  });
}

Future<void> _addIdentity(String pubkeyHex, String privkeyHex) async {
  // Save the secret first so an identity is never listed without one.
  await SettingsStore.savePrivateKey(pubkeyHex, privkeyHex);
  final identity = Identity(pubkeyHex: pubkeyHex, createdAt: DateTime.now());
  identitiesNotifier.value = [...identitiesNotifier.value, identity];
  activeIdentityPubkeyNotifier.value = identity.pubkeyHex;
}

Future<void> _generateIdentity(BuildContext context) async {
  try {
    final keyPair = generateNostrKeyPair();
    await _addIdentity(keyPair.publicKeyHex, keyPair.privateKeyHex);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate a keypair: $e')),
      );
    }
  }
}

class _ImportIdentityDialog extends StatefulWidget {
  const _ImportIdentityDialog();

  @override
  State<_ImportIdentityDialog> createState() => _ImportIdentityDialogState();
}

class _ImportIdentityDialogState extends State<_ImportIdentityDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import private key'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'nsec',
            hintText: 'nsec1...',
          ),
          validator: (value) {
            final seckeyHex = hexFromNsec((value ?? '').trim());
            if (seckeyHex == null) return 'Enter a valid nsec key';

            final String candidatePubkeyHex;
            try {
              candidatePubkeyHex = xonlyPubkeyHexFromSeckeyHex(seckeyHex);
            } catch (_) {
              return 'Enter a valid nsec key';
            }
            if (identityWithPubkey(
                  identitiesNotifier.value,
                  candidatePubkeyHex,
                ) !=
                null) {
              return 'This identity is already imported';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _controller.text.trim());
            }
          },
          child: const Text('Import'),
        ),
      ],
    );
  }
}

Future<void> _importIdentity(BuildContext context) async {
  final nsec = await showDialog<String>(
    context: context,
    builder: (context) => const _ImportIdentityDialog(),
  );
  if (nsec == null) return;

  final seckeyHex = hexFromNsec(nsec);
  if (seckeyHex == null) return;

  try {
    final pubkeyHex = xonlyPubkeyHexFromSeckeyHex(seckeyHex);
    await _addIdentity(pubkeyHex, seckeyHex);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not import this key: $e')));
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
  await SettingsStore.deletePrivateKey(identity.pubkeyHex);
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

  final privkeyHex = await SettingsStore.loadPrivateKey(identity.pubkeyHex);
  if (!context.mounted) return;
  if (privkeyHex == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Could not find this identity's private key"),
      ),
    );
    return;
  }

  final nsec = nsecFromHex(privkeyHex);
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Private key'),
      content: SelectableText(nsec),
      actions: [
        TextButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              await Clipboard.setData(ClipboardData(text: nsec));
            } catch (_) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Could not copy the private key')),
              );
              return;
            }
            _scheduleClipboardClear(nsec);
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'Copied private key. It will be cleared from the '
                  'clipboard in ${nsecClipboardClearDelay.inSeconds}s.',
                ),
              ),
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
                key: const Key('importIdentityButton'),
                icon: const Icon(Icons.key_outlined),
                tooltip: 'Import private key',
                onPressed: () => _importIdentity(context),
              ),
            ),
          ),
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
