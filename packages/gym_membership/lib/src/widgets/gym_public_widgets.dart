import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../data/trainers.dart';
import 'gym_art.dart';
import 'trainer_widgets.dart';

// The public side's look, as the Welcome page has it: navy and the brand's
// orange, the gym photo, soft cards with small gradient icon tiles. The list
// of gyms (its top and its cards), a gym's page (its photos, its facts and
// its sections) and a trainer's profile.

/// Under a card: a soft navy haze in the light, a deep shadow in the dark.
List<BoxShadow> _shadow(Brand brand, {double light = 0.07, double dark = 0.3, double blur = 28, double dy = 12}) => [
      BoxShadow(
        color: brand.pick(LightColors.navy.withValues(alpha: light), Colors.black.withValues(alpha: dark)),
        blurRadius: blur,
        spreadRadius: brand.isLight ? -4 : 0,
        offset: Offset(0, dy),
      ),
    ];

/// Behind small icons: a cool pale grey-blue, or a faint white in the dark.
Color _tint(Brand brand) => brand.pick(const Color(0xFFEAF0F8), Colors.white.withValues(alpha: 0.08));

/// Deep navy, for words over a photo.
const _shade = Color(0xFF081428);

// ─── Motion ────────────────────────────────────────────────────────────────
// Everything here moves once (a pulse a few times) and comes to rest, and
// stands still when motion is reduced.

/// [child] (a photo) settling slowly from a little close, once.
class _SlowZoom extends StatelessWidget {
  final Widget child;

  const _SlowZoom({required this.child});

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.1, end: 1),
      duration: Motion.card * 30,
      curve: Motion.ease,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: child,
    );
  }
}

/// A photo from [url], fading in once it has loaded; [fallback] if it can't.
Widget _netPhoto(String url, Widget fallback) => Image.network(
      url,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, loadedAtOnce) => loadedAtOnce
          ? child
          : AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: Motion.card,
              curve: Motion.ease,
              child: child,
            ),
      errorBuilder: (_, __, ___) => fallback,
    );

/// A small round light, ringing out a few times when [on] (open now).
class _PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool on;

  const _PulseDot({required this.color, this.size = 8, this.on = true});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  static const _rings = 4;
  // Made at once (not when first used), so a dot that never rang can still
  // be put away.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: Motion.card * 4 * _rings);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.on && !reduceMotion(context) && !_c.isAnimating && !_c.isCompleted) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
    );
    if (!widget.on || reduceMotion(context)) return dot;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              if (_c.isCompleted) return const SizedBox.shrink();
              final t = Motion.ease.transform((_c.value * _rings) % 1);
              return OverflowBox(
                maxWidth: size * 4,
                maxHeight: size * 4,
                child: Container(
                  width: size * (1 + 2 * t),
                  height: size * (1 + 2 * t),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.5 * (1 - t))),
                ),
              );
            },
          ),
          dot,
        ],
      ),
    );
  }
}

/// [child] drifting with the page's scroll at [factor] of its speed: a
/// background moving slower (or the other way) than what's over it.
class _Parallax extends StatelessWidget {
  final double factor;
  final Widget child;

  const _Parallax({required this.factor, required this.child});

  @override
  Widget build(BuildContext context) {
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null || reduceMotion(context)) return child;
    return AnimatedBuilder(
      animation: position,
      child: child,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, (position.hasPixels ? position.pixels.clamp(0.0, 600.0) : 0) * factor),
        child: child,
      ),
    );
  }
}

/// A light sweeping across [child] a couple of times, [delay] after it
/// shows, as over something new and polished; then it rests.
class _Sheen extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _Sheen({required this.child, this.delay = Duration.zero});

  @override
  State<_Sheen> createState() => _SheenState();
}

class _SheenState extends State<_Sheen> with SingleTickerProviderStateMixin {
  static const _sweeps = 2;
  late final Duration _sweep = Motion.card * 2.4;
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
        final total = _c.duration!.inMilliseconds;
        final after = _c.value * total - widget.delay.inMilliseconds;
        if (after <= 0 || _c.isCompleted) return child!;
        final t = Motion.easeInOut.transform((after / _sweep.inMilliseconds) % 1);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0)],
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

/// Five stars for [rating], popping in one after another (in their turn,
/// from [order], once their [GymReveal] has shown).
class _PopStars extends StatelessWidget {
  final double rating;
  final double size;
  final int order;

  const _PopStars({required this.rating, this.size = 16, this.order = 0});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          GymRevealItem(
            order: order + i,
            pop: true,
            child: Icon(
              rating >= i
                  ? Icons.star_rounded
                  : rating >= i - 0.5
                      ? Icons.star_half_rounded
                      : Icons.star_outline_rounded,
              size: size,
              color: const Color(0xFFF5A623),
            ),
          ),
      ],
    );
  }
}

/// A trainer's photo in an orange ring whose light sweeps round a couple of
/// times as it arrives, ringing out softly, then rests.
class _AvatarRing extends StatefulWidget {
  final Widget child;

  const _AvatarRing({required this.child});

  @override
  State<_AvatarRing> createState() => _AvatarRingState();
}

class _AvatarRingState extends State<_AvatarRing> with SingleTickerProviderStateMixin {
  static const _rings = 3;
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.card * 10);

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
    final brand = context.brand;
    final light = Color.lerp(brand.highlight, const Color(0xFFFFD29A), 0.75)!;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final turn = Motion.ease.transform(_c.value) * 2;
        // Rings going out over the first part, fading as they grow.
        final ringing = (_c.value * 1.6).clamp(0.0, 1.0);
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (ringing < 1)
              for (var k = 0; k < 2; k++)
                Builder(builder: (context) {
                  final r = Motion.ease.transform((ringing * _rings + k * 0.5) % 1);
                  return Positioned.fill(
                    child: Transform.scale(
                      scale: 1 + 0.35 * r,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: brand.highlight.withValues(alpha: 0.5 * (1 - r) * (1 - ringing)), width: 2),
                        ),
                      ),
                    ),
                  );
                }),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [brand.highlight, light, brand.highlight, brand.highlight, brand.highlight],
                  stops: const [0, 0.12, 0.3, 0.7, 1],
                  transform: GradientRotation(turn * 2 * math.pi),
                ),
                boxShadow: [BoxShadow(color: brand.highlight.withValues(alpha: 0.35), blurRadius: 30, spreadRadius: 2)],
              ),
              child: child,
            ),
          ],
        );
      },
    );
  }
}

/// [child] fades in and rises into place once it scrolls into view, [delay]
/// after; its [GymRevealItem]s follow one by one.
class GymReveal extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const GymReveal({super.key, required this.child, this.delay = Duration.zero});

  @override
  State<GymReveal> createState() => _GymRevealState();
}

class _GymRevealState extends State<GymReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.delay + Motion.card);
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(widget.delay.inMilliseconds / (widget.delay + Motion.card).inMilliseconds, 1, curve: Motion.ease),
  );
  ScrollPosition? _position;
  bool _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _detach();
      _c.value = 1;
      _shown = true;
      return;
    }
    if (_shown) return;
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _detach();
      _position = position?..addListener(_scrolled);
    }
    _scrolled();
  }

  void _detach() {
    _position?.removeListener(_scrolled);
    _position = null;
  }

  /// Looks once the page has been laid out where it scrolled to (not
  /// before: it would see where it was).
  bool _looking = false;
  void _scrolled() {
    if (_looking) return;
    _looking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _looking = false;
      _check();
    });
  }

  /// Shows it once its top comes into the window.
  void _check() {
    if (!mounted || _shown) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    if (_position != null && box.localToGlobal(Offset.zero).dy > MediaQuery.sizeOf(context).height - 24) return;
    _detach();
    setState(() => _shown = true);
    _c.forward();
  }

  @override
  void dispose() {
    _detach();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Shown(
      shown: _shown,
      child: AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (context, child) => Opacity(
          opacity: _t.value,
          child: Transform.translate(offset: Offset(0, 28 * (1 - _t.value)), child: child),
        ),
      ),
    );
  }
}

