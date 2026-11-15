import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../data/bundle.dart';
import '../../data/farm_store.dart';
import '../../data/tracker_service.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import '../alerts/alert_labels.dart';
import '../labels.dart';
import '../recommend/recommend_labels.dart';

/// Opens the add-planting form; [crop] preselects a crop (e.g. from a
/// recommendation card). Completes with the new planting's id, or null.
Future<String?> openAddPlanting(BuildContext context, {String? crop}) =>
    Navigator.of(context).push(MaterialPageRoute<String>(
      fullscreenDialog: true,
      builder: (_) => AddPlantingScreen(initialCrop: crop),
    ));

/// Add planting (doc Fig. 4): crop, planting date (not in the future),
/// method, irrigation level (prefilled from the planner profile) for the
/// app's current town. Saving replays the season from cached weather right
/// away and syncs POWER in the background, so it never waits on the network.
class AddPlantingScreen extends StatefulWidget {
  const AddPlantingScreen({super.key, this.initialCrop});

  final String? initialCrop;

  @override
  State<AddPlantingScreen> createState() => _AddPlantingScreenState();
}

class _AddPlantingScreenState extends State<AddPlantingScreen> {
  String? _crop;
  DateTime? _date;
  PlantingMethod _method = PlantingMethod.direct;
  String? _water;
  bool _waterFromProfile = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _crop = CropId.all.contains(widget.initialCrop) ? widget.initialCrop : null;
  }

  void _prefill(TrackerService t) {
    if (_water != null) return;
    _water = t.defaultWater;
    _waterFromProfile = AppScope.of(context).plannerProfile != null;
    _date ??= t.today;
  }

  Future<void> _pickDate(TrackerService t) async {
    final today = t.today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: DateTime(today.year - 1, today.month, today.day),
      lastDate: DateTime(today.year, today.month, today.day),
    );
    if (picked != null) setState(() => _date = DateTime.utc(picked.year, picked.month, picked.day));
  }

  Future<void> _save(TrackerService t, Town town) async {
    final crop = _crop, date = _date, water = _water;
    if (_busy || crop == null || date == null || water == null) return;
    final state = AppScope.of(context);
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final v = await t.addPlanting(
        town: town,
        crop: crop,
        plantedOn: date,
        method: _method,
        water: water,
        sync: false,
      );
      // POWER sync + notifications happen in the background.
      state.refreshTracker().ignore();
      state.requestNotificationPermissionOnce().ignore();
      messenger.showSnackBar(SnackBar(content: Text(l.plantingSaved)));
      navigator.pop(v.planting.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(l.plantingSaveError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final town = state.town;
    final t = state.trackerService;
    if (t == null) state.tracker().ignore();
    if (t != null) _prefill(t);
    final ready = t != null && town != null && _crop != null && _date != null && _water != null && !_busy;

    Widget section(String text) => Padding(
          padding: const EdgeInsets.only(top: AniSpacing.lg, bottom: AniSpacing.sm),
          child: Eyebrow(text),
        );
    Widget hint(String text) => Padding(
          padding: const EdgeInsets.only(top: AniSpacing.xs),
          child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: AniColors.muted)),
        );

    return Scaffold(
      key: const ValueKey('add-planting'),
      backgroundColor: AniColors.cream,
      appBar: AppBar(
        backgroundColor: AniColors.cream,
        elevation: 0,
        title: Text(l.myFarmAddPlanting),
        leading: IconButton(
          key: const ValueKey('add-planting-close'),
          tooltip: l.actionClose,
          icon: const Icon(Icons.close),
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                key: const ValueKey('add-planting-list'),
                padding: const EdgeInsets.fromLTRB(AniSpacing.screen, 0, AniSpacing.screen, AniSpacing.lg),
                children: [
                  if (town != null)
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 18, color: AniColors.olive),
                        const SizedBox(width: AniSpacing.xs),
                        Expanded(
                          child: Text('${l.plantingTownLabel}: ${l.townName(town)}',
                              key: const ValueKey('add-planting-town'), style: theme.textTheme.titleSmall),
                        ),
                      ],
                    ),
                  section(l.plantingCrop),
                  for (final id in CropId.all) ...[
                    ChoiceTile(
                      key: ValueKey('add-crop-$id'),
                      title: l.cropNameOf(id),
                      subtitle: l.cropGlossOf(id),
                      leading: const Icon(Icons.eco_outlined, color: AniColors.olive),
                      selected: _crop == id,
                      onTap: () => setState(() => _crop = id),
                    ),
                    const SizedBox(height: AniSpacing.sm),
                  ],
                  section(l.plantingDate),
                  OutlinedButton.icon(
                    key: const ValueKey('add-date'),
                    onPressed: t == null ? null : () => _pickDate(t),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      alignment: Alignment.centerLeft,
                      foregroundColor: AniColors.ink,
                      backgroundColor: AniColors.paper,
                      side: const BorderSide(color: AniColors.line),
                      shape: const RoundedRectangleBorder(borderRadius: AniRadius.tile),
                    ),
                    icon: const Icon(Icons.calendar_today_outlined, color: AniColors.olive),
                    label: Text(_date == null ? '' : fmtDate(context, _date!)),
                  ),
                  section(l.plantingMethod),
                  for (final m in PlantingMethod.values) ...[
                    ChoiceTile(
                      key: ValueKey('add-method-${m.name}'),
                      title: l.methodName(m),
                      selected: _method == m,
                      onTap: () => setState(() => _method = m),
                    ),
                    const SizedBox(height: AniSpacing.sm),
                  ],
                  hint(l.plantingMethodHint),
                  section(l.plantingIrrigation),
                  for (final w in WaterScenario.all) ...[
                    ChoiceTile(
                      key: ValueKey('add-water-$w'),
                      title: l.waterLevelName(w),
                      selected: _water == w,
                      onTap: () => setState(() => _water = w),
                    ),
                    const SizedBox(height: AniSpacing.sm),
                  ],
                  if (_waterFromProfile) hint(l.plantingIrrigationHint),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AniSpacing.screen, AniSpacing.sm, AniSpacing.screen, AniSpacing.lg),
              child: PrimaryButton(
                key: const ValueKey('add-save'),
                label: l.plantingSave,
                icon: Icons.check,
                onPressed: ready ? () => _save(t, town) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
