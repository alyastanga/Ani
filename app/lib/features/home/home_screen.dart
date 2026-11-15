import 'package:flutter/material.dart';

import '../../app_shell.dart';
import '../../app_state.dart';
import '../../core/dryness.dart' show dryRank;
import '../../data/bundle.dart';
import '../../data/farm_store.dart';
import '../../data/live_outlook.dart';
import '../../data/planner_profile.dart';
import '../../data/tracker_service.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import '../alerts/alerts_screen.dart';
import '../farm/add_planting_screen.dart';
import '../farm/planting_detail_screen.dart';
import '../farm/planting_widgets.dart';
import '../farm/tracker_builder.dart';
import '../labels.dart';
import '../outlook/heat_safety.dart';
import 'conditions_card.dart';
import '../recommend/recommend_flow.dart';
import '../recommend/recommend_labels.dart';
import 'settings_sheet.dart';

/// Start screen (doc Fig. 2): El Niño outlook, dryness banner, heat-safety
/// strip, the planner CTA, the tracked-crop summary and alerts.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final town = state.town;
    final bundle = state.bundle;
    final saved = state.plannerProfile;

    return SafeArea(
      child: ListView(
        key: const ValueKey('home-list'),
        padding: const EdgeInsets.fromLTRB(AniSpacing.screen, AniSpacing.sm, AniSpacing.screen, AniSpacing.xxl),
        children: [
          // Olive hero panel, as in the Make prototype's "today" card.
          Container(
            decoration: const BoxDecoration(
              color: AniColors.olive,
              borderRadius: BorderRadius.all(Radius.circular(AniRadius.xl)),
            ),
            padding: const EdgeInsets.fromLTRB(AniSpacing.xl, AniSpacing.md, AniSpacing.sm, AniSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(color: AniColors.gold, shape: BoxShape.circle),
                      child: const Icon(Icons.eco, size: 16, color: AniColors.paper),
                    ),
                    const SizedBox(width: AniSpacing.sm),
                    Expanded(child: Eyebrow(l.appTitle, color: AniColors.sand)),
                    const AlertsBell(color: AniColors.cream),
                    IconButton(
                      key: const ValueKey('home-settings'),
                      tooltip: l.settingsTitle,
                      icon: const Icon(Icons.settings_outlined, color: AniColors.cream),
                      onPressed: () => showSettingsSheet(context),
                    ),
                  ],
                ),
                const SizedBox(height: AniSpacing.sm),
                Text(
                  town == null ? '' : l.townName(town),
                  key: const ValueKey('home-town'),
                  style: theme.textTheme.headlineMedium?.copyWith(color: AniColors.paper),
                ),
              ],
            ),
          ),
          const SizedBox(height: AniSpacing.lg),
          if (bundle != null) ...[
            if (state.live?.latestWeather != null) ...[
              ConditionsCard(weather: state.live!.latestWeather),
              const SizedBox(height: AniSpacing.md),
            ],
            _EnsoCard(enso: bundle.enso),
            const SizedBox(height: AniSpacing.md),
            _DrynessBanner(dryness: bundle.dryness),
            const SizedBox(height: AniSpacing.md),
            _HeatStrip(heat: bundle.heat, live: state.live),
            const SizedBox(height: AniSpacing.xl),
          ],
          PrimaryButton(
            key: const ValueKey('home-cta'),
            label: l.homeCta,
            icon: Icons.eco_outlined,
            onPressed: () => openRecommendFlow(context),
          ),
          if (state.hasRecommendation && saved != null) ...[
            const SizedBox(height: AniSpacing.md),
            _LastRecommendation(saved: saved),
          ],
          const SizedBox(height: AniSpacing.xl),
          const _TrackedCropCard(),
          const SizedBox(height: AniSpacing.md),
          const _AlertsCard(),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ helpers

/// Signed fixed-point number, e.g. "+2.2" / "-1.45".
String _signed(double x, int digits) => '${x >= 0 ? '+' : ''}${x.toStringAsFixed(digits)}';

/// "42" for whole numbers, else one decimal.
String _degrees(double x) => x == x.roundToDouble() ? x.toStringAsFixed(0) : x.toStringAsFixed(1);

