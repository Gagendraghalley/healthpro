import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../assistant/assistant_chat.dart';
import '../assistant/public_assistant.dart';
import '../theme/brand.dart';
import '../widgets/feedback.dart';
import '../widgets/logo.dart';
import '../widgets/motion.dart';

/// What the photo says beside the form: Health Pro's perks in a bar along
/// the foot (signing in), or a welcome with a short list of them (joining).
enum AuthSide { signIn, join }

/// The frame of the sign-in, sign-up and code pages: a navy panel on the
/// left with the logo, a headline and what Health Pro offers, fading into
/// the Bhutan photo on the right, and the form on a white card over it. On a phone the photo is a
/// banner and the form a sheet under it. Back at the top left, Ask AI at the
/// top right.
class AuthLayout extends StatelessWidget {
  final AuthSide side;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// Where the back button goes. Given, the button always shows (signing in
  /// and up go back to the Welcome page); else it shows only when there is
  /// a page to go back to, and goes there.
  final VoidCallback? onBack;

  const AuthLayout({
    super.key,
    required this.side,
    required this.title,
    this.subtitle,
    required this.children,
    this.onBack,
  });

  /// The photo behind every sign-in page (assets/PHOTO_CREDITS.md): save
  /// another over it to change it.
  static const photo = 'assets/auth/background.jpg';

  /// The photo's width over its height (1672 x 941).
  static const photoAspect = 1672 / 941;

  /// The photo fills the window from this width; under it, it's a banner.
  static const wideFrom = 900.0;

