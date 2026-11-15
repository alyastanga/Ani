import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import '../alerts/alerts_screen.dart';
import 'add_planting_screen.dart';
import 'demo_screen.dart';
import 'planting_detail_screen.dart';
import 'planting_widgets.dart';
import 'tracker_builder.dart';

/// My farm (doc Fig. 4): the farmer's plantings with stage and progress,
/// add planting, and the season replay (demo) entry. The shell also
/// refreshes the tracker each time this tab is opened.
class FarmScreen extends StatefulWidget {
  const FarmScreen({super.key});

  @override
  State<FarmScreen> createState() => _FarmScreenState();
}

class _FarmScreenState extends State<FarmScreen> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (!_started && !state.trackerLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => state.refreshTracker().ignore());
    }
    _started = true;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final loaded = AppScope.of(context).trackerLoaded;
    return SafeArea(
      child: TrackerBuilder(builder: (context, t) {
        final views = t?.views ?? const [];
        final open = [for (final v in views) if (!v.isClosed) v];
        final closed = [for (final v in views) if (v.isClosed) v];
        return ListView(
          key: const ValueKey('farm-list'),
          padding: const EdgeInsets.fromLTRB(AniSpacing.screen, AniSpacing.sm, AniSpacing.screen, AniSpacing.xxl),
          children: [
            Row(
              children: [
                Expanded(child: Text(l.navMyFarm, style: theme.textTheme.headlineMedium)),
                const AlertsBell(),
              ],
            ),
            const SyncStatusLine(),
            const SizedBox(height: AniSpacing.md),
            if (t == null || (!loaded && views.isEmpty))
              const Padding(
                padding: EdgeInsets.all(AniSpacing.xxl),
                child: Center(child: CircularProgressIndicator(color: AniColors.olive)),
              )
            else if (views.isEmpty)
              AniCard(
                key: const ValueKey('farm-empty'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.grass_outlined, color: AniColors.sand, size: 36),
                    const SizedBox(height: AniSpacing.sm),
                    Text(l.myFarmEmptyTitle, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AniSpacing.xs),
                    Text(l.myFarmEmptyHint,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: AniColors.muted)),
                    const SizedBox(height: AniSpacing.lg),
                    PrimaryButton(
                      key: const ValueKey('farm-add-empty'),
                      label: l.myFarmAddPlanting,
                      icon: Icons.add,
                      onPressed: () => openAddPlanting(context),
                    ),
                  ],
                ),
              )
            else ...[
              if (open.isNotEmpty) ...[
                Eyebrow(l.myFarmGrowing),
                const SizedBox(height: AniSpacing.sm),
                for (final v in open) ...[
                  PlantingRow(view: v, onTap: () => openPlantingDetail(context, v.planting.id)),
                  const SizedBox(height: AniSpacing.sm),
                ],
              ],
              const SizedBox(height: AniSpacing.xs),
              PrimaryButton(
                key: const ValueKey('farm-add'),
                label: l.myFarmAddPlanting,
                icon: Icons.add,
                onPressed: () => openAddPlanting(context),
              ),
              if (closed.isNotEmpty) ...[
                const SizedBox(height: AniSpacing.xl),
                Eyebrow(l.myFarmPast),
                const SizedBox(height: AniSpacing.sm),
                for (final v in closed) ...[
                  PlantingRow(view: v, onTap: () => openPlantingDetail(context, v.planting.id)),
                  const SizedBox(height: AniSpacing.sm),
                ],
              ],
            ],
            const SizedBox(height: AniSpacing.xl),
            AniCard(
              key: const ValueKey('farm-demo'),
              onTap: () => openDemo(context),
              padding: const EdgeInsets.all(AniSpacing.md),
              child: Row(
                children: [
                  const Icon(Icons.replay_outlined, color: AniColors.gold),
                  const SizedBox(width: AniSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.demoTitle, style: theme.textTheme.titleSmall),
                        Text(l.demoBanner, style: theme.textTheme.bodySmall?.copyWith(color: AniColors.muted)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AniColors.muted),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}
