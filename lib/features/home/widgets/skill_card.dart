import 'package:flutter/material.dart';

class EcoSkill {
  const EcoSkill({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.route,
    this.isAvailable = true,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final String route;
  final bool isAvailable;
}

class SkillCard extends StatelessWidget {
  const SkillCard({
    super.key,
    required this.skill,
    required this.onTap,
  });

  final EcoSkill skill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final available = skill.isAvailable;

    return Semantics(
      label: available
          ? 'Open ${skill.title}'
          : '${skill.title}, coming soon',
      button: available,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        elevation: available ? 2 : 0,
        color: available ? colors.surface : colors.surfaceContainerHighest,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: available ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                _SkillIcon(icon: skill.icon, available: available),
                const SizedBox(width: 16),
                Expanded(
                  child: _SkillText(
                    title: skill.title,
                    description: skill.description,
                    available: available,
                  ),
                ),
                _StatusBadge(available: available),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkillIcon extends StatelessWidget {
  const _SkillIcon({required this.icon, required this.available});
  final IconData icon;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: available
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        icon,
        size: 28,
        color: available ? colors.onPrimaryContainer : colors.outline,
      ),
    );
  }
}

class _SkillText extends StatelessWidget {
  const _SkillText({
    required this.title,
    required this.description,
    required this.available,
  });
  final String title;
  final String description;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: available ? colors.onSurface : colors.outline,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: textTheme.bodySmall?.copyWith(
            color: available ? colors.onSurfaceVariant : colors.outlineVariant,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.available});
  final bool available;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (available) {
      return Icon(Icons.arrow_forward_ios_rounded,
          size: 16, color: colors.primary);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Text(
        'Soon',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.outline,
            ),
      ),
    );
  }
}
