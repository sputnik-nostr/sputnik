import 'package:flutter/material.dart';

/// Says some relays did not answer, so what is shown may not be current.
class UncheckedWarning extends StatelessWidget {
  const UncheckedWarning({
    super.key,
    required this.message,
    required this.onRetry,
    this.retryKey,
  });

  final String message;
  final VoidCallback onRetry;
  final Key? retryKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.warning_amber_outlined,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
        TextButton(
          key: retryKey,
          onPressed: onRetry,
          child: const Text('Retry'),
        ),
      ],
    );
  }
}
