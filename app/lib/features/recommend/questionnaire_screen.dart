import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/planner.dart';
import '../../data/bundle.dart';
import '../../data/farm_store.dart';
import '../../data/planner_profile.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import '../labels.dart';
import 'answers.dart';
import 'recommend_labels.dart';
import 'result_screen.dart';

/// Recommendation questionnaire (doc Fig. 3): five answers, one per step, in
/// the onboarding choice-tile style. Prefilled from the saved answers, else
/// with the app's town. "See advice" saves the answers and replaces this
/// screen with the [ResultScreen].
class QuestionnaireScreen extends StatefulWidget {
  const QuestionnaireScreen({super.key});

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  int _step = 0;
  RecommendAnswers? _answers;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (_answers != null) return;
    final saved = state.plannerProfile;
    final town = saved?.town ?? state.town;
    final tracker = state.trackerService;
    final outcomes = [
      for (final o in tracker?.outcomes ?? const <OutcomeRecord>[])
        if (o.town == town) o
    ];
    DateTime? recordedAt;
    for (final o in outcomes) {
      if (recordedAt == null || o.date.isAfter(recordedAt)) recordedAt = o.date;
    }
    _answers = RecommendAnswers.prefill(
      saved: saved,
      fallbackTown: state.town,
      recordedLast: outcomes.isEmpty ? null : tracker!.lastTwoCrops(town: town),
      recordedAt: recordedAt,
    );
  }

  RecommendAnswers get _a => _answers!;

  void _update(VoidCallback f) => setState(f);

  Future<void> _finish() async {
    if (_busy || !_a.isReady) return;
    final state = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final saved = _a.toSaved(DateTime.now());
      final bundle = await state.bundleFor(_a.town!);
      await state.savePlannerProfile(saved);
      final result = planWithBundle(saved.profile, bundle);
      if (!mounted) return;
      await navigator.pushReplacement(MaterialPageRoute<void>(
        builder: (_) => ResultScreen(saved: saved, result: result),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(l.bundleLoadError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (title, hint, tiles) = switch (_step) {
      0 => (l.questionTownTitle, null, _townStep(l)),
      1 => (l.questionLastCropsTitle, l.questionLastCropsHint, _lastCropsStep(l)),
      2 => (l.questionWaterTitle, null, _waterStep(l)),
      3 => (l.questionWontTitle, l.questionWontHint, _wontStep(l)),
      _ => (l.questionPrioritiesTitle, l.questionPrioritiesHint, _prioritiesStep(l)),
    };
    final last = _step == RecommendAnswers.steps - 1;
    final canContinue = !_busy && _a.isComplete(_step);

    return Scaffold(
      key: const ValueKey('questionnaire'),
      backgroundColor: AniColors.cream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AniSpacing.xxl, AniSpacing.md, AniSpacing.xxl, AniSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Eyebrow(l.questionStepOf(_step + 1, RecommendAnswers.steps))),
                  IconButton(
                    key: const ValueKey('questionnaire-close'),
                    tooltip: l.actionClose,
                    icon: const Icon(Icons.close, color: AniColors.olive),
                    onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              AniProgressBar(value: (_step + 1) / RecommendAnswers.steps),
              const SizedBox(height: AniSpacing.lg),
              Expanded(
                child: ListView(
                  key: ValueKey('question-step-$_step'),
                  padding: EdgeInsets.zero,
                  children: [
                    Text(title, style: theme.textTheme.headlineMedium?.copyWith(color: AniColors.ink)),
                    if (hint != null) ...[
                      const SizedBox(height: AniSpacing.sm),
                      Text(hint, style: theme.textTheme.bodyLarge?.copyWith(color: AniColors.muted)),
                    ],
                    const SizedBox(height: AniSpacing.lg),
                    ..._spaced(tiles),
                  ],
                ),
              ),
              const SizedBox(height: AniSpacing.lg),
              Row(
                children: [
                  if (_step > 0) ...[
                    OutlinedButton(
                      key: const ValueKey('questionnaire-back'),
                      onPressed: _busy ? null : () => setState(() => _step--),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        foregroundColor: AniColors.olive,
                        side: const BorderSide(color: AniColors.sand),
                        shape: const RoundedRectangleBorder(borderRadius: AniRadius.button),
                        padding: const EdgeInsets.symmetric(horizontal: AniSpacing.xl),
                      ),
                      child: Text(l.onboardingBack),
                    ),
                    const SizedBox(width: AniSpacing.md),
                  ],
                  Expanded(
                    child: PrimaryButton(
                      key: const ValueKey('questionnaire-next'),
                      label: last ? l.questionSeeResult : l.onboardingContinue,
                      icon: last ? Icons.check : Icons.arrow_forward,
                      onPressed: !canContinue
                          ? null
                          : last
                              ? _finish
                              : () => setState(() => _step++),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static List<Widget> _spaced(List<Widget> tiles) => [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(height: AniSpacing.md),
          tiles[i],
        ],
      ];

  // ---------------------------------------------------------------- steps

  List<Widget> _townStep(AppLocalizations l) => [
        for (final t in Town.values)
          ChoiceTile(
            key: ValueKey('q-town-${t.id}'),
            title: l.townName(t),
            subtitle: 'Nueva Ecija',
            leading: const Icon(Icons.location_on_outlined, color: AniColors.olive),
            selected: _a.town == t,
            onTap: () => _update(() => _a.town = t),
          ),
      ];

  List<Widget> _lastCropsStep(AppLocalizations l) {
    List<Widget> pick(String prefix, String? value, void Function(String?) set) => [
          for (final id in [null, ...CropId.all])
            ChoiceTile(
              key: ValueKey('q-$prefix-${id ?? 'none'}'),
              title: id == null ? l.answerNone : l.cropNameOf(id),
              subtitle: id == null ? null : l.cropGlossOf(id),
              leading: _cropIcon(id),
              selected: value == id,
              onTap: () => _update(() => set(id)),
            ),
        ];
    return [
      if (_a.lastFromRecords)
        Row(
          key: const ValueKey('q-last-from-records'),
          children: [
            const Icon(Icons.history, size: 16, color: AniColors.olive),
            const SizedBox(width: AniSpacing.xs),
            Expanded(
              child: Text(l.questionLastCropsFromRecords,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AniColors.olive)),
            ),
          ],
        ),
      _SectionLabel(l.questionLastCropRecent),
      ...pick('recent', _a.lastRecent, (v) => _a.lastRecent = v),
      const SizedBox(height: AniSpacing.sm),
      _SectionLabel(l.questionLastCropBefore),
      ...pick('before', _a.lastBefore, (v) => _a.lastBefore = v),
    ];
  }

  List<Widget> _waterStep(AppLocalizations l) => [
        _SectionLabel(l.questionWaterSourceLabel),
        for (final s in WaterSource.all)
          ChoiceTile(
            key: ValueKey('q-source-$s'),
            title: l.waterSourceName(s),
            leading: Icon(_sourceIcon(s), color: AniColors.olive),
            selected: _a.waterSource == s,
            onTap: () => _update(() => _a.setWaterSource(s)),
          ),
        const SizedBox(height: AniSpacing.sm),
        _SectionLabel(l.questionIrrigationsLabel),
        for (final w in WaterScenario.all)
          ChoiceTile(
            key: ValueKey('q-water-$w'),
            title: l.waterLevelName(w),
            leading: _WaterDrops(WaterScenario.all.indexOf(w)),
            selected: _a.water == w,
            onTap: () => _update(() => _a.setWater(w)),
          ),
      ];

  List<Widget> _wontStep(AppLocalizations l) => [
        for (final id in CropId.all)
          ChoiceTile(
            key: ValueKey('q-wont-$id'),
            title: l.cropNameOf(id),
            subtitle: l.cropGlossOf(id),
            leading: _cropIcon(id),
            selected: _a.wont.contains(id),
            onTap: () => _update(() => _a.toggleWont(id)),
          ),
        const SizedBox(height: AniSpacing.sm),
        _SectionLabel(l.questionColdStorageLabel),
        ChoiceTile(
          key: const ValueKey('q-cold-storage'),
          title: l.questionColdStorage,
          subtitle: l.questionColdStorageHint,
          leading: const Icon(Icons.ac_unit, color: AniColors.olive),
          selected: _a.coldStorage,
          onTap: () => _update(() => _a.coldStorage = !_a.coldStorage),
        ),
      ];

  List<Widget> _prioritiesStep(AppLocalizations l) => [
        Eyebrow(
          l.questionPrioritiesPicked(_a.priorities.length),
          key: const ValueKey('q-priorities-count'),
        ),
        for (final c in kCriteria)
          ChoiceTile(
            key: ValueKey('q-priority-$c'),
            title: l.priorityName(c),
            leading: _RankBadge(_a.priorities.contains(c) ? _a.priorities.indexOf(c) + 1 : null),
            selected: _a.priorities.contains(c),
            onTap: () => _update(() => _a.togglePriority(c)),
          ),
      ];

  static Widget _cropIcon(String? id) => Icon(
        id == null ? Icons.do_not_disturb_alt_outlined : Icons.eco_outlined,
        color: id == null ? AniColors.muted : AniColors.olive,
      );

  static IconData _sourceIcon(String s) => switch (s) {
        WaterSource.rain => Icons.cloud_outlined,
        WaterSource.pump => Icons.water_drop_outlined,
        WaterSource.canal => Icons.waves_outlined,
        _ => Icons.water_outlined,
      };
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AniSpacing.xs),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AniColors.ink)),
      );
}

/// 0-3 filled drops for the irrigation levels.
class _WaterDrops extends StatelessWidget {
  const _WaterDrops(this.level);

  final int level;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Icon(
                i < level ? Icons.water_drop : Icons.water_drop_outlined,
                size: 14,
                color: i < level ? AniColors.olive : AniColors.sand,
              ),
          ],
        ),
      );
}

/// Rank number in a circle (empty when unranked).
class _RankBadge extends StatelessWidget {
  const _RankBadge(this.rank);

  final int? rank;

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: rank == null ? AniColors.cream : AniColors.olive,
        ),
        child: Text(
          rank == null ? '' : '$rank',
          style: const TextStyle(
            fontFamily: aniFontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AniColors.paper,
          ),
        ),
      );
}
