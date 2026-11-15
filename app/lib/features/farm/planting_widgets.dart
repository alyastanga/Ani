import 'package:flutter/material.dart';

import '../../core/field_machine.dart' show FieldState;
import '../../data/farm_store.dart';
import '../../data/tracker_service.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import '../alerts/alert_labels.dart';
import '../alerts/alerts_screen.dart' show AlertList;
import '../labels.dart';
import '../recommend/recommend_labels.dart';

/// Pill colour for a stage.
Color stageColor(FieldState s) => switch (s) {
      FieldState.failed => AniColors.statusDelikado,
      FieldState.harvest => AniColors.statusNormal,
      FieldState.mature => AniColors.gold,
      _ => AniColors.olive,
    };

/// One planting in a list: crop, stage, progress bar, data lag, demo tag.
class PlantingRow extends StatelessWidget {
  const PlantingRow({super.key, required this.view, this.onTap, this.compact = false});

  final PlantingView view;
  final VoidCallback? onTap;

  /// Home summary: no planting-date line.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = view.planting;
    return AniCard(
      key: ValueKey('planting-row-${p.id}'),
      onTap: onTap,
      padding: const EdgeInsets.all(AniSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.eco_outlined, color: stageColor(view.stage)),
              const SizedBox(width: AniSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.cropNameOf(p.crop), style: theme.textTheme.titleMedium),
                    if (!compact)
                      Text(
                        l.plantingPlantedOn(fmtDate(context, p.plantedOn)),
                        style: theme.textTheme.bodySmall?.copyWith(color: AniColors.muted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AniSpacing.sm),
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AniSpacing.xs,
                  runSpacing: AniSpacing.xs,
                  children: [
                    if (view.isDemo) AniPill(l.plantingDemoTag, color: AniColors.gold),
                    AniPill(l.stageName(view.stage),
                        key: ValueKey('planting-stage-${p.id}'), color: stageColor(view.stage)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AniSpacing.sm),
          AniProgressBar(value: view.progress, color: stageColor(view.stage)),
          const SizedBox(height: AniSpacing.xs),
          Text(
            l.plantingProgress((view.progress * 100).round()),
            style: theme.textTheme.bodySmall?.copyWith(color: AniColors.muted),
          ),
          if (view.waitingForDataDays > 0) ...[
            const SizedBox(height: AniSpacing.xs),
            _WaitingNote(days: view.waitingForDataDays, keyId: p.id),
          ],
        ],
      ),
    );
  }
}

class _WaitingNote extends StatelessWidget {
  const _WaitingNote({required this.days, required this.keyId});

  final int days;
  final String keyId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      key: ValueKey('planting-waiting-$keyId'),
      children: [
        const Icon(Icons.hourglass_empty, size: 16, color: AniColors.gold),
        const SizedBox(width: AniSpacing.xs),
        Expanded(
          child: Text(
            l.waitingForDataDays(days),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AniColors.ink),
          ),
        ),
      ],
    );
  }
}

/// Stage timeline: Prep -> Estab -> Veg -> Repro -> Mature -> Harvest/Failed
/// with the date each stage was reached.
class StageTimeline extends StatelessWidget {
  const StageTimeline({super.key, required this.timeline});

