import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/brand.dart';
import 'motion.dart';

/// The Health Pro logo, in two versions: blue lettering for light
/// backgrounds, and white lettering for dark ones (the `_on_dark` pictures),
/// so it sits straight on the navy without a white tile.
///
/// It is built from layers rather than one picture: the mark and the name
/// (logo_base), the green heartbeat over the name (logo_heartbeat), which
/// slowly traces from left to right like a monitor, and the tagline, drawn
/// as text so it stays sharp at any size. The pictures are made from the
/// brand files in tool/brand/ by tool/brand_images.dart, which also prints
/// the boxes below.
class HealthProLogo extends StatelessWidget {
  final double height;

  /// Just the mark (the cross with the runner), without the name.
  final bool markOnly;

  /// Whether it sits on something dark: the white-lettered version. Null
  /// follows the theme; true for places that are navy in both themes (the
  /// side menu, the splash screen).
  final bool? onDark;

  /// Whether the heartbeat traces. False where the logo is saved as a
  /// picture (the QR pass, the gym poster), so it is never caught half-way.
  /// It also stands still with Reduce motion.
  final bool animate;

  /// How long after it shows the first trace starts: a moment, so a page
  /// settles first; none on the splash, which is short.
  final Duration delay;

  const HealthProLogo({
    super.key,
    this.height = 56,
    this.markOnly = false,
    this.onDark,
    this.animate = true,
    this.delay = const Duration(milliseconds: 500),
  });

  /// Width over height of the whole logo, and of the mark alone.
  static const aspectRatio = 2048 / 598;
  static const markAspectRatio = 1.0;

  /// Where the heartbeat picture goes, as fractions of the whole logo.
  static const heartbeatBox = Rect.fromLTWH(819 / 2048, 2 / 598, 841 / 2048, 244 / 598);

  /// The package the pictures are in, and each picture: 'mark', or the
  /// logo's 'logo_base' and 'logo_heartbeat'.
  static const package = 'health_pro_core';
  static const parts = ['mark', 'logo_base', 'logo_heartbeat'];
  static String assetFor(String part, {required bool onDark}) => 'assets/images/$part${onDark ? '_on_dark' : ''}.webp';

