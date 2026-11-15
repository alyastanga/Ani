import 'package:flutter/material.dart';

import '../../core/planner.dart';
import '../../data/planner_profile.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import '../farm/add_planting_screen.dart';
import '../labels.dart';
import 'questionnaire_screen.dart';
import 'recommend_labels.dart';

/// Planner output (doc Fig. 3): up to three crop cards, or the Hold screen.
///
/// Card and Hold text comes from the planner itself ([PlanCard.why],
/// [PlanCard.riskText], [HoldMessage]); those sentences are Filipino in both
/// locales. Only the surrounding labels are localized.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.saved, required this.result});

  final SavedPlannerProfile saved;
  final PlanResult result;

  PlannerProfile get profile => saved.profile;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final town = saved.town;
    final elNino = result.elNino == true;

    return Scaffold(
      key: const ValueKey('result-screen'),
      backgroundColor: AniColors.cream,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AniSpacing.screen, AniSpacing.md, AniSpacing.screen, AniSpacing.xxl),
          children: [
            Row(
              children: [
                Expanded(child: Eyebrow(l.recommendTitle)),
                IconButton(
                  key: const ValueKey('result-close'),
                  tooltip: l.actionClose,
                  icon: const Icon(Icons.close, color: AniColors.olive),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            Text(
              result.isHold ? result.message!.title : l.resultTitle,
              key: const ValueKey('result-title'),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: result.isHold ? AniColors.statusDelikado : AniColors.ink,
              ),
            ),
            const SizedBox(height: AniSpacing.xs),
            Text(
              l.resultSubtitle(town == null ? profile.muni : l.townName(town), l.waterLevelName(profile.water)),
              style: theme.textTheme.bodyLarge?.copyWith(color: AniColors.muted),
            ),
            if (elNino && !result.isHold) ...[
              const SizedBox(height: AniSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: AniPill(l.resultElNinoMode, color: AniColors.statusDelikado, icon: Icons.wb_sunny_outlined),
              ),
            ],
            const SizedBox(height: AniSpacing.lg),
            if (result.isHold)
              HoldView(result: result, profile: profile)
            else
              for (var i = 0; i < result.cards.length; i++) ...[
                if (i > 0) const SizedBox(height: AniSpacing.md),
                CropCardView(card: result.cards[i], rank: i + 1, elNino: elNino),
              ],
            const SizedBox(height: AniSpacing.xxl),
            Text(
              l.resultSaved,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: AniColors.muted),
            ),
            const SizedBox(height: AniSpacing.md),
            OutlinedButton.icon(
              key: const ValueKey('result-again'),
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(builder: (_) => const QuestionnaireScreen()),
              ),
              icon: const Icon(Icons.edit_outlined, size: 20),
              label: Text(l.resultStartOver),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: AniColors.olive,
                side: const BorderSide(color: AniColors.sand),
                shape: const RoundedRectangleBorder(borderRadius: AniRadius.button),
              ),
            ),
            const SizedBox(height: AniSpacing.md),
            PrimaryButton(
              key: const ValueKey('result-done'),
              label: l.resultDone,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// One crop card: risk "X sa Y taon" with the Wilson range, water need, net
/// income p10-p90, "Bakit?", confidence, onion price-risk (g3) and MAO
/// referral on Low confidence.
class CropCardView extends StatelessWidget {
  const CropCardView({super.key, required this.card, required this.rank, required this.elNino});

  final PlanCard card;
  final int rank;
  final bool elNino;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final gloss = l.cropGlossOf(card.crop);
    final conf = card.confidence;
    final low = conf == Confidence.low;
    final onionRisk = card.flags.contains(_flagOnion);
    final smallMarket = card.flags.contains(_flagSmallMarket);

    return AniCard(
      key: ValueKey('card-${card.crop}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow(l.cardRank(rank)),
                    const SizedBox(height: AniSpacing.xxs),
                    Text(card.name, style: theme.textTheme.headlineSmall?.copyWith(color: AniColors.ink)),
                    if (gloss != null)
                      Text(gloss, style: theme.textTheme.bodyMedium?.copyWith(color: AniColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: AniSpacing.sm),
              Flexible(
                child: AniPill(
                  l.cardConfidence(l.confidenceName(conf)),
                  key: ValueKey('card-${card.crop}-confidence'),
                  color: confidenceColor(conf),
                ),
              ),
            ],
          ),
          const SizedBox(height: AniSpacing.md),
          _Fact(
            icon: Icons.warning_amber_rounded,
            text: elNino
                ? l.cardFailedSeasonsElNino(card.failed, card.seasons)
                : l.cardFailedSeasons(card.failed, card.seasons),
            detail: l.cardFailRange(pct0(card.failLo), pct0(card.failHi)),
          ),
          _Fact(icon: Icons.water_drop_outlined, text: l.cardWaterNeeded(card.waterMm)),
          _Fact(icon: Icons.payments_outlined, text: l.cardNetIncome(peso(card.net.p10), peso(card.net.p90))),
          const SizedBox(height: AniSpacing.md),
          Eyebrow(l.whyLabel, color: AniColors.olive),
          const SizedBox(height: AniSpacing.xs),
          for (final w in card.why)
            Padding(
              padding: const EdgeInsets.only(top: AniSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7, right: AniSpacing.sm),
                    child: Icon(Icons.circle, size: 6, color: AniColors.olive),
                  ),
                  Expanded(child: Text(w, style: theme.textTheme.bodyMedium?.copyWith(color: AniColors.ink))),
                ],
              ),
            ),
          if (onionRisk) ...[
            const SizedBox(height: AniSpacing.md),
            _Notice(
              key: ValueKey('card-${card.crop}-price-risk'),
              icon: Icons.trending_down,
              color: AniColors.statusBantay,
              background: AniColors.statusBantayBg,
              text: l.onionPriceWarning,
            ),
          ],
          if (smallMarket) ...[
            const SizedBox(height: AniSpacing.sm),
            _Notice(
              icon: Icons.storefront_outlined,
              color: AniColors.muted,
              background: AniColors.cream,
              text: l.cardSmallMarket,
            ),
          ],
          if (low) ...[
            const SizedBox(height: AniSpacing.sm),
            _Notice(
              key: ValueKey('card-${card.crop}-mao'),
              icon: Icons.support_agent,
              color: AniColors.statusDelikado,
              background: AniColors.statusDelikadoBg,
              text: l.lowConfidenceNote,
              action: l.consultMao,
            ),
          ],
          const SizedBox(height: AniSpacing.xs),
          TextButton.icon(
            key: ValueKey('card-${card.crop}-track'),
            onPressed: () => openAddPlanting(context, crop: card.crop),
            icon: const Icon(Icons.agriculture_outlined, size: 20),
            label: Text(l.resultTrackThis),
          ),
        ],
      ),
    );
  }

  // planner.py `card` flag texts.
  static const _flagOnion = 'Walang cold storage: mataas ang panganib sa presyo';
  static const _flagSmallMarket = 'Maliit ang lokal na pamilihan: kumonsulta sa MAO';
}

