import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';

/// Opens the About / limits page.
Future<void> openAbout(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen()));

/// Delimitations of the advice and the data it is built from.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final limits = [l.aboutLimitPoint, l.aboutLimitAdvisory, l.aboutLimitRice, l.aboutLimitTrials, l.aboutLimitHeat];
    final sources = [
      l.aboutSourcePower,
      l.aboutSourceSoil,
      l.aboutSourceEnso,
      l.aboutSourceFao,
      l.aboutSourcePsa,
      l.aboutSourcePagasa,
      l.aboutSourceMao,
    ];
    return Scaffold(
      backgroundColor: AniColors.cream,
      appBar: AppBar(title: Text(l.aboutTitle)),
      body: SafeArea(
        child: ListView(
          key: const ValueKey('about-list'),
          padding: const EdgeInsets.all(AniSpacing.screen),
          children: [
            Eyebrow(l.aboutLimitsHeading),
            const SizedBox(height: AniSpacing.sm),
            _PointsCard(keyPrefix: 'about-limit', icon: Icons.info_outline, points: limits),
            const SizedBox(height: AniSpacing.lg),
            Eyebrow(l.aboutSourcesHeading),
            const SizedBox(height: AniSpacing.sm),
            _PointsCard(keyPrefix: 'about-source', icon: Icons.dataset_outlined, points: sources),
          ],
        ),
      ),
    );
  }
}

class _PointsCard extends StatelessWidget {
  const _PointsCard({required this.keyPrefix, required this.icon, required this.points});

  final String keyPrefix;
  final IconData icon;
  final List<String> points;

  @override
  Widget build(BuildContext context) {
    return AniCard(
      padding: const EdgeInsets.all(AniSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < points.length; i++) ...[
            if (i > 0) const SizedBox(height: AniSpacing.md),
            Row(
              key: ValueKey('$keyPrefix-$i'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: AniColors.gold),
                const SizedBox(width: AniSpacing.md),
                Expanded(child: Text(points[i], style: Theme.of(context).textTheme.bodyMedium)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
