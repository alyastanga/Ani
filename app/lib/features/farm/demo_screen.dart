import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../data/demo_seasons.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import '../alerts/alert_labels.dart';
import '../labels.dart';
import '../recommend/recommend_labels.dart';
import 'planting_widgets.dart';

/// Opens the season replay (demo) picker.
Future<void> openDemo(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DemoPickerScreen()));

/// Persistent "Replay of a past season – not live data" banner.
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      key: const ValueKey('demo-banner'),
      width: double.infinity,
      color: AniColors.statusBantayBg,
      padding: const EdgeInsets.symmetric(horizontal: AniSpacing.screen, vertical: AniSpacing.sm),
      child: Row(
        children: [
          const Icon(Icons.replay_outlined, size: 18, color: AniColors.oliveDark),
          const SizedBox(width: AniSpacing.sm),
          Expanded(
            child: Text(
              l.demoBanner,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AniColors.oliveDark),
            ),
          ),
        ],
      ),
    );
  }
}

/// Picks one of the bundled past seasons to replay.
class DemoPickerScreen extends StatefulWidget {
  const DemoPickerScreen({super.key});

  @override
  State<DemoPickerScreen> createState() => _DemoPickerScreenState();
}

class _DemoPickerScreenState extends State<DemoPickerScreen> {
  Future<List<DemoSeason>>? _seasons;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _seasons ??= AppScope.of(context).demoSeasons();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('demo-picker'),
      backgroundColor: AniColors.cream,
      appBar: AppBar(backgroundColor: AniColors.cream, elevation: 0, title: Text(l.demoTitle)),
      body: Column(
        children: [
          const DemoBanner(),
          Expanded(
            child: FutureBuilder(
              future: _seasons,
              builder: (context, snap) {
                final seasons = snap.data;
                if (seasons == null) {
                  return Center(
                    child: snap.hasError
                        ? Text(l.demoLoadError)
                        : const CircularProgressIndicator(color: AniColors.olive),
                  );
                }
                return ListView(
                  key: const ValueKey('demo-seasons'),
                  padding: const EdgeInsets.all(AniSpacing.screen),
                  children: [
                    Text(l.demoPickHint, style: theme.textTheme.bodyMedium?.copyWith(color: AniColors.muted)),
                    const SizedBox(height: AniSpacing.md),
                    for (final s in seasons) ...[
                      AniCard(
                        key: ValueKey('demo-season-${s.town.id}'),
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => DemoReplayScreen(season: s))),
                        child: Row(
                          children: [
                            const Icon(Icons.eco_outlined, color: AniColors.olive),
                            const SizedBox(width: AniSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.demoSeasonTitle(l.cropNameOf(s.crop), l.townName(s.town)),
                                      style: theme.textTheme.titleMedium),
                                  const SizedBox(height: AniSpacing.xxs),
                                  Text(l.demoSeasonSubtitle(s.drySeason, l.waterLevelName(s.water)),
                                      style: theme.textTheme.bodySmall?.copyWith(color: AniColors.muted)),
                                  const SizedBox(height: AniSpacing.xs),
                                  Text(
                                    l.demoShows([
                                      for (final t in s.shows) l.alertTypeTitle(t),
                                    ].join(', ')),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: AniColors.muted),
                          ],
                        ),
                      ),
                      const SizedBox(height: AniSpacing.sm),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Steps through a past season day by day with the same row, timeline and
/// alert widgets My farm uses. Runs on the replay's own in-memory store:
/// nothing is written to the farmer's records and nothing notifies.
class DemoReplayScreen extends StatefulWidget {
  const DemoReplayScreen({super.key, required this.season});

  final DemoSeason season;

  @override
  State<DemoReplayScreen> createState() => _DemoReplayScreenState();
}

class _DemoReplayScreenState extends State<DemoReplayScreen> {
  DemoReplay? _replay;
  Object? _error;
  bool _busy = false;
  bool _starting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_replay == null && !_starting) _start();
  }

  Future<void> _start() async {
    _starting = true;
    final state = AppScope.of(context);
    try {
      final r = await state.startDemo(widget.season);
      await r.advanceTo(0);
      if (!mounted) {
        r.dispose();
        return;
      }
      final old = _replay;
      setState(() {
        _replay = r;
        _error = null;
      });
      old?.dispose();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    _starting = false;
  }

  Future<void> _run(Future<void> Function(DemoReplay r) f) async {
    final r = _replay;
    if (r == null || _busy) return;
    setState(() => _busy = true);
    try {
      await f(r);
    } catch (e) {
      debugPrint('demo step failed: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Advances until the crop is ready (confirm is left to the farmer), the
  /// season closes, or the data ends.
  Future<void> _runToEnd(DemoReplay r) async {
    while (!r.atEnd) {
      await r.advanceBy(1);
      final v = r.view;
      if (v == null || v.isClosed || v.canConfirmHarvest) break;
    }
  }

  @override
  void dispose() {
    _replay?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = widget.season;
    final r = _replay;
    return Scaffold(
      key: const ValueKey('demo-replay'),
      backgroundColor: AniColors.cream,
      appBar: AppBar(
        backgroundColor: AniColors.cream,
        elevation: 0,
        title: Text(l.demoTitle),
      ),
      body: Column(
        children: [
          const DemoBanner(),
          Expanded(
            child: r == null
                ? Center(
                    child: _error != null
                        ? Text(l.demoLoadError)
                        : const CircularProgressIndicator(color: AniColors.olive),
                  )
                : ListenableBuilder(
                    listenable: r,
                    builder: (context, _) {
                      final v = r.view;
                      final closed = v?.isClosed ?? false;
                      final stop = closed || r.atEnd;
                      return ListView(
                        key: const ValueKey('demo-list'),
                        padding: const EdgeInsets.all(AniSpacing.screen),
                        children: [
                          AniCard(
                            key: const ValueKey('demo-controls'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Eyebrow(l.demoSeasonSubtitle(s.drySeason, l.waterLevelName(s.water))),
                                const SizedBox(height: AniSpacing.xs),
                                Text(
                                  l.demoSeasonTitle(l.cropNameOf(s.crop), l.townName(s.town)),
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: AniSpacing.xs),
                                Text(
                                  '${l.demoDayOf(r.dayIndex, r.totalDays)} · '
                                  '${l.demoDate(fmtDate(context, r.simulatedToday))}',
                                  key: const ValueKey('demo-day'),
                                  style: theme.textTheme.bodySmall?.copyWith(color: AniColors.muted),
                                ),
                                if (stop) ...[
                                  const SizedBox(height: AniSpacing.xs),
                                  Text(l.demoEnded,
                                      key: const ValueKey('demo-ended'),
                                      style: theme.textTheme.titleSmall?.copyWith(color: AniColors.olive)),
                                ],
                                if (v != null && v.canConfirmHarvest) ...[
                                  const SizedBox(height: AniSpacing.md),
                                  PrimaryButton(
                                    key: const ValueKey('detail-confirm-harvest'),
                                    label: l.confirmHarvest,
                                    icon: Icons.check,
                                    onPressed: _busy ? null : () => _run((r) => r.confirmHarvest()),
                                  ),
                                ],
                                const SizedBox(height: AniSpacing.md),
                                Wrap(
                                  spacing: AniSpacing.sm,
                                  runSpacing: AniSpacing.sm,
                                  children: [
                                    _DemoButton(
                                      key: const ValueKey('demo-next-day'),
                                      icon: Icons.skip_next_outlined,
                                      label: l.demoNextDay,
                                      onPressed: _busy || stop ? null : () => _run((r) => r.advanceBy(1)),
                                    ),
                                    _DemoButton(
                                      key: const ValueKey('demo-next-week'),
                                      icon: Icons.fast_forward_outlined,
                                      label: l.demoNextWeek,
                                      onPressed: _busy || stop ? null : () => _run((r) => r.advanceBy(7)),
                                    ),
                                    _DemoButton(
                                      key: const ValueKey('demo-run'),
                                      icon: Icons.double_arrow,
                                      label: l.demoRunToEnd,
                                      onPressed: _busy || stop || (v?.canConfirmHarvest ?? false)
                                          ? null
                                          : () => _run(_runToEnd),
                                    ),
                                    _DemoButton(
                                      key: const ValueKey('demo-restart'),
                                      icon: Icons.restart_alt,
                                      label: l.demoRestart,
                                      onPressed: _busy || _starting ? null : _start,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AniSpacing.md),
                          if (v != null) ...[
                            PlantingRow(view: v),
                            const SizedBox(height: AniSpacing.md),
                            PlantingDetailBody(
                              view: v,
                              busy: _busy,
                              demoNote: true,
                              showConfirm: false,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DemoButton extends StatelessWidget {
  const _DemoButton({super.key, required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AniColors.olive,
          side: const BorderSide(color: AniColors.sand),
          shape: const RoundedRectangleBorder(borderRadius: AniRadius.button),
          minimumSize: const Size(0, 44),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
}