/// Rank sentence for `dryness.latest`, localized. The rank is recomputed with
/// [dryRank] against the same calendar month in `dryness.monthly` (the
/// pipeline's `dry_rank` / `dry_n`) and phrased like `rank_text`: "driest r
/// of n" when D >= 0, "wettest (n - r + 1) of n" otherwise. Falls back to the
/// bundle's own Filipino sentence if the month is missing from the series.
String? drynessRankSentence(AppLocalizations l, Dryness dryness) {
  final latest = dryness.latest;
  final m = latest.month.length >= 7 ? int.tryParse(latest.month.substring(5, 7)) : null;
  final others = [
    for (final p in dryness.monthly)
      if (p.monthOfYear == m && p.month != latest.month) p.d,
  ];
  final present = dryness.monthly.any((p) => p.month == latest.month);
  if (!present || others.isEmpty) return latest.rank;
  final r = dryRank(latest.d, others);
  return latest.d >= 0 ? l.drynessRank(r.rank, r.n) : l.drynessRankWet(r.n - r.rank + 1, r.n);
}

// ------------------------------------------------------------------ El Niño

class _EnsoCard extends StatelessWidget {
  const _EnsoCard({required this.enso});

  final Enso enso;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final strength = ensoStrengthKey(enso.jas);
    final tagColor = enso.isElNino ? AniColors.statusDelikado : AniColors.olive;
    return AniCard(
      key: const ValueKey('home-enso'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: tagColor.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(Icons.wb_sunny_outlined, color: tagColor),
          ),
          const SizedBox(width: AniSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow('${l.homeOutlookTitle} · ${enso.comingSeason}'),
                const SizedBox(height: AniSpacing.xs),
                Text(
                  enso.isElNino ? l.elNinoExpected : l.ensoTagName(enso.tag),
                  key: const ValueKey('home-enso-headline'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AniSpacing.sm),
                Wrap(
                  spacing: AniSpacing.sm,
                  runSpacing: AniSpacing.sm,
                  children: [
                    AniPill(l.ensoTagName(enso.tag), color: tagColor),
                    if (strength != null)
                      AniPill(
                        l.ensoStrength(strength),
                        key: const ValueKey('home-enso-jas'),
                        color: AniColors.muted,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ dryness

class _DrynessBanner extends StatelessWidget {
  const _DrynessBanner({required this.dryness});

  final Dryness dryness;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final latest = dryness.latest;
    final fg = drynessColor(latest.label);
    final rank = drynessRankSentence(l, dryness);
    return Container(
      key: const ValueKey('home-dryness'),
      decoration: BoxDecoration(
        color: drynessBgColor(latest.label),
        borderRadius: AniRadius.card,
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.all(AniSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.water_drop_outlined, color: fg),
          const SizedBox(width: AniSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow('${l.drynessTitle} · ${latest.month}', color: fg),
                const SizedBox(height: AniSpacing.xs),
                Wrap(
                  spacing: AniSpacing.sm,
                  runSpacing: AniSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l.drynessLabelName(latest.label),
                      key: const ValueKey('home-dryness-label'),
                      style: theme.textTheme.headlineSmall?.copyWith(color: fg),
                    ),
                    AniPill(
                      l.drynessDValue(_signed(latest.d, 2)),
                      key: const ValueKey('home-dryness-d'),
                      color: fg,
                    ),
                  ],
                ),
                if (rank != null) ...[
                  const SizedBox(height: AniSpacing.xs),
                  Text(
                    rank,
                    key: const ValueKey('home-dryness-rank'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: AniColors.ink),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ heat

/// People-safety advice only; never feeds the planner (doc requirement).
class _HeatStrip extends StatelessWidget {
  const _HeatStrip({required this.heat, this.live});

  final HeatInfo heat;

  /// Live reading from the POWER cache, or null before the first sync.
  final LiveOutlook? live;

  static const _dangerLabels = {'danger', 'extreme danger'};

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    HeatCategory? danger;
    for (final c in heat.indexCategoriesC) {
      if (_dangerLabels.contains(c.label)) {
        danger = c;
        break;
      }
    }
    return AniCard(
      key: const ValueKey('home-heat'),
      padding: const EdgeInsets.symmetric(horizontal: AniSpacing.lg, vertical: AniSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: AniColors.statusBantayBg, shape: BoxShape.circle),
            child: const Icon(Icons.thermostat_outlined, color: AniColors.gold),
          ),
          const SizedBox(width: AniSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow(l.heatSafetyTitle),
                const SizedBox(height: AniSpacing.xs),
                LiveHeatReading(live: live),
                const SizedBox(height: AniSpacing.xs),
                if (danger != null)
                  Text(
                    l.homeHeatDangerFrom(l.heatCategoryName(danger.label), _degrees(danger.from)),
                    style: theme.textTheme.bodyMedium,
                  ),
                Text(
                  l.workEarly,
                  key: const ValueKey('home-heat-advice'),
                  style: theme.textTheme.titleSmall?.copyWith(color: AniColors.statusDelikado),
                ),
                if (heat.indexCategoriesC.isNotEmpty) ...[
                  const SizedBox(height: AniSpacing.sm),
                  Wrap(
                    spacing: AniSpacing.xs,
                    runSpacing: AniSpacing.xs,
                    children: [
                      for (final c in heat.indexCategoriesC)
                        AniPill(
                          '${l.heatCategoryName(c.label)} ${_degrees(c.from)}${c.to == null ? '+' : '–${_degrees(c.to!)}'}°C',
                          color: _dangerLabels.contains(c.label) ? AniColors.statusDelikado : AniColors.gold,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: AniSpacing.sm),
                Text(
                  l.heatSafetyNote,
                  style: theme.textTheme.bodySmall?.copyWith(color: AniColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ last recommendation

class _LastRecommendation extends StatelessWidget {
  const _LastRecommendation({required this.saved});

  final SavedPlannerProfile saved;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final town = saved.town;
    return AniCard(
      key: const ValueKey('home-last-rec'),
      padding: const EdgeInsets.all(AniSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Eyebrow(l.homeLastRecommendationTitle),
          const SizedBox(height: AniSpacing.xs),
          Text(
            l.resultSubtitle(
              town == null ? saved.profile.muni : l.townName(town),
              l.waterLevelName(saved.profile.water),
            ),
            key: const ValueKey('home-last-rec-summary'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AniSpacing.sm),
          OutlinedButton.icon(
            key: const ValueKey('home-last-rec-open'),
            onPressed: () => openLastRecommendation(context),
            icon: const Icon(Icons.history, size: 20),
            label: Text(l.homeLastRecommendation),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ tracked crop, alerts

/// Active plantings with stage and progress (tap: detail), or the empty
/// state with "Add planting".
class _TrackedCropCard extends StatelessWidget {
  const _TrackedCropCard();

  static const _max = 3;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return TrackerBuilder(builder: (context, t) {
      final open = [for (final v in t?.views ?? const <PlantingView>[]) if (!v.isClosed) v];
      return AniCard(
        key: const ValueKey('home-crops'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Eyebrow(l.homeTrackedTitle),
            const SizedBox(height: AniSpacing.sm),
            if (open.isEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.grass_outlined, color: AniColors.sand),
                  const SizedBox(width: AniSpacing.sm),
                  Expanded(
                    child: Text(
                      l.homeTrackedEmpty,
                      key: const ValueKey('home-crops-empty'),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AniSpacing.xs),
              Text(l.homeTrackedHint, style: theme.textTheme.bodyMedium?.copyWith(color: AniColors.muted)),
              const SizedBox(height: AniSpacing.sm),
              OutlinedButton.icon(
                key: const ValueKey('home-add-planting'),
                onPressed: () => openAddPlanting(context),
                icon: const Icon(Icons.add, size: 20),
                label: Text(l.myFarmAddPlanting),
              ),
            ] else ...[
              for (final v in open.take(_max)) ...[
                PlantingRow(view: v, compact: true, onTap: () => openPlantingDetail(context, v.planting.id)),
                const SizedBox(height: AniSpacing.sm),
              ],
              TextButton.icon(
                key: const ValueKey('home-open-farm'),
                onPressed: () => AppShell.selectTab(context, AppShell.farmTab),
                icon: const Icon(Icons.agriculture_outlined, size: 20),
                label: Text(l.homeOpenMyFarm),
              ),
            ],
          ],
        ),
      );
    });
  }
}

/// The latest alerts (water-now runs collapsed), with "See all".
class _AlertsCard extends StatelessWidget {
  const _AlertsCard();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return TrackerBuilder(builder: (context, t) {
      final alerts = t?.alerts ?? const <AlertRecord>[];
      return AniCard(
        key: const ValueKey('home-alerts'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Eyebrow(l.alertsTitle),
            const SizedBox(height: AniSpacing.sm),
            if (alerts.isEmpty)
              Row(
                children: [
                  const Icon(Icons.notifications_none_outlined, color: AniColors.sand),
                  const SizedBox(width: AniSpacing.sm),
                  Expanded(
                    child: Text(
                      l.alertsEmpty,
                      key: const ValueKey('home-alerts-empty'),
                      style: theme.textTheme.bodyMedium?.copyWith(color: AniColors.muted),
                    ),
                  ),
                ],
              )
            else ...[
              AlertList(
                key: const ValueKey('home-alerts-list'),
                alerts: alerts,
                maxGroups: 3,
                newIds: {for (final a in alerts) if (!a.seen) a.id},
              ),
              const SizedBox(height: AniSpacing.sm),
              TextButton(
                key: const ValueKey('home-alerts-all'),
                onPressed: () => openAlerts(context),
                child: Text(l.alertsSeeAll),
              ),
            ],
          ],
        ),
      );
    });
  }
}
