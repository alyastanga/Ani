import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../data/tracker_service.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import 'planting_widgets.dart';
import 'tracker_builder.dart';

/// Opens the detail of one of the farmer's plantings.
Future<void> openPlantingDetail(BuildContext context, String plantingId) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => PlantingDetailScreen(plantingId: plantingId)));

/// Detail of a real planting: timeline, harvest window, last data day,
/// alerts, confirm harvest, outcome, remove.
class PlantingDetailScreen extends StatefulWidget {
  const PlantingDetailScreen({super.key, required this.plantingId});

  final String plantingId;

  @override
  State<PlantingDetailScreen> createState() => _PlantingDetailScreenState();
}

class _PlantingDetailScreenState extends State<PlantingDetailScreen> {
  bool _busy = false;

  Future<void> _confirm(TrackerService t) async {
    setState(() => _busy = true);
    try {
      await t.confirmHarvest(widget.plantingId);
    } catch (e) {
      debugPrint('confirm harvest failed: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove(TrackerService t) async {
    final l = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.plantingRemoveConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.actionCancel)),
          TextButton(
            key: const ValueKey('remove-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AniColors.statusDelikado),
            child: Text(l.actionRemove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    await t.removePlanting(widget.plantingId);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      key: const ValueKey('planting-detail'),
      backgroundColor: AniColors.cream,
      appBar: AppBar(backgroundColor: AniColors.cream, elevation: 0, title: Text(l.plantingDetailTitle)),
      body: SafeArea(
        child: TrackerBuilder(builder: (context, t) {
          final v = t?.viewFor(widget.plantingId);
          if (t == null || v == null) {
            return const Center(child: CircularProgressIndicator(color: AniColors.olive));
          }
          return ListView(
            key: const ValueKey('planting-detail-list'),
            padding: const EdgeInsets.fromLTRB(AniSpacing.screen, AniSpacing.sm, AniSpacing.screen, AniSpacing.xxl),
            children: [
              if (AppScope.of(context).lastTrackerRefresh?.offline ?? false) ...[
                const SyncStatusLine(),
                const SizedBox(height: AniSpacing.sm),
              ],
              PlantingDetailBody(
                view: v,
                busy: _busy,
                onConfirmHarvest: () => _confirm(t),
                onRemove: () => _remove(t),
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// Unobtrusive one-line sync state: updating / offline / last updated.
class SyncStatusLine extends StatelessWidget {
  const SyncStatusLine({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final r = state.lastTrackerRefresh;
    final at = state.lastTrackerRefreshAt;
    final (IconData icon, String text, Color color) = state.trackerRefreshing
        ? (Icons.sync, l.syncUpdating, AniColors.muted)
        : (r?.offline ?? false)
            ? (Icons.cloud_off_outlined, l.offlineNote, AniColors.gold)
            : at != null && (r?.syncs.isNotEmpty ?? false)
                ? (Icons.cloud_done_outlined, l.lastUpdated(TimeOfDay.fromDateTime(at).format(context)), AniColors.muted)
                : (Icons.cloud_queue, '', AniColors.muted);
    if (text.isEmpty) return const SizedBox.shrink(key: ValueKey('sync-status-none'));
    return Row(
      key: const ValueKey('sync-status'),
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AniSpacing.xs),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color))),
      ],
    );
  }
}
