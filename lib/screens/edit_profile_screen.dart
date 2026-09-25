import 'package:flutter/material.dart';

import '../main.dart';
import '../models/identity.dart';
import '../nostr/nip05.dart';
import '../nostr/nostr.dart';
import '../services/cache_store.dart';
import '../services/settings_store.dart';
import 'edit_payment_targets_screen.dart';

bool _isWebUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.hasAuthority &&
      uri.host.isNotEmpty &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}

String? _validateUrl(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty || _isWebUrl(trimmed)) return null;
  return 'Enter a valid http:// or https:// URL';
}

String? _validateNip05(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty || parseNip05(trimmed) != null) return null;
  return 'Enter an address, such as name@example.com';
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, this.relayClient = const RelayClient()});

  final RelayClient relayClient;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _pictureController = TextEditingController();
  final _bannerController = TextEditingController();
  final _nip05Controller = TextEditingController();
  final _websiteController = TextEditingController();

  /// The kind:0 event the edit is applied on top of, as read from the relays.
  NostrEvent? _base;
  bool _loading = true;
  bool _baseConclusive = true;
  bool _saving = false;

  RelayProfileRepository get _profiles =>
      RelayProfileRepository(client: widget.relayClient);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _nameController.dispose();
    _bioController.dispose();
    _pictureController.dispose();
    _bannerController.dispose();
    _nip05Controller.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  /// A retry keeps what has been typed and only refreshes the base event.
  Future<void> _load({bool seedFields = true}) async {
    final pubkeyHex = activeIdentityPubkeyNotifier.value;
    if (pubkeyHex == null) {
      setState(() => _loading = false);
      return;
    }
    if (seedFields) setState(() => _loading = true);

    final own = await _profiles.fetchOwnProfileEvent(
      pubkeyHex,
      selectedRelaysNotifier.value,
    );
    if (!mounted) return;

    NostrMetadata? metadata;
    final event = own.event;
    if (event != null) {
      try {
        metadata = NostrMetadata.fromContent(event.content);
      } catch (_) {
        // Unreadable content; the form starts from the cached profile.
      }
    }
    metadata ??= profileCacheNotifier.value[pubkeyHex];

    setState(() {
      _base = event ?? _base;
      _baseConclusive = own.conclusive;
      _loading = false;
    });
    if (!seedFields) return;

    setState(() {
      _displayNameController.text = metadata?.displayName ?? '';
      _nameController.text = metadata?.name ?? '';
      _bioController.text = metadata?.about ?? '';
      _pictureController.text = metadata?.picture ?? '';
      _bannerController.text = metadata?.banner ?? '';
      _nip05Controller.text = metadata?.nip05 ?? '';
      _websiteController.text = metadata?.website ?? '';
    });
  }

  Future<bool> _confirmSave(int relayCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update profile?'),
        content: Text(
          _baseConclusive
              ? 'This publishes your profile to $relayCount relay(s).'
              : 'This publishes your profile to $relayCount relay(s). Some '
                    'relays did not respond, so your current profile could not '
                    'be checked and fields you set elsewhere may be '
                    'overwritten.',
        ),
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
    if (_loading || _saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final pubkeyHex = activeIdentityPubkeyNotifier.value;
    if (pubkeyHex == null) return;
    final identity = identityWithPubkey(identitiesNotifier.value, pubkeyHex);
    if (identity == null) return;

    final relayUrls = selectedRelaysNotifier.value;
    if (!await _confirmSave(relayUrls.length) || !mounted) return;

    // Only touch secure storage once the user has actually confirmed.
    final privkeyHex = await SettingsStore.loadPrivateKey(identity.pubkeyHex);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (privkeyHex == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Could not find this identity's private key"),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final published = await _profiles.publishProfile(
        seckeyHex: privkeyHex,
        pubkeyHex: identity.pubkeyHex,
        base: _base,
        fields: {
          'display_name': _displayNameController.text,
          'name': _nameController.text,
          'about': _bioController.text,
          'picture': _pictureController.text,
          'banner': _bannerController.text,
          'nip05': _nip05Controller.text,
          'website': _websiteController.text,
        },
        relayUrls: relayUrls,
      );
      if (!mounted) return;

      final results = published.results;
      final accepted = results.values
          .where((result) => result.outcome == RelayPublishOutcome.accepted)
          .length;
      if (accepted == 0) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not publish this profile update to any relay'),
          ),
        );
        return;
      }

      final updated = NostrMetadata.fromContent(published.event.content);
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
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not sign this profile update: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              key: const Key('saveProfileButton'),
              onPressed: _loading || _saving ? null : _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        if (!_baseConclusive)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_outlined,
                                  color: theme.colorScheme.error,
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Some relays did not respond, so your published '
                                    'profile could not be checked.',
                                  ),
                                ),
                                TextButton(
                                  key: const Key('retryLoadProfileButton'),
                                  onPressed: () => _load(seedFields: false),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        TextFormField(
                          key: const Key('editNameField'),
                          controller: _displayNameController,
                          maxLength: 50,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: const Key('editUsernameField'),
                          controller: _nameController,
                          maxLength: 50,
                          decoration: const InputDecoration(labelText: 'Name'),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: const Key('editBioField'),
                          controller: _bioController,
                          maxLength: 500,
                          minLines: 1,
                          maxLines: 6,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(labelText: 'Bio'),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: const Key('editPictureField'),
                          controller: _pictureController,
                          keyboardType: TextInputType.url,
                          validator: _validateUrl,
                          decoration: const InputDecoration(
                            labelText: 'Picture URL',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('editBannerField'),
                          controller: _bannerController,
                          keyboardType: TextInputType.url,
                          validator: _validateUrl,
                          decoration: const InputDecoration(
                            labelText: 'Banner URL',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('editNip05Field'),
                          controller: _nip05Controller,
                          keyboardType: TextInputType.emailAddress,
                          validator: _validateNip05,
                          decoration: const InputDecoration(
                            labelText: 'NIP-05 address',
                            hintText: 'name@example.com',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('editWebsiteField'),
                          controller: _websiteController,
                          keyboardType: TextInputType.url,
                          validator: _validateUrl,
                          decoration: const InputDecoration(
                            labelText: 'Website',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    key: const Key('editPaymentTargetsTile'),
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: const Text('Payment targets'),
                    subtitle: const Text('Addresses others can use to pay you'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditPaymentTargetsScreen(
                          relayClient: widget.relayClient,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
