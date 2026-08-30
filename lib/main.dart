import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/app_seed_color.dart';
import 'models/note.dart';
import 'nostr/nostr.dart';
import 'screens/root_screen.dart';
import 'services/cache_store.dart';
import 'services/feed_loader.dart';
import 'services/settings_store.dart';

final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.light,
);

final ValueNotifier<AppSeedColor> seedColorNotifier = ValueNotifier(
  AppSeedColor.blue,
);

final ValueNotifier<List<Note>?> notesNotifier = ValueNotifier(null);

final ValueNotifier<Map<String, Note>> bookmarkedNotesNotifier = ValueNotifier(
  const {},
);

final ValueNotifier<Set<String>> selectedRelaysNotifier = ValueNotifier(
  const {},
);

final ValueNotifier<Map<String, NostrMetadata>> profileCacheNotifier =
    ValueNotifier(const {});

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize cache store, load persistent settings
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
    SettingsStore.loadBookmarkedNotes,
    SettingsStore.saveBookmarkedNotes,
  );
  final selectedRelaysBound = bindPersisted(
    selectedRelaysNotifier,
    SettingsStore.loadSelectedRelays,
    SettingsStore.saveSelectedRelays,
  );

  await cacheInit;
  await themeModeBound;
  await seedColorBound;
  await bookmarkedNotesBound;
  await selectedRelaysBound;

  // Load profile data from cache store
  profileCacheNotifier.value = CacheStore.loadAllProfiles();

  runApp(const MainApp());

  loadFeed();
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
