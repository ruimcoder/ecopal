import 'package:flutter/material.dart';

/// Dialog that requests user consent before sending camera frames to the cloud
/// for improved species identification.
class CloudConsentDialog extends StatelessWidget {
  const CloudConsentDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Semantics(
        // TODO(#27): AppLocalizations
        label: 'Enable cloud identification',
        child: Text(
          // TODO(#27): AppLocalizations
          'Enable Cloud Identification?',
          style: theme.textTheme.titleLarge,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: 'What data is sent: a single camera frame',
            child: _InfoRow(
              icon: Icons.camera_alt_outlined,
              // TODO(#27): AppLocalizations
              text: 'A single camera frame is sent to our cloud API.',
              colorScheme: colorScheme,
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            label: 'Why: for better species identification',
            child: _InfoRow(
              icon: Icons.search_outlined,
              // TODO(#27): AppLocalizations
              text: 'This improves identification accuracy when on-device '
                  'confidence is low.',
              colorScheme: colorScheme,
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            label: 'Privacy note: frames are not stored',
            child: _InfoRow(
              icon: Icons.lock_outline,
              // TODO(#27): AppLocalizations
              text: 'Frames are processed in real time and never stored.',
              colorScheme: colorScheme,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            // TODO(#27): AppLocalizations
            'Not now',
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            // TODO(#27): AppLocalizations
            'Enable',
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.text,
    required this.colorScheme,
  });

  final IconData icon;
  final String text;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}
