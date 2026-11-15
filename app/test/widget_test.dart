import 'package:ani/app_state.dart';
import 'package:ani/data/bundle.dart';
import 'package:ani/data/settings_store.dart';
import 'package:ani/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps (letting real async work such as asset loads run) until [finder]
/// matches or [timeout] passes.
Future<void> pumpUntil(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

class _FailingBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => Future.error(FlutterError('missing $key'));
}

void main() {
  setUp(() {
    BundleLoader.instance.clear();
  });

  testWidgets('onboarding: Filipino then Bongabon, lands on home with bundle data', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await tester.pumpWidget(AniApp(state: state));
    await pumpUntil(tester, find.text('Choose your language'));

    expect(find.text('Step 1 of 2'.toUpperCase()), findsOneWidget);
    // Continue is disabled until a language is picked.
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Choose your language'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lang-fil')));
    await tester.pumpAndSettle();
    expect(state.localeCode, 'fil');
    expect(find.text('Piliin ang iyong wika'), findsOneWidget);
    expect(find.text('Magpatuloy'), findsOneWidget);

    await tester.tap(find.text('Magpatuloy'));
    await tester.pumpAndSettle();
    expect(find.text('Saan ang inyong bukid?'), findsOneWidget);
    expect(find.text('Hakbang 2 sa 2'.toUpperCase()), findsOneWidget);

    // Back returns to the language step, keeping the choice.
    await tester.tap(find.text('Bumalik'));
    await tester.pumpAndSettle();
    expect(find.text('Piliin ang iyong wika'), findsOneWidget);
    await tester.tap(find.text('Magpatuloy'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('town-bongabon')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Magpatuloy'));
    await pumpUntil(tester, find.byKey(const ValueKey('home-enso')));

    expect(find.byKey(const ValueKey('home-town')), findsOneWidget);
    expect(find.text('Bongabon'), findsOneWidget);
    expect(find.text('Simula'), findsOneWidget); // nav in Filipino
    final b = state.bundle!;
    expect(b.meta.muni, 'bongabon');
    expect(find.text('El Niño'), b.enso.isElNino ? findsOneWidget : findsNothing);
    expect(find.text('Napakalakas'), findsOneWidget);
    expect(find.text('Inaasahan ang El Niño ngayong tag-araw'), b.enso.isElNino ? findsOneWidget : findsNothing);
    expect(find.byKey(const ValueKey('home-dryness')), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SettingsStore.keyLocale), 'fil');
    expect(prefs.getString(SettingsStore.keyTown), 'bongabon');
    expect(prefs.getBool(SettingsStore.keyOnboardingComplete), isTrue);
  });

  testWidgets('saved settings skip onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({
      SettingsStore.keyLocale: 'en',
      SettingsStore.keyTown: 'guimba',
      SettingsStore.keyOnboardingComplete: true,
    });
    await tester.pumpWidget(AniApp(state: AppState()));
    await pumpUntil(tester, find.byKey(const ValueKey('home-enso')));
    expect(find.text('Choose your language'), findsNothing);
    expect(find.text('Guimba'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Dry-season outlook · 2026-27'.toUpperCase()), findsOneWidget);
  });

  testWidgets('tab switching shows outlook, crops, my farm, and keeps home', (tester) async {
    SharedPreferences.setMockInitialValues({
      SettingsStore.keyLocale: 'en',
      SettingsStore.keyTown: 'munoz',
      SettingsStore.keyOnboardingComplete: true,
    });
    await tester.pumpWidget(AniApp(state: AppState()));
    await pumpUntil(tester, find.byKey(const ValueKey('home-enso')));

    const soon = 'This screen is coming soon.';
    expect(find.text(soon), findsNothing);

    // Outlook is the real season outlook.
    await tester.tap(find.text('Outlook').last);
    await pumpUntil(tester, find.byKey(const ValueKey('outlook-list')));
    expect(find.text(soon), findsNothing);
    expect(find.byKey(const ValueKey('outlook-enso')), findsOneWidget);

    // Crops is the real crop library.
    await tester.tap(find.text('Crops').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-list')), findsOneWidget);
    expect(find.text(soon), findsNothing);

    // My farm is the real tracker screen (empty state on a fresh install).
    await tester.tap(find.text('My farm').last);
    await pumpUntil(tester, find.byKey(const ValueKey('farm-empty')));
    expect(find.text(soon), findsNothing);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text(soon), findsNothing);
    expect(find.text('Science City of Muñoz'), findsOneWidget);
  });

  testWidgets('settings sheet changes language and town', (tester) async {
    SharedPreferences.setMockInitialValues({
      SettingsStore.keyLocale: 'en',
      SettingsStore.keyTown: 'guimba',
      SettingsStore.keyOnboardingComplete: true,
    });
    final state = AppState();
    await tester.pumpWidget(AniApp(state: state));
    await pumpUntil(tester, find.byKey(const ValueKey('home-enso')));

    await tester.tap(find.byKey(const ValueKey('home-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-lang-fil')));
    await tester.pumpAndSettle();
    expect(find.text('Mga setting'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-town-bongabon')));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Bongabon'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(state.bundle!.meta.muni, 'bongabon');
    expect(find.text('Simula'), findsOneWidget);
  });

  testWidgets('bundle load failure shows an error card', (tester) async {
    SharedPreferences.setMockInitialValues({
      SettingsStore.keyLocale: 'en',
      SettingsStore.keyTown: 'guimba',
      SettingsStore.keyOnboardingComplete: true,
    });
    await tester.pumpWidget(AniApp(state: AppState(loader: BundleLoader(), assets: _FailingBundle())));
    await pumpUntil(tester, find.byKey(const ValueKey('bundle-error')));
    expect(find.text('Could not load the data for this town.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