  /// The card's width on a computer.
  static const cardWidth = 448.0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= wideFrom;
    final backButton = onBack != null
        ? _BackButton(tooltip: 'Back to home', onPressed: onBack!)
        : Navigator.of(context).canPop()
            ? _BackButton(tooltip: 'Back', onPressed: () => Navigator.of(context).maybePop())
            : null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The photo is dark at the top in both layouts.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: wide ? _navy(context) : context.colors.surface,
        body: _AuthInputs(child: wide ? _wide(context, backButton) : _narrow(context, backButton)),
      ),
    );
  }

  /// The title, its line and the fields arrive one after another, a beat
  /// behind the card; the fields as one, so nothing shuffles when an error
  /// appears among them.
  Widget _form(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeSlideIn(
          delay: const Duration(milliseconds: 120),
          offset: 12,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 30,
              height: 1.15,
              letterSpacing: -0.6,
              fontWeight: FontWeight.w800,
              color: context.brand.ink,
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          FadeSlideIn(
            delay: const Duration(milliseconds: 180),
            offset: 12,
            child: Text(subtitle!,
                style: TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w500, color: context.brand.muted)),
          ),
        ],
        const SizedBox(height: 26),
        FadeSlideIn(
          delay: const Duration(milliseconds: 240),
          offset: 12,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
        ),
      ],
    );
  }

  Widget _wide(BuildContext context, Widget? backButton) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The same photo on every sign-in page: it stays put as they move
        // between them, and only the card changes.
        _WidePhoto(navy: _navy(context)),
        SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(40, 28, 28, 32),
                  child: _Showcase(side: side, backButton: backButton),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  // Room at the top for Ask AI over it.
                  padding: const EdgeInsets.fromLTRB(16, 88, 48, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 80),
                        child: Container(
                          width: cardWidth,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: context.colors.surface,
                            // The app's standard card edge.
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: context.brand.glassBorder),
                            boxShadow: dark
                                ? const [BoxShadow(color: Color(0x47000000), blurRadius: 50, offset: Offset(0, 24))]
                                : const [BoxShadow(color: Color(0x40050B1C), blurRadius: 44, offset: Offset(0, 20))],
                          ),
                          child: Stack(
                            children: [
                              Padding(padding: const EdgeInsets.fromLTRB(36, 36, 36, 28), child: _form(context)),
                              // An orange line growing along the card's top.
                              Positioned(
                                left: 0,
                                right: 0,
                                top: 0,
                                height: 3,
                                child: _GrowIn(
                                  delay: const Duration(milliseconds: 380),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          context.brand.highlight.withValues(alpha: 0),
                                          context.brand.highlight,
                                          context.brand.highlight.withValues(alpha: 0),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Ask AI in the top corner, level with Back, over the card's edge.
        const SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(padding: EdgeInsets.fromLTRB(16, 28, 48, 0), child: FadeSlideIn(child: _AskAiButton())),
          ),
        ),
      ],
    );
  }

  Widget _narrow(BuildContext context, Widget? backButton) {
    final insets = MediaQuery.paddingOf(context);
    final navy = _navy(context);
    final join = side == AuthSide.join;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The photo along the top fading down into the navy, the headline
          // on the navy under it, as on a computer.
          ColoredBox(
            color: navy,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: insets.top + 190,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // The rainbow's top just behind the buttons, over the dzong.
                      const Hero(
                        tag: _Photo.heroTag,
                        child: ClipRect(child: _Drift(child: _Sky(rainbow: _Rainbow(center: Offset(0.5, 1.25), radius: 0.6)))),
                      ),
                      // A shade at the top for the buttons, clear over the dzong.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [navy.withValues(alpha: 0.5), navy.withValues(alpha: 0), navy.withValues(alpha: 0), navy],
                            stops: const [0, 0.3, 0.55, 0.95],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  // Room at the foot for the sheet rising over it.
                  padding: EdgeInsets.fromLTRB(20, insets.top + 8, 12, 54),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (backButton != null) ...[backButton, const SizedBox(width: 10)],
                          // Catching the light once it has arrived.
                          const Expanded(
                            child: FadeSlideIn(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: _Sheen(
                                    delay: Duration(milliseconds: 700),
                                    child: HealthProLogo(height: 52, onDark: true),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const _AskAiButton(),
                        ],
                      ),
                      // A short strip of photo: the form comes first.
                      const SizedBox(height: 56),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _Pitch(
                          eyebrow: 'Gyms across Bhutan',
                          lines: join ? ('Join', 'Health Pro.') : ('Your Health.', 'Our Priority.'),
                          body: join
                              ? 'Be part of our fitness community'
                              : 'Find a gym, join in minutes and check in with your phone.',
                          size: 36,
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // The sheet rises over the foot of the banner, sliding up into
          // place as the page opens.
          Transform.translate(
            offset: const Offset(0, -30),
            child: FadeSlideIn(
              offset: 40,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 30, 20, insets.bottom + 4),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: FadeSlideIn(child: _form(context)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The photo's slow breath: a gentle push in towards the dzong over 15
/// seconds and back again, calm enough to sit behind a form; still when
/// they ask for less motion. Where it is in the swing comes from the clock,
/// so moving between the sign-in pages doesn't jump it.
class _Drift extends StatefulWidget {
  final Widget child;

  const _Drift({required this.child});

  @override
  State<_Drift> createState() => _DriftState();
}

class _DriftState extends State<_Drift> with SingleTickerProviderStateMixin {
  static const _period = Duration(seconds: 30);

  late final AnimationController _swing = AnimationController(vsync: this, duration: _period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _swing.value = 0;
    } else if (!_swing.isAnimating) {
      _swing.value = DateTime.now().millisecondsSinceEpoch % _period.inMilliseconds / _period.inMilliseconds;
      _swing.repeat();
    }
  }

  @override
  void dispose() {
    _swing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _swing,
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        final t = _swing.value;
        final closer = Motion.easeInOut.transform(t < 0.5 ? t * 2 : 2 - t * 2);
        // The dzong, on the photo's left.
        return Transform.scale(scale: 1 + 0.08 * closer, alignment: const Alignment(-0.5, 0.05), child: child);
      },
    );
  }
}

/// The photo with a rainbow in its sky.
class _Sky extends StatelessWidget {
  final _Rainbow rainbow;

  const _Sky({required this.rainbow});

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [const _Photo(), rainbow]);
}

/// A soft rainbow arching over the photo: drawn in from its left foot the
/// first time a sign-in page opens, then a light running along it every
/// few seconds as it glows a little brighter and back; still when they ask
/// for less motion. [center] is a share of the box's width and height,
/// [radius] a share of its width; its feet fade into the hills.
class _Rainbow extends StatefulWidget {
  final Offset center;
  final double radius;

  const _Rainbow({required this.center, required this.radius});

  @override
  State<_Rainbow> createState() => _RainbowState();
}

class _RainbowState extends State<_Rainbow> with TickerProviderStateMixin {
  static const _period = Duration(seconds: 9);

  /// Drawn in once: moving between the sign-in pages doesn't draw it again.
  static bool _drawn = false;

  late final AnimationController _draw =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400), value: _drawn ? 1 : 0);
  late final AnimationController _cycle = AnimationController(vsync: this, duration: _period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _draw.value = 1;
      _cycle.value = 0;
    } else {
      if (!_drawn) {
        _drawn = true;
        _draw.forward();
      }
      if (!_cycle.isAnimating) {
        // From the clock, so the light carries on where it was on the last page.
        _cycle.value = DateTime.now().millisecondsSinceEpoch % _period.inMilliseconds / _period.inMilliseconds;
        _cycle.repeat();
      }
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_draw, _cycle]),
          builder: (context, _) {
            final t = _cycle.value;
            return CustomPaint(
              painter: _RainbowPainter(
                center: widget.center,
                radius: widget.radius,
                reveal: Motion.easeInOut.transform(_draw.value),
                // The light runs along it in the first part of each cycle, then rests.
                glint: still || t > 0.4 ? null : t / 0.4,
                glow: still ? 1 : 0.92 + 0.08 * math.sin(t * 2 * math.pi),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RainbowPainter extends CustomPainter {
  final Offset center;
  final double radius;
  final double reveal;
  final double? glint;
  final double glow;

  const _RainbowPainter({
    required this.center,
    required this.radius,
    required this.reveal,
    required this.glint,
    required this.glow,
  });

  /// Outside in, as in the sky.
  static const _colors = [
    Color(0xFFFF4D5E),
    Color(0xFFFF9A3C),
    Color(0xFFFFE05C),
    Color(0xFF5EE087),
    Color(0xFF45B8F5),
    Color(0xFF6C7CFF),
    Color(0xFFB57BFF),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (reveal <= 0) return;
    final c = Offset(center.dx * size.width, center.dy * size.height);
    final r = radius * size.width;
    final circle = Rect.fromCircle(center: c, radius: r);
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint()..color = Color.fromRGBO(0, 0, 0, 0.88 * glow));

    // Drawn from its left foot, over the top, to its right one.
    canvas.clipPath(Path()
      ..moveTo(c.dx, c.dy)
      ..arcTo(Rect.fromCircle(center: c, radius: r * 1.1), math.pi, math.pi * reveal, false)
      ..close());

    // The band: crisp-edged, violet inside to red outside.
    const band = 0.1;
    final stops = <double>[1 - band];
    for (var i = 0; i < _colors.length; i++) {
      stops.add(1 - band + band * (0.04 + 0.92 * i / (_colors.length - 1)));
    }
    stops.add(1);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [const Color(0x00B57BFF), ..._colors.reversed, const Color(0x00FF4D5E)],
          stops: stops,
        ).createShader(circle),
    );

    // A light running along it.
    final at = glint;
    if (at != null) {
      final angle = math.pi + math.pi * at;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..blendMode = BlendMode.srcATop
          ..shader = SweepGradient(
            colors: const [Color(0x00FFFFFF), Color(0xB3FFFFFF), Color(0x00FFFFFF)],
            stops: const [0, 0.03, 0.06],
            transform: GradientRotation(angle - 0.03 * 2 * math.pi),
          ).createShader(circle),
      );
    }

    // Its feet fading into the hills.
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          stops: [0, ((c.dy - r * 0.55) / size.height).clamp(0.0, 1.0), ((c.dy - r * 0.1) / size.height).clamp(0.0, 1.0)],
        ).createShader(bounds),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RainbowPainter old) =>
      old.center != center || old.radius != radius || old.reveal != reveal || old.glint != glint || old.glow != glow;
}