/// Whether the [GymReveal] around has shown.
class _Shown extends InheritedWidget {
  final bool shown;

  const _Shown({required this.shown, required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_Shown>()?.shown ?? true;

  @override
  bool updateShouldNotify(_Shown oldWidget) => oldWidget.shown != shown;
}

/// One of a card's parts (a tile, a row) arriving in its turn ([order])
/// once its [GymReveal] has shown: fading in, rising and growing a little.
class GymRevealItem extends StatefulWidget {
  final int order;
  final Widget child;

  /// Popping into place from small, a hair past full size (a star, a chip),
  /// rather than rising.
  final bool pop;

  /// Growing out from its left end (a bar of hours), rather than rising.
  final bool grow;

  const GymRevealItem({super.key, required this.order, required this.child, this.pop = false, this.grow = false});

  @override
  State<GymRevealItem> createState() => _GymRevealItemState();
}

class _GymRevealItemState extends State<GymRevealItem> with SingleTickerProviderStateMixin {
  late final Duration _delay = Motion.card * 0.35 + Motion.stagger * widget.order.clamp(0, 12);
  late final AnimationController _c = AnimationController(vsync: this, duration: _delay + Motion.card);
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(
      _delay.inMilliseconds / (_delay + Motion.card).inMilliseconds,
      1,
      curve: widget.pop ? Motion.pop : Motion.ease,
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.value = 1;
    } else if (_Shown.of(context) && !_c.isAnimating && !_c.isCompleted) {
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
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        final t = _t.value;
        if (widget.grow) {
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform(
              alignment: Alignment.centerLeft,
              transform: Matrix4.diagonal3Values(t.clamp(0.0, 1.0), 1, 1),
              child: child,
            ),
          );
        }
        if (widget.pop) {
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.scale(scale: 0.4 + 0.6 * t, child: child),
          );
        }
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
          ),
        );
      },
    );
  }
}

/// [text] in the brand's orange, warming along the line.
class _Accent extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _Accent(this.text, {required this.style});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) =>
          LinearGradient(colors: [brand.highlight, Color.lerp(brand.highlight, const Color(0xFFFFB067), 0.6)!]).createShader(bounds),
      child: Text(text, style: style),
    );
  }
}

/// A small rounded tile of the brand's orange, fading, with [icon].
class _IconTile extends StatelessWidget {
  final IconData icon;
  final double size;

  const _IconTile(this.icon, {this.size = 38});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [brand.accent.withValues(alpha: 0.18), brand.accent.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: brand.accent.withValues(alpha: 0.18)),
      ),
      child: Icon(icon, size: size * 0.5, color: brand.accentText),
    );
  }
}

/// A rounded pill on a photo: deep navy glass, white words.
class _PhotoPill extends StatelessWidget {
  final Widget? leading;
  final String text;

  /// Before [text] and a slash (the photo's number, of [text]).
  final Widget? lead;

  const _PhotoPill({this.leading, required this.text, this.lead});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _shade.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          if (lead != null) ...[
            ClipRect(child: lead!),
            const Text(' / ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// A gym with no photo yet: navy, a warm light and the orange bands, its
/// icon on glass. Never another gym's picture.
class GymPhotoPlaceholder extends StatelessWidget {
  final double iconSize;

  const GymPhotoPlaceholder({super.key, this.iconSize = 34});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1530), Color(0xFF1B3F8A)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(right: -60, top: -80, child: GymGlow(color: brand.highlight.withValues(alpha: 0.28), size: 240)),
          CustomPaint(painter: GymStripesPainter.of(context)),
          Center(
            child: Container(
              width: iconSize * 2.1,
              height: iconSize * 2.1,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Icon(Icons.fitness_center_rounded, size: iconSize, color: Colors.white.withValues(alpha: 0.92)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── The list of gyms ──────────────────────────────────────────────────────

/// The top of the list of gyms, on navy over the gym photo: what the page is
/// for, how many gyms (in how many dzongkhags, how many open now), and
/// [filters] on a card under them.
class GymListHeader extends StatelessWidget {
  final int gyms;
  final int places;

  /// Null when no gym has given its hours.
  final int? openNow;
  final Widget filters;

  const GymListHeader({super.key, required this.gyms, required this.places, required this.openNow, required this.filters});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;
    final phone = width < 600;
    final size = wide ? 44.0 : (phone ? 30.0 : 38.0);
    final title = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w800,
      height: 1.08,
      letterSpacing: -size * 0.03,
      color: Colors.white,
    );
    final stats = [
      (gyms, gyms == 1 ? 'gym' : 'gyms'),
      (places, places == 1 ? 'dzongkhag' : 'dzongkhags'),
      if (openNow != null) (openNow!, 'open now'),
    ];
    final pad = wide ? 40.0 : (phone ? 18.0 : 28.0);
    // Each part arriving in its turn.
    Widget rise(int turn, Widget child) => FadeSlideIn(delay: Motion.stagger * turn, offset: 16, child: child);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: BrandColors.navy,
        borderRadius: BorderRadius.circular(phone ? 22 : 28),
        boxShadow: _shadow(brand, light: 0.22, dark: 0.4, blur: 44, dy: 20),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: _SlowZoom(child: GymPhoto('gym', alignment: Alignment(0.6, -0.2)))),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFA0A1C45),
                    const Color(0xEB0A1C45),
                    BrandColors.navy.withValues(alpha: wide ? 0.45 : 0.8),
                  ],
                  stops: const [0, 0.5, 1],
                ),
              ),
            ),
          ),
          Positioned(
            right: -80,
            top: -130,
            child: GentleFloat(
              distance: 18,
              cycles: 3,
              child: GymGlow(color: brand.highlight.withValues(alpha: 0.32), size: 360),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(pad, wide ? 40 : 24, pad, phone ? 16 : 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                rise(0, const _Badge(icon: Icons.verified_rounded, text: 'VERIFIED GYMS')),
                const SizedBox(height: 16),
                rise(1, Wrap(children: [Text('Find your ', style: title), _Accent('gym', style: title)])),
                const SizedBox(height: 12),
                rise(
                  2,
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Text(
                      'Compare packages, prices and opening hours, then join in the app or at the front desk.',
                      style: TextStyle(fontSize: phone ? 14.5 : 16, height: 1.6, color: Colors.white.withValues(alpha: 0.8)),
                    ),
                  ),
                ),
                SizedBox(height: phone ? 18 : 24),
                rise(
                  3,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, (count, label)) in stats.indexed) ...[
                        if (i > 0)
                          Container(
                            width: 1,
                            height: 32,
                            margin: EdgeInsets.symmetric(horizontal: phone ? 14 : 22),
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Counting up as they arrive.
                            AnimatedCount(
                              value: count,
                              format: AnimatedCount.whole,
                              duration: Motion.count,
                              style: TextStyle(fontSize: phone ? 22 : 26, fontWeight: FontWeight.w800, height: 1, color: Colors.white),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              label,
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.7)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: phone ? 20 : 28),
                rise(
                  4,
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(phone ? 12 : 16),
                    decoration: BoxDecoration(
                      color: brand.card,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10))],
                    ),
                    child: filters,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A small glass pill on navy: an orange [icon] and capitals.
class _Badge extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Badge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: context.brand.highlight),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.3, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// A gym in the list: its photo (open or closed, its rating, how far), its
/// name and place, and its prices. Rises under the mouse, its photo drawing
/// closer.
class GymListCard extends StatefulWidget {
  final Venue gym;
  final ({int low, int high})? price;
  final double? km;
  final VoidCallback onTap;

  const GymListCard({super.key, required this.gym, required this.price, required this.km, required this.onTap});

  @override
  State<GymListCard> createState() => _GymListCardState();
}

