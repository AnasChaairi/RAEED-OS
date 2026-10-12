import 'package:flutter/material.dart';

import '../theme/raeed_theme.dart';

/// An error under a form, in words people can act on.
class FormError extends StatelessWidget {
  const FormError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFDE8E3), borderRadius: BorderRadius.circular(12)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: RaeedColors.error, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: RaeedColors.error)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown inside a button while its action runs.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key});

  @override
  Widget build(BuildContext context) =>
      const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white));
}
