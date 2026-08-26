import 'package:flutter/material.dart';

import 'models/app_seed_color.dart';
import 'models/note.dart';
import 'models/note_mapper.dart';
import 'nostr/nostr.dart';
import 'screens/root_screen.dart';
import 'services/settings_store.dart';

final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.light,
);

final ValueNotifier<AppSeedColor> seedColorNotifier = ValueNotifier(
  AppSeedColor.blue,
);

final ValueNotifier<List<Note>> notesNotifier = ValueNotifier(const []);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  themeModeNotifier.value = await SettingsStore.loadThemeMode();
  themeModeNotifier.addListener(() {
    SettingsStore.saveThemeMode(themeModeNotifier.value);
  });

  seedColorNotifier.value = await SettingsStore.loadSeedColor();
  seedColorNotifier.addListener(() {
    SettingsStore.saveSeedColor(seedColorNotifier.value);
  });

  const PostRepository postRepository = JsonPostRepository();
  final posts = await postRepository.fetchPosts();
  notesNotifier.value = posts.map(noteFromNostrPost).toList();

  runApp(const MainApp());
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
            );
          },
        );
      },
    );
  }
}
