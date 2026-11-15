import 'package:ani/core/planner.dart';
import 'package:ani/core/season_replay.dart';
import 'package:ani/data/bundle.dart';
import 'package:ani/data/farm_store.dart';
import 'package:ani/data/kv_store.dart';
import 'package:ani/data/planner_profile.dart';
import 'package:ani/data/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

OutcomeRecord _o(String id, String crop, DateTime date, {Town town = Town.guimba, OutcomeResult r = OutcomeResult.harvest}) =>
    OutcomeRecord(plantingId: id, crop: crop, town: town, sowDate: DateTime.utc(date.year, date.month - 3, 1), result: r, date: date);

void main() {
  test('last two crops: most recent first, failed seasons count, optional town filter', () {
    final outs = [
      _o('a', 'rice', DateTime.utc(2024, 4, 1)),
      _o('b', 'onion', DateTime.utc(2025, 3, 20), r: OutcomeResult.failed),
      _o('c', 'mungbean', DateTime.utc(2025, 9, 1), town: Town.bongabon),
      _o('d', 'maize', DateTime.utc(2023, 3, 1)),
    ];
    expect(lastTwoCrops(outs), ['mungbean', 'onion']);
    expect(lastTwoCrops(outs, town: Town.guimba), ['onion', 'rice']);
    expect(lastTwoCrops([outs.first]), ['rice']);
    expect(lastTwoCrops(const []), isEmpty);
  });

  test('outcomes are stored once per planting', () async {
    final s = FarmStore(MemoryKvStore());
    expect(await s.addOutcome(_o('a', 'rice', DateTime.utc(2024, 4, 1))), isTrue);
    expect(await s.addOutcome(_o('a', 'rice', DateTime.utc(2024, 4, 9))), isFalse);
    expect(await s.addOutcome(_o('b', 'maize', DateTime.utc(2025, 4, 1))), isTrue);
    expect(s.outcomes(), hasLength(2));
    expect(s.lastTwoCrops(), ['maize', 'rice']);
  });

  test('alerts dedupe by id and can be marked seen', () async {
    final s = FarmStore(MemoryKvStore());
    AlertRecord a(TrackerAlertType t, DateTime d) =>
        AlertRecord(id: AlertRecord.idFor('p1', t, d), type: t, date: d, plantingId: 'p1', crop: 'rice');
    final first = await s.addAlerts([a(TrackerAlertType.waterNow, DateTime.utc(2025, 1, 2)), a(TrackerAlertType.failed, DateTime.utc(2025, 1, 9))]);
    expect(first, hasLength(2));
    final again = await s.addAlerts([a(TrackerAlertType.waterNow, DateTime.utc(2025, 1, 2)), a(TrackerAlertType.waterNow, DateTime.utc(2025, 1, 5))]);
    expect(again.map((x) => x.id), ['p1|waterNow|2025-01-05']);
    expect(s.alerts().map((x) => x.date), [DateTime.utc(2025, 1, 9), DateTime.utc(2025, 1, 5), DateTime.utc(2025, 1, 2)]);
    await s.markAlertsSeen(['p1|failed|2025-01-09']);
    expect(s.alerts().where((x) => x.seen).map((x) => x.type), [TrackerAlertType.failed]);
    await s.markAlertsSeen();
    expect(s.alerts().every((x) => x.seen), isTrue);
  });

  test('planting JSON round trip, removal drops its alerts', () async {
    final s = FarmStore(MemoryKvStore());
    final p = Planting(
      id: 'p1',
      town: Town.bongabon,
      crop: 'onion',
      plantedOn: DateTime.utc(2025, 12, 1),
      method: PlantingMethod.transplant,
      water: 'limited_4',
      createdAt: DateTime.utc(2025, 12, 2, 8),
      harvestConfirmedOn: DateTime.utc(2026, 3, 30),
      closedAs: OutcomeResult.harvest,
      closedOn: DateTime.utc(2026, 3, 30),
      s0Frac: 0.7,
      snapshot: TrackerSnapshot(
          machine: const {'q': 'Mature'},
          lastDay: DateTime.utc(2026, 3, 28),
          replayedDays: 118,
          reached: {'Prep': DateTime.utc(2025, 12, 1), 'Veg': DateTime.utc(2025, 12, 20)},
          readyOn: DateTime.utc(2026, 3, 27)),
    );
    await s.savePlanting(p);
    final back = s.planting('p1')!;
    expect(back.toJson(), p.toJson());
    expect(back.method, PlantingMethod.transplant);
    expect(back.snapshot!.reached['Veg'], DateTime.utc(2025, 12, 20));
    await s.addAlerts([
      AlertRecord(id: 'x', type: TrackerAlertType.onionRot, date: DateTime.utc(2025, 12, 5), plantingId: 'p1', crop: 'onion'),
    ]);
    await s.removePlanting('p1');
    expect(s.plantings(), isEmpty);
    expect(s.alerts(), isEmpty);
  });

  test('irrigation level defaults from the saved planner profile', () async {
    final kv = MemoryKvStore();
    final s = FarmStore(kv);
    expect(s.defaultWater(), 'rainfed');
    await kv.setString(
        SettingsStore.keyPlannerProfile,
        SavedPlannerProfile(
          profile: const PlannerProfile(muni: 'guimba', water: 'limited_2', last: [], wont: {}, coldStorage: false, priorities: []),
          savedAt: DateTime.utc(2026, 11, 1),
        ).encode());
    expect(s.defaultWater(), 'limited_2');
  });

  test('corrupt storage reads as empty', () {
    final s = FarmStore(MemoryKvStore({FarmStore.keyPlantings: 'x', FarmStore.keyAlerts: '{}', FarmStore.keyOutcomes: '[1, {"a": 2}]'}));
    expect(s.plantings(), isEmpty);
    expect(s.alerts(), isEmpty);
    expect(s.outcomes(), isEmpty);
  });
}
