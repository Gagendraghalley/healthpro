import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/brand.dart';
import '../widgets/logo.dart';
import '../widgets/motion.dart';

/// What the photo says beside the form: Health Pro's perks in a bar along
/// the foot (signing in), or a welcome with a short list of them (joining).
enum AuthSide { signIn, join }

/// The frame of the sign-in, sign-up and code pages: a sports
/// photo across the window with the logo and what Health Pro offers on it,
/// and the form on a white card at the right. On a phone the photo is a
/// banner and the form a sheet under it.
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
        backgroundColor: wide ? BrandColors.night : context.colors.surface,
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
        const Hero(tag: _Photo.heroTag, child: _Photo()),
        _Wash(side: side),
        // A warm light drifting over the card's side; the wave drawn in.
        const Positioned(right: 80, top: -140, child: _Glow(size: 460)),
        const _Wave(),
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
                  padding: const EdgeInsets.fromLTRB(16, 24, 48, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const FadeSlideIn(child: _Motto()),
                      const SizedBox(height: 18),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 80),
                        child: Container(
                          width: cardWidth,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: context.colors.surface,
                            borderRadius: BorderRadius.circular(28),
                            border: dark ? Border.all(color: context.brand.glassBorder) : null,
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
      ],
    );
  }

  Widget _narrow(BuildContext context, Widget? backButton) {
    final insets = MediaQuery.paddingOf(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: insets.top + 250,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const Hero(tag: _Photo.heroTag, child: _Photo()),
                const _Wash(side: AuthSide.signIn, banner: true),
                const Positioned(right: -70, top: -90, child: _Glow(size: 280)),
                const _Wave(banner: true),
                // The logo popping in, catching the light.
                Padding(
                  padding: EdgeInsets.fromLTRB(16, insets.top + 8, 16, 80),
                  child: const Center(
                    child: PopIn(
                      child: _Sheen(delay: Duration(milliseconds: 700), child: HealthProLogo(height: 112, onDark: true)),
                    ),
                  ),
                ),
                if (backButton != null) Positioned(top: insets.top + 8, left: 12, child: backButton),
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
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
      alignment: const Alignment(-0.2, -0.6),
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

/// Navy over the photo where words sit on it, so they read on any photo.
class _Wash extends StatelessWidget {
  final AuthSide side;
  final bool banner;

  const _Wash({required this.side, this.banner = false});

  static Color _night(double alpha) => BrandColors.night.withValues(alpha: alpha);

  @override
  Widget build(BuildContext context) {
    final LinearGradient gradient;
    if (banner) {
      gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_night(0.62), _night(0.30), _night(0.55)],
        stops: const [0, 0.55, 1],
      );
    } else if (side == AuthSide.join) {
      // The welcome reads down the left.
      gradient = LinearGradient(
        colors: [_night(0.90), _night(0.62), _night(0.28), _night(0.45)],
        stops: const [0, 0.35, 0.65, 1],
      );
    } else {
      // The logo at the top left; the card's side a little darker.
      gradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_night(0.70), _night(0.18), _night(0.50)],
        stops: const [0, 0.48, 1],
      );
    }
    return DecoratedBox(decoration: BoxDecoration(gradient: gradient));
  }
}

/// The orange wave, drawn in from the left as the page opens, then
/// swaying a few times before it rests.
class _Wave extends StatefulWidget {
  final bool banner;

  const _Wave({this.banner = false});

  @override
  State<_Wave> createState() => _WaveState();
}

class _WaveState extends State<_Wave> with SingleTickerProviderStateMixin {
  static const _sways = 3;
  static const _draw = Duration(milliseconds: 1100);
  static const _sway = Duration(milliseconds: 2400);
  // Made at once, so a page left before it moved can still put it away.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _draw + _sway * _sways);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.value = 1;
    } else if (!_c.isAnimating && !_c.isCompleted) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = (_draw + _sway * _sways).inMilliseconds;
    final drawn = _draw.inMilliseconds / total;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final reveal = Motion.ease.transform((t / drawn).clamp(0.0, 1.0));
        // Swaying after it's drawn, less and less, to rest where it began.
        final after = ((t - drawn) / (1 - drawn)).clamp(0.0, 1.0);
        final sway = after == 0 || after == 1 ? 0.0 : math.sin(after * _sways * 2 * math.pi) * (1 - after);
        return CustomPaint(painter: _WavePainter.of(context, banner: widget.banner, reveal: reveal, sway: sway));
      },
    );
  }
}

