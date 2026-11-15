import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/heat_index.dart';
import '../../data/live_outlook.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import '../labels.dart';

/// PAGASA band name (matches `heat.index_categories_c[].label`), or null for none.
String? bandLabel(PagasaBand b) => b.bundleLabel;

Color bandColor(PagasaBand b) => switch (b) {
      PagasaBand.danger || PagasaBand.extremeDanger => AniColors.statusDelikado,
      PagasaBand.none => AniColors.statusNormal,
      _ => AniColors.gold,
    };

String _hi(double v) => v.toStringAsFixed(1);

/// "Caution · 31.2" style pill text for a reading.
String heatBandText(AppLocalizations l, HeatDay h) {
  final label = bandLabel(h.band);
  final name = label == null ? l.dryNormal : l.heatCategoryName(label);
  return '$name · ${l.heatIndexValue(_hi(h.hi))}';
}

/// The latest live heat reading with the as-of date. On danger days it adds
/// "Magtrabaho nang maaga". People-safety advice only: nothing here feeds the
/// planner or the field machine.
class LiveHeatReading extends StatelessWidget {
  const LiveHeatReading({super.key, required this.live});

  final LiveOutlook? live;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final h = live?.latestHeat;
    if (h == null) {
      return Text(
        l.heatNoLive,
        key: const ValueKey('heat-no-live'),
        style: theme.textTheme.bodySmall?.copyWith(color: AniColors.muted),
      );
    }
    final color = bandColor(h.band);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AniSpacing.sm,
          runSpacing: AniSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AniPill(heatBandText(l, h), key: const ValueKey('heat-live-reading'), color: color),
            Text(
              l.heatAsOf(DateFormat.MMMd(l.localeName).format(h.date)),
              style: theme.textTheme.bodySmall?.copyWith(color: AniColors.muted),
            ),
          ],
        ),
        if (h.isDanger) ...[
          const SizedBox(height: AniSpacing.xs),
          Text(
            l.workEarly,
            key: const ValueKey('heat-live-work-early'),
            style: theme.textTheme.titleSmall?.copyWith(color: AniColors.statusDelikado),
          ),
          Text(l.heatDangerToday, style: theme.textTheme.bodySmall?.copyWith(color: AniColors.statusDelikado)),
        ],
      ],
    );
  }
}

/// Heat-safety card for the Outlook tab: latest reading, recent days and the
/// PAGASA bands.
class HeatSafetyCard extends StatelessWidget {
  const HeatSafetyCard({super.key, required this.live});

  final LiveOutlook? live;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final heat = live?.heat ?? const <HeatDay>[];
    final dangerDays = live?.dangerDays ?? 0;
    return AniCard(
      key: const ValueKey('outlook-heat'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.thermostat_outlined, color: AniColors.gold),
              const SizedBox(width: AniSpacing.sm),
              Expanded(child: Eyebrow(l.heatSafetyTitle)),
            ],
          ),
          const SizedBox(height: AniSpacing.sm),
          LiveHeatReading(live: live),
          if (heat.length > 1) ...[
            const SizedBox(height: AniSpacing.md),
            Eyebrow(l.heatRecentTitle),
            const SizedBox(height: AniSpacing.xs),
            Wrap(
              spacing: AniSpacing.xs,
              runSpacing: AniSpacing.xs,
              children: [
                for (final h in heat)
                  AniPill(
                    '${DateFormat.Md(l.localeName).format(h.date)} ${_hi(h.hi)}°',
                    color: bandColor(h.band),
                  ),
              ],
            ),
            if (dangerDays > 0) ...[
              const SizedBox(height: AniSpacing.sm),
              Text(
                l.heatDangerDays(dangerDays),
                key: const ValueKey('outlook-heat-danger-days'),
                style: theme.textTheme.bodySmall?.copyWith(color: AniColors.statusDelikado),
              ),
            ],
          ],
          const SizedBox(height: AniSpacing.sm),
          Text(l.heatSafetyNote, style: theme.textTheme.bodySmall?.copyWith(color: AniColors.muted)),
        ],
      ),
    );
  }
}