/// The photo, cropped to fill; navy if it can't be read. The first time,
/// it fades up from the navy and settles from a slight zoom: once, then
/// still.
class _Photo extends StatelessWidget {
  const _Photo();

  static const heroTag = 'health-pro-auth-photo';

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return Image.asset(
      AuthLayout.photo,
      package: HealthProLogo.package,
      fit: BoxFit.cover,
      // Keeping the dzong (the photo's left) when the window crops it.
      alignment: const Alignment(-0.6, -0.6),
      excludeFromSemantics: true,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, synchronous) {
        // Already in memory (another sign-in page): no entrance.
        if (synchronous || still) return child;
        final shown = frame != null;
        return AnimatedOpacity(
          opacity: shown ? 1 : 0,
          duration: const Duration(milliseconds: 700),
          curve: Motion.ease,
          child: AnimatedScale(
            scale: shown ? 1 : 1.06,
            duration: const Duration(milliseconds: 1600),
            curve: Motion.ease,
            child: child,
          ),
        );
      },
      errorBuilder: (_, __, ___) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [BrandColors.midnight, BrandColors.night],
          ),
        ),
      ),
    );
  }
}

/// The navy of the panel on a computer: royal navy in light, the night in dark.
Color _navy(BuildContext context) => context.brand.pick(const Color(0xFF0C2152), BrandColors.night);

/// On a computer: the photo on the right, its dzong just clear of the card,
/// with the navy panel on the left fading into it, and a light shade along
/// the top for Ask AI on the bright sky.
class _WidePhoto extends StatelessWidget {
  final Color navy;

