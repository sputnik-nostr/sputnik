import 'package:flutter/material.dart';

import '../main.dart';
import '../models/current_user.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;

  @override
  void initState() {
    super.initState();
    final profile = currentUserProfileNotifier.value;
    _nameController = TextEditingController(text: profile.displayName);
    _bioController = TextEditingController(text: profile.bio);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    currentUserProfileNotifier.value = currentUserProfileNotifier.value
        .copyWith(
          displayName: name.isEmpty ? CurrentUser.displayName : name,
          bio: _bioController.text.trim(),
        );
    Navigator.pop(context);
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
