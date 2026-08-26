import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/app_seed_color.dart';
import 'models/note.dart';
import 'models/note_mapper.dart';
import 'nostr/nostr.dart';
import 'screens/root_screen.dart';
import 'services/cache_store.dart';
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
  await CacheStore.init();

  themeModeNotifier.value = await SettingsStore.loadThemeMode();
  themeModeNotifier.addListener(() {
    SettingsStore.saveThemeMode(themeModeNotifier.value);
  });

  seedColorNotifier.value = await SettingsStore.loadSeedColor();
  seedColorNotifier.addListener(() {
    SettingsStore.saveSeedColor(seedColorNotifier.value);
  });

  bookmarkedNotesNotifier.value = await SettingsStore.loadBookmarkedNotes();
  bookmarkedNotesNotifier.addListener(() {
    SettingsStore.saveBookmarkedNotes(bookmarkedNotesNotifier.value);
  });

  selectedRelaysNotifier.value = await SettingsStore.loadSelectedRelays();
  selectedRelaysNotifier.addListener(() {
    SettingsStore.saveSelectedRelays(selectedRelaysNotifier.value);
  });

  profileCacheNotifier.value = CacheStore.loadAllProfiles();

  runApp(const MainApp());

  _loadFeed();
}

Future<void> _loadFeed() async {
  final relayUrls = selectedRelaysNotifier.value;
  final PostRepository postRepository = RelayPostRepository(
    relayUrls: relayUrls,
  );
  final posts = await postRepository.fetchPosts();

  final authorPubkeys = posts.map((post) => post.author.pubkey).toSet();
  final profilesFuture = const RelayProfileRepository().fetchProfiles(
    authorPubkeys,
    relayUrls,
  );
  final reactionsFuture = const RelayReactionsRepository().fetchReactions(
    posts.map((post) => post.id).toList(),
    relayUrls,
  );
  final profilesByPubkey = await profilesFuture;
  final reactionsByPostId = await reactionsFuture;

  final notes = posts
      .map(
        (post) => noteFromNostrPost(
          post,
          authorMetadata: profilesByPubkey[post.author.pubkey],
        ),
      )
      .toList();

  notesNotifier.value = applyReactionCounts(notes, reactionsByPostId);
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<AppSeedColor>(
          valueListenable: seedColorNotifier,
          builder: (context, seedColor, _) {
            return MaterialApp(
              title: 'Sputnik',
              debugShowCheckedModeBanner: false,
              navigatorKey: navigatorKey,
              themeMode: themeMode,
              theme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.light,
                colorSchemeSeed: seedColor.color,
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                colorSchemeSeed: seedColor.color,
              ),
              home: const RootScreen(),
              builder: (context, child) => CallbackShortcuts(
                bindings: {
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
      },
    );
  }
}
