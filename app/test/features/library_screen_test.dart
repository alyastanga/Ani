import 'package:ani/app_state.dart';
import 'package:ani/data/bundle.dart';
import 'package:ani/data/settings_store.dart';
import 'package:ani/features/library/library_screen.dart';
import 'package:ani/l10n/app_localizations.dart';
import 'package:ani/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> _start(WidgetTester tester, {String locale = 'en', Town town = Town.guimba}) async {
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    SettingsStore.keyLocale: locale,
    SettingsStore.keyTown: town.id,
    SettingsStore.keyOnboardingComplete: true,
  });
  final state = AppState();
  addTearDown(state.dispose);
  await tester.runAsync(state.init);
  await tester.pumpWidget(AppScope(
    state: state,
    child: ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        theme: AniTheme.light(),
        locale: state.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: LibraryScreen()),
      ),
    ),
  ));
  for (var i = 0; i < 50 && state.bundle == null; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  }
  await tester.pumpAndSettle();
  return state;
}

void main() {
  setUp(BundleLoader.instance.clear);

  testWidgets('lists five crops with duration and sowing window', (tester) async {
    final state = await _start(tester);
    for (final id in CropId.all) {
      expect(find.byKey(ValueKey('library-crop-$id')), findsOneWidget);
    }
    final rice = state.bundle!.crops[CropId.rice]!;
    expect(find.text('${rice.durationDays} days'), findsOneWidget);
    expect(find.textContaining('Nov 16 to Dec 16'), findsNWidgets(5));
    expect(find.text('Five dry-season crops for Guimba'), findsOneWidget);
  });

  testWidgets('detail sheet shows failed X of N by irrigation from the bundle', (tester) async {
    final state = await _start(tester);
    await tester.tap(find.byKey(const ValueKey('library-crop-rice')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('crop-sheet')), findsOneWidget);
    final risk = state.bundle!.risk;
    for (final w in WaterScenario.all) {
      final row = risk.row(w, CropId.rice)!;
      final rowFinder = find.byKey(ValueKey('crop-risk-$w'));
      expect(rowFinder, findsOneWidget);
      expect(find.descendant(of: rowFinder, matching: find.text('Failed ${row.elNino.failX} of ${row.elNino.failN}')),
          findsOneWidget);
      expect(find.descendant(of: rowFinder, matching: find.text('Failed ${row.other.failX} of ${row.other.failN}')),
          findsOneWidget);
    }
    expect(find.text('Poaceae'), findsOneWidget);
    expect(find.text(AppLocalizations.of(tester.element(find.byKey(const ValueKey('crop-sheet')))).cropWaterNeedRiceNote),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Filipino strings and another town', (tester) async {
    await _start(tester, locale: 'fil', town: Town.bongabon);
    expect(find.text('Mga pananim'), findsOneWidget);
    expect(find.text('Limang pananim sa tag-araw para sa Bongabon'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('library-crop-mungbean')));
    await tester.pumpAndSettle();
    expect(find.text('Nasirang panahon ayon sa patubig'.toUpperCase()), findsOneWidget);
    expect(find.textContaining('Nasira ang'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
