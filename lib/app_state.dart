import 'package:flutter/material.dart';

import 'models/app_seed_color.dart';
import 'models/identity.dart';
import 'models/note.dart';
import 'models/relay.dart';
import 'nostr/nostr.dart';

/// A user setting that knows its default, so a reset needs no second copy.
class Preference<T> extends ValueNotifier<T> {
  Preference(this.defaultValue) : super(defaultValue);

  final T defaultValue;

  void reset() => value = defaultValue;
}

final themeModeNotifier = Preference(ThemeMode.system);

final seedColorNotifier = Preference(AppSeedColor.blue);

/// The global feed, from every selected relay.
final ValueNotifier<List<Note>?> notesNotifier = ValueNotifier(null);

/// Posts from the active identity and the people it follows.
final ValueNotifier<List<Note>?> followingNotesNotifier = ValueNotifier(null);

final ValueNotifier<Map<String, Note>> bookmarkedNotesNotifier = ValueNotifier(
  const {},
);

final selectedRelaysNotifier = Preference<Set<String>>(defaultRelays.toSet());

final ValueNotifier<Set<String>> customRelaysNotifier = ValueNotifier(const {});

final ValueNotifier<Map<String, NostrMetadata>> profileCacheNotifier =
    ValueNotifier(const {});

final ValueNotifier<List<Identity>> identitiesNotifier = ValueNotifier(
  const [],
);

final ValueNotifier<String?> activeIdentityPubkeyNotifier = ValueNotifier(null);

final loadProfileImagesNotifier = Preference(false);

final loadNoteImagesNotifier = Preference(false);

/// Off by default: a NIP-05 check contacts a domain the profile's author
/// chose.
final autoVerifyNip05Notifier = Preference(false);

/// Whether liking or following asks for confirmation first; posting and
/// reposting always do.
final confirmBeforeReactingNotifier = Preference(false);

/// Payment target types (e.g. "monero") to hide on every profile.
final hiddenPaymentTargetTypesNotifier = Preference<Set<String>>(const {});

/// The active identity's own following list, shared across every screen.
final ValueNotifier<Set<String>?> myFollowingNotifier = ValueNotifier(null);

/// What "Reset preferences" restores; identities and bookmarks are not here.
final List<Preference<Object?>> preferences = [
  themeModeNotifier,
  seedColorNotifier,
  selectedRelaysNotifier,
  loadProfileImagesNotifier,
  loadNoteImagesNotifier,
  autoVerifyNip05Notifier,
  confirmBeforeReactingNotifier,
  hiddenPaymentTargetTypesNotifier,
];

final navigatorKey = GlobalKey<NavigatorState>();
