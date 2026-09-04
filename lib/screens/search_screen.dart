import 'package:flutter/material.dart';

import '../main.dart';
import '../models/note.dart';
import '../models/note_mapper.dart';
import '../nostr/nostr.dart';
import '../widgets/note_tile.dart';
import '../widgets/placeholder_tab.dart';
import '../widgets/profile_result_tile.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = decodeNostrUri(_query.trim());

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SearchBar(
            controller: _controller,
            hintText: 'Search notes and people',
            leading: const Icon(Icons.search),
            trailing: _query.isEmpty
                ? null
                : [
                    IconButton(
                      icon: const Icon(Icons.clear),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                    ),
                  ],
            onChanged: (value) => setState(() => _query = value),
            elevation: const WidgetStatePropertyAll(0),
            constraints: const BoxConstraints(minHeight: 40, maxHeight: 40),
            shape: const WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
              ),
            ),
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.focused)) {
                return BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                );
              }
              return BorderSide.none;
            }),
          ),
        ),
        if (target?.pubkeyHex != null)
          _NpubResult(
            key: ValueKey(target!.pubkeyHex),
            pubkeyHex: target.pubkeyHex!,
          )
        else if (target?.eventIdHex != null)
          _NoteResult(
            key: ValueKey(target!.eventIdHex),
            eventIdHex: target.eventIdHex!,
          )
        else
          Expanded(
            child: _query.isEmpty
                ? const PlaceholderTab(icon: Icons.search, label: 'Search')
                : PlaceholderTab(
                    icon: Icons.search_off,
                    label: 'No results for "$_query"',
                  ),
          ),
      ],
    );
  }
}

class _NpubResult extends StatefulWidget {
  const _NpubResult({super.key, required this.pubkeyHex});

  final String pubkeyHex;

  @override
  State<_NpubResult> createState() => _NpubResultState();
}

class _NpubResultState extends State<_NpubResult> {
  @override
  void initState() {
    super.initState();
    const RelayProfileRepository().fetchProfile(
      widget.pubkeyHex,
      selectedRelaysNotifier.value,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, NostrMetadata>>(
      valueListenable: profileCacheNotifier,
      builder: (context, profileCache, _) {
        return ProfileResultTile(
          pubkeyHex: widget.pubkeyHex,
          metadata: profileCache[widget.pubkeyHex],
        );
      },
    );
  }
}

class _NoteResult extends StatefulWidget {
  const _NoteResult({super.key, required this.eventIdHex});

  final String eventIdHex;

  @override
  State<_NoteResult> createState() => _NoteResultState();
}

class _NoteResultState extends State<_NoteResult> {
  late final Future<Note?> _noteFuture;

  @override
  void initState() {
    super.initState();
    _noteFuture = _load();
  }

  Future<Note?> _load() async {
    final relayUrls = selectedRelaysNotifier.value;
    final post = await RelayPostRepository(relayUrls: relayUrls)
        .fetchPostById(widget.eventIdHex);
    if (post == null) return null;

    final authorMetadata = await const RelayProfileRepository().fetchProfile(
      post.author.pubkey,
      relayUrls,
    );
    return noteFromNostrPost(post, authorMetadata: authorMetadata);
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FutureBuilder<Note?>(
        future: _noteFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final note = snapshot.data;
          if (note == null) {
            return const PlaceholderTab(
              icon: Icons.search_off,
              label: 'Note not found',
            );
          }
          return ListView(children: [NoteTile(note: note)]);
        },
      ),
    );
  }
}
