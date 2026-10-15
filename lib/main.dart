import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'models/relay.dart';
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
