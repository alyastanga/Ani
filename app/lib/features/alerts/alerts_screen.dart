import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../data/farm_store.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import '../farm/tracker_builder.dart';
import '../recommend/recommend_labels.dart';
import 'alert_labels.dart';

/// Opens the alerts list.
Future<void> openAlerts(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AlertsScreen()));

/// Bell with the number of unseen alerts; opens [AlertsScreen].
class AlertsBell extends StatelessWidget {
  const AlertsBell({super.key, this.color = AniColors.olive});

  /// Icon colour (cream on the olive Home hero).
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return TrackerBuilder(builder: (context, tracker) {
      final n = tracker?.unseenAlertCount ?? 0;
      return IconButton(
        key: const ValueKey('alerts-bell'),
        tooltip: n > 0 ? l.alertsUnseenCount(n) : l.alertsTitle,
        onPressed: () => openAlerts(context),
        icon: Badge(
          key: const ValueKey('alerts-badge'),
          isLabelVisible: n > 0,
          backgroundColor: AniColors.statusDelikado,
          label: Text(n > 99 ? '99+' : '$n', key: const ValueKey('alerts-badge-count')),
          child: Icon(n > 0 ? Icons.notifications_active_outlined : Icons.notifications_none_outlined,
              color: color),
        ),
      );
    });
  }
}

/// All the farmer's alerts, newest first. Opening it marks them seen; the
/// ones that were unseen keep a "New" tag while the screen is open.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  Set<String>? _newIds;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_newIds != null) return;
    _newIds = {};
    AppScope.of(context).tracker().then((t) {
      final ids = {for (final a in t.alerts) if (!a.seen) a.id};
      if (mounted) setState(() => _newIds = ids);
      if (ids.isNotEmpty) return t.markAlertsSeen(ids);
    }).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('alerts-screen'),
      backgroundColor: AniColors.cream,
      appBar: AppBar(
        backgroundColor: AniColors.cream,
        elevation: 0,
        title: Text(l.alertsTitle),
      ),
      body: SafeArea(
        child: TrackerBuilder(builder: (context, tracker) {
          final alerts = tracker?.alerts ?? const <AlertRecord>[];
          return ListView(
            key: const ValueKey('alerts-list'),
            padding: const EdgeInsets.fromLTRB(AniSpacing.screen, AniSpacing.sm, AniSpacing.screen, AniSpacing.xxl),
            children: [
              if (alerts.isEmpty)
                AniCard(
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_none_outlined, color: AniColors.sand),
                      const SizedBox(width: AniSpacing.sm),
                      Expanded(
                        child: Text(l.alertsEmpty,
                            key: const ValueKey('alerts-empty'),
                            style: theme.textTheme.bodyMedium?.copyWith(color: AniColors.muted)),
                      ),
                    ],
                  ),
                )
              else
                AlertList(alerts: alerts, newIds: _newIds ?? const {}, cards: true),
            ],
          );
        }),
      ),
    );
  }
}

/// A non-scrolling list of alerts (newest first) with consecutive water-now
/// alerts of a planting collapsed into one expandable row.
class AlertList extends StatelessWidget {
  const AlertList({
    super.key,
    required this.alerts,
    this.newIds = const {},
    this.showCrop = true,
    this.cards = false,
    this.maxGroups,
  });

  final List<AlertRecord> alerts;

  /// Ids to tag "New".
  final Set<String> newIds;
  final bool showCrop;

  /// Each group on its own card (full list) vs. divided rows (inside a card).
  final bool cards;

  /// Show only the first n groups.
  final int? maxGroups;

  @override
  Widget build(BuildContext context) {
    var groups = groupAlerts(alerts);
    if (maxGroups != null && groups.length > maxGroups!) groups = groups.sublist(0, maxGroups);
    final tiles = [
      for (final g in groups)
        AlertGroupTile(
          group: g,
          isNew: g.alerts.any((a) => newIds.contains(a.id)),
          showCrop: showCrop,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, t) in tiles.indexed) ...[
          if (i > 0) cards ? const SizedBox(height: AniSpacing.sm) : const Divider(height: AniSpacing.lg, color: AniColors.line),
          cards ? AniCard(padding: const EdgeInsets.all(AniSpacing.md), child: t) : t,
        ],
      ],
    );
  }
}

/// One alert (or a collapsed run of water-now alerts): icon, title, crop and
/// date, short advice. A collapsed run expands to its individual dates.
class AlertGroupTile extends StatefulWidget {
  const AlertGroupTile({super.key, required this.group, this.isNew = false, this.showCrop = true});

  final AlertGroup group;
  final bool isNew;
  final bool showCrop;

  @override
  State<AlertGroupTile> createState() => _AlertGroupTileState();
}

class _AlertGroupTileState extends State<AlertGroupTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final g = widget.group;
    final a = g.latest;
    final color = alertColor(a.type);
    final date = g.collapsed
        ? '${fmtDate(context, g.earliest.date)} – ${fmtDate(context, g.latest.date)}'
        : fmtDate(context, a.date);
    final meta = [if (widget.showCrop) l.cropNameOf(a.crop), date].join(' · ');
    final content = Row(
      key: ValueKey('alert-${a.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(alertIcon(a.type), color: color, size: 20),
        ),
        const SizedBox(width: AniSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AniSpacing.sm,
                runSpacing: AniSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(l.alertTypeTitle(a.type), style: theme.textTheme.titleSmall?.copyWith(color: AniColors.ink)),
                  if (g.collapsed) AniPill(l.alertsTimes(g.count), key: const ValueKey('alert-times'), color: color),
                  if (widget.isNew) AniPill(l.alertsNew, key: const ValueKey('alert-new'), color: AniColors.statusDelikado),
                  if (a.isDemo) AniPill(l.plantingDemoTag, color: AniColors.gold),
                ],
              ),
              const SizedBox(height: AniSpacing.xxs),
              Text(meta, style: theme.textTheme.bodySmall?.copyWith(color: AniColors.muted)),
              const SizedBox(height: AniSpacing.xs),
              Text(l.alertAdvice(a), style: theme.textTheme.bodyMedium),
              if (g.collapsed && _open) ...[
                const SizedBox(height: AniSpacing.xs),
                Wrap(
                  spacing: AniSpacing.xs,
                  runSpacing: AniSpacing.xs,
                  children: [
                    for (final x in g.alerts) AniPill(fmtDate(context, x.date), color: AniColors.muted),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (g.collapsed)
          Icon(_open ? Icons.expand_less : Icons.expand_more, color: AniColors.muted),
      ],
    );
    if (!g.collapsed) return content;
    return InkWell(onTap: () => setState(() => _open = !_open), child: content);
  }
}
