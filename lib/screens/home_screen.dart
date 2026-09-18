import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/note.dart';
import '../services/feed_loader.dart';
import '../widgets/compact_tab_bar.dart';
import '../widgets/load_more_footer.dart';
import '../widgets/note_tile.dart';
import '../widgets/placeholder_tab.dart';
import 'identities_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  )..addListener(_onTabChanged);

  bool _globalRequested = false;

  // The global feed is only fetched once someone actually opens it.
  void _onTabChanged() {
    if (_tabController.index != 1 || _globalRequested) return;
    _globalRequested = true;
    if (notesNotifier.value == null) {
      runFeedLoad(loadGlobalFeed, 'loading the global feed');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CompactTabBar(
          controller: _tabController,
          labels: const ['Following', 'Global'],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _KeepAlive(child: _FollowingFeed()),
              _KeepAlive(child: _GlobalFeed()),
            ],
          ),
        ),
      ],
    );
  }
}

// Keeps each feed's scroll position when swiping between tabs.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _GlobalFeed extends StatelessWidget {
  const _GlobalFeed();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Note>?>(
      valueListenable: notesNotifier,
      builder: (context, notes, _) => _NotesList(
        notes: notes,
        onRefresh: loadGlobalFeed,
        onLoadMore: () =>
            runFeedLoad(loadMoreGlobalFeed, 'loading more of the global feed'),
        hasMore: globalFeedHasMore,
        emptyLabel: 'No posts from your relays',
      ),
    );
  }
}

class _FollowingFeed extends StatelessWidget {
  const _FollowingFeed();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        activeIdentityPubkeyNotifier,
        myFollowingNotifier,
        followingNotesNotifier,
      ]),
      builder: (context, _) {
        if (activeIdentityPubkeyNotifier.value == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PlaceholderTab(
                  icon: Icons.people_outline,
                  label: 'No identity yet',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('createIdentityFromFeedButton'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const IdentitiesScreen()),
                  ),
                  child: const Text('Create or import an identity'),
                ),
              ],
            ),
          );
        }

        final notFollowingAnyone = myFollowingNotifier.value?.isEmpty ?? false;
        return _NotesList(
          notes: followingNotesNotifier.value,
          onRefresh: loadFollowingFeed,
          onLoadMore: () => runFeedLoad(
            loadMoreFollowingFeed,
            'loading more of the following feed',
          ),
          hasMore: followingFeedHasMore,
          emptyLabel: notFollowingAnyone
              ? 'Follow people to see their posts here'
              : 'No posts from people you follow',
        );
      },
    );
  }
}

class _NotesList extends StatelessWidget {
  const _NotesList({
    required this.notes,
    required this.onRefresh,
    required this.onLoadMore,
    required this.hasMore,
    required this.emptyLabel,
  });

  final List<Note>? notes;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final ValueListenable<bool> hasMore;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final notes = this.notes;

    // RefreshIndicator needs a scrollable child to attach its drag
    // gesture to, so the loading/empty states use a scrollable ListView
    // too rather than a bare centered widget.
    Widget body;
    if (notes == null) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(
            height: 400,
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    } else if (notes.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 400,
            child: PlaceholderTab(
              icon: Icons.rss_feed_outlined,
              label: emptyLabel,
            ),
          ),
        ],
      );
    } else {
      body = ValueListenableBuilder<bool>(
        valueListenable: hasMore,
        builder: (context, more, _) => ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: notes.length + (more ? 1 : 0),
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) => index == notes.length
              // A new key per page, so the next one is asked for if still in view.
              ? LoadMoreFooter(
                  key: ValueKey(notes.length),
                  onLoadMore: onLoadMore,
                )
              : NoteTile(note: notes[index]),
        ),
      );
    }

    return RefreshIndicator(onRefresh: onRefresh, child: body);
  }
}
