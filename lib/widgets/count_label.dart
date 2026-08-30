import 'package:flutter/material.dart';

// A "<count> <label>" pill (e.g. "20 reposts"), optionally tappable. Used
// anywhere a count links through to the list of users behind it.
class CountLabel extends StatelessWidget {
  const CountLabel({
    super.key,
    required this.count,
    required this.label,
    this.onTap,
  });

  final int? count;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: const BorderRadius.all(Radius.circular(4)),
      onTap: onTap,
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodySmall,
          children: [
            TextSpan(
              text: '${count ?? '···'} ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: label,
              style: TextStyle(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