  @override
  Widget build(BuildContext context) {
    final dark = onDark ?? Theme.of(context).brightness == Brightness.dark;
    Widget fallback(BuildContext context, Object error, StackTrace? stack) => Text(
          'Health Pro',
          style: TextStyle(
            fontSize: height * 0.4,
            fontWeight: FontWeight.w900,
            color: dark ? Colors.white : BrandColors.navy,
          ),
        );
    if (markOnly) {
      return Image.asset(
        assetFor('mark', onDark: dark),
        package: package,
        height: height,
        fit: BoxFit.contain,
        semanticLabel: 'Health Pro',
        errorBuilder: fallback,
      );
    }
    final width = height * aspectRatio;
    final beat = heartbeatBox;
    return Semantics(
      label: 'Health Pro',
      image: true,
      child: SizedBox(
        width: width,
        height: height,
        child: FittedBox(
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              alignment: Alignment.topLeft,
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Image.asset(
                    assetFor('logo_base', onDark: dark),
                    package: package,
                    fit: BoxFit.fill,
                    excludeFromSemantics: true,
                    errorBuilder: fallback,
                  ),
                ),
                Positioned(
                  left: beat.left * width,
                  top: beat.top * height,
                  width: beat.width * width,
                  height: beat.height * height,
                  child: RepaintBoundary(
                    child: _Heartbeat(
                      image: AssetImage(assetFor('logo_heartbeat', onDark: dark), package: package),
                      animate: animate,
                      delay: delay,
                      onDark: dark,
                      logoHeight: height,
                    ),
                  ),
                ),
                Positioned.fill(child: CustomPaint(painter: HealthProTagline(onDark: dark))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The tagline under the name, "Your Health. Our Priority.", between two
/// tapering rules. Drawn as text (bold, slanted like the name) so it stays
/// clear at every size; paints over the whole logo's box.
class HealthProTagline extends CustomPainter {
  final bool onDark;

  const HealthProTagline({required this.onDark});

  static const text = 'Your Health. Our Priority.';

  /// The text's size, and the middle of its capitals, against the logo's
  /// height; the rules' outer ends against its width.
  static const fontSize = 0.145;
  static const capsMiddle = 0.829;
  static const rulesFrom = 0.262, rulesTo = 0.989;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final ink = onDark ? Colors.white.withValues(alpha: 0.92) : const Color(0xFF012166);
    final text = TextPainter(
      text: TextSpan(
        text: HealthProTagline.text,
        style: TextStyle(
          fontFamily: brandFont,
          fontWeight: FontWeight.w700,
          fontSize: h * fontSize,
          letterSpacing: h * fontSize * 0.02,
          height: 1,
          color: ink,
          shadows: onDark ? [Shadow(color: const Color(0xA6040A1A), blurRadius: h * 0.025)] : null,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    // Capitals are about 0.72 of the size: the baseline sits that far below
    // the middle of them.
    final baseline = h * capsMiddle + h * fontSize * 0.36;
    final top = baseline - text.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final gap = h * 0.05;
    final ruleSpace = (w * (rulesTo - rulesFrom) - text.width - gap * 2) / 2;
    final textLeft = w * rulesFrom + ruleSpace + gap;
    canvas
      ..save()
      // Slanted like the name: the foot moves left of the top.
      ..translate(0, baseline)
      ..skew(-0.2, 0)
      ..translate(0, -baseline);
    text.paint(canvas, Offset(textLeft, top));
    canvas.restore();

    // The rules: thin at the outside, thickest next to the text.
    final ruleY = h * capsMiddle;
    final thick = h * 0.022;
    final rule = onDark
        ? [Colors.white.withValues(alpha: 0.15), Colors.white.withValues(alpha: 0.85)]
        : [const Color(0x332F86E8), const Color(0xFF0141A6)];
    void taper(double outer, double inner) {
      final path = Path()
        ..moveTo(outer, ruleY)
        ..lineTo(inner, ruleY - thick / 2)
        ..lineTo(inner, ruleY + thick / 2)
        ..close();
      final shader = LinearGradient(colors: rule).createShader(Rect.fromPoints(Offset(outer, ruleY), Offset(inner, ruleY + 1)));
      canvas.drawPath(path, Paint()..shader = shader);
    }

    if (ruleSpace > h * 0.08) {
      taper(w * rulesFrom, w * rulesFrom + ruleSpace);
      taper(w * rulesTo, w * rulesTo - ruleSpace);
    }
  }

  @override
  bool shouldRepaint(HealthProTagline old) => old.onDark != onDark;
}

/// The green heartbeat, tracing slowly from left to right: a bright head
/// runs along the line with a glowing tail, and just ahead of it the old
/// trace fades and comes back, as on a heart monitor. Then it rests a
/// moment and goes again. Still with Reduce motion, or when not [animate].
class _Heartbeat extends StatefulWidget {
  final ImageProvider image;
  final bool animate;
  final Duration delay;
  final bool onDark;
  final double logoHeight;

  const _Heartbeat({
    required this.image,
    required this.animate,
    required this.delay,
    required this.onDark,
    required this.logoHeight,
  });

  @override
  State<_Heartbeat> createState() => _HeartbeatState();
}

class _HeartbeatState extends State<_Heartbeat> with SingleTickerProviderStateMixin {
  /// Slow on purpose: a calm, resting pulse.
  static const _trace = Duration(milliseconds: 4800);
  static const _rest = Duration(milliseconds: 1600);

  // Made at once, so one that never ran (less motion) can still be put away.
  late final AnimationController _c = AnimationController(vsync: this, duration: _trace)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) _goAfter(_rest);
    });

  // Between traces nothing is drawn: a timer waits, not the animation.
  Timer? _wait;

  bool get _runs => widget.animate && !reduceMotion(context);

  void _goAfter(Duration delay) {
    _wait?.cancel();
    _wait = Timer(delay, () {
      _wait = null;
      if (mounted && _runs) _c.forward(from: 0);
    });
  }

  void _update() {
    if (_runs) {
      if (!_c.isAnimating && _wait == null) _goAfter(widget.delay);
    } else {
      _wait?.cancel();
      _wait = null;
      _c.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(_Heartbeat old) {
    super.didUpdateWidget(old);
    _update();
  }

  @override
  void dispose() {
    _wait?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = Image(image: widget.image, fit: BoxFit.fill, excludeFromSemantics: true, gaplessPlayback: true);
    if (!_runs) return line;
    // Near white on the navy; on white, a vivid lime (a pale one would look
    // like the line fading).
    final glow = widget.onDark ? const Color(0xFFE2FF8A) : const Color(0xFF9EF01A);
    final bloom = widget.logoHeight * 0.035;
    return AnimatedBuilder(
      animation: _c,
      child: line,
      builder: (context, line) {
        if (!_c.isAnimating) return line!;
        // The head, across the line's width; it starts and ends out of
        // sight, so a trace begins and finishes on the whole line.
        final head = -0.3 + _c.value * 1.65;
        double at(double x) => x.clamp(0.0, 1.0);
        // The glowing tail behind the head, in [colour].
        Shader tail(Rect bounds, Color colour) => LinearGradient(
              colors: [colour.withValues(alpha: 0), colour.withValues(alpha: 0), colour, colour.withValues(alpha: 0), colour.withValues(alpha: 0)],
              stops: [0, at(head - 0.2), at(head), at(head + 0.006), 1],
            ).createShader(bounds);
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            // A soft light round the head.
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: bloom, sigmaY: bloom),
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => tail(bounds, Colors.white),
                child: ColorFiltered(colorFilter: ColorFilter.mode(glow.withValues(alpha: 0.9), BlendMode.srcIn), child: line),
              ),
            ),
            ShaderMask(
              // Ahead of the head the old trace fades, then comes back.
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  Colors.white,
                  Colors.white,
                  Colors.white.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.12),
                  Colors.white,
                  Colors.white,
                ],
                stops: [0, at(head), at(head + 0.03), at(head + 0.13), at(head + 0.24), 1],
              ).createShader(bounds),
              // The head and its tail, lit.
              child: ShaderMask(blendMode: BlendMode.srcATop, shaderCallback: (bounds) => tail(bounds, glow), child: line),
            ),
          ],
        );
      },
    );
  }
}
