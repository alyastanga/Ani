import 'package:ani/core/planner.dart';
import 'package:ani/data/planner_profile.dart';
import 'package:ani/data/settings_store.dart';
import 'package:ani/features/recommend/answers.dart';
import 'package:ani/data/bundle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

SavedPlannerProfile _sample() => SavedPlannerProfile(
      profile: const PlannerProfile(
        muni: 'bongabon',
        water: 'full',
        last: ['onion', 'rice'],
        wont: {'maize', 'rice'},
        coldStorage: true,
        priorities: ['income', 'risk', 'pest'],
      ),
      waterSource: WaterSource.pump,
      savedAt: DateTime.utc(2026, 11, 15, 8),
    );

void main() {
  test('JSON round trip keeps every planner input', () {
    final s = _sample();
    final back = SavedPlannerProfile.tryDecode(s.encode())!;
    final p = back.profile;
    expect(p.muni, 'bongabon');
    expect(p.water, 'full');
    expect(p.last, ['onion', 'rice']);
    expect(p.wont, {'maize', 'rice'});
    expect(p.coldStorage, isTrue);
    expect(p.priorities, ['income', 'risk', 'pest']);
    expect(back.waterSource, WaterSource.pump);
    expect(back.savedAt, DateTime.utc(2026, 11, 15, 8));
    expect(back.town, Town.bongabon);
  });

  test('invalid data decodes to null', () {
    expect(SavedPlannerProfile.tryDecode(null), isNull);
    expect(SavedPlannerProfile.tryDecode('not json'), isNull);
    expect(SavedPlannerProfile.tryDecode('[1]'), isNull);
    expect(SavedPlannerProfile.tryDecode('{"muni":"manila","water":"full","last":[],"wont":[],"priorities":[]}'), isNull);
    expect(SavedPlannerProfile.tryDecode('{"muni":"guimba","water":"lots","last":[],"wont":[],"priorities":[]}'), isNull);
    expect(SavedPlannerProfile.tryDecode('{"muni":"guimba","water":"full","last":"rice","wont":[],"priorities":[]}'), isNull);
  });

  test('settings store persists and clears the profile', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await SettingsStore.load();
    expect(store.plannerProfile, isNull);
    await store.setPlannerProfile(_sample());
    final again = await SettingsStore.load();
    expect(again.plannerProfile!.profile.priorities, ['income', 'risk', 'pest']);
    await again.clear();
    expect(again.plannerProfile, isNull);
  });

  group('RecommendAnswers', () {
    test('maps answers onto the planner profile', () {
      final a = RecommendAnswers(town: Town.guimba)
        ..lastRecent = 'rice'
        ..lastBefore = null
        ..setWater(WaterScenario.limited4)
        ..toggleWont('onion')
        ..coldStorage = true;
      expect(a.isComplete(4), isFalse);
      expect(() => a.toProfile(), throwsStateError);
      a
        ..togglePriority('water')
        ..togglePriority('risk')
        ..togglePriority('income')
        ..togglePriority('soil'); // ignored: already 3
      final p = a.toProfile();
      expect(p.muni, 'guimba');
      expect(p.water, 'limited_4');
      expect(p.last, ['rice']);
      expect(p.wont, {'onion'});
      expect(p.coldStorage, isTrue);
      expect(p.priorities, ['water', 'risk', 'income']);
      a.togglePriority('water');
      expect(a.priorities, ['risk', 'income']);
    });

    test('rain-only source implies rainfed, irrigation clears it', () {
      final a = RecommendAnswers()..setWaterSource(WaterSource.rain);
      expect(a.water, WaterScenario.rainfed);
      a.setWater(WaterScenario.limited2);
      expect(a.waterSource, isNull);
      a
        ..setWaterSource(WaterSource.canal)
        ..setWater(WaterScenario.full);
      expect(a.waterSource, WaterSource.canal);
    });

    test('prefill from saved answers, else the app town', () {
      expect(RecommendAnswers.prefill(fallbackTown: Town.munoz).town, Town.munoz);
      final a = RecommendAnswers.prefill(saved: _sample(), fallbackTown: Town.munoz);
      expect(a.town, Town.bongabon);
      expect(a.toProfile().last, ['onion', 'rice']);
      expect(a.waterSource, WaterSource.pump);
      expect(a.priorities, ['income', 'risk', 'pest']);
    });
  });
}
