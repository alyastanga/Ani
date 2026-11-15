import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../data/bundle.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import '../labels.dart';

/// First-run flow: language (step 1) then town (step 2).
///
/// Picking a language switches the app locale immediately. Continue on the
/// town step saves settings and loads the bundle via [AppState.completeOnboarding];
/// the root then swaps to the app shell.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const totalSteps = 2;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  Town? _town;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Preselect a previously saved town, if any.
    _town ??= AppScope.of(context).town;
  }

  Future<void> _finish(AppState state) async {
    final town = _town;
    if (town == null || _busy) return;
    setState(() => _busy = true);
    await state.completeOnboarding(town);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final theme = Theme.of(context);

    final isLanguage = _step == 0;
    final title = isLanguage ? l.onboardingLanguageTitle : l.onboardingTownTitle;
    final subtitle = isLanguage ? l.onboardingLanguageSubtitle : l.onboardingTownSubtitle;

    final List<Widget> tiles = isLanguage
        ? [
            _languageTile(state, 'en', l.languageEnglish, 'EN'),
            _languageTile(state, 'fil', l.languageFilipino, 'FIL'),
          ]
        : [
            for (final t in Town.values)
              ChoiceTile(
                key: ValueKey('town-${t.id}'),
                title: l.townName(t),
                subtitle: 'Nueva Ecija',
                leading: const Icon(Icons.location_on_outlined, color: AniColors.olive),
                selected: _town == t,
                onTap: () => setState(() => _town = t),
              ),
          ];

    final canContinue = isLanguage ? state.localeCode != null : _town != null && !_busy;

    return Scaffold(
      backgroundColor: AniColors.cream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AniSpacing.xxl,
            AniSpacing.xxl,
            AniSpacing.xxl,
            AniSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Eyebrow(l.onboardingStepOf(_step + 1, OnboardingScreen.totalSteps)),
              const SizedBox(height: AniSpacing.sm),
              AniProgressBar(value: (_step + 1) / OnboardingScreen.totalSteps),
              const SizedBox(height: AniSpacing.xxxl),
              Text(title, style: theme.textTheme.displaySmall?.copyWith(color: AniColors.ink)),
              const SizedBox(height: AniSpacing.sm),
              Text(subtitle, style: theme.textTheme.bodyLarge?.copyWith(color: AniColors.muted)),
              const SizedBox(height: AniSpacing.xxl),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: tiles.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AniSpacing.md),
                  itemBuilder: (_, i) => tiles[i],
                ),
              ),
              const SizedBox(height: AniSpacing.lg),
              Row(
                children: [
                  if (!isLanguage) ...[
                    OutlinedButton(
                      key: const ValueKey('onboarding-back'),
                      onPressed: _busy ? null : () => setState(() => _step = 0),
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
                      key: const ValueKey('onboarding-continue'),
                      label: l.onboardingContinue,
                      icon: Icons.arrow_forward,
                      onPressed: !canContinue
                          ? null
                          : isLanguage
                              ? () => setState(() => _step = 1)
                              : () => _finish(state),
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

  Widget _languageTile(AppState state, String code, String name, String badge) {
    return ChoiceTile(
      key: ValueKey('lang-$code'),
      title: name,
      leading: _Badge(badge),
      selected: state.localeCode == code,
      onTap: () => state.setLocale(code),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AniColors.cream, shape: BoxShape.circle),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: aniFontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AniColors.olive,
        ),
      ),
    );
  }
}