  const _WidePhoto({required this.navy});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final cardLeft = w - AuthLayout.cardWidth - 48;
        // As tall as the window, and always reaching past the card.
        final photoWidth = math.max(h * AuthLayout.photoAspect, 820.0);
        final photoHeight = photoWidth / AuthLayout.photoAspect;
        // The dzong ends about 37% of the way across the photo.
        final photoLeft = cardLeft - 16 - 0.37 * photoWidth;
        // Solid navy over the photo's left edge, clear just into the dzong.
        final solid = (photoLeft / w).clamp(0.18, 0.6);
        final clear = math.min(0.95, solid + 0.18 * photoWidth / w);
        return Stack(
          children: [
            Positioned(
              left: photoLeft,
              top: (h - photoHeight) / 2,
              width: photoWidth,
              height: photoHeight,
              // The rainbow over the dzong, its top just left of the card.
              child: const Hero(
                tag: _Photo.heroTag,
                child: ClipRect(child: _Drift(child: _Sky(rainbow: _Rainbow(center: Offset(0.27, 0.66), radius: 0.29)))),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [navy, navy, navy.withValues(alpha: 0)], stops: [0, solid, clear]),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: h * 0.3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [navy.withValues(alpha: 0.35), navy.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A light sweeping across [child] a couple of times, [delay] after it
/// shows; then it rests.
class _Sheen extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _Sheen({required this.child, this.delay = Duration.zero});

  @override
  State<_Sheen> createState() => _SheenState();
}

class _SheenState extends State<_Sheen> with SingleTickerProviderStateMixin {
  static const _sweeps = 2;
  static const _sweep = Duration(milliseconds: 1000);
  // Made at once, so one that never swept (less motion) can still be put
  // away.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.delay + _sweep * _sweeps);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && !_c.isAnimating && !_c.isCompleted) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final after = _c.value * _c.duration!.inMilliseconds - widget.delay.inMilliseconds;
        if (after <= 0 || _c.isCompleted) return child!;
        final t = Motion.easeInOut.transform((after / _sweep.inMilliseconds) % 1);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.5), Colors.white.withValues(alpha: 0)],
            stops: const [0.35, 0.5, 0.65],
            transform: _SheenSlide(t),
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

/// Moves the sheen from beyond the left edge to beyond the right.
class _SheenSlide extends GradientTransform {
  final double t;

  const _SheenSlide(this.t);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2.4 - 1.2), 0, 0);
}

/// [child] growing out from its left end, [delay] after it shows.
class _GrowIn extends StatelessWidget {
  final Widget child;
  final Duration delay;

  const _GrowIn({required this.child, this.delay = Duration.zero});

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    final total = delay + const Duration(milliseconds: 700);
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      builder: (context, t, child) {
        final local = t <= start ? 0.0 : Motion.ease.transform((t - start) / (1 - start));
        return Transform(
            alignment: Alignment.centerLeft, transform: Matrix4.diagonal3Values(local, 1, 1), child: child);
      },
      child: child,
    );
  }
}

/// The navy side on a computer: the logo, a headline, and what Health Pro
/// gives, numbered along the foot.
class _Showcase extends StatelessWidget {
  final AuthSide side;
  final Widget? backButton;

  const _Showcase({required this.side, required this.backButton});

  static const _signIn = ['Find a gym', 'Membership management', 'QR check-in', 'Analytics & reports'];
  static const _join = ['Find gyms across Bhutan', 'Your membership card on your phone', 'One account, on the web and in the app'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // A short or narrow window keeps just the logo.
        final room = box.maxHeight >= 600 && box.maxWidth >= 340;
        final join = side == AuthSide.join;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (backButton != null) ...[backButton!, const SizedBox(width: 14)],
                // Smaller when the navy side is narrow.
                // Catching the light once it has arrived.
                const Flexible(
                  child: FadeSlideIn(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: _Sheen(delay: Duration(milliseconds: 700), child: HealthProLogo(height: 96, onDark: true)),
                    ),
                  ),
                ),
              ],
            ),
            if (room) ...[
              const Spacer(flex: 2),
              _Pitch(
                eyebrow: 'Gyms across Bhutan',
                lines: join ? ('Join', 'Health Pro.') : ('Your Health.', 'Our Priority.'),
                body: join ? 'Be part of our fitness community' : 'Find a gym, join in minutes and check in with your phone.',
                size: (box.maxWidth * 0.062).clamp(36.0, 64.0),
              ),
              const Spacer(flex: 3),
              _Steps(join ? _join : _signIn, wide: box.maxWidth >= 520),
            ] else
              const Spacer(),
          ],
        );
      },
    );
  }
}

/// The headline down the navy side: a small spaced-out line, two big ones
/// (the second in the brand's orange), and a sentence under them.
class _Pitch extends StatelessWidget {
  final String eyebrow;
  final (String, String) lines;
  final String body;
  final double size;

  /// Smaller words and gaps, on a phone.
  final bool compact;

