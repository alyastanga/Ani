import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_state.dart';
import '../../data/bundle.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import '../labels.dart';

/// Crop library: the five crops with duration, sowing window, family and water
/// need; tapping one opens a detail sheet with the failed-X-of-N table by
/// irrigation level for the selected town.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final bundle = state.bundle;
    final town = state.town;
    return SafeArea(
      child: ListView(
        key: const ValueKey('library-list'),
        padding: const EdgeInsets.fromLTRB(AniSpacing.screen, AniSpacing.sm, AniSpacing.screen, AniSpacing.xxl),
        children: [
          Text(l.libraryTitle, style: theme.textTheme.headlineMedium),
          if (town != null)
            Padding(
              padding: const EdgeInsets.only(top: AniSpacing.xs),
              child: Text(l.cropLibrarySubtitle(l.townName(town)),
                  style: theme.textTheme.bodyMedium?.copyWith(color: AniColors.muted)),
            ),
          const SizedBox(height: AniSpacing.lg),
          if (bundle == null)
            state.bundleError != null
                ? AniCard(key: const ValueKey('library-error'), child: Text(l.bundleLoadError))
                : const Padding(
                    padding: EdgeInsets.all(AniSpacing.xxl),
                    child: Center(child: CircularProgressIndicator(color: AniColors.olive)),
                  )
          else
            for (final id in CropId.all)
              if (bundle.crops[id] case final crop?)
                Padding(
                  padding: const EdgeInsets.only(bottom: AniSpacing.md),
                  child: _CropCard(crop: crop, bundle: bundle),
                ),
        ],
      ),
    );
  }
}

/// Qualitative water need per crop (rice is a lower bound; see the About page).
String waterNeedLabel(AppLocalizations l, String cropId) => switch (cropId) {
      CropId.rice => l.cropWaterNeedHigh,
      CropId.onion || CropId.maize => l.cropWaterNeedMedium,
      _ => l.cropWaterNeedLow,
    };

/// "Nov 16 to Dec 16": the sowing window counted from 1 November.
String sowWindowText(AppLocalizations l, CropInfo crop) {
  final f = DateFormat.MMMd(l.localeName);
  // Any non-leap year: only month and day are shown.
  final nov1 = DateTime.utc(2025, 11, 1);
  return l.cropSowWindowRange(
    f.format(nov1.add(Duration(days: crop.sowWindowStart))),
    f.format(nov1.add(Duration(days: crop.sowWindowEnd))),
  );
}

class _CropCard extends StatelessWidget {
  const _CropCard({required this.crop, required this.bundle});

  final CropInfo crop;
  final AniBundle bundle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AniCard(
      key: ValueKey('library-crop-${crop.id}'),
      padding: const EdgeInsets.all(AniSpacing.lg),
      onTap: () => showCropSheet(context, crop: crop, bundle: bundle),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(l.cropName(crop), style: theme.textTheme.titleLarge)),
              AniPill(l.cropDurationDays(crop.durationDays)),
              const SizedBox(width: AniSpacing.xs),
              const Icon(Icons.chevron_right, color: AniColors.muted),
            ],
          ),
          const SizedBox(height: AniSpacing.sm),
          Text('${l.cropSowingWindow}: ${sowWindowText(l, crop)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: AniColors.muted)),
          Text('${l.cropWaterNeed}: ${waterNeedLabel(l, crop.id)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: AniColors.muted)),
        ],
      ),
    );
  }
}

/// Opens the crop detail sheet (Make-style cream sheet with a drag handle).
Future<void> showCropSheet(BuildContext context, {required CropInfo crop, required AniBundle bundle}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AniColors.cream,
    showDragHandle: true,
    builder: (_) => CropSheet(crop: crop, bundle: bundle),
  );
}

class CropSheet extends StatelessWidget {
  const CropSheet({super.key, required this.crop, required this.bundle});

  final CropInfo crop;
  final AniBundle bundle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final town = bundle.meta.town;
    final townLabel = town == null ? bundle.meta.muni : l.townName(town);
    final waters = [for (final w in WaterScenario.all) if (bundle.risk.row(w, crop.id) != null) w];
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('crop-sheet'),
        padding: const EdgeInsets.fromLTRB(AniSpacing.screen, 0, AniSpacing.screen, AniSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.cropName(crop), style: theme.textTheme.headlineSmall),
            const SizedBox(height: AniSpacing.md),
            AniCard(
              padding: const EdgeInsets.all(AniSpacing.md),
              child: Column(
                children: [
                  _Fact(l.cropDurationLabel, l.cropDurationDays(crop.durationDays)),
                  _Fact(l.cropSowingWindow, sowWindowText(l, crop)),
                  _Fact(l.cropFamily, crop.family),
                  _Fact(l.cropWaterNeed, waterNeedLabel(l, crop.id)),
                ],
              ),
            ),
            if (crop.id == CropId.rice) _Note(l.cropWaterNeedRiceNote),
            if (crop.legume) _Note(l.cropLegumeNote),
            if (crop.smallMarket) _Note(l.cropSmallMarketNote),
            const SizedBox(height: AniSpacing.lg),
            Eyebrow(l.cropRiskByIrrigation),
            const SizedBox(height: AniSpacing.sm),
            AniCard(
              key: const ValueKey('crop-risk-table'),
              padding: const EdgeInsets.all(AniSpacing.md),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(flex: 5, child: Text(l.cropRiskIrrigationColumn, style: _head(theme))),
                      Expanded(flex: 3, child: Text(l.cropRiskElNinoSeasons, style: _head(theme))),
                      Expanded(flex: 3, child: Text(l.cropRiskOtherSeasons, style: _head(theme))),
                    ],
                  ),
                  const Divider(height: AniSpacing.lg),
                  for (final w in waters)
                    Padding(
                      key: ValueKey('crop-risk-$w'),
                      padding: const EdgeInsets.symmetric(vertical: AniSpacing.xs),
                      child: Row(
                        children: [
                          Expanded(flex: 5, child: Text(_waterName(l, w), style: theme.textTheme.bodyMedium)),
                          for (final m in [bundle.risk.row(w, crop.id)!.elNino, bundle.risk.row(w, crop.id)!.other])
                            Expanded(
                              flex: 3,
                              child: Text(l.cropFailedOf(m.failX, m.failN),
                                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AniSpacing.sm),
            Text(l.cropRiskNote(townLabel),
                style: theme.textTheme.bodySmall?.copyWith(color: AniColors.muted)),
            const SizedBox(height: AniSpacing.lg),
            PrimaryButton(label: l.actionClose, onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }

  static TextStyle? _head(ThemeData t) =>
      t.textTheme.bodySmall?.copyWith(color: AniColors.muted, fontWeight: FontWeight.w600);

  static String _waterName(AppLocalizations l, String w) => switch (w) {
        WaterScenario.rainfed => l.waterRainfed,
        WaterScenario.limited2 => l.waterLimited2,
        WaterScenario.limited4 => l.waterLimited4,
        _ => l.waterFull,
      };
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AniSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: AniColors.muted))),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AniSpacing.sm),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AniColors.muted)),
      );
}
