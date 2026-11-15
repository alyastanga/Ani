import 'package:ani/data/bundle.dart';
import 'package:ani/data/power_client.dart';
import 'package:ani/features/home/home_screen.dart';
import 'package:ani/features/outlook/outlook_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/live_outlook_test.dart' show weatherDays;
import '../support/farm_harness.dart';

final _today = DateTime.utc(2026, 11, 15);

Future<FarmHarness> _start(WidgetTester tester, List<DailyWeather> days, {String locale = 'en'}) async {
  final h = await FarmHarness.start(tester,
      locale: locale, today: _today, weather: {Town.guimba: days}, size: const Size(900, 4000));
  await h.pump(tester, const Scaffold(body: OutlookScreen()));
  await tester.runAsync(() => h.state.refreshLive());
  await tester.pumpAndSettle();
  return h;
}

Finder _in(String key, Finder f) => find.descendant(of: find.byKey(ValueKey(key)), matching: f);

void main() {
  setUp(BundleLoader.instance.clear);

  testWidgets('offline (empty cache): bundled dryness.latest, El Niño tag, past seasons, chart', (tester) async {
    final h = await _start(tester, const []);
    final b = h.state.bundle!;
    expect(_in('outlook-enso', find.text('Inaasahan ang El Niño ngayong tag-araw')), findsOneWidget);
    expect(_in('outlook-enso', find.text('Very strong')), findsOneWidget);
    // bundled fallback
    expect(_in('outlook-live', find.text('Normal')), findsOneWidget);
    expect(_in('outlook-live', find.text('D -1.45')), findsOneWidget);
    expect(find.byKey(const ValueKey('outlook-live-source')), findsOneWidget);
    expect(find.textContaining('Saved reading for ${b.dryness.latest.month}'), findsOneWidget);
    // past seasons with tags
    expect(_in('outlook-past', find.text('2015-16 El Niño')), findsOneWidget);
    expect(_in('outlook-past', find.text('2022-23 La Niña')), findsOneWidget);
    expect(_in('outlook-past', find.text('2024-25 Neutral')), findsOneWidget);
    // chart + legend
    expect(find.byKey(const ValueKey('outlook-chart')), findsOneWidget);
    expect(find.byKey(const ValueKey('outlook-chart-legend')), findsOneWidget);
    // heat: no live data
    expect(find.byKey(const ValueKey('heat-no-live')), findsOneWidget);
    expect(find.text('Magtrabaho nang maaga'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live dry cache: live D, Delikado and the dekad list replace the bundled value', (tester) async {
    final h = await _start(tester, weatherDays(DateTime.utc(2026, 1, 1), DateTime.utc(2026, 11, 14), et0: 7, gwet: 0.05));
    final live = h.state.live!;
    expect(live.hasLiveD, isTrue);
    expect(tester.widget<Text>(find.byKey(const ValueKey('outlook-live-label'))).data, 'Delikado');
    expect(find.textContaining('Live from NASA POWER'), findsOneWidget);
    expect(_in('outlook-live', find.textContaining('so far')), findsOneWidget);
    expect(find.textContaining('Saved reading'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('danger-day heat shows Magtrabaho nang maaga on Outlook and Home', (tester) async {
    final days = [
      ...weatherDays(DateTime.utc(2026, 11, 1), DateTime.utc(2026, 11, 10)),
      ...weatherDays(DateTime.utc(2026, 11, 11), DateTime.utc(2026, 11, 13), tmax: 38, tdew: 28),
    ];
    final h = await _start(tester, days);
    expect(_in('outlook-heat', find.byKey(const ValueKey('heat-live-work-early'))), findsOneWidget);
    expect(find.byKey(const ValueKey('outlook-heat-danger-days')), findsOneWidget);
    expect(_in('outlook-heat', find.byKey(const ValueKey('heat-live-reading'))), findsOneWidget);
    await h.pump(tester, const Scaffold(body: HomeScreen()));
    expect(_in('home-heat', find.byKey(const ValueKey('heat-live-reading'))), findsOneWidget);
    expect(_in('home-heat', find.byKey(const ValueKey('heat-live-work-early'))), findsOneWidget);
  });

  testWidgets('cool day: live reading but no work-early line from the live reading; Filipino strings', (tester) async {
    final h = await _start(tester, weatherDays(DateTime.utc(2026, 11, 1), DateTime.utc(2026, 11, 13), tmax: 29, tdew: 20),
        locale: 'fil');
    expect(find.byKey(const ValueKey('heat-live-reading')), findsOneWidget);
    expect(find.byKey(const ValueKey('heat-live-work-early')), findsNothing);
    expect(find.text('Tanaw sa panahon'), findsOneWidget);
    expect(find.textContaining('Naka-save na basa'), findsOneWidget); // 13 days cached: too thin to score, bundled D
    expect(h.l.localeName, 'fil');
  });
}
