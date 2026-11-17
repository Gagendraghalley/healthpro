import 'package:flutter/material.dart';

import '../theme/brand.dart';
import 'motion.dart';

// The deep band at the top of a dashboard (the greeting, the date, the
// first shortcuts), and the pieces that sit on it. Its colours come from
// the theme, so a colour picked under Account -> Appearance carries
// through.

/// The band's colours, from the app's theme: deep in the colour of the
/// light theme's buttons (navy, or the one picked), or in the dark the
/// page's navy tinted with it. Its bright glow is the main colour
/// ([Brand.highlight]).
@immutable
class DeepTone {
  final Color base;

  /// How much lighter its top left is: less in the dark, so it stays deep.
  final double lift;

  const DeepTone(this.base, {this.lift = 0.12});

  factory DeepTone.of(BuildContext context) {
    final brand = context.brand;
    final scheme = Theme.of(context).colorScheme;
    // The light theme's buttons are its primary; the dark's, its secondary.
    return DeepTone(
      brand.pick(scheme.primary, Color.lerp(BrandColors.navy, scheme.secondary, 0.13)!),
      lift: 0.12 - 0.07 * brand.darkness,
    );
  }

  /// Lighter at the top left, deepest at the bottom right.
  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(base, Colors.white, lift)!, base, shade],
      );

  Color get shade => Color.lerp(base, Colors.black, 0.4)!;

  /// The soft glow opposite the bright one: the same colour, lighter.
  Color get glow => Color.lerp(base, Colors.white, 0.45)!;
}

/// A soft round glow of [color], [strength] at its heart, fading out.
class SoftGlow extends StatelessWidget {
  final Color color;
  final double size;
  final double strength;

  const SoftGlow({super.key, required this.color, required this.size, required this.strength});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color.withValues(alpha: strength), color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

/// The deep band at the top of a dashboard: [eyebrow] small over [title],
/// [subtitle] under it and [bottom] (shortcuts) under that; [leading] (an
/// avatar) before them and [trailing] (a pill) across from them. Soft glows
/// drift over it. On a narrow page [leading] and [trailing] go on a row
/// above.
class WelcomeBand extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final Widget? bottom;

  const WelcomeBand({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.leading,
    this.trailing,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final deep = DeepTone.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: deep.gradient,
        boxShadow: [
          BoxShadow(color: deep.base.withValues(alpha: 0.24), blurRadius: 34, spreadRadius: -6, offset: const Offset(0, 18)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -80,
            top: -130,
            child: GentleFloat(
              distance: 14,
              period: const Duration(milliseconds: 5600),
              child: SoftGlow(color: brand.highlight, size: 320, strength: 0.42),
            ),
          ),
          Positioned(
            left: -110,
            bottom: -180,
            child: GentleFloat(
              distance: 12,
              phase: 0.5,
              period: const Duration(milliseconds: 6400),
              child: SoftGlow(color: deep.glow, size: 360, strength: 0.26),
            ),
          ),
          const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Rings()))),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 700;
              final words = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (eyebrow != null) ...[
                    Text(
                      eyebrow!.toUpperCase(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: wide ? 30 : 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1.15,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle!,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 14.5, height: 1.4),
                    ),
                  ],
                  if (bottom != null) ...[const SizedBox(height: 18), bottom!],
                ],
              );
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: wide ? 30 : 20, vertical: wide ? 28 : 22),
                child: wide
                    ? Row(
                        children: [
                          if (leading != null) ...[leading!, const SizedBox(width: 20)],
                          Expanded(child: words),
                          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (leading != null || trailing != null) ...[
                            Row(children: [if (leading != null) leading!, const Spacer(), if (trailing != null) trailing!]),
                            const SizedBox(height: 16),
                          ],
                          words,
                        ],
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Faint rings spreading from the band's top right corner.
class _Rings extends CustomPainter {
  const _Rings();

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width - 60, -10);
    for (var i = 0; i < 5; i++) {
      canvas.drawCircle(
        centre,
        80.0 + i * 56,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.07 - i * 0.011),
      );
    }
  }

  @override
  bool shouldRepaint(_Rings old) => false;
}

/// An initial in a bright ringed circle on the band, popping in.
class BandAvatar extends StatelessWidget {
  final String initial;
  final double size;

  const BandAvatar({super.key, required this.initial, this.size = 68});

  /// The first letter of [name], or '?'.
  static String initialOf(String name) => name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return PopIn(
      delay: const Duration(milliseconds: 180),
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.5),
          boxShadow: [BoxShadow(color: brand.highlight.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 8))],
        ),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [brand.themedShade(const Color(0xFFFFA24D)), brand.highlight],
            ),
          ),
          child: Text(initial, style: TextStyle(color: Colors.white, fontSize: size * 0.4, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

/// A glassy pill on the band: an icon, with a bright [dot] when there's
/// something new, and its words. A tap opens what it's about.
class BandPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool dot;
  final VoidCallback onTap;

  const BandPill({super.key, required this.icon, required this.label, required this.onTap, this.dot = false});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Pressable(
      child: Material(
        color: Colors.white.withValues(alpha: 0.1),
        shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.16))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, size: 18, color: Colors.white),
                    if (dot)
                      Positioned(
                        right: -1,
                        top: -1,
                        child: PopIn(
                          delay: const Duration(milliseconds: 450),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: brand.highlight,
                              shape: BoxShape.circle,
                              border: Border.all(color: DeepTone.of(context).base, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A shortcut on the band: the [main] one in the bright colour, the rest
/// glassy white. Each gives a little under the hand.
class BandAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool main;

  const BandAction({super.key, required this.icon, required this.label, required this.onPressed, this.main = false});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: main ? context.brand.highlight : Colors.white.withValues(alpha: 0.12),
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          side: main ? null : BorderSide(color: Colors.white.withValues(alpha: 0.16)),
          textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 14.5),
        ),
        icon: Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }
}
