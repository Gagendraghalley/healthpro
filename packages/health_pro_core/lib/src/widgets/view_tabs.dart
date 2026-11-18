import 'package:flutter/material.dart';

import '../theme/brand.dart';
import 'motion.dart';

/// One of [ViewTabs]: its [label], an [icon], and a [count] beside it
/// (null for none).
class ViewTab<T> {
  final T value;
  final String label;
  final IconData icon;
  final int? count;

  const ViewTab({required this.value, required this.label, required this.icon, this.count});
}

/// A page's views, side by side on a soft track: the open one raised on a
/// card, its icon in the highlight colour, each with its count. On a phone
/// ([compactBelow]) the tabs share the width and drop their icons (and
/// their counts, where even that is too narrow). The change eases in
/// ([Motion.hover]) and is instant with Reduce motion.
class ViewTabs<T> extends StatelessWidget {
  final List<ViewTab<T>> tabs;
  final T selected;
  final ValueChanged<T> onChanged;
  final double compactBelow;

  const ViewTabs({super.key, required this.tabs, required this.selected, required this.onChanged, this.compactBelow = 520});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < compactBelow;
        // A tab's share of a phone's width, after the track's padding and the gaps.
        final share = (constraints.maxWidth - 10 - 4 * (tabs.length - 1)) / tabs.length;
        final counts = !compact || share >= 104;
        final row = Row(
          mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
          children: [
            for (final (i, t) in tabs.indexed) ...[
              if (i > 0) const SizedBox(width: 4),
              if (compact)
                Expanded(
                    child: _Tab(tab: t, selected: t.value == selected, compact: true, counts: counts, onTap: () => onChanged(t.value)))
              else
                _Tab(tab: t, selected: t.value == selected, compact: false, counts: true, onTap: () => onChanged(t.value)),
            ],
          ],
        );
        final track = Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: brand.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: brand.fieldBorder.withValues(alpha: brand.isLight ? 0.6 : 0.3)),
          ),
          child: row,
        );
        return Semantics(container: true, explicitChildNodes: true, child: compact ? track : Align(alignment: Alignment.centerLeft, child: track));
      },
    );
  }
}

class _Tab<T> extends StatelessWidget {
  final ViewTab<T> tab;
  final bool selected;
  final bool compact;
  final bool counts;
  final VoidCallback onTap;

  const _Tab({required this.tab, required this.selected, required this.compact, required this.counts, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final duration = Motion.of(context, Motion.hover);
    final ink = selected ? brand.ink : brand.muted;
    final count = counts ? tab.count : null;
    // Raised on a card in the light; a lighter pill in the dark, where a shadow doesn't show.
    final fill = brand.isLight ? brand.card : Colors.white.withValues(alpha: 0.09);
    return Semantics(
      button: true,
      selected: selected,
      label: count == null ? tab.label : '${tab.label}, $count',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: duration,
        curve: Motion.ease,
        decoration: BoxDecoration(
          color: selected ? fill : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected && brand.isLight ? brand.cardShadow : const [],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: selected ? null : onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 14, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!compact) ...[
                    AnimatedSwitcher(
                      duration: duration,
                      child: Icon(tab.icon, key: ValueKey(selected), size: 18, color: selected ? brand.highlight : brand.muted),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: AnimatedDefaultTextStyle(
                      duration: duration,
                      curve: Motion.ease,
                      style: TextStyle(
                        fontFamily: brandFont,
                        fontSize: compact ? 13 : 14,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                        color: ink,
                      ),
                      child: Text(tab.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  if (count != null) ...[
                    SizedBox(width: compact ? 4 : 6),
                    AnimatedContainer(
                      duration: duration,
                      curve: Motion.ease,
                      constraints: const BoxConstraints(minWidth: 22),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: (selected ? brand.highlight : brand.muted).withValues(alpha: selected ? 0.14 : 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: selected ? brand.readable(brand.highlight) : brand.muted,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