  const _Pitch({
    required this.eyebrow,
    required this.lines,
    required this.body,
    required this.size,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: staggered([
        Text(
          eyebrow.toUpperCase(),
          style: TextStyle(
            color: const Color(0xFFA5B4E0),
            fontSize: compact ? 12 : 14,
            letterSpacing: compact ? 3 : 3.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: compact ? 12 : 18),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${lines.$1}\n'),
                TextSpan(text: lines.$2, style: TextStyle(color: context.brand.highlight)),
              ],
            ),
            style: TextStyle(
              color: Colors.white,
              fontSize: size,
              height: 1.04,
              letterSpacing: -0.035 * size,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: compact ? 12 : 22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(
              body,
              style: TextStyle(
                color: const Color(0xFFC9D3EA),
                fontSize: compact ? 15.5 : 19,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// What Health Pro gives, along the foot: each under a thin rule, its number
/// in the brand's orange over its words. One row, or rows of two where the
/// navy side is narrow.
class _Steps extends StatelessWidget {
  final List<String> labels;
  final bool wide;

  const _Steps(this.labels, {required this.wide});

  @override
  Widget build(BuildContext context) {
    // Each rule drawn in, then its words, one after another.
    final items = <Widget>[
      for (final (i, label) in labels.indexed)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _GrowIn(
              delay: Duration(milliseconds: 420 + 90 * i),
              child: Container(height: 2, color: const Color(0xFF2A4790)),
            ),
            const SizedBox(height: 16),
            FadeSlideIn(
              delay: Duration(milliseconds: 480 + 90 * i),
              offset: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${i + 1}'.padLeft(2, '0'),
                    style: TextStyle(color: context.brand.highlight, fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(color: Color(0x66000000), blurRadius: 10)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
    ];
    Widget row(List<Widget> cells) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, cell) in cells.indexed) ...[
              if (i > 0) const SizedBox(width: 24),
              Expanded(child: cell),
            ],
          ],
        );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 146.0 * labels.length + 24 * (labels.length - 1)),
      child: wide
          ? row(items)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < items.length; i += 2) ...[
                  if (i > 0) const SizedBox(height: 22),
                  row([items[i], if (i + 1 < items.length) items[i + 1] else const SizedBox()]),
                ],
              ],
            ),
    );
  }
}

/// Back, in a frosted circle on the photo.
class _BackButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onPressed;

  const _BackButton({required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.22))),
      child: IconButton(
        tooltip: tooltip,
        color: Colors.white,
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: onPressed,
      ),
    );
  }
}

/// Ask AI (Health Pro's assistant), frosted on the photo like Back: "Ask AI"
/// beside its icon on a computer, the icon alone on a phone.
class _AskAiButton extends StatelessWidget {
  const _AskAiButton();

  @override
  Widget build(BuildContext context) {
    // The panel opens under the button.
    void open() => openAssistant(context, const HealthProAssistantPanel(), underBar: 64);
    final icon = Icon(Icons.auto_awesome_rounded, size: 20, color: context.brand.highlight);
    final side = BorderSide(color: Colors.white.withValues(alpha: 0.22));
    final glass = Colors.white.withValues(alpha: 0.14);
    if (MediaQuery.sizeOf(context).width < 700) {
      return Material(
        color: glass,
        shape: CircleBorder(side: side),
        child: IconButton(tooltip: 'Ask AI', color: Colors.white, icon: icon, onPressed: open),
      );
    }
    return Tooltip(
      message: 'Ask AI',
      child: Pressable(
        child: TextButton.icon(
          onPressed: open,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            foregroundColor: Colors.white,
            backgroundColor: glass,
            shape: StadiumBorder(side: side),
            textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 14),
          ),
          icon: icon,
          label: const Text('Ask AI'),
        ),
      ),
    );
  }
}

/// The card's fields: white, with soft borders, orange when typing in them.
class _AuthInputs extends StatelessWidget {
  final Widget child;

  const _AuthInputs({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final dark = theme.brightness == Brightness.dark;
    OutlineInputBorder outline(Color color, [double width = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: color, width: width));
    final edge = brand.fieldBorder;
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          fillColor: brand.card,
          prefixIconColor: WidgetStateColor.resolveWith(
              (states) => states.contains(WidgetState.focused) && !dark ? brand.accentText : brand.muted),
          suffixIconColor: brand.muted,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          border: outline(edge),
          enabledBorder: outline(edge),
          focusedBorder: outline(brand.accent, 1.6),
          floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) => TextStyle(
                color: states.contains(WidgetState.error)
                    ? theme.colorScheme.error
                    : states.contains(WidgetState.focused)
                        // On white, the orange that reads as text.
                        ? brand.accentText
                        : brand.muted,
              )),
        ),
      ),
      child: child,
    );
  }
}

// ─── The card's parts ─────────────────────────────────────────────────────

