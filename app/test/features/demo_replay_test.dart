import 'package:ani/core/season_replay.dart';
import 'package:ani/data/bundle.dart';
import 'package:ani/features/alerts/alert_labels.dart';
import 'package:ani/features/farm/demo_screen.dart';
import 'package:ani/features/farm/farm_screen.dart';
import 'package:ani/features/home/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/farm_harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));
Finder _in(String k, Finder f) => find.descendant(of: _key(k), matching: f);

String _day(WidgetTester tester) => tester.widget<Text>(_key('demo-day')).data!;

/// Runs the open replay to its end (confirming the harvest when offered).
Future<void> _runToEnd(WidgetTester tester) async {
  await tester.tap(_key('demo-run'));
  await tester.pumpAndSettle();
  if (_key('demo-ended').evaluate().isEmpty) {
    // Ready to harvest: the season waits for the farmer's confirm, which
    // sits with the replay controls.
    expect(_in('demo-controls', _key('detail-confirm-harvest')), findsOneWidget);
    expect(_key('demo-run'), findsOneWidget);
    await tester.tap(_key('detail-confirm-harvest'));
    await tester.pumpAndSettle();
  }
  expect(_key('demo-ended'), findsOneWidget);
}

void main() {
  testWidgets('replays all three seasons to the end; together they show every alert type', (tester) async {
    final h = await FarmHarness.start(tester, today: DateTime.utc(2026, 11, 15));
    await h.pump(tester, const Scaffold(body: FarmScreen()));
    final l = h.l;

    await tester.tap(_key('farm-demo'));
    await tester.pumpAndSettle();
    expect(_key('demo-picker'), findsOneWidget);
    expect(_key('demo-banner'), findsOneWidget);
    expect(find.text('Replay of a past season – not live data'), findsOneWidget);

    final seen = <TrackerAlertType>{};
    for (final town in Town.values) {
      await tester.tap(_key('demo-season-${town.id}'));
      await tester.pumpAndSettle();
      expect(_key('demo-replay'), findsOneWidget);
      // The banner stays on screen for the whole replay.
      expect(_key('demo-banner'), findsOneWidget);
      expect(_in('detail-stage', find.text('Prep')), findsOneWidget);
      expect(_day(tester), contains('Day 0 of'));

      await tester.tap(_key('demo-next-day'));
      await tester.pumpAndSettle();
      expect(_day(tester), contains('Day 1 of'));
      await tester.tap(_key('demo-next-week'));
      await tester.pumpAndSettle();
      expect(_day(tester), contains('Day 8 of'));

      await _runToEnd(tester);
      expect(_key('detail-outcome'), findsOneWidget);
      for (final t in TrackerAlertType.values) {
        if (_in('detail-alerts', find.text(l.alertTypeTitle(t))).evaluate().isNotEmpty) seen.add(t);
      }
      // Demo rows are tagged.
      expect(find.text('Demo'), findsWidgets);
      expect(find.text(l.alertsDemoNote), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(seen, TrackerAlertType.values.toSet());

    // Nothing reached the farmer's records or the notifier.
    expect(h.tracker.store.plantings(), isEmpty);
    expect(h.tracker.alerts, isEmpty);
    expect(h.tracker.outcomes, isEmpty);
    expect(h.notifier.shown, isEmpty);
    expect(h.notifier.permissionRequests, 0);
  });

  testWidgets('start over resets the replay', (tester) async {
    final h = await FarmHarness.start(tester, today: DateTime.utc(2026, 11, 15));
    final seasons = demoSeasonsFromFile();
    await h.pump(tester, DemoReplayScreen(season: seasons.first));
    await tester.tap(_key('demo-next-week'));
    await tester.pumpAndSettle();
    expect(_day(tester), contains('Day 7 of'));
    await tester.tap(_key('demo-restart'));
    await tester.pumpAndSettle();
    expect(_day(tester), contains('Day 0 of'));
  });

  testWidgets('settings sheet opens the replay', (tester) async {
    final h = await FarmHarness.start(tester, today: DateTime.utc(2026, 11, 15));
    await h.pump(tester, Builder(
      builder: (context) => Scaffold(
        body: TextButton(onPressed: () => showSettingsSheet(context), child: const Text('settings')),
      ),
    ));
    await tester.tap(find.text('settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_key('settings-demo'));
    await tester.tap(_key('settings-demo'));
    await tester.pumpAndSettle();
    expect(_key('demo-picker'), findsOneWidget);
  });

  testWidgets('small phone in Filipino: picker and replay have no overflow', (tester) async {
    final h = await FarmHarness.start(tester, locale: 'fil', size: const Size(360, 640), today: DateTime.utc(2026, 11, 15));
    await h.pump(tester, const DemoPickerScreen());
    expect(find.text('Replay ng nakaraang panahon – hindi live na datos'), findsOneWidget);
    await scrollThrough(tester, _key('demo-seasons'), steps: 4);
    for (final town in Town.values) {
      await tester.drag(_key('demo-seasons'), const Offset(0, 2000));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(_key('demo-season-${town.id}'), 150,
          scrollable: find.descendant(of: _key('demo-seasons'), matching: find.byType(Scrollable)).first);
      await tester.pumpAndSettle();
      await tester.tap(_key('demo-season-${town.id}'));
      await tester.pumpAndSettle();
      await _runToEnd(tester);
      await tester.drag(_key('demo-list'), const Offset(0, 5000));
      await tester.pumpAndSettle();
      await scrollThrough(tester, _key('demo-list'), steps: 15);
      // Expand any collapsed water-now run.
      final times = _key('alert-times');
      if (times.evaluate().isNotEmpty) {
        await tester.ensureVisible(times.first);
        await tester.pumpAndSettle();
        await tester.tap(times.first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }
  });
}
