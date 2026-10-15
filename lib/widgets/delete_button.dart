import 'package:flutter/material.dart';

import '../models/note.dart';
import '../services/reaction_actions.dart';
import 'note_action_button.dart';

/// A delete button for [note]; publishes a NIP-09 deletion request on tap.
///
/// Callers are responsible for only showing this for the active identity's
/// own notes.
class DeleteButton extends StatefulWidget {
  const DeleteButton({
    super.key,
    required this.note,
    this.onDeleted,
    this.size = 16,
  });

  final Note note;

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
    final succeeded = await deleteNote(context, widget.note);
    if (!mounted) return;
    setState(() => _pending = false);
    if (succeeded) widget.onDeleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    return NoteActionButton(
      icon: Icons.delete_outline,
      tooltip: 'Delete',
      size: widget.size,
      onTap: _pending ? null : _tap,
    );
  }
}