  final List<StageMark> timeline;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('stage-timeline'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, m) in timeline.indexed)
          IntrinsicHeight(
            child: Row(
              key: ValueKey('timeline-${m.stage.label}'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 24,
                  child: Column(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: m.reached ? stageColor(m.stage) : AniColors.paper,
                          border: Border.all(
                            color: m.reached ? stageColor(m.stage) : AniColors.sand,
                            width: m.current ? 3 : 2,
                          ),
                        ),
                      ),
                      if (i < timeline.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: timeline[i + 1].reached ? AniColors.olive : AniColors.line,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AniSpacing.sm),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AniSpacing.md),
                    child: Wrap(
                      spacing: AniSpacing.sm,
                      runSpacing: AniSpacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          l.stageName(m.stage),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: m.reached ? AniColors.ink : AniColors.muted,
                            fontWeight: m.current ? FontWeight.w700 : null,
                          ),
                        ),
                        Text(
                          m.reachedOn == null ? l.stageNotYet : fmtDate(context, m.reachedOn!),
                          style: theme.textTheme.bodySmall?.copyWith(color: AniColors.muted),
                        ),
                        if (m.current) AniPill(l.stageNow, color: stageColor(m.stage)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Everything the detail of one planting shows. Used for the farmer's
/// plantings and for the demo replay alike.
class PlantingDetailBody extends StatelessWidget {
  const PlantingDetailBody({
    super.key,
    required this.view,
    this.onConfirmHarvest,
    this.onRemove,
    this.busy = false,
    this.demoNote = false,
    this.showConfirm = true,
  });

  final PlantingView view;
  final VoidCallback? onConfirmHarvest;
  final VoidCallback? onRemove;
  final bool busy;

  /// Show the "replay alerts are not saved" note above the alerts.
  final bool demoNote;

  /// Show "Confirm harvest" here when the crop is ready (the demo shows it
  /// with its own controls instead).
  final bool showConfirm;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = view.planting;
    final harvest = view.expectedHarvest;
    final closedOn = p.closedOn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AniCard(
          key: const ValueKey('planting-detail-summary'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Eyebrow(l.townName(p.town)),
                        const SizedBox(height: AniSpacing.xs),
                        Text(l.cropNameOf(p.crop), style: theme.textTheme.headlineSmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: AniSpacing.sm),
                  Flexible(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AniSpacing.xs,
                      runSpacing: AniSpacing.xs,
                      children: [
                        if (view.isDemo) AniPill(l.plantingDemoTag, color: AniColors.gold),
                        AniPill(l.stageName(view.stage),
                            key: const ValueKey('detail-stage'), color: stageColor(view.stage)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AniSpacing.sm),
              Text(
                [
                  l.plantingPlantedOn(fmtDate(context, p.plantedOn)),
                  l.methodName(p.method),
                  '${l.plantingIrrigation}: ${l.waterLevelName(p.water)}',
                ].join(' · '),
                style: theme.textTheme.bodyMedium?.copyWith(color: AniColors.muted),
              ),
              const SizedBox(height: AniSpacing.md),
              AniProgressBar(value: view.progress, color: stageColor(view.stage)),
              const SizedBox(height: AniSpacing.xs),
              Text(l.plantingProgress((view.progress * 100).round()), style: theme.textTheme.bodySmall),
              const SizedBox(height: AniSpacing.sm),
              if (p.closedAs == OutcomeResult.harvest && closedOn != null)
                _Line(
                  key: const ValueKey('detail-outcome'),
                  icon: Icons.check_circle_outline,
                  color: AniColors.statusNormal,
                  text: l.outcomeHarvested(fmtDate(context, closedOn)),
                  strong: true,
                )
              else if (p.closedAs == OutcomeResult.failed && closedOn != null)
                _Line(
                  key: const ValueKey('detail-outcome'),
                  icon: Icons.dangerous_outlined,
                  color: AniColors.statusDelikado,
                  text: l.outcomeFailed(fmtDate(context, closedOn)),
                  strong: true,
                ),
              if (view.readyOn != null && !view.isClosed)
                _Line(
                  icon: Icons.agriculture_outlined,
                  color: AniColors.statusNormal,
                  text: l.plantingReadySince(fmtDate(context, view.readyOn!)),
                ),
              if (harvest != null && !view.isClosed)
                _Line(
                  key: const ValueKey('detail-harvest-window'),
                  icon: Icons.event_outlined,
                  color: AniColors.olive,
                  text: l.expectedHarvest(fmtDate(context, harvest.start), fmtDate(context, harvest.end)),
                ),
              _Line(
                key: const ValueKey('detail-last-data'),
                icon: Icons.cloud_done_outlined,
                color: AniColors.muted,
                text: view.lastDataDay == null
                    ? l.plantingNoDataYet
                    : l.plantingLastData(fmtDate(context, view.lastDataDay!)),
              ),
              if (view.waitingForDataDays > 0) ...[
                _WaitingNote(days: view.waitingForDataDays, keyId: 'detail'),
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: AniSpacing.xxs),
                  child: Text(l.waitingForDataNote,
                      style: theme.textTheme.bodySmall?.copyWith(color: AniColors.muted)),
                ),
              ],
              if (showConfirm && view.canConfirmHarvest) ...[
                const SizedBox(height: AniSpacing.md),
                PrimaryButton(
                  key: const ValueKey('detail-confirm-harvest'),
                  label: l.confirmHarvest,
                  icon: Icons.check,
                  onPressed: busy ? null : onConfirmHarvest,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AniSpacing.md),
        AniCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Eyebrow(l.plantingStages),
              const SizedBox(height: AniSpacing.md),
              StageTimeline(timeline: view.timeline),
            ],
          ),
        ),
        const SizedBox(height: AniSpacing.md),
        AniCard(
          key: const ValueKey('detail-alerts'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Eyebrow(l.alertsTitle),
              if (demoNote) ...[
                const SizedBox(height: AniSpacing.xs),
                Text(l.alertsDemoNote, style: theme.textTheme.bodySmall?.copyWith(color: AniColors.muted)),
              ],
              const SizedBox(height: AniSpacing.sm),
              if (view.alerts.isEmpty)
                Text(l.plantingNoAlerts, style: theme.textTheme.bodyMedium?.copyWith(color: AniColors.muted))
              else
                AlertList(alerts: view.alerts, showCrop: false),
            ],
          ),
        ),
        if (onRemove != null) ...[
          const SizedBox(height: AniSpacing.lg),
          TextButton.icon(
            key: const ValueKey('detail-remove'),
            onPressed: busy ? null : onRemove,
            style: TextButton.styleFrom(foregroundColor: AniColors.statusDelikado),
            icon: const Icon(Icons.delete_outline),
            label: Text(l.plantingRemove),
          ),
        ],
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({super.key, required this.icon, required this.color, required this.text, this.strong = false});

  final IconData icon;
  final Color color;
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AniSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AniSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: strong
                  ? theme.textTheme.titleSmall?.copyWith(color: color)
                  : theme.textTheme.bodyMedium?.copyWith(color: AniColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
