import 'package:flutter/material.dart';

import '../widgets/app_drawer.dart';
import 'bookmarks_screen.dart';
import 'home_screen.dart';
import 'notifications_screen.dart';
import 'search_screen.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  int _index = 0;

  static const _tabs = [
    HomeScreen(),
    SearchScreen(),
    NotificationsScreen(),
    BookmarksScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(12),
          child: GestureDetector(
            key: const Key('profileAvatarButton'),
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                'A',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
      drawer: const AppDrawer(),
      body: IndexedStack(index: _index, children: _tabs),
      floatingActionButton: KeyedSubtree(
        key: const ValueKey('composeFab'),
        child: _index == 0
            ? FloatingActionButton.small(
                onPressed: () {},
                tooltip: 'New note',
                elevation: 0,
                highlightElevation: 0,
                focusElevation: 0,
                hoverElevation: 0,
                child: const Icon(Icons.edit_outlined),
              )
            : const SizedBox.shrink(),
      ),
      floatingActionButtonAnimator: FloatingActionButtonAnimator.noAnimation,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Notifications',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Bookmarks',
          ),
        ],
      ),
    );
  }
}
