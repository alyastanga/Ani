import 'dart:convert';
import 'dart:io';

import 'package:ani/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync())
        as Map<String, dynamic>;

Iterable<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@'));

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final fil = lookupAppLocalizations(const Locale('fil'));

  test('supported locales are en and fil', () {
    expect(
      AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
      {'en', 'fil'},
    );
  });

  test('English strings', () {
    expect(en.appTitle, 'Ani');
    expect(en.onboardingLanguageTitle, 'Choose your language');
    expect(en.onboardingTownTitle, 'Where is your farm?');
    expect(en.townMunoz, 'Science City of Muñoz');
    expect(en.homeCta, 'What should I plant?');
    expect(en.onboardingStepOf(1, 2), 'Step 1 of 2');
    expect(en.cropPalayGloss, 'Rice');
  });

  test('Filipino strings', () {
    expect(fil.onboardingContinue, 'Magpatuloy');
    expect(fil.navHome, 'Simula');
    expect(fil.onboardingStepOf(2, 2), 'Hakbang 2 sa 2');
  });

  test('doc-quoted strings are identical Filipino in both locales', () {
    for (final pick in <String Function(AppLocalizations)>[
      (l) => l.holdTitle,
      (l) => l.whyLabel,
      (l) => l.dryNormal,
      (l) => l.dryBantay,
      (l) => l.dryDelikado,
      (l) => l.consultMao,
      (l) => l.workEarly,
      (l) => l.elNinoExpected,
    ]) {
      expect(pick(en), pick(fil));
    }
    expect(en.holdTitle, 'Huwag munang magtanim');
    expect(fil.holdTitle, 'Huwag munang magtanim');
  });

  test('crop names match planner.NAME in both locales', () {
    for (final l in [en, fil]) {
      expect(
        [l.cropPalay, l.cropSibuyas, l.cropMunggo, l.cropMais, l.cropKamote],
        ['Palay', 'Sibuyas', 'Munggo', 'Mais', 'Kamote'],
      );
    }
  });

  test('plural placeholders', () {
    expect(en.drynessRank(1, 25), 'Driest of 25 years');
    expect(en.drynessRank(3, 25), 'No. 3 driest of 25 years');
    expect(fil.drynessRank(3, 25), 'Ika-3 sa pinakatuyo sa 25 na taon');
    expect(en.cardFailedSeasons(2, 9), 'Failed in 2 of 9 years');
    expect(fil.cardFailedSeasons(2, 9), 'Nasira sa 2 sa 9 na taon');
    expect(en.waitingForDataDays(1), '1 day waiting for data');
  });

  test('every en key exists in fil', () {
    final enKeys = _messageKeys(_arb('app_en.arb')).toSet();
    final filKeys = _messageKeys(_arb('app_fil.arb')).toSet();
    expect(enKeys.difference(filKeys), isEmpty);
    expect(filKeys.difference(enKeys), isEmpty);
  });

  test('every en key has a description', () {
    final arb = _arb('app_en.arb');
    for (final k in _messageKeys(arb)) {
      final meta = arb['@$k'] as Map<String, dynamic>?;
      expect(meta?['description'], isA<String>(), reason: k);
    }
  });
}
