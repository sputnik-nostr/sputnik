import 'package:flutter/material.dart';

import '../models/note.dart';
import '../screens/compose_screen.dart';
import '../services/reaction_actions.dart';
import 'note_action_button.dart';

/// A like button for [note]; toggles a like on tap.
class LikeButton extends StatelessWidget {
  const LikeButton({
    super.key,
    required this.note,
    this.showCount = true,
    this.size = 16,
  });

  final Note note;
  final bool showCount;
  final double size;

  @override
  Widget build(BuildContext context) {
    return _ReactionToggle(
      scope: note.id,
      active: note.likedByMe,
      count: note.likeCount,
      showCount: showCount,
      size: size,
      icon: (liked) => liked ? Icons.favorite : Icons.favorite_border,
      tooltip: (liked) => liked ? 'Liked' : 'Like',
      toggle: (liked) =>
          liked ? unlikeNote(context, note) : likeNote(context, note),
    );
  }
}

/// A repost button for [note]; toggles a repost on tap, quotes on hold.
class RepostButton extends StatelessWidget {
  const RepostButton({
    super.key,
    required this.note,
    this.showCount = true,
    this.size = 16,
  });

  final Note note;
  final bool showCount;
  final double size;

  @override
  Widget build(BuildContext context) {
    return _ReactionToggle(
      scope: note.id,
      active: note.repostedByMe,
      count: note.repostCount,
      showCount: showCount,
      size: size,
      icon: (_) => Icons.repeat,
      tooltip: (reposted) =>
          '${reposted ? 'Reposted' : 'Repost'} (hold to quote)',
      toggle: (reposted) =>
          reposted ? unrepostNote(context, note) : repostNote(context, note),
      onLongPress: () => openQuoteComposer(context, note),
    );
  }
}

class _ReactionToggle extends StatefulWidget {
  const _ReactionToggle({
    required this.scope,
    required this.active,
    required this.count,
    required this.showCount,
    required this.size,
    required this.icon,
    required this.tooltip,
    required this.toggle,
    this.onLongPress,
  });

  /// What [active] and a tap are about. When it changes this button is showing
  /// something else, and what it did for the previous scope no longer applies.
  final Object scope;

  /// Whether the relays say the active identity already reacted.
  final bool active;

  /// What the relays count, before any toggle from this button.
  final int count;
  final bool showCount;
  final double size;
  final IconData Function(bool active) icon;
  final String Function(bool active) tooltip;

  /// Undoes the reaction if [active], else adds it; true if it went through.
  final Future<bool> Function(bool active) toggle;
  final VoidCallback? onLongPress;

  @override
  State<_ReactionToggle> createState() => _ReactionToggleState();
}

class _ReactionToggleState extends State<_ReactionToggle> {
  bool _pending = false;

  /// Set once this button has toggled itself; null defers to [widget.active].
  bool? _localOverride;

  /// How often the scope changed, so a tap can tell that it was overtaken.
  int _scopeChanges = 0;

  @override
  void didUpdateWidget(_ReactionToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scope == oldWidget.scope) return;
    _localOverride = null;
    _pending = false;
    _scopeChanges++;
  }

  Future<void> _tap() async {
    final active = _localOverride ?? widget.active;
    final scopeChanges = _scopeChanges;
    setState(() => _pending = true);
    final succeeded = await widget.toggle(active);
    if (!mounted || scopeChanges != _scopeChanges) return;
    setState(() {
      _pending = false;
      if (succeeded) _localOverride = !active;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = _localOverride ?? widget.active;
    final delta = active == widget.active ? 0 : (active ? 1 : -1);

    return NoteActionButton(
      icon: widget.icon(active),
      tooltip: widget.tooltip(active),
      count: widget.showCount ? widget.count + delta : 0,
      size: widget.size,
      color: active ? colorScheme.primary : null,
      onTap: _pending ? null : _tap,
      onLongPress: _pending ? null : widget.onLongPress,
    );
  }
}
