import 'package:flutter/material.dart';

import '../widgets/placeholder_tab.dart';

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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SearchBar(
            controller: _controller,
            hintText: 'Search notes and people',
            leading: const Icon(Icons.search),
            onChanged: (value) => setState(() => _query = value),
            elevation: const WidgetStatePropertyAll(0),
            constraints: const BoxConstraints(minHeight: 44, maxHeight: 44),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
