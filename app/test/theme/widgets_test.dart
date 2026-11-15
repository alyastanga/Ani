import 'package:ani/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {Widget? bottom}) => MaterialApp(
      theme: AniTheme.light(),
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
        bottomNavigationBar: bottom,
      ),
    );

void main() {
  test('AniTheme.light uses tokens', () {
    final t = AniTheme.light();
    expect(t.useMaterial3, isTrue);
    expect(t.scaffoldBackgroundColor, AniColors.cream);
    expect(t.colorScheme.primary, AniColors.olive);
    expect(t.textTheme.bodyMedium?.color, AniColors.ink);
    expect(t.textTheme.bodyMedium?.fontFamily, aniFontFamily);
  });

  testWidgets('AniCard renders child and handles tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(AniCard(onTap: () => taps++, child: const Text('Card body'))));
    expect(find.text('Card body'), findsOneWidget);
    await tester.tap(find.text('Card body'));
    expect(taps, 1);
  });

  testWidgets('AniCard without onTap has no InkWell', (tester) async {
    await tester.pumpWidget(_wrap(const AniCard(child: Text('Static'))));
    expect(find.descendant(of: find.byType(AniCard), matching: find.byType(InkWell)), findsNothing);
  });

  testWidgets('Eyebrow uppercases text', (tester) async {
    await tester.pumpWidget(_wrap(const Eyebrow('Season outlook')));
    expect(find.text('SEASON OUTLOOK'), findsOneWidget);
  });

  testWidgets('AniPill shows text and optional icon', (tester) async {
    await tester.pumpWidget(_wrap(const AniPill('Delikado', color: AniColors.statusDelikado, icon: Icons.warning)));
    expect(find.text('Delikado'), findsOneWidget);
    expect(find.byIcon(Icons.warning), findsOneWidget);
    final text = tester.widget<Text>(find.text('Delikado'));
    expect(text.style?.color, AniColors.statusDelikado);
  });

  testWidgets('AniProgressBar clamps value', (tester) async {
    Future<double> factorFor(double v) async {
      await tester.pumpWidget(_wrap(AniProgressBar(value: v)));
      return tester.widget<FractionallySizedBox>(find.byKey(const ValueKey('aniProgressFill'))).widthFactor!;
    }

    expect(await factorFor(0.4), 0.4);
    expect(await factorFor(1.7), 1.0);
    expect(await factorFor(-0.2), 0.0);
  });

  testWidgets('ChoiceTile shows check only when selected and taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(ChoiceTile(
      title: 'Guimba',
      subtitle: 'Nueva Ecija',
      selected: false,
      onTap: () => taps++,
    )));
    expect(find.text('Guimba'), findsOneWidget);
    expect(find.text('Nueva Ecija'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    await tester.tap(find.text('Guimba'));
    expect(taps, 1);

    await tester.pumpWidget(_wrap(ChoiceTile(
      title: 'Guimba',
      leading: const Icon(Icons.place),
      selected: true,
      onTap: () => taps++,
    )));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.place), findsOneWidget);
  });

  testWidgets('PrimaryButton taps when enabled, ignores when disabled', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(PrimaryButton(label: 'Next', icon: Icons.arrow_forward, onPressed: () => taps++)));
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    await tester.tap(find.text('Next'));
    expect(taps, 1);
    // Full width inside 16px padding on the 800px test surface.
    expect(tester.getSize(find.byType(PrimaryButton)).width, 800 - 32);

    await tester.pumpWidget(_wrap(const PrimaryButton(label: 'Next')));
    final button = tester.widget<FilledButton>(find.byWidgetPredicate((w) => w is FilledButton));
    expect(button.enabled, isFalse);
    await tester.tap(find.text('Next'));
    expect(taps, 1);
  });

  testWidgets('AniBottomNav renders items and reports taps', (tester) async {
    final tapped = <int>[];
    const items = [
      AniNavItem(Icons.home_outlined, 'Home'),
      AniNavItem(Icons.wb_sunny_outlined, 'Outlook'),
      AniNavItem(Icons.grass_outlined, 'Crops'),
      AniNavItem(Icons.agriculture_outlined, 'My farm'),
    ];
    await tester.pumpWidget(_wrap(
      const SizedBox(),
      bottom: AniBottomNav(currentIndex: 1, onTap: tapped.add, items: items),
    ));
    for (final item in items) {
      expect(find.text(item.label), findsOneWidget);
      expect(find.byIcon(item.icon), findsOneWidget);
    }
    final selected = tester.widget<Text>(find.text('Outlook'));
    expect(selected.style?.color, AniColors.olive);
    final other = tester.widget<Text>(find.text('Home'));
    expect(other.style?.color, AniColors.muted);

    await tester.tap(find.text('My farm'));
    await tester.tap(find.text('Home'));
    expect(tapped, [3, 0]);
  });
}
