import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/theme.dart';

/// Empty tab screen used until the real screen is built.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AniSpacing.screen),
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: AniSpacing.lg),
          AniCard(
            child: Row(
              children: [
                Icon(icon, color: AniColors.muted),
                const SizedBox(width: AniSpacing.md),
                Expanded(child: Text(l.comingSoon, style: const TextStyle(color: AniColors.muted))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