/// Hold screen body: the blocking guard's reason and the crops it removed,
/// the mulch / rest-soil tip, and the MAO referral (planner `hold_message`).
class HoldView extends StatelessWidget {
  const HoldView({super.key, required this.result, required this.profile});

  final PlanResult result;
  final PlannerProfile profile;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final m = result.message!;
    final guard = result.blockingGuard!;
    final fil = l.localeName == 'fil';
    final removed = result.blocked[guard] ?? const [];

    return Column(
      key: const ValueKey('hold-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AniCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.pause_circle_outline, color: AniColors.statusDelikado, size: 32),
              const SizedBox(height: AniSpacing.sm),
              Eyebrow(l.holdReasonLabel),
              const SizedBox(height: AniSpacing.xs),
              Text(
                fil ? m.reason : l.holdGuardReason(guard),
                key: const ValueKey('hold-reason'),
                style: theme.textTheme.titleMedium?.copyWith(color: AniColors.ink),
              ),
              if (removed.isNotEmpty) ...[
                const SizedBox(height: AniSpacing.md),
                Text(
                  l.holdRemovedCrops(removed.map(l.cropNameOf).join(', ')),
                  key: const ValueKey('hold-removed'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: AniColors.muted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AniSpacing.md),
        AniCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(l.holdTipLabel, color: AniColors.olive),
              const SizedBox(height: AniSpacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.grass, color: AniColors.olive),
                  const SizedBox(width: AniSpacing.md),
                  Expanded(
                    child: Text(
                      fil ? m.tip : l.holdTip,
                      key: const ValueKey('hold-tip'),
                      style: theme.textTheme.bodyLarge?.copyWith(color: AniColors.ink),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AniSpacing.md),
        _Notice(
          key: const ValueKey('hold-mao'),
          icon: Icons.support_agent,
          color: AniColors.statusDelikado,
          background: AniColors.statusDelikadoBg,
          text: m.refer,
          bold: true,
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, this.detail});

  final IconData icon;
  final String text;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AniSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AniColors.olive),
          const SizedBox(width: AniSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: theme.textTheme.titleSmall?.copyWith(color: AniColors.ink)),
                if (detail != null)
                  Text(detail!, style: theme.textTheme.bodySmall?.copyWith(color: AniColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.icon,
    required this.color,
    required this.background,
    required this.text,
    this.action,
    this.bold = false,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String text;
  final String? action;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AniSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AniRadius.tile,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AniSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: (bold ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)?.copyWith(color: AniColors.ink),
                ),
                if (action != null) ...[
                  const SizedBox(height: AniSpacing.xs),
                  Text(action!, style: theme.textTheme.titleSmall?.copyWith(color: color)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
