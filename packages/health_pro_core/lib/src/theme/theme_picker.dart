import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/common.dart';
import '../widgets/motion.dart';
import 'brand.dart';
import 'theme_colors.dart';

/// Pick the app's two colours. Each shows at once, behind the dialog, and
/// stays on this device.
Future<void> showThemeColorPicker(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const ThemeColorDialog());

/// "App theme" in Account -> Appearance: the two colours they have, and a tap
/// to change them.
class ThemeColorsTile extends ConsumerWidget {
  const ThemeColorsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picked = ref.watch(themeColorsProvider);
    final brightness = Theme.of(context).brightness;
    final brand = context.brand;
    Widget dot(ThemeSwatch swatch) => Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
              color: swatch.shown(brightness), shape: BoxShape.circle, border: Border.all(color: brand.glassBorder)),
        );
    return SettingRow(
      icon: Icons.palette_outlined,
      title: 'App theme',
      subtitle: '${picked.primary.name} and ${picked.accent.name.toLowerCase()}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot(picked.primary),
          dot(picked.accent),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, color: brand.muted),
        ],
      ),
      onTap: () => showThemeColorPicker(context),
    );
  }
}

/// A primary colour and an accent colour, each a set of dots; and back to
/// Health Pro's own.
class ThemeColorDialog extends ConsumerWidget {
  const ThemeColorDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picked = ref.watch(themeColorsProvider);
    final colors = ref.read(themeColorsProvider.notifier);
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final heading = context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700);
    final note = TextStyle(color: context.brand.muted, fontSize: 13);
    return AlertDialog(
      title: const Text('Pick colour theme'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Primary colours', style: heading),
              const SizedBox(height: 2),
              Text(dark ? 'Buttons, what\'s active, switches and focus' : 'What\'s active, the main actions, switches and focus',
                  style: note),
              const SizedBox(height: 12),
              SwatchGrid(swatches: ThemePalette.primaries, selected: picked.primary, onPick: colors.setPrimary),
              const SizedBox(height: 24),
              Text('Accent colours', style: heading),
              const SizedBox(height: 2),
              Text(dark ? 'Selected chips, tabs and segments' : 'Buttons, selected chips and tabs', style: note),
              const SizedBox(height: 12),
              SwatchGrid(swatches: ThemePalette.accents, selected: picked.accent, onPick: colors.setAccent),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  // In the orange it goes back to.
                  style: FilledButton.styleFrom(
                      backgroundColor: ThemePalette.orange.shown(brightness), foregroundColor: Colors.white),
                  onPressed: colors.reset,
                  child: const Text('Reset to default orange'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}

/// [swatches] as round dots, six to a row as room allows; [selected] ringed,
/// with a tick.
class SwatchGrid extends StatelessWidget {
  final List<ThemeSwatch> swatches;
  final ThemeSwatch selected;
  final ValueChanged<ThemeSwatch> onPick;

  const SwatchGrid({super.key, required this.swatches, required this.selected, required this.onPick});

  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return LayoutBuilder(builder: (context, constraints) {
      final size = ((constraints.maxWidth - _gap * 5) / 6).clamp(30.0, 44.0);
      return Wrap(
        spacing: _gap,
        runSpacing: _gap,
        children: [
          for (final swatch in swatches)
            _SwatchDot(
              name: swatch.name,
              color: swatch.shown(brightness),
              size: size,
              selected: swatch == selected,
              onTap: () => onPick(swatch),
            ),
        ],
      );
    });
  }
}

class _SwatchDot extends StatelessWidget {
  final String name;
  final Color color;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  const _SwatchDot(
      {required this.name, required this.color, required this.size, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    final ring = context.colors.onSurface;
    // White on deep colours, navy on soft ones.
    final tick = ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : BrandColors.navy;
    return Tooltip(
      message: name,
      child: Semantics(
        label: name,
        selected: selected,
        child: AnimatedContainer(
          duration: still ? Duration.zero : Motion.press,
          curve: Motion.ease,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            // A faint edge keeps the palest dots apart from the dialog.
            border: Border.all(
                color: selected ? ring : ring.withValues(alpha: 0.12), width: selected ? 3 : 1),
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: AnimatedScale(
                scale: selected ? 1 : 0,
                duration: still ? Duration.zero : Motion.press,
                curve: Motion.pop,
                child: Icon(Icons.check_rounded, size: 18, color: tick),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
