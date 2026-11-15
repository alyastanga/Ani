import 'package:flutter/material.dart';

import 'tokens.dart';

/// Paper card with a hairline border, as in the Make prototype.
class AniCard extends StatelessWidget {
  const AniCard({super.key, required this.child, this.padding, this.onTap});

  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(AniSpacing.lg),
      child: child,
    );
    return Material(
      color: AniColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: AniRadius.card,
        side: BorderSide(color: AniColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// Small uppercase, letter-spaced muted label shown above headings.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: aniFontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.4,
        height: 1.2,
        color: color ?? AniColors.muted,
      ),
    );
  }
}

/// Rounded badge. [color] tints the text/icon; the background is a pale
/// wash of the same colour.
class AniPill extends StatelessWidget {
  const AniPill(this.text, {super.key, this.color, this.icon});

  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AniColors.olive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AniSpacing.md - 2, vertical: AniSpacing.xs),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: AniRadius.chip,
        border: Border.all(color: fg.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: AniSpacing.xs),
          ],
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: aniFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.2,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin rounded progress bar; [value] is clamped to 0..1.
class AniProgressBar extends StatelessWidget {
  const AniProgressBar({super.key, required this.value, this.color});

  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      value: '${(v * 100).round()}%',
      child: ClipRRect(
        borderRadius: AniRadius.chip,
        child: SizedBox(
          height: 8,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: AniColors.line),
              FractionallySizedBox(
                key: const ValueKey('aniProgressFill'),
                alignment: Alignment.centerLeft,
                widthFactor: v,
                child: ColoredBox(color: color ?? AniColors.olive),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Onboarding-choice tile. Selected: olive border, pale olive wash, check.
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AniColors.statusNormalBg : AniColors.paper,
        shape: RoundedRectangleBorder(
          borderRadius: AniRadius.tile,
          side: BorderSide(
            color: selected ? AniColors.olive : AniColors.line,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              // Keep content from shifting when the border thickens.
              padding: EdgeInsets.all(selected ? AniSpacing.lg - 1 : AniSpacing.lg),
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: AniSpacing.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontFamily: aniFontFamily,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            color: AniColors.ink,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: AniSpacing.xxs),
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              fontFamily: aniFontFamily,
                              fontSize: 14,
                              height: 1.3,
                              color: AniColors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AniSpacing.md),
                  _CheckMark(selected: selected),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AniColors.olive : Colors.transparent,
        border: Border.all(color: selected ? AniColors.olive : AniColors.sand, width: 2),
      ),
      child: selected ? const Icon(Icons.check, size: 16, color: AniColors.paper) : null,
    );
  }
}

/// Full-width olive button. `onPressed == null` renders the disabled state.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: AniColors.olive,
      foregroundColor: AniColors.paper,
      disabledBackgroundColor: AniColors.sand,
      disabledForegroundColor: AniColors.muted,
      minimumSize: const Size.fromHeight(52),
      padding: const EdgeInsets.symmetric(horizontal: AniSpacing.xl, vertical: AniSpacing.md),
      shape: const RoundedRectangleBorder(borderRadius: AniRadius.button),
      textStyle: const TextStyle(
        fontFamily: aniFontFamily,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ).copyWith(
      overlayColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.pressed) ? AniColors.oliveDark.withValues(alpha: 0.4) : null,
      ),
    );
    return SizedBox(
      width: double.infinity,
      child: icon == null
          ? FilledButton(onPressed: onPressed, style: style, child: Text(label))
          : FilledButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon, size: 20),
              label: Text(label),
            ),
    );
  }
}

/// One entry in [AniBottomNav].
class AniNavItem {
  const AniNavItem(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// Bottom navigation in the Make style: paper bar with a top hairline,
/// active tab olive with a pale olive pill behind the icon.
class AniBottomNav extends StatelessWidget {
  const AniBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<AniNavItem> items;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AniColors.paper,
        border: Border(top: BorderSide(color: AniColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavButton(
                    item: items[i],
                    selected: i == currentIndex,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});

  final AniNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AniColors.olive : AniColors.muted;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        highlightShape: BoxShape.rectangle,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: AniSpacing.md, vertical: AniSpacing.xxs),
              decoration: BoxDecoration(
                color: selected ? AniColors.statusNormalBg : Colors.transparent,
                borderRadius: AniRadius.chip,
              ),
              child: Icon(item.icon, size: 24, color: fg),
            ),
            const SizedBox(height: AniSpacing.xxs),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: aniFontFamily,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
