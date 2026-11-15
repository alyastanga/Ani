import 'package:flutter/material.dart';

import '../../core/field_machine.dart' show FieldState;
import '../../core/season_replay.dart' show TrackerAlertType;
import '../../data/alert_notifier.dart';
import '../../data/farm_store.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import '../recommend/recommend_labels.dart';

/// Localized labels for the tracker (stages, alerts, methods).
extension TrackerLabels on AppLocalizations {
  String stageName(FieldState s) => switch (s) {
        FieldState.fallow || FieldState.prep => stagePrep,
        FieldState.estab => stageEstab,
        FieldState.veg => stageVeg,
        FieldState.repro => stageRepro,
        FieldState.mature => stageMature,
        FieldState.harvest => stageHarvest,
        FieldState.failed => stageFailed,
      };

  String alertTypeTitle(TrackerAlertType t) => switch (t) {
        TrackerAlertType.waterNow => alertWaterNow,
        TrackerAlertType.heatAtFlowering => alertHeatFlowering,
        TrackerAlertType.onionRot => alertOnionRot,
        TrackerAlertType.failed => alertFailed,
        TrackerAlertType.harvestReady => alertHarvestReady,
      };

  /// Short advice for an alert. Water-now says "irrigate today" when the
  /// machine's refill rule fired, and "short of water" when the crop is
  /// stressed (rainfed / out of irrigations). Failed adds "Kumonsulta sa MAO".
  String alertAdvice(AlertRecord a) => switch (a.type) {
        TrackerAlertType.waterNow => a.detail == 'stress' ? alertWaterStressBody : alertWaterNowBody,
        TrackerAlertType.heatAtFlowering => alertHeatFloweringBody,
        TrackerAlertType.onionRot => alertOnionRotBody,
        TrackerAlertType.failed => '$alertFailedBody $consultMao.',
        TrackerAlertType.harvestReady => alertHarvestReadyBody,
      };

  String methodName(PlantingMethod m) => switch (m) {
        PlantingMethod.direct => methodDirectSeed,
        PlantingMethod.transplant => methodTransplant,
      };
}

/// Icon for an alert type.
IconData alertIcon(TrackerAlertType t) => switch (t) {
      TrackerAlertType.waterNow => Icons.water_drop_outlined,
      TrackerAlertType.heatAtFlowering => Icons.thermostat_outlined,
      TrackerAlertType.onionRot => Icons.water_damage_outlined,
      TrackerAlertType.failed => Icons.dangerous_outlined,
      TrackerAlertType.harvestReady => Icons.agriculture_outlined,
    };

/// Status colour for an alert type.
Color alertColor(TrackerAlertType t) => switch (t) {
      TrackerAlertType.waterNow => AniColors.gold,
      TrackerAlertType.heatAtFlowering || TrackerAlertType.onionRot => AniColors.statusDelikado,
      TrackerAlertType.failed => AniColors.statusDelikado,
      TrackerAlertType.harvestReady => AniColors.statusNormal,
    };

/// Medium date in the app's locale (dates are UTC-midnight calendar days).
String fmtDate(BuildContext context, DateTime d) =>
    MaterialLocalizations.of(context).formatMediumDate(DateTime(d.year, d.month, d.day));

/// A run of alerts shown as one row: a single alert, or consecutive
/// water-now alerts of one planting (a season can have dozens) collapsed.
class AlertGroup {
  AlertGroup(this.alerts);

  /// Newest first.
  final List<AlertRecord> alerts;

  AlertRecord get latest => alerts.first;
  AlertRecord get earliest => alerts.last;
  TrackerAlertType get type => latest.type;
  int get count => alerts.length;
  bool get collapsed => alerts.length > 1;
}

/// Groups [alerts] (newest first): consecutive water-now alerts of the same
/// planting fold into one group; everything else stays on its own.
List<AlertGroup> groupAlerts(List<AlertRecord> alerts) {
  final out = <AlertGroup>[];
  for (final a in alerts) {
    final last = out.isEmpty ? null : out.last;
    if (last != null &&
        a.type == TrackerAlertType.waterNow &&
        last.type == TrackerAlertType.waterNow &&
        last.latest.plantingId == a.plantingId) {
      last.alerts.add(a);
    } else {
      out.add(AlertGroup([a]));
    }
  }
  return out;
}

/// Notifications for newly emitted alerts: the farmer's own only (demo
/// alerts are dropped), and at most one per planting and alert type (the
/// newest), so a sync that fills in a week of data does not buzz 7 times.
List<AlertNotice> noticesFor(AppLocalizations l, Iterable<AlertRecord> fresh) {
  final newest = <String, AlertRecord>{};
  for (final a in fresh) {
    if (a.isDemo) continue;
    final k = '${a.plantingId}|${a.type.name}';
    final cur = newest[k];
    if (cur == null || a.date.isAfter(cur.date)) newest[k] = a;
  }
  return [
    for (final a in newest.values)
      AlertNotice(
        id: noticeIdFor(a.id),
        title: '${l.cropNameOf(a.crop)}: ${l.alertTypeTitle(a.type)}',
        body: l.alertAdvice(a),
      ),
  ];
}
