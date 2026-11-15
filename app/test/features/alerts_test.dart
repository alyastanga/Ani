import 'package:ani/core/season_replay.dart';
import 'package:ani/data/alert_notifier.dart';
import 'package:ani/data/bundle.dart';
import 'package:ani/data/farm_store.dart';
import 'package:ani/features/alerts/alert_labels.dart';
import 'package:ani/features/alerts/alerts_screen.dart';
import 'package:ani/features/home/home_screen.dart';
import 'package:ani/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/farm_harness.dart';
import '../support/tracker_fixtures.dart';

Finder _key(String k) => find.byKey(ValueKey(k));
Finder _in(String k, Finder f) => find.descendant(of: _key(k), matching: f);

AlertRecord _a(String pid, TrackerAlertType t, int day, {String? detail}) => AlertRecord(
      id: AlertRecord.idFor(pid, t, DateTime.utc(2023, 1, day)),
      type: t,
      date: DateTime.utc(2023, 1, day),
      plantingId: pid,
      crop: CropId.maize,
      detail: detail,
    );

void main() {
  test('consecutive water-now alerts of one planting collapse; others stay apart', () {
    final alerts = [
      _a('p1', TrackerAlertType.harvestReady, 20),
      _a('p1', TrackerAlertType.waterNow, 18, detail: 'irrigate'),
      _a('p1', TrackerAlertType.waterNow, 15, detail: 'irrigate'),
      _a('p2', TrackerAlertType.waterNow, 14, detail: 'stress'),
      _a('p1', TrackerAlertType.waterNow, 12, detail: 'irrigate'),
      _a('p1', TrackerAlertType.heatAtFlowering, 10),
      _a('p1', TrackerAlertType.waterNow, 8, detail: 'irrigate'),
    ];
    final g = groupAlerts(alerts);
    expect([for (final x in g) x.count], [1, 2, 1, 1, 1, 1]);
    expect(g[1].latest.date.day, 18);
    expect(g[1].earliest.date.day, 15);
  });

  test('notices: one per planting and type, newest; demo alerts dropped; doc strings stay Filipino', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final demo = AlertRecord(
        id: 'd|failed|2023-01-01', type: TrackerAlertType.failed, date: DateTime.utc(2023), plantingId: 'd', crop: 'rice', isDemo: true);
    final n = noticesFor(en, [
      _a('p1', TrackerAlertType.waterNow, 3, detail: 'irrigate'),
      _a('p1', TrackerAlertType.waterNow, 9, detail: 'stress'),
      _a('p1', TrackerAlertType.failed, 10),
      demo,
    ]);
    expect(n, hasLength(2));
    expect(n.map((x) => x.title), containsAll(['Mais: Water now', 'Mais: Crop failed']));
    expect(n.firstWhere((x) => x.title.contains('Water')).body, en.alertWaterStressBody);
    expect(n.firstWhere((x) => x.title.contains('failed')).body, contains('Kumonsulta sa MAO'));
    expect(noticesFor(en, [demo]), isEmpty);
  });

  testWidgets('bell badge, alerts list newest first with water-now collapsed, opening marks seen', (tester) async {
    final c = fixtureCase('guimba|maize|2022-23|full');
    final days = fixtureWeather(c);
    final h = await FarmHarness.start(tester, today: addDays(days.last.date, 1), weather: {Town.guimba: days});
    await h.tracker.addPlanting(
        town: Town.guimba, crop: CropId.maize, plantedOn: days.first.date, water: 'full', s0Frac: n(c['s0_frac']), sync: false);
    final unseen = h.tracker.unseenAlertCount;
    expect(unseen, greaterThan(3));
    final irrigate = h.tracker.alerts.where((a) => a.type == TrackerAlertType.waterNow).length;
    expect(irrigate, greaterThan(1));

    await h.pump(tester, const Scaffold(body: HomeScreen()));
    expect(_in('alerts-badge', find.text('$unseen')), findsOneWidget);

    // Home: the tracked crop with its stage, and the latest alerts.
    expect(_in('home-crops', find.text('Mais')), findsOneWidget);
    expect(_in('home-crops', find.text('Maturing')), findsOneWidget);
    expect(_in('home-alerts', find.text('Ready to harvest')), findsOneWidget);
    expect(_key('home-alerts-empty'), findsNothing);

    await tester.tap(_key('alerts-bell'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertsScreen), findsOneWidget);

    // Newest first: harvest-ready is the last event of the season.
    final titles = tester
        .widgetList<Text>(_in('alerts-list', find.byType(Text)))
        .map((t) => t.data)
        .where((s) => s == 'Ready to harvest' || s == 'Water now')
        .toList();
    expect(titles.first, 'Ready to harvest');
    // Water-now runs are collapsed: fewer rows than alerts, with a count.
    expect(titles.where((s) => s == 'Water now').length, lessThan(irrigate));
    expect(_key('alert-times'), findsWidgets);
    // Unseen ones keep their "New" tag while the screen is open...
    expect(_key('alert-new'), findsWidgets);
    // ...but are now stored as seen.
    expect(h.tracker.unseenAlertCount, 0);

    // A collapsed run expands to its dates.
    final times = _key('alert-times').first;
    await tester.tap(times);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    final badge = tester.widget<Badge>(_key('alerts-badge'));
    expect(badge.isLabelVisible, isFalse);
  });

  testWidgets('empty alerts list', (tester) async {
    final h = await FarmHarness.start(tester, today: DateTime.utc(2023, 1, 1));
    await h.pump(tester, const AlertsScreen());
    expect(_key('alerts-empty'), findsOneWidget);
  });

  testWidgets('refresh notifies new real alerts only, never demo ones', (tester) async {
    final c = fixtureCase('guimba|rice|2023-24|rainfed');
    final days = fixtureWeather(c);
    final h = await FarmHarness.start(tester, today: days.first.date, weather: {Town.guimba: days});
    // On the planting day nothing has happened yet.
    await h.tracker.addPlanting(
        town: Town.guimba, crop: CropId.rice, plantedOn: days.first.date, water: 'rainfed', isDemo: true, sync: false);
    final real = await h.tracker.addPlanting(
        town: Town.guimba, crop: CropId.rice, plantedOn: days.first.date, water: 'rainfed', sync: false);
    expect(h.tracker.alerts, isEmpty);
    await h.state.refreshTracker();
    expect(h.notifier.shown, isEmpty);

    // The season's data arrives: both plantings emit alerts.
    h.today = addDays(days.last.date, 1);
    final r = await h.state.refreshTracker();
    expect(r!.newAlerts.where((a) => a.isDemo), isNotEmpty);
    expect(r.newAlerts.where((a) => !a.isDemo), isNotEmpty);
    expect(h.notifier.shown, hasLength(1));
    final notices = h.notifier.shown.single;
    final realKeys = {
      for (final a in r.newAlerts)
        if (a.plantingId == real.planting.id) a.type.name
    };
    expect(notices, hasLength(realKeys.length));
    final realIds = {for (final a in r.newAlerts) if (!a.isDemo) noticeIdFor(a.id)};
    final demoIds = {for (final a in r.newAlerts) if (a.isDemo) noticeIdFor(a.id)};
    expect(notices.every((x) => realIds.contains(x.id)), isTrue);
    expect(notices.any((x) => demoIds.contains(x.id)), isFalse, reason: 'no demo notices');
    expect(notices.every((x) => x.title.startsWith('Palay: ')), isTrue);

    // Nothing new on the next refresh: no second notification.
    await h.state.refreshTracker();
    expect(h.notifier.shown, hasLength(1));
  });

  testWidgets('small phone in Filipino: home alerts and alerts list have no overflow', (tester) async {
    final c = fixtureCase('guimba|maize|2022-23|full');
    final days = fixtureWeather(c);
    final r = fixtureCase('guimba|rice|2022-23|full');
    final h = await FarmHarness.start(tester,
        locale: 'fil', size: const Size(360, 640), today: addDays(days.last.date, 1), weather: {Town.guimba: days});
    await h.tracker.addPlanting(
        town: Town.guimba, crop: CropId.maize, plantedOn: days.first.date, water: 'full', s0Frac: n(c['s0_frac']), sync: false);
    await h.tracker.addPlanting(
        town: Town.guimba, crop: CropId.rice, plantedOn: days.first.date, water: 'full', s0Frac: n(r['s0_frac']), sync: false);
    await h.pump(tester, const Scaffold(body: HomeScreen()));
    await scrollThrough(tester, _key('home-list'), steps: 12);

    await tester.drag(_key('home-list'), const Offset(0, 8000));
    await tester.pumpAndSettle();
    await tester.tap(_key('alerts-bell'));
    await tester.pumpAndSettle();
    expect(find.text('Mga babala'), findsWidgets);
    // Expand every collapsed run while scrolling through.
    for (var i = 0; i < 20; i++) {
      for (final e in _key('alert-times').hitTestable().evaluate().toList()) {
        await tester.tap(find.byWidget(e.widget), warnIfMissed: false);
        await tester.pumpAndSettle();
      }
      await tester.drag(_key('alerts-list'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