/// The orange wave over a navy foot, sweeping from the left down to the
/// right, as on the logo.
class _WavePainter extends CustomPainter {
  final bool banner;

  /// The brand's orange, or the colour they picked (Brand.highlight).
  final Color color;

  /// The lighter middle of the wave.
  final Color soft;

  /// How much of it is drawn, from the left (0 to 1).
  final double reveal;

  /// How far its curve leans from rest (-1 to 1).
  final double sway;

  const _WavePainter({
    this.banner = false,
    this.color = BrandColors.orange,
    this.soft = const Color(0xFFFF8A3D),
    this.reveal = 1,
    this.sway = 0,
  });

  _WavePainter.of(BuildContext context, {bool banner = false, double reveal = 1, double sway = 0})
      : this(
            banner: banner,
            color: context.brand.highlight,
            soft: context.brand.themedShade(const Color(0xFFFF8A3D)),
            reveal: reveal,
            sway: sway);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (reveal <= 0) return;
    if (reveal < 1) canvas.clipRect(Rect.fromLTWH(0, 0, w * reveal, h));
    // Where the wave meets the left and the right edge.
    final left = h * (banner ? 0.70 : 0.80);
    final right = h * (banner ? 0.86 : 0.90);
    final lift = h * (banner ? 0.10 : 0.07) * (1 + 0.35 * sway);
    Path wave(double dy) => Path()
      ..moveTo(0, left + dy)
      ..cubicTo(w * 0.32, left - lift + dy, w * 0.60, right + lift * 0.4 + dy, w, right - lift * 0.5 + dy)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(
      wave(0),
      Paint()
        ..shader = LinearGradient(
          colors: [color, soft, color.withValues(alpha: 0.35)],
          stops: const [0, 0.5, 1],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(wave(banner ? 9 : 16), Paint()..color = BrandColors.night.withValues(alpha: 0.94));
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.banner != banner || old.color != color || old.soft != soft || old.reveal != reveal || old.sway != sway;
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

/// [child] growing out from one end ([alignment]), [delay] after it shows.
class _GrowIn extends StatelessWidget {
  final Widget child;
  final Duration delay;
  final Alignment alignment;

  const _GrowIn({required this.child, this.delay = Duration.zero, this.alignment = Alignment.centerLeft});

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
        return Transform(alignment: alignment, transform: Matrix4.diagonal3Values(local, 1, 1), child: child);
      },
      child: child,
    );
  }
}

/// A soft round light of the brand's orange, drifting gently a few times.
class _Glow extends StatelessWidget {
  final double size;

  const _Glow({required this.size});

  @override
  Widget build(BuildContext context) {
    final color = context.brand.highlight;
    return IgnorePointer(
      child: GentleFloat(
        distance: 18,
        cycles: 3,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)]),
          ),
        ),
      ),
    );
  }
}

/// The photo's side on a computer: the logo, and the perks.
class _Showcase extends StatelessWidget {
  final AuthSide side;
  final Widget? backButton;

  const _Showcase({required this.side, required this.backButton});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // A short or narrow window keeps just the logo.
        final room = box.maxHeight >= 560 && box.maxWidth >= 340;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (backButton != null) ...[backButton!, const SizedBox(width: 14)],
                // Smaller when the photo's side is narrow.
                // Catching the light once it has arrived.
                const Flexible(
                  child: FadeSlideIn(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: _Sheen(delay: Duration(milliseconds: 700), child: HealthProLogo(height: 118, onDark: true)),
                    ),
                  ),
                ),
              ],
            ),
            if (room && side == AuthSide.join) ...[
              const Spacer(flex: 3),
              const _JoinPitch(),
              const Spacer(flex: 4),
            ] else ...[
              const Spacer(),
              if (room) _PerkBar(wide: box.maxWidth >= 500),
            ],
          ],
        );
      },
    );
  }
}

typedef _Perk = (IconData icon, String label);

/// Signing in: what Health Pro does, along the navy foot.
class _PerkBar extends StatelessWidget {
  final bool wide;

  const _PerkBar({required this.wide});

