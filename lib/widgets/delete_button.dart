import 'package:flutter/material.dart';

import '../models/note.dart';
import '../nostr/nostr.dart';
import '../services/reaction_actions.dart';

/// A delete button for [note]; publishes a NIP-09 deletion request on tap.
///
/// Callers are responsible for only showing this for the active identity's
/// own notes.
class DeleteButton extends StatefulWidget {
  const DeleteButton({
    super.key,
    required this.note,
    this.relayClient = const RelayClient(),
    this.onDeleted,
    this.size = 16,
  });

  final Note note;
  final RelayClient relayClient;

  /// Called once the deletion request has been published successfully.
  final VoidCallback? onDeleted;
  final double size;

  @override
  State<DeleteButton> createState() => _DeleteButtonState();
}

class _DeleteButtonState extends State<DeleteButton> {
  bool _pending = false;

  Future<void> _tap() async {
    setState(() => _pending = true);
    final succeeded = await deleteNote(
      context,
      widget.note,
      relayClient: widget.relayClient,
    );
    if (!mounted) return;
    setState(() => _pending = false);
    if (succeeded) widget.onDeleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: 'Delete',
      child: InkResponse(
        onTap: _pending ? null : _tap,
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.delete_outline,
            size: widget.size,
            color: theme.colorScheme.outline,
          ),
        ),
      ),
    );
  }
}
