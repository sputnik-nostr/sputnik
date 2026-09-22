import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/app_seed_color.dart';
import 'models/identity.dart';
import 'models/note.dart';
import 'models/relay.dart';
import 'nostr/nostr.dart';
import 'screens/root_screen.dart';
import 'services/bookmark_store.dart';
import 'services/cache_store.dart';
import 'services/feed_loader.dart';
import 'services/settings_store.dart';
import 'services/ssrf_guard.dart';
import 'services/video_store.dart';

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

/// Whether liking or following asks for confirmation first; posting and
/// reposting always do.
final ValueNotifier<bool> confirmBeforeReactingNotifier = ValueNotifier(false);

/// Payment target types (e.g. "monero") to hide on every profile.
final ValueNotifier<Set<String>> hiddenPaymentTargetTypesNotifier =
    ValueNotifier(const {});

/// The active identity's own following list, shared across every screen.
final ValueNotifier<Set<String>?> myFollowingNotifier = ValueNotifier(null);

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Blocks SSRF via attacker-controlled URLs (e.g. profile pictures).
  HttpOverrides.global = SsrfGuardedHttpOverrides();

  VideoStore.instance.sweepStale().ignore();
  SettingsStore.removeObsoleteKeys().ignore();

  final cacheInit = CacheStore.init();
  final themeModeBound = bindPersisted(
    themeModeNotifier,
    SettingsStore.loadThemeMode,
    SettingsStore.saveThemeMode,
  );
  final seedColorBound = bindPersisted(
    seedColorNotifier,
    SettingsStore.loadSeedColor,
    SettingsStore.saveSeedColor,
  );
  final bookmarkedNotesBound = bindPersisted(
    bookmarkedNotesNotifier,
    BookmarkStore.load,
    BookmarkStore.save,
  );
  final customRelaysBound = bindPersisted(
    customRelaysNotifier,
    SettingsStore.loadCustomRelays,
    SettingsStore.saveCustomRelays,
  );
  final identitiesBound = bindPersisted(
    identitiesNotifier,
    SettingsStore.loadIdentities,
    SettingsStore.saveIdentities,
  );
  final activeIdentityPubkeyBound = bindPersisted(
    activeIdentityPubkeyNotifier,
    SettingsStore.loadActiveIdentityPubkey,
    SettingsStore.saveActiveIdentityPubkey,
  );
  final loadMediaBound = bindPersisted(
    loadMediaNotifier,
    SettingsStore.loadLoadMedia,
    SettingsStore.saveLoadMedia,
  );
  final loadNoteImagesBound = bindPersisted(
    loadNoteImagesNotifier,
    SettingsStore.loadLoadNoteImages,
    SettingsStore.saveLoadNoteImages,
  );
  final hiddenPaymentTargetTypesBound = bindPersisted(
    hiddenPaymentTargetTypesNotifier,
    SettingsStore.loadHiddenPaymentTargetTypes,
    SettingsStore.saveHiddenPaymentTargetTypes,
  );
  final confirmBeforeReactingBound = bindPersisted(
    confirmBeforeReactingNotifier,
    SettingsStore.loadConfirmBeforeReacting,
    SettingsStore.saveConfirmBeforeReacting,
  );

  await cacheInit;
  await themeModeBound;
  await seedColorBound;
  await bookmarkedNotesBound;
  await customRelaysBound;
  await identitiesBound;
  await activeIdentityPubkeyBound;
  await loadMediaBound;
  await loadNoteImagesBound;
  await hiddenPaymentTargetTypesBound;
  await confirmBeforeReactingBound;

  await bindPersisted(
    selectedRelaysNotifier,
    () => SettingsStore.loadSelectedRelays({
      ...defaultRelays,
      ...customRelaysNotifier.value,
    }),
    SettingsStore.saveSelectedRelays,
  );

  profileCacheNotifier.value = CacheStore.loadAllProfiles();

  runApp(const MainApp());

  runFeedLoad(loadFollowingFeed, 'loading the following feed');
  activeIdentityPubkeyNotifier.addListener(() {
    followingNotesNotifier.value = null;
    runFeedLoad(loadFollowingFeed, 'loading the following feed');
  });
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([themeModeNotifier, seedColorNotifier]),
      builder: (context, child) {
        final seedColor = seedColorNotifier.value.color;
        return MaterialApp(
          title: 'Sputnik',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          themeMode: themeModeNotifier.value,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorSchemeSeed: seedColor,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: seedColor,
          ),
          home: const RootScreen(),
          builder: (context, child) => CallbackShortcuts(
            bindings: {
              // Go back when the escape key is pressed (mostly for desktop)
              const SingleActivator(LogicalKeyboardKey.escape): () {
                final navigator = navigatorKey.currentState;
                if (navigator != null && navigator.canPop()) {
                  navigator.pop();
                }
              },
            },
            child: Focus(autofocus: true, child: child!),
          ),
        );
      },
    );
  }
}
