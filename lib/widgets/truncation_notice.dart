import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';

/// Follows the text of a note that was cut short.
class TruncationNotice extends StatelessWidget {
  const TruncationNotice({super.key, this.full = false});

  /// True on the note's own screen, where there is no more to open.
  final bool full;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (full) {
      return Text(
        'This post is too long to display in full',
        style: theme.metadata,
      );
    }
    // A tap lands on the row or card around it, which opens the post.
    return Text(
      'Show more',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.primary,
      ),
    );
  }
}
