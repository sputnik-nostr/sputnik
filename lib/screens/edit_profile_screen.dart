import 'dart:convert';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/identity.dart';
import '../nostr/nostr.dart';
import '../services/cache_store.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, this.relayClient = const RelayClient()});

  final RelayClient relayClient;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;

  @override
  void initState() {
    super.initState();
    final pubkeyHex = activeIdentityPubkeyNotifier.value;
    final metadata = pubkeyHex == null
        ? null
        : profileCacheNotifier.value[pubkeyHex];
    _nameController = TextEditingController(
      text: metadata?.displayName ?? metadata?.name ?? '',
    );
    _bioController = TextEditingController(text: metadata?.about ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<bool> _confirmSave(int relayCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update profile?'),
        content: Text('This publishes your profile to $relayCount relay(s).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmSaveProfileButton'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _save() async {
    final pubkeyHex = activeIdentityPubkeyNotifier.value;
    if (pubkeyHex == null) return;
    final identity = identityWithPubkey(identitiesNotifier.value, pubkeyHex);
    if (identity == null) return;

    final relayUrls = selectedRelaysNotifier.value;
    if (!await _confirmSave(relayUrls.length) || !mounted) return;

    // Apply the edited fields on top of whatever metadata is already known,
    // so fields this form doesn't expose (picture/banner/nip05/website)
    // survive the update rather than being wiped.
    final existing =
        profileCacheNotifier.value[pubkeyHex] ?? const NostrMetadata();
    final updated = existing.copyWith(
      displayName: _nameController.text.trim(),
      about: _bioController.text.trim(),
    );

    final NostrEvent event;
    try {
      event = signEvent(
        seckeyHex: identity.privkeyHex,
        pubkeyHex: identity.pubkeyHex,
        kind: 0,
        content: jsonEncode(updated.toEventContent()),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not sign this profile update: $e')),
        );
      }
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final results = await widget.relayClient.publish(event, relayUrls);
    if (!mounted) return;

    final accepted = results.values
        .where((result) => result.outcome == RelayPublishOutcome.accepted)
        .length;

    if (accepted > 0) {
      profileCacheNotifier.value = {
        ...profileCacheNotifier.value,
        pubkeyHex: updated,
      };
      await CacheStore.putProfiles({pubkeyHex: updated});
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Updated profile on $accepted/${results.length} relays',
          ),
        ),
      );
      if (mounted) Navigator.pop(context);
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not publish this profile update to any relay'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              key: const Key('saveProfileButton'),
              onPressed: _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('editNameField'),
            controller: _nameController,
            maxLength: 50,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('editBioField'),
            controller: _bioController,
            maxLength: 160,
            maxLines: 1,
            decoration: const InputDecoration(labelText: 'Bio'),
          ),
        ],
      ),
    );
  }
}
