import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'models/relay.dart';
import 'nostr/relay_connection_pool.dart';
import 'screens/root_screen.dart';
import 'services/bookmark_store.dart';
import 'services/cache_store.dart';
import 'services/feed_loader.dart';
import 'services/settings_store.dart';
import 'services/ssrf_guard.dart';
import 'services/video_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Blocks SSRF via attacker-controlled URLs (e.g. profile pictures).
  HttpOverrides.global = SsrfGuardedHttpOverrides();

  VideoStore.instance.sweepStale().ignore();
  SettingsStore.removeObsoleteKeys().ignore();

  await Future.wait([
    CacheStore.init(),
    bindPersisted(
      themeModeNotifier,
      SettingsStore.loadThemeMode,
      SettingsStore.saveThemeMode,
    ),
    bindPersisted(
      seedColorNotifier,
      SettingsStore.loadSeedColor,
      SettingsStore.saveSeedColor,
    ),
    bindPersisted(
      bookmarkedNotesNotifier,
      BookmarkStore.load,
      BookmarkStore.save,
    ),
    bindPersisted(
      customRelaysNotifier,
      SettingsStore.loadCustomRelays,
      SettingsStore.saveCustomRelays,
    ),
    bindPersisted(
      identitiesNotifier,
      SettingsStore.loadIdentities,
      SettingsStore.saveIdentities,
    ),
    bindPersisted(
      activeIdentityPubkeyNotifier,
      SettingsStore.loadActiveIdentityPubkey,
      SettingsStore.saveActiveIdentityPubkey,
    ),
    bindPersisted(
      loadProfileImagesNotifier,
      SettingsStore.loadLoadProfileImages,
      SettingsStore.saveLoadProfileImages,
    ),
    bindPersisted(
      loadNoteImagesNotifier,
      SettingsStore.loadLoadNoteImages,
      SettingsStore.saveLoadNoteImages,
    ),
    bindPersisted(
      autoVerifyNip05Notifier,
      SettingsStore.loadAutoVerifyNip05,
      SettingsStore.saveAutoVerifyNip05,
    ),
    bindPersisted(
      hiddenPaymentTargetTypesNotifier,
      SettingsStore.loadHiddenPaymentTargetTypes,
      SettingsStore.saveHiddenPaymentTargetTypes,
    ),
    bindPersisted(
      confirmBeforeReactingNotifier,
      SettingsStore.loadConfirmBeforeReacting,
      SettingsStore.saveConfirmBeforeReacting,
    ),
  ]);

  // Valid selections depend on the custom relays loaded above.
  await bindPersisted(
    selectedRelaysNotifier,
    () => SettingsStore.loadSelectedRelays({
      ...defaultRelays,
      ...customRelaysNotifier.value,
    }),
    SettingsStore.saveSelectedRelays,
  );

  selectedRelaysNotifier.addListener(() {
    RelayConnectionPool.instance
        .retainOnly(selectedRelaysNotifier.value)
        .ignore();
  });

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
            brightness: Brightness.light,
            colorSchemeSeed: seedColor,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            colorSchemeSeed: seedColor,
          ),
          home: const RootScreen(),
          builder: (context, child) => CallbackShortcuts(
            bindings: {
              // Desktop has no system back button.
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