/// The page's main action: an orange button with the app's standard
/// corners, a spinner while it works.
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool busy;
  final VoidCallback? onPressed;

  const AuthPrimaryButton({super.key, required this.label, this.icon, this.busy = false, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final accent = context.brand.accent;
    // Faded while there's nothing to press yet (not while it's working); a
    // light sweeping across it once the page has arrived.
    return AnimatedOpacity(
      opacity: busy || onPressed != null ? 1 : 0.45,
      duration: Motion.of(context, Motion.hover),
      child: Pressable(
        enabled: !busy && onPressed != null,
        child: _Sheen(
          delay: const Duration(milliseconds: 1100),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(colors: [context.brand.themedShade(const Color(0xFFFF8A3D)), accent]),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.38),
                  blurRadius: 24,
                  spreadRadius: -8,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: FilledButton(
              onPressed: busy ? null : onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
                shadowColor: Colors.transparent,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 16.5),
              ),
              // The words give way to a spinner, and back, without a jump.
              child: AnimatedSwitcher(
                duration: Motion.of(context, Motion.press),
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(a), child: child),
                ),
                child: busy
                    ? const SizedBox(
                        key: ValueKey('busy'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Row(
                        key: const ValueKey('ready'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[Icon(icon, size: 21), const SizedBox(width: 10)],
                          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Show or hide the 6-digit sign-in code: the eye opens and closes rather
/// than swapping.
class CodeEye extends StatelessWidget {
  final bool hidden;
  final VoidCallback onPressed;

  const CodeEye({super.key, required this.hidden, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: hidden ? 'Show code' : 'Hide code',
      onPressed: onPressed,
      icon: AnimatedSwitcher(
        duration: Motion.of(context, Motion.hover),
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(scale: Tween(begin: 0.7, end: 1.0).animate(a), child: child),
        ),
        child: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined, key: ValueKey(hidden)),
      ),
    );
  }
}

/// A code typed into boxes, one digit each: the 6-digit sign-in code, or
/// the 6-digit code from an email. One unseen field under the boxes takes
/// the typing, so pasting and the keyboard's code suggestion fill them all.
class CodeBoxes extends StatefulWidget {
  final TextEditingController controller;

  /// How many digits, and so how many boxes.
  final int length;

  /// Above the boxes; with [onToggleHidden], the eye sits at its right.
  final String? label;

  /// Dots instead of the digits.
  final bool hidden;
  final VoidCallback? onToggleHidden;

  final bool autofocus;
  final FocusNode? focusNode;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final FormFieldValidator<String>? validator;

  /// The last box was filled.
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onSubmitted;

  /// The code was refused (wrong, or too short): the boxes shake as it
  /// turns true.
  final bool refused;

  /// A Paste code button under the boxes, for a code from an email (phones
  /// have no other way to paste into the boxes).
  final bool showPaste;

  /// A whole code in [text] ("895955", "895 955", "8-9-5-9-5-5", or inside
  /// a sentence), else every digit in it.
  static String codeIn(String text, int length) {
    final run = RegExp('(?:^|[^0-9])([0-9](?:[ -]?[0-9]){${length - 1}})(?![0-9])').firstMatch(text);
    return (run?[1] ?? text).replaceAll(_notDigit, '');
  }

  const CodeBoxes({
    super.key,
    required this.controller,
    this.length = 6,
    this.label,
    this.hidden = false,
    this.onToggleHidden,
    this.autofocus = false,
    this.focusNode,
    this.autofillHints,
    this.textInputAction,
    this.validator,
    this.onCompleted,
    this.onSubmitted,
    this.refused = false,
    this.showPaste = false,
  });

  @override
  State<CodeBoxes> createState() => _CodeBoxesState();
}

class _CodeBoxesState extends State<CodeBoxes> with TickerProviderStateMixin {
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  /// The boxes bobbing one after another once the last is filled.
  late final AnimationController _done;

  /// The boxes shaking when the code is refused.
  late final AnimationController _shake;

  int _length = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _done = AnimationController(vsync: this, duration: Motion.card * 2);
    _shake = AnimationController(vsync: this, duration: Motion.card * 1.2);
    _length = widget.controller.text.length;
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(CodeBoxes old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_changed);
      _focus.addListener(_changed);
    }
    if (widget.refused && !old.refused) _shakeThem();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.removeListener(_changed);
    _ownFocus?.dispose();
    _done.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final length = widget.controller.text.length;
    if (length == widget.length && _length < widget.length && !reduceMotion(context)) _done.forward(from: 0);
    _length = length;
    setState(() {});
  }

  void _shakeThem() {
    if (mounted && !reduceMotion(context)) _shake.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final label = widget.label;
    return FormField<String>(
      validator: (_) => widget.validator?.call(widget.controller.text),
      builder: (field) {
        final text = widget.controller.text;
        final error = field.errorText;
        // Refused here too: a shake as the message appears.
        if (error != null && _error == null) WidgetsBinding.instance.addPostFrameCallback((_) => _shakeThem());
        _error = error;
        // The box the next digit goes in (the last one once they're full).
        final active = _focus.hasFocus ? text.length.clamp(0, widget.length - 1) : -1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null)
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: brand.muted),
                      ),
                    ),
                    if (widget.onToggleHidden != null)
                      CodeEye(hidden: widget.hidden, onPressed: widget.onToggleHidden!),
                  ],
                ),
              ),
            Semantics(
              label: label ?? '${widget.length}-digit code',
              textField: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _focus.requestFocus();
                  // Asked for again, so the keyboard comes back if it was put away.
                  SystemChannels.textInput.invokeMethod<void>('TextInput.show');
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: 0,
                          child: TextField(
                            controller: widget.controller,
                            focusNode: _focus,
                            autofocus: widget.autofocus,
                            keyboardType: TextInputType.number,
                            maxLength: widget.length,
                            showCursor: false,
                            enableInteractiveSelection: false,
                            autofillHints: widget.autofillHints,
                            textInputAction: widget.textInputAction,
                            inputFormatters: [_CodeFormatter(widget.length)],
                            decoration: const InputDecoration(counterText: ''),
                            onChanged: (v) {
                              if (field.hasError) field.validate();
                              if (v.length == widget.length) widget.onCompleted?.call(v);
                            },
                            onSubmitted: widget.onSubmitted,
                          ),
                        ),
                      ),
                    ),
                    LayoutBuilder(
                      builder: (context, box) {
                        const gap = 10.0;
                        final size = ((box.maxWidth - gap * (widget.length - 1)) / widget.length).clamp(36.0, 58.0);
                        final height = (size * 1.12).clamp(44.0, 60.0);
                        // Shaking when refused; each box bobbing in turn once
                        // they're all filled.
                        return AnimatedBuilder(
                          animation: Listenable.merge([_shake, _done]),
                          builder: (context, _) {
                            final s = _shake.value;
                            final shake = s == 0 || s == 1 ? 0.0 : math.sin(s * math.pi * 6) * 10 * (1 - s);
                            double bob(int i) {
                              final d = _done.value;
                              if (d == 0 || d == 1) return 1;
                              final t = ((d - i * 0.09) / 0.45).clamp(0.0, 1.0);
                              return 1 + 0.1 * math.sin(t * math.pi);
                            }

                            return Transform.translate(
                              offset: Offset(shake, 0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (var i = 0; i < widget.length; i++) ...[
                                    if (i > 0) const SizedBox(width: gap),
                                    // Arriving one after another.
                                    PopIn(
                                      delay: Duration(milliseconds: 260 + 55 * i),
                                      child: Transform.scale(
                                        scale: bob(i),
                                        child: AnimatedContainer(
                                          duration: Motion.of(context, Motion.hover),
                                          curve: Motion.ease,
                                          width: size,
                                          // A little shorter when they're narrow (a phone).
                                          height: height,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            // Filled ones warm a little; the one waiting glows.
                                            color: i < text.length
                                                ? Color.alphaBlend(brand.accent.withValues(alpha: 0.07), brand.card)
                                                : brand.card,
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(
                                              color: error != null
                                                  ? brand.danger
                                                  : i == active
                                                      ? brand.accent
                                                      : i < text.length
                                                          ? brand.accent.withValues(alpha: 0.45)
                                                          : brand.fieldBorder,
                                              width: i == active ? 1.8 : 1,
                                            ),
                                            boxShadow: i == active && error == null
                                                ? [BoxShadow(color: brand.accent.withValues(alpha: 0.24), blurRadius: 14, spreadRadius: 1)]
                                                : null,
                                          ),
                                          // Each digit popping in as it's typed;
                                          // the waiting box showing where it goes.
                                          child: AnimatedSwitcher(
                                            duration: Motion.of(context, Motion.dropdown),
                                            transitionBuilder: (child, a) => FadeTransition(
                                              opacity: a,
                                              child: ScaleTransition(
                                                scale: Tween(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: a, curve: Motion.pop)),
                                                child: child,
                                              ),
                                            ),
                                            child: i < text.length
                                                ? Text(
                                                    widget.hidden ? '•' : text[i],
                                                    key: ValueKey('$i ${widget.hidden ? '•' : text[i]}'),
                                                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: brand.ink),
                                                  )
                                                : i == active
                                                    ? Container(
                                                        key: const ValueKey('caret'),
                                                        width: 2.5,
                                                        height: height * 0.42,
                                                        decoration: BoxDecoration(
                                                          color: brand.accent,
                                                          borderRadius: BorderRadius.circular(2),
                                                        ),
                                                      )
                                                    : const SizedBox.shrink(key: ValueKey('empty')),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: brand.danger),
                ),
              ),
            if (widget.showPaste)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => _paste(field),
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    label: const Text('Paste code'),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Paste code: the code on the clipboard fills the boxes.
  Future<void> _paste(FormFieldState<String> field) async {
    var copied = '';
    try {
      copied = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    } catch (_) {
      // The browser said no: the same as nothing copied.
    }
    if (!mounted) return;
    var code = CodeBoxes.codeIn(copied, widget.length);
    if (code.isEmpty) {
      showFeedback(context, 'No code copied yet. Copy it from the email, then tap Paste code.', problem: true);
      return;
    }
    if (code.length > widget.length) code = code.substring(0, widget.length);
    widget.controller.value = TextEditingValue(text: code, selection: TextSelection.collapsed(offset: code.length));
    _focus.requestFocus();
    if (field.hasError) field.validate();
    if (code.length == widget.length) widget.onCompleted?.call(code);
  }
}

final _notDigit = RegExp('[^0-9]');

/// Keeps a code to digits, at most [length]. A whole code arriving at once
/// (pasted, autofilled, or the keyboard's suggestion) takes the place of
/// what was typed, whatever is around it: "895 955", "8-9-5-9-5-5" or
/// "Your code is 895955".
class _CodeFormatter extends TextInputFormatter {
  final int length;

  const _CodeFormatter(this.length);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue next) {
    final before = old.text, after = next.text;
    // What this edit put in: the part between what stayed the same at each end.
    var start = 0;
    while (start < before.length && start < after.length && before[start] == after[start]) {
      start++;
    }
    var end = 0;
    while (end < before.length - start &&
        end < after.length - start &&
        before[before.length - 1 - end] == after[after.length - 1 - end]) {
      end++;
    }
    final added = CodeBoxes.codeIn(after.substring(start, after.length - end), length);
    var code = added.length == length ? added : after.replaceAll(_notDigit, '');
    if (code.length > length) code = code.substring(0, length);
    return TextEditingValue(text: code, selection: TextSelection.collapsed(offset: code.length));
  }
}

/// Another way through: a white button with a soft border.
class AuthSecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;

  /// In place of [icon]: a picture of its own (Google's 'G').
  final Widget? leading;
  final VoidCallback? onPressed;

  const AuthSecondaryButton({super.key, required this.label, this.icon, this.leading, required this.onPressed})
      : assert(icon != null || leading != null);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Pressable(
      enabled: onPressed != null,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: brand.card,
          foregroundColor: brand.pick(LightColors.navy, Colors.white),
          side: BorderSide(color: brand.fieldBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w600, fontSize: 15),
        ),
        icon: leading ?? Icon(icon, size: 21, color: brand.accent),
        label: Text(label),
      ),
    );
  }
}

