import 'package:flutter/material.dart';

import 'models/app_seed_color.dart';
import 'models/identity.dart';
import 'models/note.dart';
import 'nostr/nostr.dart';

final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.system,
);

final ValueNotifier<AppSeedColor> seedColorNotifier = ValueNotifier(
  AppSeedColor.blue,
);

/// The global feed, from every selected relay.
final ValueNotifier<List<Note>?> notesNotifier = ValueNotifier(null);

/// Posts from the active identity and the people it follows.
final ValueNotifier<List<Note>?> followingNotesNotifier = ValueNotifier(null);

final ValueNotifier<Map<String, Note>> bookmarkedNotesNotifier = ValueNotifier(
  const {},
);

final ValueNotifier<Set<String>> selectedRelaysNotifier = ValueNotifier(
  const {},
);

final ValueNotifier<Set<String>> customRelaysNotifier = ValueNotifier(const {});

final ValueNotifier<Map<String, NostrMetadata>> profileCacheNotifier =
    ValueNotifier(const {});

final ValueNotifier<List<Identity>> identitiesNotifier = ValueNotifier(
  const [],
);

final ValueNotifier<String?> activeIdentityPubkeyNotifier = ValueNotifier(null);

final ValueNotifier<bool> loadMediaNotifier = ValueNotifier(false);

final ValueNotifier<bool> loadNoteImagesNotifier = ValueNotifier(false);

/// Off by default: a NIP-05 check contacts a domain the profile's author
/// chose.
final ValueNotifier<bool> autoVerifyNip05Notifier = ValueNotifier(false);

/// Whether liking or following asks for confirmation first; posting and
/// reposting always do.
final ValueNotifier<bool> confirmBeforeReactingNotifier = ValueNotifier(false);

/// Payment target types (e.g. "monero") to hide on every profile.
final ValueNotifier<Set<String>> hiddenPaymentTargetTypesNotifier =
    ValueNotifier(const {});

/// The active identity's own following list, shared across every screen.
final ValueNotifier<Set<String>?> myFollowingNotifier = ValueNotifier(null);

final navigatorKey = GlobalKey<NavigatorState>();
