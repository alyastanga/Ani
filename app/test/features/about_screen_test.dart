import 'package:ani/features/about/about_screen.dart';
import 'package:ani/features/home/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/farm_harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  testWidgets('settings sheet opens About with limits and sources', (tester) async {
    final h = await FarmHarness.start(tester, today: DateTime.utc(2026, 11, 15));
    await h.pump(tester, Builder(
      builder: (context) => Scaffold(
        body: TextButton(onPressed: () => showSettingsSheet(context), child: const Text('settings')),
      ),
    ));
    await tester.tap(find.text('settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_key('settings-about'));
    await tester.tap(_key('settings-about'));
    await tester.pumpAndSettle();

    expect(find.text('About and limits'), findsOneWidget);
    expect(find.textContaining('One point per town'), findsOneWidget);
    expect(find.textContaining('Advisory only'), findsOneWidget);
    expect(find.textContaining('lower bound'), findsOneWidget);
    expect(find.textContaining('field trials'), findsOneWidget);
    for (final name in ['NASA POWER', 'ISRIC SoilGrids', 'NOAA CPC RONI', 'FAO-56', 'PSA OpenSTAT', 'PAGASA', 'MAO referral']) {
      expect(find.textContaining(name), findsOneWidget, reason: name);
    }
  });

  testWidgets('Filipino on a small phone: no overflow', (tester) async {
    final h = await FarmHarness.start(tester, locale: 'fil', size: const Size(360, 640), today: DateTime.utc(2026, 11, 15));
    await h.pump(tester, const AboutScreen());
    expect(find.text('Tungkol at mga limitasyon'), findsOneWidget);
    await tester.drag(_key('about-list'), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.textContaining('MAO referral'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