/// A line with a word in the middle: 'or'.
class AuthDivider extends StatelessWidget {
  final String text;

  const AuthDivider({super.key, this.text = 'or'});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(text, style: TextStyle(color: context.brand.muted, fontSize: 13.5, fontWeight: FontWeight.w500)),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

/// The card's foot: 'Don't have an account? Register here'.
class AuthSwitchLink extends StatelessWidget {
  final String question;
  final String action;
  final VoidCallback onPressed;

  const AuthSwitchLink({super.key, required this.question, required this.action, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(question, style: TextStyle(color: context.brand.muted, fontSize: 14.5)),
        TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: context.brand.accent,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
          child: Text(action),
        ),
      ],
    );
  }
}

/// A short note on a soft tint: what happens next.
class AuthNote extends StatelessWidget {
  final IconData icon;
  final String text;

  const AuthNote({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final accent = context.brand.accent;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: accent),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.4, color: context.brand.muted))),
        ],
      ),
    );
  }
}

/// What went wrong, on a soft red. It fades in with one short shake (a
/// head shaking 'no'), and again when the message changes.
class AuthError extends StatelessWidget {
  final String text;

  const AuthError(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return _box(context);
    return TweenAnimationBuilder<double>(
      key: ValueKey(text),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 460),
      builder: (context, t, child) {
        final dx = 6 * (1 - t) * math.sin(t * 3 * 2 * math.pi);
        return Opacity(
          opacity: Motion.ease.transform((t * 2.5).clamp(0, 1)),
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      },
      child: _box(context),
    );
  }

  Widget _box(BuildContext context) {
    final danger = context.brand.danger;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: danger.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: danger, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: danger, fontWeight: FontWeight.w600, height: 1.35))),
        ],
      ),
    );
  }
}