class _GymListCardState extends State<GymListCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final gym = widget.gym;
    final price = widget.price;
    final hover = _hover && !reduceMotion(context);
    final now = gym.openingHours?.at(BhutanTime.now());
    final cover = gym.coverPhoto;
    final photo = AspectRatio(
      aspectRatio: 16 / 10,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedScale(
            scale: hover ? 1.05 : 1,
            duration: Motion.card,
            curve: Motion.ease,
            child: cover == null ? const GymPhotoPlaceholder() : _netPhoto(cover, const GymPhotoPlaceholder()),
          ),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0x8C081428), Color(0x00081428), Color(0x00081428), Color(0x59081428)],
                  stops: [0, 0.45, 0.7, 1],
                ),
              ),
            ),
          ),
          if (now != null)
            Positioned(
              left: 12,
              top: 12,
              right: gym.ratingCount > 0 ? 96 : 12,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _PhotoPill(
                  leading: _PulseDot(
                    on: now.open,
                    color: now.open ? Color.lerp(brand.success, Colors.white, 0.25)! : Colors.white.withValues(alpha: 0.5),
                  ),
                  text: now.label,
                ),
              ),
            ),
          if (gym.ratingCount > 0)
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                child: Text.rich(
                  TextSpan(
                    children: [
                      const WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: EdgeInsets.only(right: 3),
                          child: Icon(Icons.star_rounded, size: 15, color: Color(0xFFF5A623)),
                        ),
                      ),
                      TextSpan(text: gym.ratingAverage!.toStringAsFixed(1)),
                      TextSpan(
                        text: ' (${gym.ratingCount})',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: LightColors.muted),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: LightColors.ink),
                ),
              ),
            ),
          if (widget.km != null)
            Positioned(
              left: 12,
              bottom: 12,
              child: _PhotoPill(
                leading: const Icon(Icons.near_me_rounded, size: 13, color: Colors.white),
                text: '${distanceText(widget.km!)} away',
              ),
            ),
        ],
      ),
    );
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  gym.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: brand.ink),
                ),
              ),
              if (gym.isVerified) ...[
                const SizedBox(width: 6),
                Tooltip(message: 'Verified', child: Icon(Icons.verified_rounded, size: 17, color: brand.success)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.place_outlined, size: 15, color: brand.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  gym.place,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: brand.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: brand.glassBorder),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PACKAGES',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: brand.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      price == null ? 'Prices at the desk' : priceRangeText(price.low, price.high),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: price == null ? brand.muted : brand.ink,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: Motion.hover,
                curve: Motion.ease,
                width: 38,
                height: 38,
                decoration: BoxDecoration(shape: BoxShape.circle, color: hover ? brand.accent : _tint(brand)),
                child: AnimatedSlide(
                  offset: Offset(hover ? 0.12 : 0, 0),
                  duration: Motion.hover,
                  curve: Motion.ease,
                  child: Icon(Icons.arrow_forward_rounded, size: 19, color: hover ? BrandColors.navy : brand.ink),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Pressable(
        scale: 0.985,
        child: AnimatedContainer(
          duration: Motion.hover,
          curve: Motion.ease,
          transform: Matrix4.translationValues(0, hover ? -4 : 0, 0),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: brand.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: hover ? brand.accent.withValues(alpha: 0.35) : brand.glassBorder),
            boxShadow: hover
                ? _shadow(brand, light: 0.14, dark: 0.45, blur: 36, dy: 18)
                : _shadow(brand, light: 0.06, blur: 24, dy: 10),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [photo, body]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── A gym's page ──────────────────────────────────────────────────────────

/// The top of a gym's page: its photos, swiped (or stepped through with the
/// arrows on a computer), with its name, place and Verified over them.
class GymProfileHero extends StatefulWidget {
  final Venue gym;

  const GymProfileHero({super.key, required this.gym});

  @override
  State<GymProfileHero> createState() => _GymProfileHeroState();
}

class _GymProfileHeroState extends State<GymProfileHero> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int page) {
    if (reduceMotion(context)) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(page, duration: Motion.card, curve: Motion.easeInOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gym = widget.gym;
    final photos = gym.photos;
    final brand = context.brand;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final wide = w >= 760;
        final height = wide ? (w * 0.36).clamp(320.0, 460.0) : (w * 0.8).clamp(270.0, 400.0);
        final pad = wide ? 32.0 : 18.0;
        final nameSize = wide ? 40.0 : 27.0;
        final many = photos.length > 1;
        return Container(
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: BrandColors.navy,
            borderRadius: BorderRadius.circular(wide ? 28 : 22),
            boxShadow: _shadow(brand, light: 0.2, dark: 0.4, blur: 44, dy: 20),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photos.isEmpty)
                const GymPhotoPlaceholder(iconSize: 56)
              else
                PageView.builder(
                  controller: _pages,
                  itemCount: photos.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  // Each photo settling slowly as it comes.
                  itemBuilder: (_, i) => _SlowZoom(child: _netPhoto(photos[i], const GymPhotoPlaceholder(iconSize: 56))),
                ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xF0081428), Color(0x8C081428), Color(0x00081428)],
                      stops: [0, 0.4, 0.75],
                    ),
                  ),
                ),
              ),
              if (wide)
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0x8C081428), Color(0x00081428)],
                        stops: [0, 0.6],
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: pad,
                right: pad,
                bottom: pad,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Rising over the photo one after another.
                          if (gym.isVerified) ...[
                            FadeSlideIn(
                              delay: Motion.stagger * 2,
                              offset: 14,
                              child: const _Badge(icon: Icons.verified_rounded, text: 'VERIFIED GYM'),
                            ),
                            const SizedBox(height: 14),
                          ],
                          FadeSlideIn(
                            delay: Motion.stagger * 3,
                            offset: 18,
                            child: Text(
                              gym.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: nameSize,
                                fontWeight: FontWeight.w800,
                                height: 1.08,
                                letterSpacing: -nameSize * 0.025,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          FadeSlideIn(
                            delay: Motion.stagger * 4,
                            offset: 14,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Icon(Icons.place_rounded, size: 17, color: brand.highlight),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    [gym.place, if (gym.address != null) gym.address!].join(' · '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: wide ? 15 : 14, height: 1.4, color: Colors.white.withValues(alpha: 0.88)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (many && wide) ...[
                      const SizedBox(width: 20),
                      _Arrow(
                        icon: Icons.chevron_left_rounded,
                        tooltip: 'Previous photo',
                        onTap: _page > 0 ? () => _go(_page - 1) : null,
                      ),
                      const SizedBox(width: 10),
                      _Arrow(
                        icon: Icons.chevron_right_rounded,
                        tooltip: 'Next photo',
                        onTap: _page < photos.length - 1 ? () => _go(_page + 1) : null,
                      ),
                    ],
                  ],
                ),
              ),
              if (many)
                Positioned(
                  top: wide ? 22 : 14,
                  right: wide ? 22 : 14,
                  child: _PhotoPill(
                    leading: const Icon(Icons.photo_library_outlined, size: 14, color: Colors.white),
                    text: '${photos.length}',
                    // The photo's number rolls over as it changes.
                    lead: AnimatedSwitcher(
                      duration: Motion.of(context, Motion.hover),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        '${_page + 1}',
                        key: ValueKey(_page),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A round glass button on a photo.
class _Arrow extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _Arrow({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Pressable(
        enabled: on,
        scale: 0.9,
        child: Material(
          color: Colors.white.withValues(alpha: on ? 0.16 : 0.06),
          shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: on ? 0.28 : 0.12))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            hoverColor: Colors.white.withValues(alpha: 0.14),
            child: AnimatedOpacity(
              opacity: on ? 1 : 0.4,
              duration: Motion.hover,
              child: SizedBox(width: 46, height: 46, child: Icon(icon, size: 26, color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of a gym's facts at a glance: its prices, today's hours, its reviews.
typedef GymFact = ({IconData icon, String label, String value, Color? color});

/// A gym's facts at a glance, side by side on a card (one under another on
/// a phone).
class GymFactsBar extends StatelessWidget {
  final List<GymFact> facts;

  const GymFactsBar({super.key, required this.facts});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    Widget cell(GymFact f) => Row(
          children: [
            _IconTile(f.icon, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.label.toUpperCase(),
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: brand.muted),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    f.value,
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: -0.2, height: 1.3, color: f.color ?? brand.ink),
                  ),
                ],
              ),
            ),
          ],
        );
    return LayoutBuilder(
      builder: (context, constraints) {
        final across = constraints.maxWidth >= 560 && facts.length > 1;
        return Container(
          padding: across ? const EdgeInsets.symmetric(vertical: 18, horizontal: 4) : const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          decoration: BoxDecoration(
            color: brand.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: brand.glassBorder),
            boxShadow: _shadow(brand, light: 0.06, blur: 26, dy: 10),
          ),
          child: across
              ? IntrinsicHeight(
                  child: Row(
                    children: [
                      for (final (i, f) in facts.indexed) ...[
                        if (i > 0) VerticalDivider(width: 1, color: brand.glassBorder),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: GymRevealItem(order: i, child: cell(f)),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : Column(
                  children: [
                    for (final (i, f) in facts.indexed) ...[
                      if (i > 0) Divider(height: 1, color: brand.glassBorder),
                      Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: GymRevealItem(order: i, child: cell(f))),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

/// One part of a gym's page on its card: an orange icon tile and [title]
/// over [child] (no heading when [title] is null).
class GymSection extends StatelessWidget {
  final IconData? icon;
  final String? title;
  final Widget? trailing;
  final Widget child;

  /// Room inside the card: 22 all round (18 on a phone) unless given.
  final EdgeInsets? padding;

  const GymSection({super.key, this.icon, this.title, this.trailing, this.padding, required this.child});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final phone = MediaQuery.sizeOf(context).width < 600;
    return Container(
      width: double.infinity,
      padding: padding ?? EdgeInsets.all(phone ? 18 : 22),
      decoration: BoxDecoration(
        color: brand.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: brand.glassBorder),
        boxShadow: _shadow(brand, light: 0.06, blur: 26, dy: 10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[_IconTile(icon!), const SizedBox(width: 12)],
                Expanded(
                  child: Text(
                    title!,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: brand.ink),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 16),
          ],
          child,
        ],
      ),
    );
  }
}

/// The part of the day a week's tracks show: from the earliest start to the
/// latest end of [spans] (minutes), to the hour, six hours at least.
(int, int) _trackRange(Iterable<(int, int)> spans) {
  final list = spans.toList();
  var from = list.isEmpty ? 360 : list.map((s) => s.$1).reduce(math.min);
  var to = list.isEmpty ? 1320 : list.map((s) => s.$2).reduce(math.max);
  from = from ~/ 60 * 60;
  to = (to + 59) ~/ 60 * 60;
  if (to - from < 360) to = math.min(1440, from + 360);
  if (to - from < 360) from = math.max(0, to - 360);
  return (from, to);
}

/// One day on a track across [from]–[to] (minutes): its [spans] in orange
/// (grey where they're not [on]), growing in from the left in their turn
/// ([order]); with [now], a dot where now is.
class _DayTrack extends StatelessWidget {
  final List<({int start, int end, bool on})> spans;
  final int from;
  final int to;
  final int? now;
  final int order;

  const _DayTrack({required this.spans, required this.from, required this.to, this.now, required this.order});

  double _at(int m) => ((m - from) / (to - from)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final now = this.now;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return SizedBox(
          height: 22,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 7,
                height: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: brand.pick(const Color(0xFFE9EEF5), Colors.white.withValues(alpha: 0.08)),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              for (final (k, s) in spans.indexed)
                Positioned(
                  left: _at(s.start) * w,
                  width: math.max(4.0, (_at(s.end) - _at(s.start)) * w),
                  top: 7,
                  height: 8,
                  child: GymRevealItem(
                    order: order + 1 + k,
                    grow: true,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: s.on
                            ? LinearGradient(colors: [Color.lerp(brand.highlight, const Color(0xFFFFB067), 0.5)!, brand.highlight])
                            : null,
                        color: s.on ? null : brand.pick(const Color(0xFFC3CCD9), Colors.white.withValues(alpha: 0.24)),
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: s.on
                            ? [BoxShadow(color: brand.highlight.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))]
                            : null,
                      ),
                    ),
                  ),
                ),
              if (now != null && now >= from && now <= to)
                Positioned(
                  left: _at(now) * w - 6,
                  top: 5,
                  child: GymRevealItem(
                    order: order + 3,
                    pop: true,
                    child: Tooltip(
                      message: 'Now',
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: brand.ink,
                          border: Border.all(color: brand.card, width: 2),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4)],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The times of day under a week's tracks ([from]–[to]): its ends, and the
/// middle where there's room.
class _TrackAxis extends StatelessWidget {
  final int from;
  final int to;
  final EdgeInsets padding;

  const _TrackAxis({required this.from, required this.to, required this.padding});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: padding,
      child: SizedBox(
        height: 16,
        child: LayoutBuilder(
          builder: (context, box) {
            final mid = (from + to) ~/ 2 ~/ 60 * 60;
            return Stack(
              children: [
                for (final (m, x) in [
                  (from, -1.0),
                  if (box.maxWidth >= 200) (mid, ((mid - from) / (to - from)) * 2 - 1),
                  (to, 1.0),
                ])
                  Align(
                    alignment: Alignment(x, 0),
                    child: Text(OpenPeriod.label(m), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: brand.muted)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// On top of a week of tracks: a pulsing light and [title] (open now,
/// training now) over [detail], tinted green when [on]; [trailing] at the
/// end.
class _WeekStatus extends StatelessWidget {
  final bool on;
  final String title;
  final String? detail;
  final Widget? trailing;

  const _WeekStatus({required this.on, required this.title, this.detail, this.trailing});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: on ? brand.success.withValues(alpha: 0.08) : _tint(brand),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: on ? brand.success.withValues(alpha: 0.28) : brand.glassBorder),
      ),
      child: Row(
        children: [
          _PulseDot(size: 10, on: on, color: on ? brand.success : brand.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: on ? brand.readable(brand.success) : brand.ink),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(detail!, style: TextStyle(fontSize: 13, color: brand.muted)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

/// A day's name on a week of tracks, Today under it on today.
class _DayName extends StatelessWidget {
  final int day;
  final bool today;

  const _DayName({required this.day, required this.today});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          OpeningHours.names[day - 1],
          style: TextStyle(
            fontSize: 14,
            fontWeight: today ? FontWeight.w800 : FontWeight.w600,
            color: today ? brand.ink : brand.body,
          ),
        ),
        if (today)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PulseDot(size: 5, color: brand.accentText),
              const SizedBox(width: 3),
              Text('TODAY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1, color: brand.accentText)),
            ],
          ),
      ],
    );
  }
}

/// A day's row on a week of tracks: today tinted orange and ringed.
BoxDecoration? _dayRow(Brand brand, bool today) => today
    ? BoxDecoration(
        color: brand.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: brand.accent.withValues(alpha: 0.2)),
      )
    : null;

/// A time's words that wrap only between periods, never inside one.
String _unbroken(String text) =>
    text.replaceAll(' am', ' am').replaceAll(' pm', ' pm').replaceAll('–', '–⁠');

/// The week's opening hours: a card saying whether it's open now (until
/// when, or when it opens) beside today's hours; then each day on a track
/// across the day, its open hours in orange growing in one after another,
/// today marked with where now is; the times of day under them.
class GymHoursList extends StatelessWidget {
  final OpeningHours hours;

  const GymHoursList({super.key, required this.hours});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final moment = BhutanTime.now();
    final now = hours.at(moment);
    final today = moment.weekday;
    final minute = moment.hour * 60 + moment.minute;
    final (from, to) = _trackRange([for (final p in hours.days.values.expand((p) => p)) (p.open, p.close)]);
    final todayText = hours.textOn(today);
    final status = now?.label.split(' · ');
    return LayoutBuilder(
      builder: (context, constraints) {
        final textWidth = constraints.maxWidth < 380 ? 100.0 : 124.0;
        const dayWidth = 46.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (now != null && status != null) ...[
              GymRevealItem(
                order: 0,
                child: _WeekStatus(
                  on: now.open,
                  title: status.first,
                  detail: status.length > 1 ? status.skip(1).join(' · ') : null,
                  trailing: todayText == null
                      ? null
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'TODAY',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: brand.muted),
                            ),
                            const SizedBox(height: 2),
                            Text(todayText, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: brand.ink)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            for (var day = 1; day <= 7; day++)
              if (hours.on(day) case final open?)
                GymRevealItem(
                  order: day,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 1.5),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: _dayRow(brand, day == today),
                    child: Row(
                      children: [
                        SizedBox(width: dayWidth, child: _DayName(day: day, today: day == today)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DayTrack(
                            spans: [for (final p in open) (start: p.open, end: p.close, on: true)],
                            from: from,
                            to: to,
                            now: day == today ? minute : null,
                            order: day,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: textWidth,
                          child: Text(
                            _unbroken(hours.textOn(day)!),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: day == today ? FontWeight.w800 : FontWeight.w700,
                              color: open.isEmpty ? brand.muted : brand.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            _TrackAxis(from: from, to: to, padding: EdgeInsets.fromLTRB(10 + dayWidth + 10, 6, 10 + 12 + textWidth, 0)),
          ],
        );
      },
    );
  }
}

/// What a gym has, each ticked on a small tile: two or three across.
class GymFacilities extends StatelessWidget {
  final List<String> facilities;

  const GymFacilities({super.key, required this.facilities});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final columns = constraints.maxWidth >= 520 ? 3 : 2;
        final each = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (i, f) in facilities.indexed)
              GymRevealItem(
                order: i,
                child: Container(
                  width: each,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: brand.pick(const Color(0xFFF7F9FC), Colors.white.withValues(alpha: 0.04)),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: brand.glassBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(color: brand.accent.withValues(alpha: 0.14), shape: BoxShape.circle),
                        child: Icon(Icons.check_rounded, size: 14, color: brand.accentText),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          f,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.3, color: brand.ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A gym's packages on sale, one under another: name, length and what it
/// includes, its price in orange.
class GymPackagesList extends StatelessWidget {
  final List<GymPlan> plans;

  const GymPackagesList({super.key, required this.plans});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      children: [
        for (final (i, plan) in plans.indexed) ...[
          if (i > 0) Divider(height: 1, color: brand.glassBorder),
          GymRevealItem(
            order: i,
            child: Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 14, bottom: i == plans.length - 1 ? 0 : 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.name,
                          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: brand.ink),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.event_repeat_rounded, size: 14, color: brand.muted),
                            const SizedBox(width: 5),
                            Text(formatDuration(plan.durationDays), style: TextStyle(fontSize: 13, color: brand.muted)),
                          ],
                        ),
                        if (plan.description != null && plan.description!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(plan.description!, style: TextStyle(fontSize: 13.5, height: 1.5, color: brand.body)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    plan.price == 0 ? 'Free' : formatNu(plan.price),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: brand.accentText),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// How to reach a gym: Call, WhatsApp and Directions as tiles (whichever it
/// has), then who to ask for, its phone and email.
class GymContactPanel extends StatelessWidget {
  final Venue gym;

  const GymContactPanel({super.key, required this.gym});

  /// Whether [gym] has any way to reach it.
  static bool shows(Venue gym) =>
      gym.phone != null || gym.whatsapp != null || gym.hasLocation || gym.contactPerson != null || gym.email != null;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final actions = [
      if (gym.phone != null) (Icons.call_rounded, 'Call', () => callPhone(context, gym.phone!)),
      if (gym.whatsapp != null) (Icons.chat_rounded, 'WhatsApp', () => openWhatsApp(context, gym.whatsapp!)),
      if (gym.hasLocation) (Icons.directions_rounded, 'Directions', () => openDirections(context, gym.latitude!, gym.longitude!)),
    ];
    final details = [
      if (gym.contactPerson != null) (Icons.person_outline_rounded, 'Ask for ${gym.contactPerson}', null),
      if (gym.phone != null) (Icons.call_outlined, gym.phone!, () => callPhone(context, gym.phone!)),
      if (gym.email != null)
        (Icons.mail_outline_rounded, gym.email!, () => openExternal(context, Uri(scheme: 'mailto', path: gym.email))),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (actions.isNotEmpty)
          Row(
            children: [
              for (final (i, (icon, label, onTap)) in actions.indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: GymRevealItem(
                    order: i,
                    child: _ContactTile(icon: icon, label: label, onTap: onTap, first: i == 0),
                  ),
                ),
              ],
            ],
          ),
        if (actions.isNotEmpty && details.isNotEmpty) const SizedBox(height: 14),
        for (final (j, (icon, text, onTap)) in details.indexed)
          GymRevealItem(
            order: actions.length + j,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: _tint(brand), borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, size: 18, color: brand.muted),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(text, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: brand.ink)),
                    ),
                    if (onTap != null) Icon(Icons.north_east_rounded, size: 16, color: brand.muted),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Call, WhatsApp or Directions: a round icon over its name on a tile that
/// warms under the mouse, its icon growing, and gives under a press. The
/// [first] is filled orange.
class _ContactTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool first;

  const _ContactTile({required this.icon, required this.label, required this.onTap, required this.first});

  @override
  State<_ContactTile> createState() => _ContactTileState();
}

class _ContactTileState extends State<_ContactTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final hover = _hover && !reduceMotion(context);
    final first = widget.first;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Pressable(
        child: AnimatedContainer(
          duration: Motion.hover,
          curve: Motion.ease,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: hover ? brand.accent.withValues(alpha: 0.1) : _tint(brand),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: brand.accent.withValues(alpha: hover ? 0.3 : 0)),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                child: Column(
                  children: [
                    AnimatedScale(
                      scale: hover ? 1.1 : 1,
                      duration: Motion.hover,
                      curve: Motion.pop,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: first || hover ? brand.accent : brand.accent.withValues(alpha: 0.14),
                        ),
                        child: Icon(widget.icon, size: 20, color: first || hover ? BrandColors.navy : brand.accentText),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: brand.ink),
                    ),
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

/// A row on a card that warms under the mouse and opens with [onTap] (it
/// just sits there without one); [builder] knows when it's hovered.
class _HoverRow extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget Function(bool hover) builder;

  const _HoverRow({required this.onTap, required this.builder});

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final hover = _hover && widget.onTap != null && !reduceMotion(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: Motion.hover,
        curve: Motion.ease,
        decoration: BoxDecoration(
          color: brand.accent.withValues(alpha: hover ? 0.06 : 0),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(14),
            hoverColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: widget.builder(hover),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small round button at a row's end, filling orange (its arrow nudging)
/// when the row is hovered.
class _RowArrow extends StatelessWidget {
  final IconData icon;
  final bool hover;

  const _RowArrow({required this.icon, required this.hover});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return AnimatedContainer(
      duration: Motion.hover,
      curve: Motion.ease,
      width: 34,
      height: 34,
      decoration: BoxDecoration(shape: BoxShape.circle, color: hover ? brand.accent : _tint(brand)),
      child: AnimatedSlide(
        offset: Offset(hover ? 0.1 : 0, 0),
        duration: Motion.hover,
        curve: Motion.ease,
        child: Icon(icon, size: 17, color: hover ? BrandColors.navy : brand.ink),
      ),
    );
  }
}

// ─── A trainer's profile ───────────────────────────────────────────────────

/// The top of a trainer's public profile, on navy: their photo in an orange
/// ring, Verified (once a gym has verified them), their name and what they
/// do, their rating, years and gyms counting up, and their specialties.
class TrainerProfileHero extends StatelessWidget {
  final TrainerProfile trainer;

  /// How many gyms have verified them.
  final int gyms;

  /// Over their name: Verified trainer (once a gym has verified them),
  /// unless given.
  final ({IconData icon, String text})? badge;

  /// Buttons under it all (on their own page: changing it, seeing it as
  /// members do).
  final List<Widget> actions;

  const TrainerProfileHero({super.key, required this.trainer, required this.gyms, this.badge, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final t = trainer;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final nameSize = wide ? 38.0 : 28.0;
        final across = wide ? CrossAxisAlignment.start : CrossAxisAlignment.center;
        final align = wide ? TextAlign.start : TextAlign.center;
        // Each part arriving in its turn.
        Widget rise(int turn, Widget child) => FadeSlideIn(delay: Motion.stagger * turn, offset: 14, child: child);
        // Popping in, its ring's light sweeping round, floating gently a
        // few times; lagging a little behind the page as it scrolls.
        final avatar = _Parallax(
          factor: 0.1,
          child: PopIn(
            child: GentleFloat(
              distance: 6,
              cycles: 3,
              child: _AvatarRing(
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                  child: TrainerAvatar(name: t.name, photoUrl: t.photoUrl, size: wide ? 124 : 100),
                ),
              ),
            ),
          ),
        );
        final stats = [
          if (t.ratingCount > 0)
            (
              value: t.ratingAverage!,
              format: (num v) => v.toStringAsFixed(1),
              label: t.ratingCount == 1 ? '1 review' : '${t.ratingCount} reviews',
              star: true,
            ),
          if (t.experienceYears != null)
            (
              value: t.experienceYears!,
              format: AnimatedCount.whole,
              label: t.experienceYears == 1 ? "year's experience" : "years' experience",
              star: false,
            ),
          if (gyms > 0) (value: gyms, format: AnimatedCount.whole, label: gyms == 1 ? 'gym' : 'gyms', star: false),
        ];
        final statRow = Wrap(
          alignment: wide ? WrapAlignment.start : WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 12,
          children: [
            // One after another, counting up.
            for (final (i, s) in stats.indexed) ...[
              if (i > 0)
                GymRevealItem(
                  order: 4 + i,
                  child: Container(
                    width: 1,
                    height: 32,
                    margin: EdgeInsets.symmetric(horizontal: wide ? 22 : 16),
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
              GymRevealItem(
                order: 4 + i,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: across,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (s.star) ...[
                          GymRevealItem(
                            order: 6 + i,
                            pop: true,
                            child: const Icon(Icons.star_rounded, size: 20, color: Color(0xFFF5A623)),
                          ),
                          const SizedBox(width: 3),
                        ],
                        AnimatedCount(
                          value: s.value,
                          format: s.format,
                          duration: Motion.count,
                          style: TextStyle(fontSize: wide ? 26 : 22, fontWeight: FontWeight.w800, height: 1, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      s.label,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
        final chips = Wrap(
          alignment: wide ? WrapAlignment.start : WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          // Popping in one after another.
          children: [
            for (final (i, s) in t.specialties.indexed)
              GymRevealItem(
                order: 7 + i,
                pop: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: Text(
                    s,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.92)),
                  ),
                ),
              ),
          ],
        );
        final words = Column(
          crossAxisAlignment: across,
          children: [
            if (badge ?? (gyms > 0 ? (icon: Icons.verified_rounded, text: 'VERIFIED TRAINER') : null) case final b?) ...[
              rise(1, _Sheen(delay: Motion.card * 2, child: _Badge(icon: b.icon, text: b.text))),
              const SizedBox(height: 14),
            ],
            rise(
              2,
              Text(
                t.name,
                textAlign: align,
                style: TextStyle(
                  fontSize: nameSize,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  letterSpacing: -nameSize * 0.025,
                  color: Colors.white,
                ),
              ),
            ),
            if (t.headline != null) ...[
              const SizedBox(height: 8),
              rise(
                3,
                Text(
                  t.headline!,
                  textAlign: align,
                  style: TextStyle(fontSize: wide ? 16.5 : 15, height: 1.5, color: Colors.white.withValues(alpha: 0.82)),
                ),
              ),
            ],
            if (stats.isNotEmpty) ...[SizedBox(height: wide ? 24 : 20), statRow],
            if (t.specialties.isNotEmpty) ...[SizedBox(height: wide ? 24 : 20), chips],
            if (actions.isNotEmpty) ...[
              SizedBox(height: wide ? 26 : 22),
              rise(
                6,
                Wrap(
                  alignment: wide ? WrapAlignment.start : WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: actions,
                ),
              ),
            ],
          ],
        );
        return Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B1530), Color(0xFF1B3F8A)],
            ),
            borderRadius: BorderRadius.circular(wide ? 28 : 22),
            boxShadow: _shadow(brand, light: 0.22, dark: 0.4, blur: 44, dy: 20),
          ),
          child: Stack(
            children: [
              // The light and the bands drifting at their own pace as the
              // page scrolls.
              Positioned(
                right: -90,
                top: -130,
                child: _Parallax(
                  factor: 0.35,
                  child: GentleFloat(
                    distance: 18,
                    cycles: 3,
                    child: GymGlow(color: brand.highlight.withValues(alpha: 0.3), size: 380),
                  ),
                ),
              ),
              if (wide)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _Parallax(factor: -0.15, child: CustomPaint(painter: GymStripesPainter.of(context))),
                  ),
                ),
              Padding(
                padding: EdgeInsets.all(wide ? 40 : 22),
                child: wide
                    ? Row(children: [avatar, const SizedBox(width: 32), Expanded(child: words)])
                    : Column(children: [avatar, const SizedBox(height: 18), words]),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A trainer's certificates: each on a row with its medal, who issued it and
/// when; one with a file opens it.
class TrainerCertificatesList extends StatelessWidget {
  final List<TrainerCertificate> certificates;

  /// Taking one away (on the trainer's own page); none when null.
  final ValueChanged<TrainerCertificate>? onRemove;

  /// What it says with none.
  final String empty;

  const TrainerCertificatesList({super.key, required this.certificates, this.onRemove, this.empty = 'None added yet.'});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    if (certificates.isEmpty) return Text(empty, style: TextStyle(color: brand.muted, height: 1.5));
    return Column(
      children: [
        for (final (i, c) in certificates.indexed) ...[
          if (i > 0) Divider(height: 1, color: brand.glassBorder),
          GymRevealItem(
            order: i,
            child: _HoverRow(
              onTap: c.fileUrl == null ? null : () => openExternal(context, Uri.parse(c.fileUrl!)),
              builder: (hover) {
                final about = [if (c.issuer != null) c.issuer!, if (c.issuedOn != null) '${c.issuedOn!.year}'].join(' · ');
                return Row(
                  children: [
                    AnimatedScale(
                      scale: hover ? 1.1 : 1,
                      duration: Motion.hover,
                      curve: Motion.pop,
                      child: const _IconTile(Icons.workspace_premium_rounded, size: 42),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.title,
                            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: brand.ink),
                          ),
                          if (about.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(about, style: TextStyle(fontSize: 13, color: brand.muted)),
                          ],
                        ],
                      ),
                    ),
                    if (c.fileUrl != null) ...[
                      const SizedBox(width: 10),
                      Tooltip(message: 'Open the certificate', child: _RowArrow(icon: Icons.north_east_rounded, hover: hover)),
                    ],
                    if (onRemove != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Remove',
                        icon: Icon(Icons.delete_outline_rounded, size: 20, color: brand.muted),
                        onPressed: () => onRemove!(c),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// The gyms that verified a trainer, each opening its page ([onOpen]).
class TrainerGymsList extends StatelessWidget {
  final List<({String id, String name, String place})> gyms;
  final ValueChanged<String> onOpen;

  const TrainerGymsList({super.key, required this.gyms, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    if (gyms.isEmpty) return Text('No gyms yet.', style: TextStyle(color: brand.muted));
    return Column(
      children: [
        for (final (i, g) in gyms.indexed) ...[
          if (i > 0) Divider(height: 1, color: brand.glassBorder),
          GymRevealItem(
            order: i,
            child: _HoverRow(
              onTap: () => onOpen(g.id),
              builder: (hover) => Row(
                children: [
                  AnimatedScale(
                    scale: hover ? 1.1 : 1,
                    duration: Motion.hover,
                    curve: Motion.pop,
                    child: const _IconTile(Icons.fitness_center_rounded, size: 42),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                g.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: brand.ink),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.verified_rounded, size: 16, color: brand.success),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.place_outlined, size: 14, color: brand.muted),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                g.place,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: brand.muted),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _RowArrow(icon: Icons.arrow_forward_rounded, hover: hover),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A trainer's week, as a gym's hours are shown: a card saying whether
/// they're training now (until when), later today, or when next; then each
/// day on a track across the day, their times here in orange and at other
/// gyms in grey (seen from one gym those are only 'Not available'), today
/// marked with where now is, each day's times under its track; with
/// [showGym], each time says where.
class TrainerWeek extends StatelessWidget {
  final List<TrainerSlot> slots;
  final bool showGym;

  const TrainerWeek({super.key, required this.slots, this.showGym = false});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    if (slots.isEmpty) return Text('No times set yet.', style: TextStyle(color: brand.muted));
    final moment = BhutanTime.now();
    final today = moment.weekday;
    final minute = moment.hour * 60 + moment.minute;
    final (from, to) = _trackRange([for (final s in slots) (s.starts, s.ends)]);
    List<TrainerSlot> on(int day) => slots.where((s) => s.weekday == day).toList()..sort((a, b) => a.starts.compareTo(b.starts));
    String where(TrainerSlot s) => showGym && s.venueName != null ? ' · ${s.venueName}' : '';
    // Now, later today, or the next day they train here.
    final here = on(today).where((s) => s.here).toList();
    final current = here.where((s) => minute >= s.starts && minute < s.ends).firstOrNull;
    final later = here.where((s) => s.starts > minute).firstOrNull;
    final next = [
      for (var i = 1; i <= 7; i++)
        if (on((today - 1 + i) % 7 + 1).where((s) => s.here).firstOrNull case final s?) s,
    ].firstOrNull;
    final (title, detail) = current != null
        ? ('Training now', 'until ${OpenPeriod.label(current.ends)}${where(current)}')
        : later != null
            ? ('Training later today', 'from ${OpenPeriod.label(later.starts)}${where(later)}')
            : (
                'Not training today',
                next == null ? null : 'Next: ${weekdayName(next.weekday)} ${OpenPeriod.label(next.starts)}${where(next)}',
              );
    final others = slots.any((s) => !s.here);
    const dayWidth = 46.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GymRevealItem(order: 0, child: _WeekStatus(on: current != null, title: title, detail: detail)),
        const SizedBox(height: 14),
        for (var day = 1; day <= 7; day++)
          if (on(day) case final times when times.isNotEmpty)
            GymRevealItem(
              order: day,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 1.5),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                decoration: _dayRow(brand, day == today),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: dayWidth,
                      child: Padding(padding: const EdgeInsets.only(top: 2), child: _DayName(day: day, today: day == today)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DayTrack(
                            spans: [for (final s in times) (start: s.starts, end: s.ends, on: s.here)],
                            from: from,
                            to: to,
                            now: day == today ? minute : null,
                            order: day,
                          ),
                          const SizedBox(height: 4),
                          // The day's times under its track.
                          Wrap(
                            spacing: 12,
                            runSpacing: 2,
                            children: [
                              for (final s in times)
                                Text(
                                  s.here ? '${s.time}${where(s)}' : '${s.time} · Not available',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: s.here ? FontWeight.w800 : FontWeight.w600,
                                    color: s.here ? brand.readable(brand.accent) : brand.muted,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        _TrackAxis(from: from, to: to, padding: const EdgeInsets.fromLTRB(10 + dayWidth + 10, 6, 10, 0)),
        if (others) ...[
          const SizedBox(height: 12),
          // What the colours mean.
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              for (final (on, text) in [(true, showGym ? 'Their times' : 'At this gym'), (false, 'Elsewhere: not available')])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 16,
                      height: 6,
                      decoration: BoxDecoration(
                        color: on ? brand.highlight : brand.pick(const Color(0xFFC3CCD9), Colors.white.withValues(alpha: 0.24)),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: brand.muted)),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Members' reviews of a trainer: their rating ([average] of [count]) large
/// over the stars, then each review with its writer's initial, stars, when
/// and words.
class TrainerReviewsList extends StatelessWidget {
  final List<TrainerReview> reviews;
  final double? average;
  final int count;

  /// What it says with none.
  final String empty;

  const TrainerReviewsList({
    super.key,
    required this.reviews,
    required this.average,
    required this.count,
    this.empty = 'No reviews yet. Members who train with them can write one.',
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (count > 0 && average != null) ...[
          GymRevealItem(
            order: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: brand.pick(const Color(0xFFF7F9FC), Colors.white.withValues(alpha: 0.04)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: brand.glassBorder),
              ),
              child: Row(
                children: [
                  AnimatedCount(
                    value: average!,
                    format: (v) => v.toStringAsFixed(1),
                    duration: Motion.count,
                    style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, height: 1, letterSpacing: -1, color: brand.ink),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PopStars(rating: average!, size: 19, order: 1),
                        const SizedBox(height: 5),
                        Text(
                          'From ${count == 1 ? '1 review' : '$count reviews'}',
                          style: TextStyle(fontSize: 13, color: brand.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (reviews.isEmpty)
          Text(empty, style: TextStyle(color: brand.muted, height: 1.5))
        else
          for (final (i, r) in reviews.indexed) ...[
            if (i > 0) Divider(height: 1, color: brand.glassBorder),
            GymRevealItem(
              order: i + 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GymRevealItem(
                      order: i + 2,
                      pop: true,
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: brand.accent.withValues(alpha: 0.14)),
                        child: Text(
                          r.reviewerName.trim().isEmpty ? '?' : r.reviewerName.trim()[0].toUpperCase(),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: brand.accentText),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  r.reviewerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: brand.ink),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(timeAgo(r.createdAt), style: TextStyle(fontSize: 12, color: brand.muted)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          _PopStars(rating: r.rating.toDouble(), size: 14, order: i + 2),
                          if (r.comment != null && r.comment!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(r.comment!, style: TextStyle(fontSize: 14, height: 1.55, color: brand.body)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
      ],
    );
  }
}

// ─── A trainer's own page ──────────────────────────────────────────────────

/// A round-ended button on the navy: filled orange, or glass; warming under
/// the mouse, giving under a press.
class HeroPillButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;

  const HeroPillButton({super.key, required this.label, required this.icon, required this.onPressed, this.filled = false});

  @override
  State<HeroPillButton> createState() => _HeroPillButtonState();
}

class _HeroPillButtonState extends State<HeroPillButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final hover = _hover && !reduceMotion(context);
    final filled = widget.filled;
    final ink = filled ? BrandColors.navy : Colors.white;
    final button = AnimatedContainer(
      duration: Motion.hover,
      curve: Motion.ease,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: filled
            ? (hover ? Color.lerp(brand.accent, Colors.white, 0.12) : brand.accent)
            : Colors.white.withValues(alpha: hover ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: filled ? null : Border.all(color: Colors.white.withValues(alpha: 0.28)),
        boxShadow: filled
            ? [BoxShadow(color: brand.accent.withValues(alpha: hover ? 0.45 : 0.3), blurRadius: hover ? 22 : 14, offset: const Offset(0, 6))]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 18, color: ink),
                const SizedBox(width: 8),
                Text(widget.label, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: ink)),
              ],
            ),
          ),
        ),
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      // The filled one catching the light once it has arrived.
      child: Pressable(child: filled ? _Sheen(delay: Motion.card * 3, child: button) : button),
    );
  }
}

/// A number at a glance: what it is, its colour and icon, and a word on it.
typedef GymStat = ({IconData icon, Color color, int value, String label, String note});

/// Numbers at a glance, each on its own tile with a coloured icon and a
/// soft light of its colour, counting up as they arrive one after another;
/// four across on a computer, two on a phone, a row's tiles of one height.
class GymStatTiles extends StatelessWidget {
  final List<GymStat> stats;

  const GymStatTiles({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 14.0;
        final columns = constraints.maxWidth >= 900 ? 4 : 2;
        return Column(
          children: [
            for (var row = 0; row * columns < stats.length; row++) ...[
              if (row > 0) const SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var col = 0; col < columns; col++) ...[
                      if (col > 0) const SizedBox(width: gap),
                      Expanded(
                        child: row * columns + col < stats.length
                            ? GymRevealItem(
                                order: row * columns + col,
                                child: _StatTile(stat: stats[row * columns + col], order: row * columns + col),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// One number on its tile: its icon popping in after the tile, its light
/// drifting, a bar of its colour growing along the foot.
class _StatTile extends StatefulWidget {
  final GymStat stat;

  /// Its turn among the tiles.
  final int order;

  const _StatTile({required this.stat, required this.order});

  @override
  State<_StatTile> createState() => _StatTileState();
}

class _StatTileState extends State<_StatTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final s = widget.stat;
    final color = brand.themed(s.color);
    final hover = _hover && !reduceMotion(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: Motion.hover,
        curve: Motion.ease,
        transform: Matrix4.translationValues(0, hover ? -3 : 0, 0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: brand.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: hover ? color.withValues(alpha: 0.35) : brand.glassBorder),
          boxShadow: hover ? _shadow(brand, light: 0.12, dark: 0.4, blur: 32, dy: 14) : _shadow(brand, light: 0.06, blur: 24, dy: 10),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -40,
              top: -50,
              child: GentleFloat(
                distance: 12,
                cycles: 3,
                phase: widget.order * 0.25,
                child: GymGlow(color: color.withValues(alpha: brand.isLight ? 0.16 : 0.2), size: 150),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 3,
              child: GymRevealItem(
                order: widget.order + 3,
                grow: true,
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.15)])),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GymRevealItem(
                    order: widget.order + 2,
                    pop: true,
                    child: AnimatedScale(
                      scale: hover ? 1.08 : 1,
                      duration: Motion.hover,
                      curve: Motion.pop,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.06)],
                          ),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: color.withValues(alpha: 0.22)),
                        ),
                        child: Icon(s.icon, size: 21, color: brand.readable(color)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AnimatedCount(
                    value: s.value,
                    format: AnimatedCount.whole,
                    duration: Motion.count,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1, letterSpacing: -0.6, color: brand.ink),
                  ),
                  const SizedBox(height: 6),
                  Text(s.label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: brand.ink)),
                  const SizedBox(height: 2),
                  Text(s.note, style: TextStyle(fontSize: 12.5, height: 1.4, color: brand.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small capitals over a part of a card.
class _Caption extends StatelessWidget {
  final String text;

  const _Caption(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: context.brand.muted),
      );
}

/// One of a trainer's gyms on their own page: where they stand there (and
/// the gym's note), their times there on the week's tracks, and once
/// verified their attendance and members there; changing their times
/// ([onChangeTimes]) and leaving or taking a request back ([onLeave]) when
/// they can.
class TrainerGymCard extends StatelessWidget {
  final MyTrainerGym gym;
  final VoidCallback? onChangeTimes;
  final VoidCallback? onLeave;

  const TrainerGymCard({super.key, required this.gym, this.onChangeTimes, this.onLeave});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final color = switch (gym.status) {
      TrainerStatus.verified => brand.success,
      TrainerStatus.pending => brand.warning,
      TrainerStatus.inactive => brand.muted,
      _ => brand.danger,
    };
    final verified = gym.status == TrainerStatus.verified;
    final inactive = gym.status == TrainerStatus.inactive;
    final recent = uniqueTrainerAttendanceEntries(gym.attendance);
    final days = trainerAttendanceDaysLast30(gym.attendance, BhutanTime.today());
    Widget mini(IconData icon, int value, String label) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: brand.pick(const Color(0xFFF7F9FC), Colors.white.withValues(alpha: 0.04)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: brand.glassBorder),
          ),
          child: Row(
            children: [
              _IconTile(icon, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedCount(
                      value: value,
                      format: AnimatedCount.whole,
                      duration: Motion.count,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.1, color: brand.ink),
                    ),
                    Text(label, style: TextStyle(fontSize: 12, height: 1.3, color: brand.muted)),
                  ],
                ),
              ),
            ],
          ),
        );
    Widget pill({required Widget leading, required String text}) => Container(
          padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
          decoration: BoxDecoration(color: _tint(brand), borderRadius: BorderRadius.circular(999)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(width: 6),
              Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: brand.ink)),
            ],
          ),
        );
    return _HoverCard(
      tint: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The gym and where they stand, on a wash of the standing's colour
          // sweeping in from the left.
          Stack(
            children: [
              Positioned.fill(
                child: GymRevealItem(
                  order: 0,
                  grow: true,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [color.withValues(alpha: 0.14), color.withValues(alpha: 0.02)]),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: brand.glassBorder))),
                child: Row(
                  children: [
                    const GymRevealItem(order: 1, pop: true, child: _IconTile(Icons.fitness_center_rounded, size: 44)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            gym.venueName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: brand.ink),
                          ),
                          if (gym.place.isNotEmpty)
                            Row(
                              children: [
                                Icon(Icons.place_outlined, size: 14, color: brand.muted),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    gym.place,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, color: brand.muted),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    GymRevealItem(
                      order: 3,
                      pop: true,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: color.withValues(alpha: 0.28)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _PulseDot(size: 7, on: gym.status == TrainerStatus.pending, color: color),
                            const SizedBox(width: 6),
                            Text(
                              gym.status.label,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: brand.readable(color)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (gym.decisionNote != null) ...[
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: _tint(brand),
                      borderRadius: BorderRadius.circular(12),
                      border: Border(left: BorderSide(color: brand.highlight, width: 3)),
                    ),
                    child: Text(
                      '"${gym.decisionNote}"',
                      style: TextStyle(fontSize: 14, height: 1.5, fontStyle: FontStyle.italic, color: brand.body),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Row(
                  children: [
                    Expanded(child: _Caption(inactive ? 'Schedule at this gym' : 'Your times')),
                    if (onChangeTimes != null)
                      TextButton.icon(
                        onPressed: onChangeTimes,
                        icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                        label: const Text('Change times'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (inactive)
                  Text(
                    'This gym made your trainer role inactive. Contact them if you would like to return.',
                    style: TextStyle(color: brand.muted, height: 1.5),
                  )
                else
                  TrainerWeek(slots: gym.slots),
                if (verified) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(child: GymRevealItem(order: 1, child: mini(Icons.event_available_rounded, days, 'attendance days · last 30'))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GymRevealItem(
                          order: 2,
                          child: mini(Icons.groups_rounded, gym.members.length, gym.members.length == 1 ? 'member' : 'members'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _Caption('Recent attendance'),
                  const SizedBox(height: 8),
                  if (recent.isEmpty)
                    Text('No attendance recorded yet.', style: TextStyle(color: brand.muted, fontSize: 13))
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final (i, a) in recent.take(7).indexed)
                          GymRevealItem(
                            order: 3 + i,
                            pop: true,
                            child: pill(
                              leading: Icon(Icons.check_circle_rounded, size: 16, color: brand.success),
                              text: '${formatShortDate(BhutanTime.toBhutan(a))} · ${formatTime(a)}',
                            ),
                          ),
                      ],
                    ),
                  if (gym.members.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const _Caption('Your members here'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final (i, member) in gym.members.indexed)
                          GymRevealItem(
                            order: 4 + i,
                            pop: true,
                            child: pill(
                              leading: Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: brand.accent.withValues(alpha: 0.16)),
                                child: Text(
                                  member.name.trim().isEmpty ? '?' : member.name.trim()[0].toUpperCase(),
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: brand.accentText),
                                ),
                              ),
                              text: member.name,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
                if (onLeave != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onLeave,
                      child: Text(
                        gym.status == TrainerStatus.pending ? 'Take my request back' : 'Stop training here',
                        style: TextStyle(color: brand.danger),
                      ),
                    ),
                  ),
                ] else
                  const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A card whose border warms with [tint] under the mouse, without lifting:
/// nothing on it opens as a whole.
class _HoverCard extends StatefulWidget {
  final Color tint;
  final Widget child;

  const _HoverCard({required this.tint, required this.child});

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final hover = _hover && !reduceMotion(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: Motion.hover,
        curve: Motion.ease,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: brand.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: hover ? widget.tint.withValues(alpha: 0.4) : brand.glassBorder),
          boxShadow: hover ? _shadow(brand, light: 0.1, dark: 0.4, blur: 34, dy: 14) : _shadow(brand, light: 0.06, blur: 26, dy: 10),
        ),
        child: widget.child,
      ),
    );
  }
}
