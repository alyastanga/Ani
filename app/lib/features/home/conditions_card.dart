import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/power_client.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';

/// Sky description from the day's rain and sunshine (MJ/m2/day).
/// People-facing only; never used in crop decisions.
String conditionLabel(AppLocalizations l, DailyWeather w) {
  final p = w.precip ?? 0;
  if (p >= 10) return l.condHeavyRain;
  if (p >= 1) return l.condRain;
  final rs = w.rs;
  if (rs == null || rs >= 15) return l.condClear;
  return rs >= 10 ? l.condPartly : l.condCloudy;
}

/// Dark "Today's conditions" card: sky, temperature, feels-like, humidity, wind.
/// Shows the latest cached POWER day (POWER lags a few days), with its date.
class ConditionsCard extends StatelessWidget {
  const ConditionsCard({super.key, required this.weather});

  final DailyWeather? weather;

  @override
  Widget build(BuildContext context) {
    final w = weather;
    if (w == null || w.tmax == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rainy = (w.precip ?? 0) >= 1;
    final sunny = !rainy && (w.rs == null || w.rs! >= 10);
    final feels = w.heat?.hi;
    final light = AniColors.paper;
    final dim = AniColors.paper.withValues(alpha: 0.7);
    final stats = <(IconData, String, String)>[
      if (w.rh2m != null) (Icons.water_drop_outlined, l.humidityLabel, '${w.rh2m!.round()}%'),
      if (w.ws2m != null) (Icons.air, l.windLabel, l.windKmh((w.ws2m! * 3.6).round().toString())),
    ];
    return ClipRRect(
      key: const ValueKey('home-conditions'),
      borderRadius: AniRadius.card,
      child: Container(
        color: AniColors.oliveDark,
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _SkyPainter(sunny: sunny, rainy: rainy))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AniSpacing.xl, AniSpacing.xl, AniSpacing.xl, AniSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: AniColors.gold, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: AniSpacing.sm),
                        Flexible(
                          child: Text(
                            '${l.todayConditionsTitle.toUpperCase()} · ${DateFormat.MMMd(l.localeName).format(w.date)}',
                            style: theme.textTheme.labelLarge?.copyWith(color: dim, letterSpacing: 1.2),
                          ),
                        ),
                      ]),
                      const SizedBox(height: AniSpacing.sm),
                      Text(conditionLabel(l, w),
                          key: const ValueKey('home-conditions-sky'),
                          style: theme.textTheme.headlineMedium?.copyWith(color: light)),
                      const SizedBox(height: AniSpacing.xl),
                      Text('${w.tmax!.round()}°',
                          key: const ValueKey('home-conditions-temp'),
                          style: theme.textTheme.displayMedium?.copyWith(color: light, fontWeight: FontWeight.w700)),
                      if (feels != null)
                        Text(l.feelsLike(feels.round().toString()),
                            style: theme.textTheme.bodyMedium?.copyWith(color: dim)),
                    ],
                  ),
                ),
                if (stats.isNotEmpty)
                  Container(
                    color: Colors.black.withValues(alpha: 0.18),
                    padding: const EdgeInsets.symmetric(vertical: AniSpacing.md),
                    child: Row(
                      children: [
                        for (final s in stats)
                          Expanded(
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(s.$1, color: dim, size: 22),
                              const SizedBox(width: AniSpacing.sm),
                              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(s.$2, style: theme.textTheme.bodySmall?.copyWith(color: dim)),
                                Text(s.$3,
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(color: light, fontWeight: FontWeight.w700)),
                              ]),
                            ]),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SkyPainter extends CustomPainter {
  _SkyPainter({required this.sunny, required this.rainy});

  final bool sunny;
  final bool rainy;

  @override
  void paint(Canvas canvas, Size size) {
    // faint dot grid
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (double x = size.width * 0.5; x < size.width; x += 14) {
      for (double y = 8; y < size.height * 0.6; y += 14) {
        canvas.drawCircle(Offset(x, y), 1, dot);
      }
    }
    final cx = size.width - 80, cy = size.height - 108;
    if (sunny) {
      canvas.drawCircle(Offset(cx, cy), 46, Paint()..color = AniColors.gold.withValues(alpha: 0.18));
      canvas.drawCircle(Offset(cx, cy), 34, Paint()..color = AniColors.gold.withValues(alpha: 0.9));
    }
    final cloud = Paint()..color = (rainy ? const Color(0xFFB9BFB0) : AniColors.paper).withValues(alpha: 0.7);
    final base = Offset(cx - 6, cy + 42);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: base, width: 88, height: 28), const Radius.circular(14)),
        cloud);
    canvas.drawCircle(base.translate(-10, -14), 20, cloud);
    canvas.drawCircle(base.translate(14, -18), 16 + math.min(0, 0), cloud);
    if (rainy) {
      final rain = Paint()
        ..color = AniColors.paper.withValues(alpha: 0.6)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (final dx in [-24.0, -6.0, 12.0, 30.0]) {
        canvas.drawLine(base.translate(dx, 18), base.translate(dx - 4, 30), rain);
      }
    }
  }

  @override
  bool shouldRepaint(_SkyPainter o) => o.sunny != sunny || o.rainy != rainy;
}