  static const perks = <_Perk>[
    (Icons.travel_explore_rounded, 'Find\na gym'),
    (Icons.groups_rounded, 'Membership\nmanagement'),
    (Icons.qr_code_scanner_rounded, 'QR\ncheck-in'),
    (Icons.insights_rounded, 'Analytics\n& reports'),
  ];

  @override
  Widget build(BuildContext context) {
    // Each popping in after the bar, one after another.
    final items = <Widget>[
      for (final (i, (icon, label)) in perks.indexed)
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopIn(
              delay: Duration(milliseconds: 420 + 90 * i),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 8),
            FadeSlideIn(
              delay: Duration(milliseconds: 480 + 90 * i),
              offset: 8,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.3, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
    ];
    // One row of four, or two of two where the photo's side is narrow.
    Widget row(List<Widget> cells) => IntrinsicHeight(
          child: Row(
            children: [
              for (final (i, cell) in cells.indexed) ...[
                if (i > 0) VerticalDivider(width: 1, thickness: 1, color: Colors.white.withValues(alpha: 0.18)),
                Expanded(child: cell),
              ],
            ],
          ),
        );
    return FadeSlideIn(
      delay: const Duration(milliseconds: 160),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
            decoration: BoxDecoration(
              color: BrandColors.night.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: wide
                ? row(items)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [row(items.sublist(0, 2)), const SizedBox(height: 16), row(items.sublist(2))],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Joining: a welcome, and what an account gives.
class _JoinPitch extends StatelessWidget {
  const _JoinPitch();

  static const perks = <_Perk>[
    (Icons.travel_explore_rounded, 'Find gyms across Bhutan'),
    (Icons.qr_code_2_rounded, 'Your membership card on your phone'),
    (Icons.devices_rounded, 'One account, on the web and in the app'),
  ];

  @override
  Widget build(BuildContext context) {
    const headline = TextStyle(
      fontSize: 54,
      height: 1.02,
      letterSpacing: -1,
      fontWeight: FontWeight.w800,
      color: Colors.white,
      shadows: [Shadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 4))],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: staggered([
        _Slanted(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Join\nHealth '),
                TextSpan(text: 'Pro', style: TextStyle(color: context.brand.themedShade(const Color(0xFFFF8A3D)))),
              ],
            ),
            style: headline,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 30),
          child: Text(
            'Be part of our sports community',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 20, fontWeight: FontWeight.w500),
          ),
        ),
        for (final (i, (icon, label)) in perks.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Popping in after its line arrives.
                PopIn(
                  delay: Duration(milliseconds: 260 + 90 * i),
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [context.brand.themedShade(const Color(0xFFFF8A3D)), context.brand.highlight],
                      ),
                      boxShadow: [BoxShadow(color: context.brand.highlight.withValues(alpha: 0.4), blurRadius: 16)],
                    ),
                    child: Icon(icon, color: Colors.white, size: 23),
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
      ]),
    );
  }
}

/// 'Stronger Together' above the card, underlined with an orange stroke.
class _Motto extends StatelessWidget {
  const _Motto();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const _Slanted(
            child: Text(
              'Stronger Together',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                shadows: [Shadow(color: Color(0x80000000), blurRadius: 16, offset: Offset(0, 3))],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // The stroke drawn in from its bright end, after the words.
          Transform.rotate(
            angle: -0.04,
            child: _GrowIn(
              delay: const Duration(milliseconds: 450),
              alignment: Alignment.centerRight,
              child: Container(
                width: 150,
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(
                      colors: [context.brand.highlight.withValues(alpha: 0), context.brand.highlight]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Leaning forward, like the logo's lettering.
class _Slanted extends StatelessWidget {
  final Widget child;

  const _Slanted({required this.child});

  @override
  Widget build(BuildContext context) =>
      Transform(transform: Matrix4.skewX(-0.16), alignment: Alignment.bottomLeft, child: child);
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

/// The page's main action: an orange pill, with a spinner while it works.
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
              borderRadius: BorderRadius.circular(28),
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
                shape: const StadiumBorder(),
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
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
          ],
        );
      },
    );
  }
}

/// Another way through: a white button with a soft border.
class AuthSecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const AuthSecondaryButton({super.key, required this.label, required this.icon, required this.onPressed});

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
        icon: Icon(icon, size: 21, color: brand.accent),
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
