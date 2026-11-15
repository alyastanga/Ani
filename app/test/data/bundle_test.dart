import 'dart:convert';
import 'dart:io';

import 'package:ani/data/bundle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _readJson(Town t) =>
    jsonDecode(File(t.assetPath).readAsStringSync()) as Map<String, dynamic>;

/// Counts loadString calls so caching can be checked.
class _CountingBundle extends CachingAssetBundle {
  int loads = 0;

  @override
  Future<ByteData> load(String key) async {
    loads++;
    final bytes = File(key).readAsBytesSync();
    return ByteData.sublistView(bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Town ids, asset paths and names', () {
    expect(Town.values.map((t) => t.id), ['guimba', 'munoz', 'bongabon']);
    expect(Town.munoz.assetPath, 'assets/data/ani_munoz.json');
    expect(Town.munoz.displayName, 'Science City of Muñoz');
    expect(Town.tryFromId('bongabon'), Town.bongabon);
    expect(Town.tryFromId('nope'), isNull);
  });

  for (final town in Town.values) {
    group('${town.id} via rootBundle', () {
      late AniBundle b;
      setUpAll(() async {
        b = await BundleLoader().load(town);
      });

      test('meta', () {
        expect(b.meta.schema, 2);
        expect(b.meta.muni, town.id);
        expect(b.meta.town, town);
        expect(b.meta.point.lat, inInclusiveRange(14.0, 17.0));
        expect(b.meta.point.lon, inInclusiveRange(119.0, 122.0));
        expect(b.meta.power.rainParameter, 'PRECTOTCORR');
        expect(b.meta.power.parameters, contains('GWETROOT'));
        expect(b.meta.power.fillValue, -999.0);
        expect(b.meta.waterScenarios, {'rainfed': 0, 'limited_2': 2, 'limited_4': 4, 'full': null});
        expect(b.meta.baselineStart, isNotNull);
        expect(b.meta.generatedDate, isNotNull);
      });

      test('enso', () {
        expect(b.enso.tag, isIn([EnsoTag.elNino, EnsoTag.laNina, EnsoTag.neutral]));
        expect(b.enso.comingSeason, matches(RegExp(r'^\d{4}-\d{2}$')));
        expect(b.enso.jas, isA<double>());
        expect(b.enso.past, isNotEmpty);
        expect(b.enso.past.first.season, '2000-01');
      });

      test('dryness', () {
        final t = b.dryness.thresholds;
        expect([t.bantay, t.delikado, t.downBantay, t.downNormal], [1.0, 2.0, 1.5, 0.5]);
        expect(t.calmDekads, 2);
        expect(b.dryness.latest.label, isIn([DrynessLabel.normal, DrynessLabel.bantay, DrynessLabel.delikado]));
        expect(b.dryness.latest.month, b.dryness.monthly.last.month);
        expect(b.dryness.latest.d, b.dryness.monthly.last.d);
        expect(b.dryness.monthly.length, greaterThan(200));
        expect(b.dryness.reference.keys.toSet(), {for (var m = 1; m <= 12; m++) m});
        for (final r in b.dryness.reference.values) {
          expect(r.years.length, 25);
          expect(r.bal1.length, r.years.length);
          expect(r.bal3.length, r.years.length);
          expect(r.gwet.length, r.years.length);
        }
        // first Jan/Feb have no 3-month accumulation yet
        expect(b.dryness.reference[1]!.bal3.first, isNull);
      });

      test('crops', () {
        expect(b.cropIds, CropId.all);
        expect(b.crops.values.map((c) => c.name), ['Palay', 'Sibuyas', 'Munggo', 'Mais', 'Kamote']);
        final mung = b.crops[CropId.mungbean]!;
        expect(mung.legume, isTrue);
        expect(mung.smallMarket, isTrue);
        expect(mung.family, 'Fabaceae');
        expect(mung.durationDays, greaterThan(0));
        expect(mung.sowWindowStart, lessThan(mung.sowWindowEnd));
      });

      test('risk', () {
        expect(b.risk.waters, WaterScenario.all);
        for (final w in WaterScenario.all) {
          expect(b.risk.byWater[w]!.keys, CropId.all);
        }
        final r = b.risk.row(WaterScenario.rainfed, CropId.rice)!;
        expect(r.elNino.failN, greaterThan(0));
        expect(r.other.failN, greaterThan(0));
        expect(r.forMode(RiskMode.elNino), same(r.elNino));
        expect(r.elNino.failLo, lessThanOrEqualTo(r.elNino.failHi));
        expect(r.heatShare, inInclusiveRange(0.0, 1.0));
        // the file value must match what the raw map holds
        final raw = b.raw['risk']['full']['onion'] as Map;
        expect(b.risk.row('full', 'onion')!.other.mcNetP50, (raw['mc_net_other_p50'] as num).toDouble());
      });

      test('planner', () {
        final p = b.planner;
        expect([p.thetaF, p.thetaH, p.beta, p.rankedShare], [0.5, 0.5, 1.5, 0.8]);
        expect(p.criteria, ['income', 'risk', 'water', 'soil', 'pest']);
        expect(p.benefit['risk'], isFalse);
        expect(p.waterLabel.keys, WaterScenario.all);
      });

      test('tracker', () {
        expect(b.tracker.crops.keys, CropId.all);
        final rice = b.tracker.crops[CropId.rice]!;
        expect(rice.taw, greaterThan(0));
        expect(rice.fE < rice.fV && rice.fV < rice.fR, isTrue);
        expect(rice.kFail, 10);
        expect(rice.ksFail, 0.5);
        expect(rice.sensitive, ['Veg', 'Repro']);
        expect(rice.tUp, isNull);
        expect(b.tracker.crops[CropId.onion]!.tCrit, isNull);
        expect(b.tracker.s0FracByDoy.length, 366);
        expect(Tracker.doyIndex(DateTime(2024, 2, 29)), 59);
        expect(Tracker.doyIndex(DateTime(2025, 3, 1)), 60);
        expect(Tracker.doyIndex(DateTime(2025, 12, 31)), 365);
        expect(b.tracker.s0FracFor(DateTime(2025, 1, 1)), b.tracker.s0FracByDoy.first);
      });

      test('heat', () {
        final h = b.heat.indexCategoriesC;
        expect(h.length, 4);
        expect(h.last.to, isNull);
        expect(b.heat.categoryFor(26), isNull);
        expect(b.heat.categoryFor(45)!.label, 'danger');
      });
    });
  }

