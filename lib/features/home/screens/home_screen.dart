// issue: #56
import 'package:flutter/material.dart';
import '../widgets/skill_card.dart';

const _skills = [
  EcoSkill(
    id: 'fish-scanner',
    title: 'Fish Scanner', // TODO(#27): AppLocalizations.of(context).skillFishScannerTitle
    description: 'Point at a fish counter to check species sustainability ratings.',
    icon: Icons.set_meal_rounded,
    route: '/fish-scanner',
    isAvailable: true,
  ),
  EcoSkill(
    id: 'plastic-detector',
    title: 'Plastic Detector',
    description: 'Identify single-use plastics and find eco-friendly alternatives.',
    icon: Icons.recycling_rounded,
    route: '/plastic-detector',
    isAvailable: false,
  ),
  EcoSkill(
    id: 'bird-watcher',
    title: 'Bird Watcher',
    description: 'Identify bird species and learn about their conservation status.',
    icon: Icons.flutter_dash_rounded,
    route: '/bird-watcher',
    isAvailable: false,
  ),
  EcoSkill(
    id: 'carbon-footprint',
    title: 'Carbon Footprint',
    description: 'Scan products to estimate their environmental impact.',
    icon: Icons.eco_rounded,
    route: '/carbon-footprint',
    isAvailable: false,
  ),
];

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _EcopalAppBar(),
          SliverPadding(
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            sliver: SliverList.builder(
              itemCount: _skills.length,
              itemBuilder: (context, index) {
                final skill = _skills[index];
                return SkillCard(
                  skill: skill,
                  onTap: () => Navigator.of(context).pushNamed(skill.route),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EcopalAppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SliverAppBar(
      expandedHeight: 160,
      pinned: true,
      backgroundColor: colors.surface,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ecopal',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: colors.primary,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'Choose your eco-skill', // TODO(#27): localise
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        background: _AppBarBackground(),
      ),
    );
  }
}

class _AppBarBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer.withAlpha(180),
            colors.surface,
          ],
        ),
      ),
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Icon(
            Icons.park_rounded,
            size: 72,
            color: colors.primary.withAlpha(40),
          ),
        ),
      ),
    );
  }
}