  test('fromJson on files read from disk matches', () {
    for (final t in Town.values) {
      final b = AniBundle.fromJson(_readJson(t));
      expect(b.meta.muni, t.id);
      expect(b.raw['meta']['schema'], 2);
    }
  });

  test('wrong schema throws FormatException', () {
    final j = _readJson(Town.guimba);
    (j['meta'] as Map)['schema'] = 1;
    expect(() => AniBundle.fromJson(j),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('schema'))));
    (j['meta'] as Map).remove('schema');
    expect(() => AniBundle.fromJson(j), throwsFormatException);
  });

  test('malformed field throws FormatException with path', () {
    final j = _readJson(Town.munoz);
    (j['tracker']['rice'] as Map)['taw'] = 'x';
    expect(() => AniBundle.fromJson(j),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('tracker.rice.taw'))));
  });

  test('BundleLoader caches per town', () async {
    final assets = _CountingBundle();
    final loader = BundleLoader();
    final a1 = await loader.load(Town.guimba, bundle: assets);
    final a2 = await loader.load(Town.guimba, bundle: assets);
    expect(identical(a1, a2), isTrue);
    expect(assets.loads, 1);
    await loader.load(Town.bongabon, bundle: assets);
    expect(assets.loads, 2);
    loader.clear();
    await loader.load(Town.guimba, bundle: assets);
    expect(assets.loads, 3);
  });
}
