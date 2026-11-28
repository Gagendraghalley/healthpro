import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_repository.dart';
import '../gym_routes.dart';
import '../screens/public_screens.dart';
import '../shell/gym_search.dart';
import '../widgets/gym_art.dart';
import '../widgets/gym_type.dart';

/// The landing page for visitors, with a gym and health introduction and service
/// links supplied by the modules enabled for this installation.
///
/// Everything it claims is what the app does today: no member counts or
/// quotes until there are real ones.
class GymWelcomePage extends ConsumerStatefulWidget {
  const GymWelcomePage({super.key});

  @override
  ConsumerState<GymWelcomePage> createState() => _GymWelcomePageState();
}

class _GymWelcomePageState extends ConsumerState<GymWelcomePage> {
  final _scroll = ScrollController();
  final _servicesKey = GlobalKey();
  final _aboutKey = GlobalKey();
  final _stepsKey = GlobalKey();
  final _plansKey = GlobalKey();
  final _faqKey = GlobalKey();
  bool _scrolled = false;

  /// The page's beat (_Beat), counted by [_beat].
  final _beats = ValueNotifier<int>(0);
  Timer? _beat;

  void _restartBeat() {
    _beat?.cancel();
    _beat = Timer.periodic(_Beat.interval, (_) => _beats.value++);
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _scroll.addListener(() {
      final scrolled = _scroll.offset > 8;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    });
  }

  @override
  void dispose() {
    _beat?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    _beats.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _searching = false;

  /// The search over the page: the kinds of service and the places; the
  /// one chosen opens.
  void _search() {
    if (_searching) return;
    _searching = true;
    showPublicSearch(context, ref).whenComplete(() => _searching = false);
  }

  /// Ctrl K (⌘ K) opens the search, as in the app, unless something is open
  /// over the page.
  bool _onKey(KeyEvent event) {
    if (!isSearchShortcut(event) || !mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    _search();
    return true;
  }

  /// Scrolls [key]'s section up to just under the bar. A section not yet
  /// seen still waits a little low (_Reveal), so it lands a little high once
  /// it rises; the room left above it covers that.
  void _scrollTo(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !_scroll.hasClients) return;
    final barBottom = MediaQuery.paddingOf(context).top + _NavBar.height;
    final target = box.localToGlobal(Offset.zero).dy + _scroll.offset - barBottom - _RevealState.rise - 8;
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeInOutCubic,
    );
  }

  void _toTop() => _scroll.animateTo(0, duration: const Duration(milliseconds: 650), curve: Curves.easeInOutCubic);
  void _signUp() => context.push(CoreRoutes.signUp);
  void _logIn() => context.push(CoreRoutes.signIn);
  void _findGym() => context.push(GymRoutes.gyms);
  void _registerGym() => context.push(CoreRoutes.registerVenue);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The slide photos, ready before the top's slides sweep them in.
    for (final slide in _slides) {
      precacheImage(GymPhoto.provider(slide.photo), context);
    }
    if (reduceMotion(context)) {
      _beat?.cancel();
      _beat = null;
    } else if (_beat == null) {
      _restartBeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GymType(
      child: _Beat(
        beats: _beats,
        restart: () => _beat == null ? null : _restartBeat(),
        child: _page(_Layout(MediaQuery.sizeOf(context).width)),
      ),
    );
  }

  Widget _page(_Layout layout) {
    final modules = ref.watch(enabledModulesProvider).valueOrNull ?? const <HealthProModule>[];
    final appModules = ref.watch(appModulesProvider).valueOrNull ?? const <AppModuleRow>[];
    final enabledKeys = appModules.where((module) => module.isEnabled).map((module) => module.key).toSet();
    final serviceLinks = modules
        .where((module) => enabledKeys.contains(module.key))
        .expand((module) => module.playerMenuItems())
        .where((item) => item.isExternal)
        .toList();

    return Scaffold(
      backgroundColor: context.brand.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              controller: _scroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The user's layout: the photo and Where are you based,
                  // then every kind of service, then the rest.
                  _Hero(layout: layout, scroll: _scroll, onExplore: () => _scrollTo(_servicesKey)),
                  _ServiceMarquee(layout: layout),
                  _Reveal(
                    child: _ServiceTypes(
                      key: _servicesKey,
                      layout: layout,
                      serviceLinks: serviceLinks,
                      onFindGym: _findGym,
                    ),
                  ),
                  _Reveal(child: _About(key: _aboutKey, layout: layout, onKnowMore: () => _scrollTo(_stepsKey))),
                  _Reveal(child: _Steps(key: _stepsKey, layout: layout)),
                  _Reveal(child: _Plans(key: _plansKey, layout: layout, onFindGym: _findGym)),
                  _Reveal(child: _Faq(key: _faqKey, layout: layout, onFindGym: _findGym)),
                  _Reveal(child: _LastCall(layout: layout, onJoin: _signUp, onRegisterGym: _registerGym)),
                  _Footer(
                    layout: layout,
                    links: [
                      ('Services', _findGym),
                      ('Register as a professional', _registerGym),
                      ('How it works', () => _scrollTo(_stepsKey)),
                      ('FAQs', () => _scrollTo(_faqKey)),
                      ('Log in', _logIn),
                      ('Sign up', _signUp),
                      ('Privacy', () => showLegal(context, LegalDoc.privacy)),
                      ('Terms', () => showLegal(context, LegalDoc.terms)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _NavBar(
              layout: layout,
              scrolled: _scrolled,
              onLogo: _toTop,
              onSearch: _search,
              onRegister: _registerGym,
              onLogIn: _logIn,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Layout and colours ────────────────────────────────────────────────────

/// Sizes for the window's [width]: wide (a computer), medium (a tablet or a
/// small window) or narrow (a phone).
class _Layout {
  final double width;

  const _Layout(this.width);

  static const maxContent = 1180.0;

  /// How far What Health Pro does rises into the top, over its wave.
  static const overlap = 56.0;

  bool get wide => width >= 1024;
  bool get medium => width >= 680;

  /// The five steps side by side (one under the other below this).
  bool get stepsInRow => width >= 860;

  double get gutter => wide ? 40 : (medium ? 28 : 20);
  double get section => wide ? 96 : 64;
  double get titleSize => wide ? 44 : (medium ? 38 : 30);
}

/// The page's colours, for light or dark; mixed while the theme switches,
/// so bands and cards glide rather than flash.
class _Ink {
  /// 0 light, 1 dark ([Brand.darkness]).
  final double t;

  const _Ink(this.t);

  factory _Ink.of(BuildContext context) => _Ink(context.brand.darkness);

  bool get dark => t >= 0.5;

  Color pick(Color light, Color dark) => Color.lerp(light, dark, t)!;

  Color get heading => pick(LightColors.ink, Colors.white);
  Color get body => pick(LightColors.body, const Color(0xFFC5CCDA));

  /// Behind icons: a cool pale grey-blue, or a faint white in the dark.
  Color get tint => pick(const Color(0xFFEAF0F8), Colors.white.withValues(alpha: 0.08));

  /// A card on the page.
  Color get card => pick(LightColors.card, BrandColors.slateNavy);

  /// Under a card: a soft navy haze in the light, a deep shadow in the dark.
  List<BoxShadow> shadow({double light = 0.07, double dark = 0.3, double blur = 24, double dy = 10}) => [
        BoxShadow(
          color: pick(LightColors.navy.withValues(alpha: light), Colors.black.withValues(alpha: dark)),
          blurRadius: blur,
          spreadRadius: this.dark ? 0 : -4,
          offset: Offset(0, dy),
        ),
      ];
}

/// [child] centred, no wider than the content, with room at the sides.
class _Frame extends StatelessWidget {
  final _Layout layout;
  final Widget child;

  const _Frame({required this.layout, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _Layout.maxContent + layout.gutter * 2),
        child: Padding(padding: EdgeInsets.symmetric(horizontal: layout.gutter), child: child),
      ),
    );
  }
}


// ─── The bar ───────────────────────────────────────────────────────────────

/// The logo, Ask AI, light or dark, Register as a professional (a button on
/// a computer, an icon on a tablet; the footer has it on a phone), Log in /
/// Sign up and, last, search, on frosted glass.
class _NavBar extends StatelessWidget {
  static const height = 72.0;

  final _Layout layout;
  final bool scrolled;
  final VoidCallback onLogo;

  /// Searches the kinds of service and the places; the one chosen opens.
  final VoidCallback onSearch;
  final VoidCallback onRegister;

  /// Log in, which offers Sign up.
  final VoidCallback onLogIn;

  const _NavBar({
    required this.layout,
    required this.scrolled,
    required this.onLogo,
    required this.onSearch,
    required this.onRegister,
    required this.onLogIn,
  });

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            // Frosted from the start, so the links stay clear over the
            // top's photo; fully once the page scrolls.
            child: AnimatedOpacity(
              opacity: scrolled ? 1 : 0.85,
              duration: const Duration(milliseconds: 200),
              child: GlassBar(border: Border(bottom: BorderSide(color: context.brand.glassBorder))),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
          child: SizedBox(
            height: height,
            child: _Frame(
              layout: layout,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Semantics(
                    button: true,
                    label: 'Back to the top',
                    child: GestureDetector(
                      onTap: onLogo,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: HealthProLogo(height: layout.medium ? 46 : 38, markOnly: !layout.medium),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // The buttons at their size; on a small phone or with large
                  // text they shrink to fit rather than run off the edge.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Ask AI (Health Pro's assistant, under this bar), then
                          // light or dark. Their touch areas don't pad out past
                          // the buttons (as on a computer), leaving a phone room.
                          IconButtonTheme(
                            data: IconButtonThemeData(
                              style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap)
                                  .merge(IconButtonTheme.of(context).style),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AskAiBarButton(
                                    onPressed: () => openAssistant(context, const HealthProAssistantPanel(), underBar: height)),
                                if (MediaQuery.sizeOf(context).width >= 700) const SizedBox(width: 6),
                                ThemeModeButton(color: ink.heading),
                              ],
                            ),
                          ),
                          SizedBox(width: layout.medium ? 8 : 4),
                          if (layout.wide) ...[
                            _PillButton(label: 'Register as a professional', outlined: true, compact: true, onPressed: onRegister),
                            const SizedBox(width: 10),
                          ] else if (layout.medium) ...[
                            IconButton(
                              tooltip: 'Register as a professional',
                              onPressed: onRegister,
                              color: ink.heading,
                              icon: const Icon(Icons.add_business_outlined),
                            ),
                            const SizedBox(width: 4),
                          ],
                          _PillButton(label: 'Log in / Sign up', compact: true, onPressed: onLogIn),
                          SizedBox(width: layout.medium ? 10 : 8),
                          // Last, the search: a field with its shortcut on a
                          // computer, its icon on a tile of the same look on
                          // a tablet or phone.
                          if (GlobalSearchBox.shows(context))
                            SizedBox(
                              width: 230,
                              child: GlobalSearchBox(hint: 'Search services…', onPressed: onSearch),
                            )
                          else
                            _SearchTile(onPressed: onSearch),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The search on a tablet or phone: its icon on a tile like the computer's
/// field (a soft grey well with an edge in the light theme).
class _SearchTile extends StatelessWidget {
  final VoidCallback onPressed;

  const _SearchTile({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return IconButton(
      tooltip: 'Search services',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: _Ink.of(context).heading,
        backgroundColor: brand.pick(const Color(0xFFF1F4F9), brand.card),
        side: BorderSide(color: brand.pick(LightColors.border, brand.fieldBorder)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.search_rounded, size: 21),
    );
  }
}

// ─── The top ───────────────────────────────────────────────────────────────

/// The user's layout: a slide show of training filling the left of the
/// window (a card on top on a phone), with a membership card and a check-in
/// floating over it, and Where are you based beside it (_WhereAreYou); a
/// wave runs along the foot.
///
/// The slides move like 108.bt's opening scene: each photo sweeps in behind
/// the page's navy and orange bands, drifts slowly closer while it shows,
/// then gives way to the next.
class _Hero extends StatefulWidget {
  final _Layout layout;

  /// To every kind of service, under the top.
  final VoidCallback onExplore;

  /// The page's scroll: the photos drift up a little slower than the page
  /// and lean in (a gentle depth), and rest once the top is out of sight.
  final ScrollController scroll;

  const _Hero({required this.layout, required this.onExplore, required this.scroll});

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> with TickerProviderStateMixin {
  late final _SlideShow _show = _SlideShow(this);

  _Layout get layout => widget.layout;

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(_Hero old) {
    super.didUpdateWidget(old);
    if (old.scroll != widget.scroll) {
      old.scroll.removeListener(_onScroll);
      widget.scroll.addListener(_onScroll);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Starts the slides the first time; stills them, or sets them going,
    // when Reduce motion changes.
    _show.setStill(reduceMotion(context));
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_onScroll);
    _show.dispose();
    super.dispose();
  }

  /// The slides rest while the top is scrolled out of sight.
  void _onScroll() {
    if (!widget.scroll.hasClients) return;
    final box = context.findRenderObject();
    final height = box is RenderBox && box.hasSize ? box.size.height : 800.0;
    _show.setVisible(widget.scroll.offset < height - 40);
  }

  /// [child] moved by a share of the scroll, and leaning in by [zoom] as it
  /// goes, while the top is on screen.
  Widget _parallax(BuildContext context, Widget child, {double rate = 0.12, double zoom = 0}) {
    if (reduceMotion(context)) return child;
    return AnimatedBuilder(
      animation: widget.scroll,
      child: child,
      builder: (context, child) {
        final offset = widget.scroll.hasClients ? widget.scroll.offset.clamp(0.0, 900.0) : 0.0;
        return Transform.translate(
          offset: Offset(0, offset * rate),
          child: Transform.scale(scale: 1 + zoom * offset / 900, child: child),
        );
      },
    );
  }

  /// [child], swiped left for the next slide or right for the one before.
  Widget _swipe(Widget child) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -150) _show.next();
          if (velocity > 150) _show.previous();
        },
        child: child,
      );

  /// The sample card and the check-in note: they arrive after the photos,
  /// then float a little, out of step, and settle.
  static Widget _card(Widget child, {required int order}) => FadeSlideIn(
        delay: Duration(milliseconds: 520 + 140 * order),
        offset: 26,
        child: GentleFloat(phase: order * 0.35, distance: order == 0 ? 7 : 5, child: child),
      );

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    // Behind the words, and what the photo fades into.
    final bg = ink.pick(LightColors.backgroundAlt, BrandColors.navy);
    // Large but measured: it grows with the window and never crowds the photos.
    final headlineSize = layout.wide ? (layout.width * 0.046).clamp(52.0, 68.0) : (layout.medium ? 54.0 : 40.0);
    final headline = TextStyle(
      fontSize: headlineSize,
      fontWeight: FontWeight.w800,
      fontStyle: FontStyle.italic,
      height: 1.04,
      letterSpacing: -headlineSize * 0.03,
      color: ink.heading,
    );
    final words = _WhereAreYou(layout: layout, headline: headline, onExplore: widget.onExplore);
    final top = MediaQuery.paddingOf(context).top + _NavBar.height;
    return ClipPath(
      clipper: _WaveClipper(),
      child: ColoredBox(
        color: bg,
        child: layout.wide ? _wide(context, words, bg, top) : _narrow(context, words, bg, top),
      ),
    );
  }

  /// The slides fill the left of the window behind a clean slanted edge (an
  /// orange rule along it), graded towards navy so every slide sits in the
  /// brand's colours, with the way between them on glass under the cards.
  /// The whole window, like a stage (never shorter than what's on it).
  Widget _wide(BuildContext context, Widget words, Color bg, double top) {
    // The edge's foot sits just inside the words' column; it leans away from
    // them going up, where the headline is widest.
    final inner = math.min(layout.width - layout.gutter * 2, _Layout.maxContent);
    final photoRight = (layout.width - inner) / 2 + (inner - 40) * 11 / 21 - 30;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height.clamp(0.0, 1080.0)),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
              right: -200,
              top: 40,
              child: GymGlow(color: BrandColors.blue.withValues(alpha: _Ink.of(context).dark ? 0.16 : 0.08), size: 560)),
          Positioned(
            left: 0,
            top: 0,
            right: photoRight,
            bottom: 0,
            child: _swipe(
              // The edge, its rule and the grade drawn for a photo on the
              // right, turned round; the photos turned back, so they read true.
              Transform.flip(
                flipX: true,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipPath(
                      clipper: const _SlantClipper(),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _parallax(context, Transform.flip(flipX: true, child: _SlideStage(show: _show)), zoom: 0.06),
                          const IgnorePointer(child: _PhotoGrade()),
                          IgnorePointer(child: CustomPaint(painter: GymStripesPainter.of(context))),
                        ],
                      ),
                    ),
                    IgnorePointer(child: CustomPaint(painter: _SlantRulePainter(context.brand.highlight))),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: top + 70, bottom: _Layout.overlap + 130),
            child: _Frame(
              layout: layout,
              child: Row(
                children: [
                  Expanded(
                    flex: 10,
                    child: SizedBox(
                      height: 440,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Across the photo's edge, clear of the words beside it.
                          Positioned(right: 0, bottom: 10, child: _card(const _MiniCard(), order: 0)),
                          Positioned(
                            left: 10,
                            bottom: 30,
                            child: _card(
                              const _FloatingNote(
                                icon: Icons.check_rounded,
                                iconColor: BrandColors.green,
                                title: 'Checked in',
                                text: 'Today, 6:42 AM',
                              ),
                              order: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                  Expanded(flex: 11, child: words),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: _Layout.overlap + 62,
            child: _Frame(
              layout: layout,
              child: Row(
                children: [
                  Expanded(
                    flex: 10,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FadeSlideIn(
                        delay: const Duration(milliseconds: 900),
                        child: _SlideControls(show: _show),
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                  const Spacer(flex: 11),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The slides as a rounded card (swiped between, the way between them over
  /// its top) with the membership card and the check-in over it, then the
  /// words: the user's left-to-right, top to bottom.
  Widget _narrow(BuildContext context, Widget words, Color bg, double top) {
    return Stack(
      children: [
        Positioned(right: -160, top: -80, child: GymGlow(color: context.brand.highlight.withValues(alpha: 0.16), size: 420)),
        Padding(
          padding: EdgeInsets.only(top: top + 28, bottom: _Layout.overlap + 92),
          child: _Frame(
            layout: layout,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: layout.medium ? 460 : 380,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        bottom: 40,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(26),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _swipe(_SlideStage(show: _show)),
                              const IgnorePointer(child: _PhotoGrade()),
                              // A shade under the ticks and the slide's name,
                              // so they read over any photo.
                              const IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [Color(0x8C081428), Color(0x00081428)],
                                      stops: [0, 0.4],
                                    ),
                                  ),
                                ),
                              ),
                              IgnorePointer(child: CustomPaint(painter: GymStripesPainter.of(context))),
                              Positioned(
                                top: 8,
                                left: 14,
                                right: 12,
                                child: _SlideControls(show: _show, compact: true),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        bottom: 0,
                        child: Transform.scale(
                            scale: layout.medium ? 1 : 0.86,
                            alignment: Alignment.bottomLeft,
                            child: _card(const _MiniCard(), order: 0)),
                      ),
                      Positioned(
                        right: 12,
                        top: 88,
                        child: _card(
                          const _FloatingNote(
                            icon: Icons.check_rounded,
                            iconColor: BrandColors.green,
                            title: 'Checked in',
                            text: 'Today, 6:42 AM',
                          ),
                          order: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                words,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Where are you based ───────────────────────────────────────────────────

/// Whether [venue] is in [area].
bool _inArea(ServicesArea area, Venue venue) =>
    venue.dzongkhag == area.dzongkhag && (area.town == null || venueArea(venue) == area.town);

/// The area the welcome page shows: the one the visitor chose, else where
/// they are (once their location is known): their dzongkhag, from where
/// they stand (dzongkhagAt), and in it the area of the place nearest them,
/// when one is within [nearbyKm]. Null for everywhere (not known yet, or
/// outside Bhutan).
final _shownAreaProvider = Provider<ServicesArea?>((ref) {
  final chosen = ref.watch(servicesAreaProvider);
  if (chosen != null) return chosen;
  final here = ref.watch(myLocationProvider);
  if (here == null) return null;
  final dzongkhag = dzongkhagAt(here.latitude, here.longitude);
  if (dzongkhag == null) return null;
  String? town;
  var best = nearbyKm.toDouble();
  for (final v in ref.watch(moduleVenuesProvider(gymModuleKey)).valueOrNull ?? const <Venue>[]) {
    if (v.dzongkhag != dzongkhag || !v.hasLocation) continue;
    final km = distanceKm(here.latitude, here.longitude, v.latitude!, v.longitude!);
    if (km <= best) {
      best = km;
      town = venueArea(v);
    }
  }
  return (dzongkhag: dzongkhag, town: town);
});

/// Where are you based (the user's layout, beside the photo): "in Thimphu?",
/// the dzongkhag they are in, from their location, which the page asks for
/// each time it opens; with that dzongkhag's areas (the towns its places are
/// in) to choose from, the one nearest them chosen. Until it is known (or if
/// they say no), "in Bhutan?" and the dzongkhags to choose from, and Use my
/// location. Every kind of service under the top counts its places in the
/// area shown, and Find services starts there.
class _WhereAreYou extends ConsumerStatefulWidget {
  final _Layout layout;
  final TextStyle headline;
  final VoidCallback onExplore;

  const _WhereAreYou({required this.layout, required this.headline, required this.onExplore});

  @override
  ConsumerState<_WhereAreYou> createState() => _WhereAreYouState();
}

class _WhereAreYouState extends ConsumerState<_WhereAreYou> {
  /// How many areas show as buttons, those with the most places; the rest,
  /// and the other dzongkhags, are under More places.
  static const _shownAreas = 6;

  bool _locating = false;

  /// Asks for their location as the page opens (the browser or phone asks
  /// them, unless they have already answered); nothing said on a no.
  @override
  void initState() {
    super.initState();
    if (ref.read(myLocationProvider) != null) return;
    _locating = true;
    locationIfAllowed().then((here) {
      if (!mounted) return;
      setState(() => _locating = false);
      // Find services needn't ask again this visit.
      ref.read(locationLookedUpProvider.notifier).state = true;
      if (here != null && ref.read(myLocationProvider) == null) ref.read(myLocationProvider.notifier).state = here;
    });
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    final ok = await runAction(context, () async {
      ref.read(myLocationProvider.notifier).state = await currentLocation();
    });
    if (!mounted) return;
    setState(() => _locating = false);
    // Where they are, rather than an area picked before.
    if (ok) ref.read(servicesAreaProvider.notifier).state = null;
  }

  void _choose(ServicesArea area) => ref.read(servicesAreaProvider.notifier).state = area;

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final headline = widget.headline;
    final ink = _Ink.of(context);
    final venues = ref.watch(moduleVenuesProvider(gymModuleKey)).valueOrNull ?? const <Venue>[];
    final here = ref.watch(myLocationProvider);
    final shown = ref.watch(_shownAreaProvider);
    final fromLocation = ref.watch(servicesAreaProvider) == null;

    // Their dzongkhag, once known (from where they are, or chosen).
    final dzongkhag = shown?.dzongkhag;
    // [counts]' names, the most places first.
    List<String> mostFirst(Map<String, int> counts) => counts.keys.toList()
      ..sort((a, b) {
        final most = counts[b]!.compareTo(counts[a]!);
        return most != 0 ? most : a.compareTo(b);
      });
    final perDzongkhag = <String, int>{};
    for (final v in venues) {
      perDzongkhag[v.dzongkhag] = (perDzongkhag[v.dzongkhag] ?? 0) + 1;
    }

    // Known: all of it, and its areas (the one shown always in view); the
    // rest, and the other dzongkhags, under More places. Not known: the
    // dzongkhags with places.
    final List<(String, ServicesArea)> inView;
    final List<(String, ServicesArea)> more;
    if (dzongkhag != null) {
      final perArea = <String, int>{};
      for (final v in venues) {
        final town = venueArea(v);
        if (v.dzongkhag == dzongkhag && town != null) perArea[town] = (perArea[town] ?? 0) + 1;
      }
      final areas = mostFirst(perArea);
      final shownAreas = [
        ...areas.take(_shownAreas),
        if (shown?.town != null && areas.indexOf(shown!.town!) >= _shownAreas) shown.town!,
      ];
      inView = [
        ('All of $dzongkhag', (dzongkhag: dzongkhag, town: null)),
        for (final a in shownAreas) (a, (dzongkhag: dzongkhag, town: a)),
      ];
      more = [
        for (final a in areas)
          if (!shownAreas.contains(a)) (a, (dzongkhag: dzongkhag, town: a)),
        for (final d in mostFirst(perDzongkhag))
          if (d != dzongkhag) ('All of $d', (dzongkhag: d, town: null)),
      ];
    } else {
      final withPlaces = mostFirst(perDzongkhag);
      inView = [for (final d in withPlaces.take(_shownAreas)) (d, (dzongkhag: d, town: null))];
      more = [for (final d in withPlaces.skip(_shownAreas)) (d, (dzongkhag: d, town: null))];
    }

    Widget areaButton(String label, ServicesArea area) {
      final on = shown == area;
      return _PillButton(
        label: label,
        compact: true,
        outlined: !on,
        // The one nearest them, marked.
        icon: on && fromLocation ? Icons.near_me_rounded : null,
        onPressed: () => _choose(area),
      );
    }

    final choices = [
      for (final (label, area) in inView) areaButton(label, area),
      if (more.isNotEmpty)
        MenuAnchor(
          builder: (context, menu, _) => _PillButton(
            label: 'More places',
            icon: Icons.expand_more_rounded,
            compact: true,
            outlined: true,
            onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          ),
          menuChildren: [
            for (final (label, area) in more) MenuItemButton(onPressed: () => _choose(area), child: Text(label)),
          ],
        ),
    ];
    final buttons = [
      _PillButton(label: 'Explore services', icon: Icons.arrow_forward_rounded, onPressed: widget.onExplore),
      if (here == null)
        _PillButton(
          label: _locating ? 'Finding you…' : 'Use my location',
          icon: Icons.my_location_rounded,
          outlined: true,
          onPressed: _locating ? () {} : _useMyLocation,
        ),
    ];

    // The headline arrives a line at a time, then the rest: one short
    // cascade on arrival, then still.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: staggered(step: const Duration(milliseconds: 90), offset: 18, [
        const Padding(padding: EdgeInsets.only(bottom: 24), child: _HeroBadge('HEALTH & WELLNESS IN BHUTAN')),
        Text('Where are you', style: headline),
        Text('based in', style: headline),
        _AccentText('${dzongkhag ?? 'Bhutan'}?', style: headline),
        Padding(
          padding: EdgeInsets.only(top: layout.wide ? 24 : 18, bottom: layout.wide ? 28 : 22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 470),
            child: Text(
              'Choose your area and see every service near you. Join any of them with one Health Pro account.',
              style: TextStyle(fontSize: layout.wide ? 18 : 16, height: 1.65, color: ink.body),
            ),
          ),
        ),
        if (choices.isEmpty)
          const SizedBox.shrink()
        else
          Padding(
            padding: EdgeInsets.only(bottom: layout.wide ? 30 : 26),
            child: Wrap(spacing: 10, runSpacing: 10, children: choices),
          ),
        // Side by side; one over the other, the width of a phone.
        if (layout.medium)
          Wrap(spacing: 14, runSpacing: 12, children: buttons)
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final (i, b) in buttons.indexed) ...[if (i > 0) const SizedBox(height: 12), b]],
          ),
      ]),
    );
  }
}

// ─── The top's slides ──────────────────────────────────────────────────────

/// One side of training and health in the top's slide show, from the gym
/// photography already in the app (local, so the page never waits on an
/// image service).
class _Slide {
  /// Its photo in assets/welcome.
  final String photo;
  final String name;

  /// What the photo keeps in view as it fills its space.
  final Alignment alignment;

  /// Where it slowly draws closer to (the bar, the people training).
  final Alignment focus;

  const _Slide(this.photo, this.name, {this.alignment = Alignment.center, this.focus = Alignment.center});
}

const _slides = [
  _Slide('hero', 'Strength', focus: Alignment(-0.1, -0.5)),
  _Slide('cardio', 'Cardio', focus: Alignment(-0.2, -0.1)),
  _Slide('training', 'Training', alignment: Alignment(0.2, 0), focus: Alignment(0.1, -0.2)),
  _Slide('classes', 'Classes', focus: Alignment(-0.1, -0.2)),
  _Slide('active', 'Healthy Living', alignment: Alignment(0, 0.3), focus: Alignment(0, 0.3)),
];

/// A photo on the stage: [reveal] sweeps it in; [life] draws it closer
/// while it shows (and on while the next sweeps over it).
class _SlideLayer {
  final int serial;
  final _Slide slide;
  final AnimationController reveal;
  final AnimationController life;

  _SlideLayer({required this.serial, required this.slide, required this.reveal, required this.life});

  void stop() {
    reveal.stop();
    life.stop();
  }

  void dispose() {
    reveal.dispose();
    life.dispose();
  }
}

/// The top's slide show: which slide is showing, the photos still sweeping
/// in over it, and the clock that moves it on. It plays every slide twice
/// and then rests (Play starts it again), rests while the top is out of
/// sight, and stands still when motion is reduced (the arrows and ticks
/// still change slide, at once).
class _SlideShow extends ChangeNotifier {
  _SlideShow(this._vsync) {
    _clock = AnimationController(vsync: _vsync, duration: dwell)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _advance();
      });
  }

  /// How long each slide shows, from when it starts to sweep in.
  static const dwell = Duration(milliseconds: 6500);

  /// How long a photo takes to sweep in.
  static const sweep = Duration(milliseconds: 1150);

  /// Times through every slide before the show rests.
  static const rounds = 2;

  final TickerProvider _vsync;
  late final AnimationController _clock;
  Timer? _intro;

  /// The photos on the stage, bottom first; the top one may still be
  /// sweeping in.
  final layers = <_SlideLayer>[];

  /// The slide showing (or sweeping in).
  int index = 0;

  /// Whether it moves on by itself (Pause stops it).
  bool playing = false;

  bool _started = false;
  bool _still = false;
  bool _visible = true;
  int _serial = 0;
  int _advances = 0;

  /// How far through its time the showing slide is, 0 to 1.
  Animation<double> get progress => _clock;

  /// Motion is reduced: no clock, no sweeping, no drift.
  bool get still => _still;

  bool get _moving => playing && _visible && !_still;

  /// Starts the show (sweeping the first slide in, a moment after the page
  /// arrives), or stills it or sets it going when [still] changes.
  void setStill(bool still) {
    if (_started && still == _still) return;
    final first = !_started;
    _started = true;
    _still = still;
    playing = !still;
    if (first) {
      _show(0, delay: still ? null : const Duration(milliseconds: 250));
      return;
    }
    if (still) {
      _intro?.cancel();
      _pause();
      if (layers.isNotEmpty) layers.last.reveal.value = 1;
    } else {
      _resume();
    }
    notifyListeners();
  }

  /// Rests the show while the top is out of sight.
  void setVisible(bool visible) {
    if (visible == _visible) return;
    _visible = visible;
    visible ? _resume() : _pause();
  }

  void go(int slide) {
    if (slide == index && layers.isNotEmpty) return;
    _show(slide);
  }

  void next() => go((index + 1) % _slides.length);
  void previous() => go((index - 1 + _slides.length) % _slides.length);

  /// Pause, or Play (from the start of a round when it had rested).
  void toggle() {
    if (_still) return;
    playing = !playing;
    if (playing) {
      if (_advances >= _slides.length * rounds) _advances = 0;
      _resume();
    } else {
      _pause();
    }
    notifyListeners();
  }

  /// Puts [slide] on top, to sweep in over the one showing.
  void _show(int slide, {Duration? delay}) {
    index = slide;
    final layer = _SlideLayer(
      serial: _serial++,
      slide: _slides[slide],
      reveal: AnimationController(vsync: _vsync, duration: sweep),
      life: AnimationController(vsync: _vsync, duration: dwell + sweep),
    );
    layer.reveal.addStatusListener((status) {
      if (status == AnimationStatus.completed) _settled(layer);
    });
    layers.add(layer);
    _clock.value = 0;
    if (_still) {
      layer.reveal.value = 1;
    } else if (delay != null) {
      _intro = Timer(delay, () => _begin(layer));
    } else {
      _begin(layer);
    }
    notifyListeners();
  }

  void _begin(_SlideLayer layer) {
    if (_still) return;
    layer.reveal.forward();
    if (_moving) {
      layer.life.forward();
      _clock.forward();
    }
  }

  /// [layer] covers the stage: the photos under it go.
  void _settled(_SlideLayer layer) {
    final at = layers.indexOf(layer);
    if (at <= 0) return;
    final gone = layers.sublist(0, at);
    layers.removeRange(0, at);
    for (final old in gone) {
      old.stop();
    }
    notifyListeners();
    // Once the stage has rebuilt without them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final old in gone) {
        old.dispose();
      }
    });
  }

  void _advance() {
    _advances++;
    if (_advances >= _slides.length * rounds) playing = false;
    _show((index + 1) % _slides.length);
  }

  void _pause() {
    _clock.stop();
    for (final layer in layers) {
      layer.life.stop();
    }
  }

  void _resume() {
    if (!_moving) return;
    for (final layer in layers) {
      if (layer.reveal.value > 0 && !layer.life.isCompleted) layer.life.forward();
    }
    if (layers.isNotEmpty && layers.last.reveal.value > 0) _clock.forward();
  }

  @override
  void dispose() {
    _intro?.cancel();
    _clock.dispose();
    for (final layer in layers) {
      layer.dispose();
    }
    super.dispose();
  }
}

/// The slide show's photos, filling their space: each new one sweeps in
/// from the right behind a navy and an orange band (the page's stripes),
/// pushing the one under it aside and into shade, then draws slowly closer
/// while it shows.
class _SlideStage extends StatelessWidget {
  final _SlideShow show;

  const _SlideStage({required this.show});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: show,
        builder: (context, _) {
          final layers = show.layers;
          return Stack(
            fit: StackFit.expand,
            children: [
              for (var i = 0; i < layers.length; i++)
                _SlideLayerView(
                  key: ValueKey(layers[i].serial),
                  layer: layers[i],
                  cover: i + 1 < layers.length ? layers[i + 1].reveal : null,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SlideLayerView extends StatelessWidget {
  final _SlideLayer layer;

  /// The next photo sweeping in over this one, if any.
  final Animation<double>? cover;

  const _SlideLayerView({super.key, required this.layer, this.cover});

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    final over = cover;
    final photo = GymPhoto(layer.slide.photo, alignment: layer.slide.alignment);
    return LayoutBuilder(
      builder: (context, box) => AnimatedBuilder(
        animation: Listenable.merge([layer.reveal, layer.life, if (over != null) over]),
        child: photo,
        builder: (context, photo) {
          final shown = still ? 1.0 : Motion.easeInOut.transform(layer.reveal.value);
          final covered = still || over == null ? 0.0 : Motion.easeInOut.transform(over.value);
          // It slides in a little as it sweeps, and aside as the next one
          // does; a hair larger than its space, so the slide never shows an
          // edge.
          final dx = box.maxWidth * (0.04 * (1 - shown) - 0.03 * covered);
          final image = still
              ? photo!
              : Transform.translate(
                  offset: Offset(dx, 0),
                  child: Transform.scale(
                    scale: 1.04,
                    child: Transform.scale(
                      scale: 1 + 0.05 * layer.life.value,
                      alignment: layer.slide.focus,
                      child: photo,
                    ),
                  ),
                );
          return Stack(
            fit: StackFit.expand,
            children: [
              ClipPath(
                clipper: _SweepClipper(shown),
                clipBehavior: shown >= 1 ? Clip.none : Clip.antiAlias,
                child: image,
              ),
              if (covered > 0) IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: 0.3 * covered))),
              if (shown > 0 && shown < 1) IgnorePointer(child: CustomPaint(painter: _SweepBandsPainter(shown, context.brand.highlight))),
            ],
          );
        },
      ),
    );
  }
}

/// Where a sweeping photo's edge is, [shown] of the way across [size]: its
/// top and its foot, leaning like the page's stripes. Off to the right at
/// 0, off to the left (bands and all) at 1.
(double, double) _sweepEdge(Size size, double shown) {
  final slant = size.height * 0.45;
  const bands = _SweepBandsPainter.width;
  final top = (size.width + slant + bands) * (1 - shown) - bands * shown;
  return (top, top - slant);
}

/// The part of the stage a sweeping photo has covered.
class _SweepClipper extends CustomClipper<Path> {
  final double shown;

  const _SweepClipper(this.shown);

  @override
  Path getClip(Size size) {
    if (shown >= 1) return Path()..addRect(Offset.zero & size);
    final (top, foot) = _sweepEdge(size, shown);
    final right = top > size.width ? top : size.width;
    return Path()
      ..moveTo(top, 0)
      ..lineTo(right, 0)
      ..lineTo(right, size.height)
      ..lineTo(foot, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_SweepClipper oldClipper) => oldClipper.shown != shown;
}

/// The navy and orange bands leading a sweeping photo's edge.
class _SweepBandsPainter extends CustomPainter {
  static const orange = 12.0;
  static const navy = 30.0;
  static const width = orange + navy;

  final double shown;

  /// The orange band: the brand's, or the colour they picked.
  final Color color;

  const _SweepBandsPainter(this.shown, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final (top, foot) = _sweepEdge(size, shown);
    final h = size.height;
    // From and to, leftward of the edge.
    Path band(double from, double to) => Path()
      ..moveTo(top - to, 0)
      ..lineTo(top - from, 0)
      ..lineTo(foot - from, h)
      ..lineTo(foot - to, h)
      ..close();
    canvas.drawPath(band(orange, width), Paint()..color = BrandColors.navy.withValues(alpha: 0.92));
    // A pixel over the photo's edge, so no seam shows between.
    canvas.drawPath(band(-1, orange), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SweepBandsPainter oldDelegate) => oldDelegate.shown != shown || oldDelegate.color != color;
}

/// Which slide is showing and the way between them, on polished glass under
/// the photos: its number and name set like a scoreboard, a slim track whose
/// segment for the slide showing stretches out (tap one to see that slide),
/// the slide before and after, and beside them Pause, ringed by the time
/// the slide has left. A gleam crosses the glass as each slide arrives. Over
/// the photo's top on a phone ([compact]), where a swipe moves between them.
class _SlideControls extends StatelessWidget {
  final _SlideShow show;
  final bool compact;

  const _SlideControls({required this.show, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: show,
      builder: (context, _) => compact ? _compact(context) : _panel(context),
    );
  }

  Widget _panel(BuildContext context) {
    final panel = _Glass(
      radius: 30,
      gleam: show.index,
      child: SizedBox(
        height: 60,
        child: LayoutBuilder(
          builder: (context, box) {
            // The track needs room; in a narrow window the name takes it.
            final roomy = box.maxWidth >= 420;
            return Row(
              children: [
                const SizedBox(width: 24),
                _SlideNumber(index: show.index),
                const _FadedRule(height: 30),
                if (roomy) ...[
                  SizedBox(width: 112, child: _SlideName(index: show.index)),
                  const SizedBox(width: 4),
                  Expanded(child: _SlideTrack(show: show)),
                  const SizedBox(width: 18),
                ] else ...[
                  Expanded(child: _SlideName(index: show.index)),
                  const SizedBox(width: 10),
                ],
                _arrow(context, Icons.arrow_back_rounded, 'Previous slide', show.previous),
                const SizedBox(width: 6),
                _arrow(context, Icons.arrow_forward_rounded, 'Next slide', show.next),
                const SizedBox(width: 10),
              ],
            );
          },
        ),
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Row(
        children: [
          Expanded(child: panel),
          if (!show.still) ...[const SizedBox(width: 12), _pause(context, size: 60, onPhoto: false)],
        ],
      ),
    );
  }

  Widget _compact(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SlideTrack(show: show, onPhoto: true),
        Row(
          children: [
            _SlideNumber(index: show.index, onPhoto: true),
            const _FadedRule(height: 22, onPhoto: true, gap: 12),
            Expanded(child: _SlideName(index: show.index, onPhoto: true)),
            if (!show.still) _pause(context, size: 40, onPhoto: true),
          ],
        ),
      ],
    );
  }

  /// A faint hairline circle that warms to orange under the mouse.
  Widget _arrow(BuildContext context, IconData icon, String tooltip, VoidCallback onPressed) {
    final ink = _Ink.of(context);
    final hairline = ink.pick(LightColors.navy.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.16));
    final rest = ink.heading.withValues(alpha: 0.78);
    bool lit(Set<WidgetState> states) => states.contains(WidgetState.hovered) || states.contains(WidgetState.focused);
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll(Size.square(40)),
        minimumSize: const WidgetStatePropertyAll(Size.square(40)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: const WidgetStatePropertyAll(CircleBorder()),
        side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(color: lit(states) ? context.brand.highlight.withValues(alpha: 0.7) : hairline)),
        foregroundColor: WidgetStateProperty.resolveWith((states) => lit(states) ? context.brand.highlight : rest),
        backgroundColor: WidgetStateProperty.resolveWith((states) => lit(states)
            ? context.brand.highlight.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: ink.dark ? 0.04 : 0.35)),
        overlayColor: WidgetStatePropertyAll(context.brand.highlight.withValues(alpha: 0.1)),
      ),
    );
  }

  /// Pause (or Play) on its own glass, ringed by how much of the showing
  /// slide's time has gone.
  Widget _pause(BuildContext context, {required double size, required bool onPhoto}) {
    final ink = _Ink.of(context);
    final face = Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.all(onPhoto ? 3 : 5),
            child: AnimatedBuilder(
              animation: show.progress,
              builder: (context, _) => CustomPaint(
                painter: _RingPainter(
                  value: show.progress.value,
                  color: context.brand.highlight,
                  soft: context.brand.themedShade(_peach),
                  track: onPhoto
                      ? Colors.white.withValues(alpha: 0.28)
                      : ink.pick(LightColors.navy.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.12)),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: show.toggle,
          tooltip: show.playing ? 'Pause the slides' : 'Play the slides',
          icon: Icon(show.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: size * 0.38),
          style: IconButton.styleFrom(
            foregroundColor: onPhoto ? Colors.white : ink.heading.withValues(alpha: 0.85),
            hoverColor: context.brand.highlight.withValues(alpha: 0.1),
            fixedSize: Size.square(size),
            minimumSize: Size.square(size),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
    return _Glass(
      radius: size / 2,
      onPhoto: onPhoto,
      gleam: show.index,
      gleamDelay: const Duration(milliseconds: 260),
      child: face,
    );
  }
}

/// The track's and the ring's orange: full where it leads, fading to peach
/// behind.
const _peach = Color(0xFFFFC29B);

/// Polished glass: what's behind it blurred under a soft, see-through wash
/// (deep navy in the dark; clear over a photo), light pooled on its upper
/// half, a rim catching the light along its top, and a soft, wide shadow.
/// When [gleam] changes a streak of light crosses it.
class _Glass extends StatelessWidget {
  final double radius;
  final Widget child;

  /// Over a photo: clearer, with a brighter rim.
  final bool onPhoto;

  /// What sends a gleam across it when it changes; none when null.
  final Object? gleam;
  final Duration gleamDelay;

  const _Glass({
    required this.radius,
    required this.child,
    this.onPhoto = false,
    this.gleam,
    this.gleamDelay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final corners = BorderRadius.circular(radius);
    // An amount for light or dark, mixed while the theme switches.
    double mix(double light, double dark) => light + (dark - light) * ink.t;
    final (List<Color> wash, double sheen, Color rimTop, Color rimFoot, double shine) = onPhoto
        ? (
            [Colors.white.withValues(alpha: 0.24), Colors.white.withValues(alpha: 0.06)],
            0.32,
            Colors.white.withValues(alpha: 0.75),
            Colors.white.withValues(alpha: 0.08),
            0.45,
          )
        : (
            [
              ink.pick(Colors.white.withValues(alpha: 0.72), const Color(0xB31E2D4F)),
              ink.pick(Colors.white.withValues(alpha: 0.48), const Color(0x990B1630)),
            ],
            mix(0.8, 0.12),
            Colors.white.withValues(alpha: mix(1, 0.4)),
            Colors.white.withValues(alpha: mix(0.3, 0.05)),
            mix(0.7, 0.18),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        boxShadow: [
          BoxShadow(
            color: onPhoto
                ? Colors.black.withValues(alpha: 0.18)
                : ink.pick(LightColors.navy.withValues(alpha: 0.13), Colors.black.withValues(alpha: 0.42)),
            blurRadius: onPhoto ? 18 : 44,
            spreadRadius: -8,
            offset: Offset(0, onPhoto ? 8 : 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: corners,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: CustomPaint(
            foregroundPainter: _RimPainter(radius: radius, top: rimTop, foot: rimFoot),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: wash),
              ),
              child: Stack(
                children: [
                  // Light pooled on the upper half, as on polished glass.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.white.withValues(alpha: sheen), Colors.white.withValues(alpha: 0)],
                            stops: const [0, 0.55],
                          ),
                        ),
                      ),
                    ),
                  ),
                  child,
                  if (gleam != null)
                    Positioned.fill(
                      child: _Gleam(trigger: gleam!, delay: gleamDelay, color: Colors.white.withValues(alpha: shine)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The glass's rim: bright along the top where it catches the light,
/// fading away toward the foot.
class _RimPainter extends CustomPainter {
  final double radius;
  final Color top;
  final Color foot;

  const _RimPainter({required this.radius, required this.top, required this.foot});

  @override
  void paint(Canvas canvas, Size size) {
    const width = 1.2;
    final rim = RRect.fromRectAndRadius((Offset.zero & size).deflate(width / 2), Radius.circular(radius - width / 2));
    canvas.drawRRect(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, foot],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_RimPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.top != top || oldDelegate.foot != foot;
}

/// A streak of light that crosses once, leaning like the stripes: when it
/// first shows (a moment after the glass arrives) and each time [trigger]
/// changes. Nothing when motion is reduced.
class _Gleam extends StatefulWidget {
  final Object trigger;
  final Duration delay;
  final Color color;

  const _Gleam({required this.trigger, required this.color, this.delay = Duration.zero});

  @override
  State<_Gleam> createState() => _GleamState();
}

class _GleamState extends State<_Gleam> with SingleTickerProviderStateMixin {
  static const _cross = Duration(milliseconds: 1100);

  late final AnimationController _c = AnimationController(vsync: this, duration: widget.delay + _cross);
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(widget.delay.inMilliseconds / (widget.delay + _cross).inMilliseconds, 1, curve: Motion.easeInOut),
  );
  Timer? _first;

  @override
  void initState() {
    super.initState();
    // After the glass has risen into place.
    _first = Timer(const Duration(milliseconds: 1400), _shine);
  }

  @override
  void didUpdateWidget(_Gleam old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _shine();
  }

  void _shine() {
    if (!mounted || reduceMotion(context)) return;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _first?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) => CustomPaint(painter: _GleamPainter(t: _t.value, color: widget.color)),
      ),
    );
  }
}

class _GleamPainter extends CustomPainter {
  final double t;
  final Color color;

  const _GleamPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final h = size.height;
    final band = math.max(44.0, size.width * 0.14);
    final lean = h * 0.7;
    // From wholly off the left to wholly off the right.
    final left = -band - lean + (size.width + band + lean) * t;
    final streak = Path()
      ..moveTo(left + lean, 0)
      ..lineTo(left + lean + band, 0)
      ..lineTo(left + band, h)
      ..lineTo(left, h)
      ..close();
    canvas.drawPath(
      streak,
      Paint()
        ..shader = LinearGradient(colors: [color.withValues(alpha: 0), color, color.withValues(alpha: 0)])
            .createShader(Rect.fromLTWH(left, 0, band + lean, h)),
    );
  }

  @override
  bool shouldRepaint(_GleamPainter oldDelegate) => oldDelegate.t != t || oldDelegate.color != color;
}

/// A thin upright rule that fades away at both ends.
class _FadedRule extends StatelessWidget {
  final double height;
  final double gap;

  /// White over a photo, rather than on the glass.
  final bool onPhoto;

  const _FadedRule({required this.height, this.gap = 16, this.onPhoto = false});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final line = onPhoto
        ? Colors.white.withValues(alpha: 0.55)
        : ink.pick(LightColors.navy.withValues(alpha: 0.2), Colors.white.withValues(alpha: 0.24));
    return Container(
      width: 1,
      height: height,
      margin: EdgeInsets.symmetric(horizontal: gap),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line.withValues(alpha: 0), line, line.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

/// A thin ring, filled clockwise from the top by [value]: orange at its
/// head, fading to peach behind.
class _RingPainter extends CustomPainter {
  static const stroke = 2.0;

  final double value;
  final Color track;

  /// The brand's orange or the colour they picked, from [soft] round to [color].
  final Color color;
  final Color soft;

  const _RingPainter({required this.value, required this.track, required this.color, required this.soft});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawOval(rect, line..color = track);
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * value,
      false,
      // Its own paint: the track's faint colour would dim the gradient.
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [soft, color],
          stops: [0, value.clamp(0.01, 1.0)],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.track != track || oldDelegate.color != color || oldDelegate.soft != soft;
}

/// The showing slide's number, large and slanted like the headline and
/// fading downward, out of how many, small: "02 /06". The number rolls over
/// as the slide changes.
class _SlideNumber extends StatelessWidget {
  final int index;

  /// White over a photo, rather than on the glass.
  final bool onPhoto;

  const _SlideNumber({required this.index, this.onPhoto = false});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    String two(int n) => n.toString().padLeft(2, '0');
    final ink0 = onPhoto ? Colors.white : ink.heading;
    final fade = [ink0, ink0.withValues(alpha: onPhoto ? 0.6 : 0.38)];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        _Roll(
          index: index,
          child: ShaderMask(
            key: ValueKey(index),
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: fade,
            ).createShader(bounds),
            // Room for the slant: an italic figure leans past its own box
            // at the top right, where the roll's clip and the fade would
            // cut it off.
            child: Padding(
              padding: EdgeInsets.only(right: onPhoto ? 5 : 7),
              child: Text(
                two(index + 1),
                style: TextStyle(
                  fontSize: onPhoto ? 22 : 28,
                  fontWeight: FontWeight.w800,
                  fontStyle: FontStyle.italic,
                  letterSpacing: -0.6,
                  height: 1.1,
                  color: Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
        Text(
          '/${two(_slides.length)}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: onPhoto ? Colors.white.withValues(alpha: 0.7) : context.brand.muted.withValues(alpha: 0.8),
            fontFeatures: const [FontFeature.tabularFigures()],
            shadows: onPhoto ? const [Shadow(color: Color(0x80000000), blurRadius: 10)] : null,
          ),
        ),
      ],
    );
  }
}

/// The showing slide's name in spaced capitals, rolling over as it changes.
class _SlideName extends StatelessWidget {
  final int index;

  /// White over a photo, rather than on the glass.
  final bool onPhoto;

  const _SlideName({required this.index, this.onPhoto = false});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    return _Roll(
      index: index,
      duration: const Duration(milliseconds: 720),
      child: Text(
        _slides[index].name.toUpperCase(),
        key: ValueKey(index),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: onPhoto ? 12 : 12.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.8,
          height: 1.2,
          color: onPhoto ? Colors.white : ink.heading.withValues(alpha: 0.82),
          shadows: onPhoto ? const [Shadow(color: Color(0x80000000), blurRadius: 10)] : null,
        ),
      ),
    );
  }
}

/// [child] (keyed by [index]) rolls up into place as the one before slips
/// away upward, gone by halfway so the two never show at once; at once when
/// motion is reduced.
class _Roll extends StatelessWidget {
  final int index;
  final Duration duration;
  final Widget child;

  const _Roll({required this.index, required this.child, this.duration = const Duration(milliseconds: 640)});

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    return AnimatedSwitcher(
      duration: duration,
      // A new builder each time, so the one leaving goes up, not back down.
      transitionBuilder: (child, animation) {
        final entering = child.key == ValueKey(index);
        final rise = Tween(begin: Offset(0, entering ? 0.9 : -0.9), end: Offset.zero)
            .chain(CurveTween(curve: Motion.ease));
        return ClipRect(
          child: SlideTransition(
            position: animation.drive(rise),
            child: FadeTransition(opacity: animation.drive(CurveTween(curve: const Interval(0.5, 1))), child: child),
          ),
        );
      },
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, if (current != null) current],
      ),
      child: child,
    );
  }
}

/// A slim track, a segment for each slide: the one showing stretches out,
/// glowing orange fading to peach, as the others draw in; tap a segment to
/// see that slide.
class _SlideTrack extends StatelessWidget {
  final _SlideShow show;

  /// Over a photo, rather than on the glass.
  final bool onPhoto;

  const _SlideTrack({required this.show, this.onPhoto = false});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final rest = onPhoto
        ? Colors.white.withValues(alpha: 0.38)
        : ink.pick(LightColors.navy.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.16));
    final duration = Motion.of(context, const Duration(milliseconds: 520));
    const gap = 4.0;
    return LayoutBuilder(
      builder: (context, box) {
        // The one showing is three shares wide, the rest one each.
        final share = ((box.maxWidth - gap * (_slides.length - 1)) / (_slides.length + 2)).clamp(0.0, 400.0);
        return Row(
          children: [
            for (var i = 0; i < _slides.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              Semantics(
                button: true,
                selected: i == show.index,
                label: 'Show ${_slides[i].name}, ${i + 1} of ${_slides.length}',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => show.go(i),
                    child: AnimatedContainer(
                      duration: duration,
                      curve: Motion.ease,
                      width: share * (i == show.index ? 3 : 1),
                      height: 28,
                      alignment: Alignment.center,
                      child: AnimatedContainer(
                        duration: duration,
                        curve: Motion.ease,
                        height: i == show.index ? 3 : 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: i == show.index ? [context.brand.themedShade(_peach), context.brand.highlight] : [rest, rest],
                          ),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: context.brand.highlight.withValues(alpha: i == show.index ? 0.35 : 0),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The top's foot: low on the left, rising to the right.
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..lineTo(0, h - 36)
      ..cubicTo(w * 0.28, h + 8, w * 0.58, h - 96, w, h - 70)
      ..lineTo(w, 0)
      ..close();
  }

  @override
  bool shouldReclip(_WaveClipper oldClipper) => false;
}

/// How far the photos' edge leans across its foot, for the height of the top.
const _slant = 0.24;

/// The photos' side of the top: its left edge leans like the page's stripes.
class _SlantClipper extends CustomClipper<Path> {
  const _SlantClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.height * _slant, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_SlantClipper oldClipper) => false;
}

/// A slim rule of the brand's orange along the photos' slanted edge.
class _SlantRulePainter extends CustomPainter {
  final Color color;

  const _SlantRulePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(size.height * _slant, 0),
      Offset(0, size.height),
      Paint()
        ..color = color
        ..strokeWidth = 4
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_SlantRulePainter oldDelegate) => oldDelegate.color != color;
}

/// A quiet colour grade over the top's photos: navy settling in from the
/// foot and the left, so each slide sits in the brand's colours and the
/// cards and the way between them read over any photo.
class _PhotoGrade extends StatelessWidget {
  const _PhotoGrade();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0x99081428), Color(0x33081428), Color(0x00081428)],
              stops: [0, 0.35, 0.65],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0x4D081428), Color(0x00081428)],
              stops: [0, 0.45],
            ),
          ),
        ),
      ],
    );
  }
}

/// The top's eyebrow: what Health Pro is in small capitals on a slim glass
/// pill, after a dot of the brand's orange.
class _HeroBadge extends StatelessWidget {
  final String text;

  const _HeroBadge(this.text);

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final dot = context.brand.highlight;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 16, 7),
      decoration: BoxDecoration(
        color: ink.pick(Colors.white.withValues(alpha: 0.8), Colors.white.withValues(alpha: 0.06)),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.brand.glassBorder),
        boxShadow: ink.dark ? null : ink.shadow(light: 0.06, blur: 18, dy: 6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Pulse(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: dot.withValues(alpha: 0.28), spreadRadius: 3)],
              ),
            ),
          ),
          const SizedBox(width: 11),
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: ink.heading),
            ),
          ),
        ],
      ),
    );
  }
}

/// An illustrative member card; its sample QR is not a real member credential.
/// Set like a premium card: deep navy with a soft sheen and a warm light in
/// its corner.
class _MiniCard extends StatelessWidget {
  const _MiniCard();

  @override
  Widget build(BuildContext context) {
    final glow = context.brand.highlight;
    return ExcludeSemantics(
      child: Container(
        width: 344,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Color(0xFA0B1530), Color(0xFA1B3F8A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: const [BoxShadow(color: Color(0x590B1530), blurRadius: 44, spreadRadius: -6, offset: Offset(0, 24))],
        ),
        child: Stack(
          children: [
            Positioned(left: -70, bottom: -110, child: GymGlow(color: glow.withValues(alpha: 0.3), size: 240)),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white.withValues(alpha: 0.1), Colors.white.withValues(alpha: 0)],
                    stops: const [0, 0.5],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'HEALTH PRO',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.8,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                              ),
                              child: const Text(
                                'Sample',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Example member card',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                        ),
                        const SizedBox(height: 2),
                        Text('Gym membership', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12.5)),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Icon(Icons.qr_code_2_rounded, color: glow, size: 18),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                'QR check-in preview',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: QrImageView(
                      data: 'EXAMPLE ONLY',
                      size: 80,
                      padding: EdgeInsets.zero,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: BrandColors.navy),
                      dataModuleStyle:
                          const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: BrandColors.navy),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small card floating over the photo.
class _FloatingNote extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String text;

  const _FloatingNote({required this.icon, required this.iconColor, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
        decoration: BoxDecoration(
          color: ink.dark ? const Color(0xF216213C) : const Color(0xF7FFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.brand.glassBorder),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: ink.dark ? 0.4 : 0.18),
                blurRadius: 28,
                offset: const Offset(0, 12)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: ink.heading)),
                Text(text, style: TextStyle(fontSize: 12, color: context.brand.muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades [child] up into place the first time it scrolls into view (at
/// once with Reduce motion on).
class _Reveal extends StatefulWidget {
  final Widget child;

  const _Reveal({required this.child});

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> {
  bool _shown = false;
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _shown = true;
      return;
    }
    _position?.removeListener(_check);
    _position = Scrollable.maybeOf(context)?.position;
    _position?.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (_shown || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    if (box.localToGlobal(Offset.zero).dy < MediaQuery.sizeOf(context).height * 0.92) {
      _position?.removeListener(_check);
      setState(() => _shown = true);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    super.dispose();
  }

  /// How far below its place a section waits to rise.
  static const rise = 28.0;

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 750);
    return _Revealed(
      shown: _shown,
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: duration,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, _shown ? 0 : rise, 0),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Whether the section around has scrolled into view, for what's in it.
class _Revealed extends InheritedWidget {
  final bool shown;

  const _Revealed({required this.shown, required super.child});

  /// Shown, or not in a section that waits (it shows at once).
  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_Revealed>()?.shown ?? true;

  @override
  bool updateShouldNotify(_Revealed old) => old.shown != shown;
}

/// The page's beat. On every one the lights on the page (what it does, how
/// it works) move on together, and what they set moving is still again
/// within [settle], so the page rests a moment before the next. It counts
/// nothing with Reduce motion on.
class _Beat extends InheritedNotifier<ValueNotifier<int>> {
  /// Starts the beat again from now.
  final VoidCallback restart;

  const _Beat({required ValueNotifier<int> beats, required this.restart, required super.child}) : super(notifier: beats);

  static const interval = Duration(seconds: 2);

  /// How long what moves on a beat may take.
  static const settle = Duration(milliseconds: 1600);

  /// The beats so far, from 0.
  static int of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_Beat>()?.notifier?.value ?? 0;

  /// The beats so far, without listening for more (in a tap, say).
  static int peek(BuildContext context) => context.getInheritedWidgetOfExactType<_Beat>()?.notifier?.value ?? 0;

  /// Starts the page's beat again from now, as when someone picks a step.
  static void restartOf(BuildContext context) => context.getInheritedWidgetOfExactType<_Beat>()?.restart();
}

/// One of a section's cards: it rises into place [order] beats after the
/// section comes into view, so a row of cards arrives one after another
/// (bhutanesports.org's fade-in-up, a fifth of a second apart).
class _RevealItem extends StatefulWidget {
  final int order;
  final Widget child;

  const _RevealItem({required this.order, required this.child});

  @override
  State<_RevealItem> createState() => _RevealItemState();
}

class _RevealItemState extends State<_RevealItem> with SingleTickerProviderStateMixin {
  static const _beat = Duration(milliseconds: 200);
  late final Duration _delay = _beat * widget.order.clamp(0, 8) + const Duration(milliseconds: 150);
  late final AnimationController _c = AnimationController(vsync: this, duration: _delay + Motion.card);
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(_delay.inMilliseconds / (_delay + Motion.card).inMilliseconds, 1, curve: Motion.ease),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.value = 1;
    } else if (_Revealed.of(context) && !_c.isAnimating && !_c.isCompleted) {
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
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(offset: Offset(0, 40 * (1 - _t.value)), child: child),
      ),
    );
  }
}

// ─── Services ──────────────────────────────────────────────────────────────

/// What are you looking for (the user's layout, under the top): every kind
/// of service the team has set up in Service types (Gym, Swimming,
/// Massage...), each with how many places there are in the area the top
/// shows (all told when none). Each opens its places in Find services, in
/// that area.
class _ServiceTypes extends ConsumerWidget {
  final _Layout layout;
  final List<ModuleMenuItem> serviceLinks;
  final VoidCallback onFindGym;

  const _ServiceTypes({super.key, required this.layout, required this.serviceLinks, required this.onFindGym});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = _Ink.of(context);
    final venues = ref.watch(moduleVenuesProvider(gymModuleKey)).valueOrNull ?? const <Venue>[];
    final master = ref.watch(venueTypesProvider).valueOrNull ?? const <VenueType>[];
    final area = ref.watch(_shownAreaProvider);
    final count = <String, int>{};
    final total = <String, int>{};
    for (final v in venues) {
      total[v.type] = (total[v.type] ?? 0) + 1;
      if (area == null || _inArea(area, v)) count[v.type] = (count[v.type] ?? 0) + 1;
    }
    // In the team's order; one with none yet only when they show it (Coming soon).
    final types = [
      for (final t in findableTypes(master, venues))
        if (t.showWhenEmpty || (total[t.key] ?? 0) > 0) t,
    ];
    final title = TextStyle(
      fontSize: layout.titleSize,
      fontWeight: FontWeight.w800,
      height: 1.08,
      letterSpacing: -layout.titleSize * 0.03,
      color: ink.heading,
    );
    final buttons = Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        _PillButton(label: 'All services', icon: Icons.arrow_forward_rounded, onPressed: onFindGym),
        for (final link in serviceLinks)
          _PillButton(label: link.title, icon: link.icon, outlined: true, onPressed: () => link.open(context)),
      ],
    );
    // What Health Pro has, counted up as it comes into view: real numbers only.
    String counted(int n, String one, String many) => n == 1 ? one : many;
    final dzongkhagCount = {for (final v in venues) v.dzongkhag}.length;
    final counters = [
      _CountUp(value: venues.length, label: counted(venues.length, 'Place', 'Places'), layout: layout),
      _CountUp(value: total.length, label: counted(total.length, 'Kind of service', 'Kinds of service'), layout: layout),
      _CountUp(value: dzongkhagCount, label: counted(dzongkhagCount, 'Dzongkhag', 'Dzongkhags'), layout: layout),
    ];
    // Side by side with a fine rule between them; wrapping on a phone.
    final stats = venues.isEmpty
        ? null
        : layout.medium
            ? IntrinsicHeight(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, counter) in counters.indexed) ...[
                      if (i > 0)
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: layout.wide ? 30 : 22),
                          child: VerticalDivider(width: 1, thickness: 1, color: context.brand.glassBorder),
                        ),
                      counter,
                    ],
                  ],
                ),
              )
            : Wrap(spacing: 30, runSpacing: 16, children: counters);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow('OUR SERVICES', lineBefore: true),
        const SizedBox(height: 16),
        Text('What are you', style: title),
        _AccentText('looking for?', style: title),
      ],
    );
    void open(VenueType type) {
      // The area they were shown, kept for the list.
      if (area != null) ref.read(servicesAreaProvider.notifier).state = area;
      context.push('${GymRoutes.gyms}?type=${Uri.encodeQueryComponent(type.key)}');
    }

    return Padding(
      padding: EdgeInsets.only(top: layout.section * 0.5, bottom: layout.section),
      child: _Frame(
        layout: layout,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (layout.medium)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [Expanded(child: heading), if (stats != null) ...[const SizedBox(width: 24), stats]],
              )
            else ...[
              heading,
              if (stats != null) ...[const SizedBox(height: 24), stats],
            ],
            const SizedBox(height: 32),
            if (types.isEmpty)
              Text('Services open soon.', style: TextStyle(fontSize: 16, color: ink.body))
            else
              ResponsiveGrid(
                minItemWidth: 230,
                maxColumns: 4,
                spacing: 18,
                runSpacing: 18,
                children: [
                  for (final (i, t) in types.indexed)
                    _RevealItem(
                      order: i,
                      child: _ServiceCard(
                        number: i + 1,
                        type: t,
                        none: (count[t.key] ?? 0) == 0,
                        countText: serviceCountText(
                          count: count[t.key] ?? 0,
                          total: total[t.key] ?? 0,
                          inArea: area == null ? null : (area.town ?? area.dzongkhag),
                        ),
                        onTap: () => open(t),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 36),
            Center(child: buttons),
          ],
        ),
      ),
    );
  }
}

/// One kind of service under What are you looking for, numbered in the
/// team's order (01, 02...): a panel tinted its colour with its number drawn
/// as a fine outline and its icon's 3D picture (or the photo the team set),
/// floating up and back on the page's beat in a wave along each row; then
/// its name, what it is, and how many places there are. Under the pointer the
/// card lifts, its number fills in, the picture rises and the arrow fills.
/// Still with Reduce motion.
class _ServiceCard extends StatefulWidget {
  final int number;
  final VenueType type;
  final String countText;

  /// None in the area shown (the count is greyed).
  final bool none;
  final VoidCallback onTap;

  const _ServiceCard({required this.number, required this.type, required this.countText, required this.none, required this.onTap});

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(vsync: this, duration: _Beat.settle);

  /// Up and back once, a little later for each card along a row of four.
  late final Animation<double> _lift = CurvedAnimation(
    parent: _float,
    curve: Interval((widget.number - 1) % 4 * 0.08, (widget.number - 1) % 4 * 0.08 + 0.75, curve: Curves.easeInOut),
  );
  int? _beat;
  bool _hover = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final beat = _Beat.of(context);
    if (reduceMotion(context)) {
      _float.value = 0;
    } else if (beat != _beat) {
      _beat = beat;
      _float.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final brand = context.brand;
    final accent = widget.type.colorOr(context.colors.primary);
    final photo = widget.type.photo;
    final hover = _hover && !reduceMotion(context);
    final duration = Motion.of(context, Motion.card);
    final line = brand.glassBorder;
    return AnimatedContainer(
      duration: duration,
      curve: Motion.ease,
      transform: Matrix4.translationValues(0, hover ? -6 : 0, 0),
      decoration: BoxDecoration(
        color: ink.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: hover ? accent.withValues(alpha: 0.45) : line),
        boxShadow: hover ? ink.shadow(light: 0.14, blur: 36, dy: 18) : ink.shadow(light: 0.06, blur: 20, dy: 8),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: widget.onTap,
          onHover: (h) => setState(() => _hover = h),
          // Its own lift shows the pointer; no grey wash over it.
          hoverColor: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _panel(ink, accent, photo, hover, duration),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.type.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: ink.heading),
                    ),
                    const SizedBox(height: 6),
                    // Always two lines' room, so the cards in a row line up.
                    ConstrainedBox(
                      constraints: BoxConstraints(minHeight: MediaQuery.textScalerOf(context).scale(13.5) * 1.45 * 2),
                      child: Text(
                        widget.type.description ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, height: 1.45, color: ink.body),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(height: 1, color: line),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.none ? ink.body.withValues(alpha: 0.4) : accent,
                            boxShadow: [
                              if (!widget.none) BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 0, spreadRadius: 3),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.countText,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: widget.none ? ink.body : accent),
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedContainer(
                          duration: duration,
                          curve: Motion.ease,
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hover ? accent : Colors.transparent,
                            border: Border.all(color: hover ? accent : accent.withValues(alpha: 0.3)),
                          ),
                          child: AnimatedRotation(
                            turns: hover ? 0 : -0.125,
                            duration: duration,
                            curve: Motion.ease,
                            child: Icon(Icons.arrow_forward_rounded, size: 18, color: hover ? Colors.white : accent),
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
    );
  }

  /// The tinted panel at the top: the number, and the floating picture (or the photo).
  Widget _panel(_Ink ink, Color accent, String? photo, bool hover, Duration duration) {
    final onPhoto = photo != null;
    final digits = widget.number.toString().padLeft(2, '0');
    final numberStyle = TextStyle(fontSize: 58, fontWeight: FontWeight.w800, height: 1, letterSpacing: -2);
    final numberInk = onPhoto ? Colors.white : accent;
    return Container(
      height: 138,
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: ink.dark ? 0.26 : 0.16),
            accent.withValues(alpha: ink.dark ? 0.08 : 0.04),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (onPhoto) ...[
            AnimatedScale(
              scale: hover ? 1.06 : 1,
              duration: duration,
              curve: Motion.ease,
              child: Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [Color(0x99000000), Color(0x00000000)],
                ),
              ),
            ),
          ] else ...[
            // Two fine rings around where the picture floats.
            for (final (size, alpha) in [(180.0, 0.14), (118.0, 0.2)])
              Positioned(
                right: 58 - size / 2,
                top: 69 - size / 2,
                width: size,
                height: size,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: accent.withValues(alpha: alpha)),
                  ),
                ),
              ),
          ],
          // Its number: a fine outline that fills in under the pointer.
          Positioned(
            left: 16,
            bottom: 14,
            child: ExcludeSemantics(
              child: Stack(
                children: [
                  Text(
                    digits,
                    style: numberStyle.copyWith(
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = 1.3
                        ..color = numberInk.withValues(alpha: onPhoto ? 0.9 : 0.55),
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: hover ? 1 : 0,
                    duration: duration,
                    child: Text(digits, style: numberStyle.copyWith(color: numberInk.withValues(alpha: onPhoto ? 1 : 0.85))),
                  ),
                ],
              ),
            ),
          ),
          if (!onPhoto)
            Positioned(
              right: 14,
              top: 14,
              bottom: 8,
              width: 88,
              child: _art(accent, hover, duration),
            ),
        ],
      ),
    );
  }

  /// The 3D picture over its shadow, rising and turning a little on each
  /// beat (its shadow shrinking), and further under the pointer.
  Widget _art(Color accent, bool hover, Duration duration) {
    final picture = AnimatedSlide(
      offset: Offset(0, hover ? -0.08 : 0),
      duration: duration,
      curve: Motion.ease,
      child: AnimatedScale(
        scale: hover ? 1.1 : 1,
        duration: duration,
        curve: Motion.pop,
        child: Image.asset(
          widget.type.artAsset,
          package: 'health_pro_core',
          width: 84,
          height: 84,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
          errorBuilder: (_, __, ___) =>
              SizedBox.square(dimension: 84, child: Icon(widget.type.iconData, size: 52, color: accent)),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _lift,
      child: picture,
      builder: (context, child) {
        final up = math.sin(math.pi * _lift.value);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.translate(
              offset: Offset(0, -7 * up),
              child: Transform.rotate(angle: -0.05 * up, child: child),
            ),
            const SizedBox(height: 4),
            Transform.scale(
              scaleX: 1 - 0.3 * up,
              child: Container(
                width: 54,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.elliptical(27, 4)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.16 - 0.07 * up), blurRadius: 8, spreadRadius: -1),
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

/// [value] counting up from nought the first time its section comes into
/// view, over its [label] in small capitals (bhutanesports.org's counters).
/// At once with Reduce motion.
class _CountUp extends StatefulWidget {
  final int value;
  final String label;
  final _Layout layout;

  const _CountUp({required this.value, required this.label, required this.layout});

  @override
  State<_CountUp> createState() => _CountUpState();
}

class _CountUpState extends State<_CountUp> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.value = 1;
    } else if (_Revealed.of(context) && !_c.isAnimating && !_c.isCompleted) {
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
    final ink = _Ink.of(context);
    final size = widget.layout.wide ? 46.0 : 38.0;
    final number = TextStyle(fontSize: size, fontWeight: FontWeight.w800, height: 1, letterSpacing: -size * 0.03);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _t,
          builder: (context, _) => _AccentText('${(widget.value * _t.value).round()}', style: number),
        ),
        const SizedBox(height: 8),
        Text(
          widget.label.toUpperCase(),
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: ink.body),
        ),
      ],
    );
  }
}

/// The kinds of service on two ribbons crossing under the top, each tilted a
/// little and running off the page's sides. On the navy one in front, large
/// capitals drawn as fine outlines glide left, and a spotlight in the middle
/// fills each name in (its spark lit orange) as it passes through. On the
/// orange one behind, the same names, small and spaced, glide right. Every
/// name opens its places, as its card does, even while it moves (pointing at
/// a ribbon slows it to a stop, and the name under the pointer fills in).
/// Hidden from screen readers (the cards under it name them all); still with
/// Reduce motion; nothing until the kinds have loaded.
class _ServiceMarquee extends ConsumerWidget {
  final _Layout layout;

  const _ServiceMarquee({required this.layout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venues = ref.watch(moduleVenuesProvider(gymModuleKey)).valueOrNull ?? const <Venue>[];
    final master = ref.watch(venueTypesProvider).valueOrNull ?? const <VenueType>[];
    final kinds = [
      for (final t in findableTypes(master, venues))
        if (t.showWhenEmpty || venues.any((v) => v.type == t.key)) t,
    ];
    if (kinds.isEmpty) return const SizedBox.shrink();
    void open(VenueType type) => context.push('${GymRoutes.gyms}?type=${Uri.encodeQueryComponent(type.key)}');
    final ink = _Ink.of(context);
    final size = layout.wide ? 42.0 : (layout.medium ? 34.0 : 24.0);
    final spark = context.brand.highlight;

    // The front ribbon: deep navy (white in the dark), the names on it fine
    // outlines that fill in under the spotlight.
    final ribbon = ink.pick(LightColors.ink, Colors.white);
    final letters = ink.pick(Colors.white, LightColors.ink);
    final solid = TextStyle(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: size * 0.03, color: letters);
    // Round joins, so the outline has no spikes at the points of A, M and W.
    final outlined = solid.copyWith(
      color: null,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, size * 0.024)
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = letters.withValues(alpha: 0.45),
    );
    // Each a name and the spark after it; outlined (filled in while pointed at), or filled in. Both the same width.
    // The lit ones are only seen: the pointer reaches the outlined ones under them.
    Widget name(VenueType t, {required bool lit, bool hover = false}) {
      final label = t.name.toUpperCase();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          lit
              ? Text(label, maxLines: 1, style: solid)
              : Stack(children: [
                  Text(label, maxLines: 1, style: outlined),
                  AnimatedOpacity(
                    opacity: hover ? 1 : 0,
                    duration: Motion.of(context, Motion.hover),
                    curve: Motion.ease,
                    child: Text(label, maxLines: 1, style: solid),
                  ),
                ]),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size * 0.6),
            child: Icon(Icons.auto_awesome_rounded, size: size * 0.5, color: lit || hover ? spark : letters.withValues(alpha: 0.3)),
          ),
        ],
      );
    }

    List<Widget> names({required bool lit}) => [
          for (final t in kinds)
            lit
                ? name(t, lit: true)
                : _RibbonLink(onTap: () => open(t), builder: (hover) => name(t, lit: false, hover: hover)),
        ];

    // The ribbon behind: orange, the names small and spaced, going the other way.
    final small = size * 0.42;
    final tag = TextStyle(fontSize: small, fontWeight: FontWeight.w700, letterSpacing: small * 0.22, color: Colors.white);
    final behind = [
      for (final t in kinds)
        _RibbonLink(
          onTap: () => open(t),
          builder: (hover) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: hover ? 1.12 : 1,
                duration: Motion.of(context, Motion.hover),
                curve: Motion.ease,
                child: Text(t.name.toUpperCase(), maxLines: 1, style: tag),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: small * 1.2),
                child: Icon(Icons.circle, size: small * 0.32, color: Colors.white.withValues(alpha: hover ? 1 : 0.7)),
              ),
            ],
          ),
        ),
    ];

    // Steeper on narrow screens, so the ribbons still part enough to show both.
    final tilt = (layout.wide ? 3.5 : 6.0) * math.pi / 180;
    final front = size * 1.85;
    final back = small * 2.6;
    return ExcludeSemantics(
      child: Padding(
        padding: EdgeInsets.only(top: layout.section * 0.5, bottom: layout.section * 0.15),
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth;
            // Wider than the page, so the tilted ends run off its sides.
            Widget band({required double angle, required double height, required Widget child, Gradient? fill, List<BoxShadow>? shadow}) =>
                Transform.rotate(
                  angle: angle,
                  child: OverflowBox(
                    minWidth: width + height * 4,
                    maxWidth: width + height * 4,
                    child: Container(
                      height: height,
                      decoration: BoxDecoration(gradient: fill, boxShadow: shadow),
                      child: child,
                    ),
                  ),
                );
            return SizedBox(
              height: front + width * math.sin(tilt) * 1.1,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  band(
                    angle: tilt,
                    height: back,
                    fill: LinearGradient(colors: [spark, Color.lerp(spark, LightColors.orangeText, 0.35)!]),
                    child: _Marquee(height: back, speed: size * 0.9, reverse: true, items: behind),
                  ),
                  band(
                    angle: -tilt,
                    height: front,
                    // A faint sheen along the top edge.
                    fill: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color.lerp(ribbon, letters, 0.08)!, ribbon],
                    ),
                    shadow: ink.shadow(light: 0.16, dark: 0.45, blur: 32, dy: 14),
                    child: _Marquee(height: front, speed: size * 1.3, items: names(lit: false), lit: names(lit: true)),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One name on a ribbon, as a link: the hand cursor, [builder] told while
/// it's pointed at, and [onTap] on a click or tap, moving or not.
class _RibbonLink extends StatefulWidget {
  final VoidCallback onTap;
  final Widget Function(bool hover) builder;

  const _RibbonLink({required this.onTap, required this.builder});

  @override
  State<_RibbonLink> createState() => _RibbonLinkState();
}

class _RibbonLinkState extends State<_RibbonLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: widget.builder(_hover),
        ),
      );
}

/// [items] in a row along a band, repeated to fill the width, gliding left
/// (right if [reverse]) at an even [speed] in pixels a second. Over it may
/// lie [lit], the same row drawn bright, seen only through a soft spotlight
/// in the middle, so each item fills in as it passes and fades back after.
/// Pointing at it eases it to a stop, and letting go eases it back up. It
/// rests while scrolled out of sight, and stands still with Reduce motion.
class _Marquee extends StatefulWidget {
  final double height;
  final double speed;
  final bool reverse;
  final List<Widget> items;

  /// [items] lit up: the same widths, in the same order.
  final List<Widget>? lit;

  const _Marquee({required this.height, required this.speed, this.reverse = false, required this.items, this.lit});

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee> with SingleTickerProviderStateMixin {
  final _run = GlobalKey();
  late final Ticker _ticker;

  /// How far the row has slid, within one run.
  final _offset = ValueNotifier<double>(0);

  /// One run's width, once laid out.
  double _width = 0;

  /// Share of [_Marquee.speed] it moves at: eases to 0 while pointed at.
  double _pace = 1;
  bool _hover = false;
  Duration _last = Duration.zero;

  /// Whether any of it is in the window.
  bool _inSight = true;
  ScrollPosition? _position;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _position?.removeListener(_onScroll);
    _position = Scrollable.maybeOf(context)?.position;
    _position?.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    _sync();
  }

  @override
  void didUpdateWidget(_Marquee old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _onScroll() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    _inSight = top < MediaQuery.sizeOf(context).height && top + box.size.height > 0;
    _sync();
  }

  void _measure() {
    if (!mounted) return;
    final run = _run.currentContext?.findRenderObject();
    if (run is! RenderBox || !run.hasSize || run.size.width == _width) return;
    setState(() => _width = run.size.width);
    _offset.value %= _width;
    _sync();
  }

  /// Runs the clock only while there is something to move.
  void _sync() {
    final go = mounted && _width > 0 && _inSight && !reduceMotion(context) && (!_hover || _pace > 0.01);
    if (go && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!go && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final dt = math.min((elapsed - _last).inMicroseconds / 1e6, 0.1);
    _last = elapsed;
    _pace += ((_hover ? 0.0 : 1.0) - _pace) * math.min(1.0, dt * 3.5);
    _offset.value = (_offset.value + widget.speed * _pace * dt) % _width;
    if (_hover && _pace <= 0.01) _sync();
  }

  void _point(bool on) {
    _hover = on;
    _sync();
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    _ticker.dispose();
    _offset.dispose();
    super.dispose();
  }

  /// Seen only between [from] and [to] (shares of the width), with soft edges [soft] wide.
  static Shader _window(Rect rect, double from, double to, double soft) => LinearGradient(
        colors: const [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
        stops: [from, from + soft, to - soft, to],
      ).createShader(rect);

  @override
  Widget build(BuildContext context) {
    final lit = widget.lit;
    return MouseRegion(
      onEnter: (_) => _point(true),
      onExit: (_) => _point(false),
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, box) {
            // Enough runs to cover the band however far along it is (and one more going right).
            final span = box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width;
            final runs = _width == 0 ? 1 : (span / _width).ceil() + (widget.reverse ? 2 : 1);
            Widget slide(List<Widget> items, {Key? measure}) => ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    child: ValueListenableBuilder<double>(
                      valueListenable: _offset,
                      builder: (context, at, child) =>
                          Transform.translate(offset: Offset(widget.reverse ? at - _width : -at, 0), child: child),
                      child: RepaintBoundary(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Row(key: measure, mainAxisSize: MainAxisSize.min, children: items),
                          for (var i = 1; i < runs; i++) Row(mainAxisSize: MainAxisSize.min, children: items),
                        ]),
                      ),
                    ),
                  ),
                );
            return Stack(
              fit: StackFit.expand,
              children: [
                slide(widget.items, measure: _run),
                if (lit != null)
                  // Only seen: taps and the pointer go to [items] under it.
                  IgnorePointer(
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      // The spotlight: about a name wide, soft on both sides.
                      shaderCallback: (rect) {
                        final half = rect.width == 0 ? 0.0 : math.min(0.45, math.max(rect.width * 0.16, widget.height * 2.6) / rect.width);
                        return _window(rect, 0.5 - half, 0.5 + half, half * 0.55);
                      },
                      child: slide(lit),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// [child] breathing like a live light (bhutanesports.org's "Now ongoing"
/// dot): on every beat of the page (_Beat) a little smaller and fainter, and
/// back, then still until the next. Still with Reduce motion.
class _Pulse extends StatefulWidget {
  final Widget child;

  const _Pulse({required this.child});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  int? _beat;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final beat = _Beat.of(context);
    if (reduceMotion(context)) {
      _c.value = 0;
    } else if (beat != _beat) {
      _beat = beat;
      _c.forward(from: 0);
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
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        // Down and back up in one swell.
        final dip = math.sin(math.pi * _c.value);
        return Opacity(opacity: 1 - 0.55 * dip, child: Transform.scale(scale: 1 - 0.15 * dip, child: child));
      },
    );
  }
}

// ─── About ─────────────────────────────────────────────────────────────────

/// What Health Pro is, beside a gym's floor: what members get, three facts
/// about it on a card, and the way to more, on a tinted band.
class _About extends StatelessWidget {
  final _Layout layout;
  final VoidCallback onKnowMore;

  const _About({super.key, required this.layout, required this.onKnowMore});

  static const points = ['Easy membership management', 'Real-time attendance', 'Secure, reliable platform'];

  static const facts = [
    (Icons.event_available_rounded, '6 plan lengths', 'Day pass to a year'),
    (Icons.payments_outlined, '3 ways to pay', 'Cash, mBoB or bank'),
    (Icons.location_on_outlined, 'Made for Bhutan', 'Prices in Ngultrum'),
  ];

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final brand = context.brand;
    final title = TextStyle(
      fontSize: layout.titleSize,
      fontWeight: FontWeight.w800,
      height: 1.08,
      letterSpacing: -layout.titleSize * 0.03,
      color: ink.heading,
    );
    final cells = [
      for (final (i, (icon, value, label)) in facts.indexed)
        _RevealItem(order: i + 2, child: _AboutFact(icon: icon, value: value, label: label, inRow: !layout.medium)),
    ];
    // The facts on one card: side by side, or a list on a phone.
    final factCard = Container(
      decoration: BoxDecoration(
        color: ink.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: brand.glassBorder),
        boxShadow: ink.shadow(light: 0.07, dark: 0.3, blur: 32, dy: 14),
      ),
      child: layout.medium
          ? IntrinsicHeight(
              child: Row(
                children: [
                  for (var i = 0; i < cells.length; i++) ...[
                    if (i > 0) VerticalDivider(width: 1, color: brand.glassBorder, indent: 16, endIndent: 16),
                    Expanded(child: cells[i]),
                  ],
                ],
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < cells.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: brand.glassBorder, indent: 16, endIndent: 16),
                  cells[i],
                ],
              ],
            ),
    );
    // Navy in the light, blue in the dark; white words on either (they
    // were navy on navy in the light, so the button read as empty).
    final knowMore = _PillButton(
      label: 'Know More',
      icon: Icons.arrow_forward_rounded,
      color: ink.dark ? BrandColors.blue : LightColors.navy,
      foreground: ink.dark ? BrandColors.navy : Colors.white,
      onPressed: onKnowMore,
    );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow('ABOUT HEALTH PRO', lineBefore: true),
        const SizedBox(height: 16),
        Text('The Digital Home', style: title),
        _AccentText('for Gyms & Fitness', style: title),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'Health Pro brings members, trainers and gyms together on one platform built for Bhutan. '
            'Memberships, check-ins and payments live in one place, so you can focus on training and staying healthy.',
            style: TextStyle(fontSize: layout.wide ? 16.5 : 16, height: 1.65, color: ink.body),
          ),
        ),
        const SizedBox(height: 22),
        Wrap(spacing: 10, runSpacing: 10, children: [for (final point in points) _AboutPoint(point)]),
        const SizedBox(height: 28),
        factCard,
        const SizedBox(height: 30),
        if (layout.medium) knowMore else SizedBox(width: double.infinity, child: knowMore),
      ],
    );
    return Container(
      margin: EdgeInsets.only(bottom: layout.section),
      padding: EdgeInsets.symmetric(vertical: layout.section * 0.9),
      color: ink.pick(LightColors.backgroundAlt, Colors.white.withValues(alpha: 0.03)),
      child: _Frame(
        layout: layout,
        child: layout.wide
            ? Row(
                children: [
                  const Expanded(flex: 10, child: _AboutArt(height: 540)),
                  const SizedBox(width: 72),
                  Expanded(flex: 11, child: words),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AboutArt(height: layout.medium ? 360 : 250, compact: !layout.medium),
                  SizedBox(height: layout.medium ? 48 : 40),
                  words,
                ],
              ),
      ),
    );
  }
}

/// What members get, on a slim pill after a soft orange tick.
class _AboutPoint extends StatelessWidget {
  final String text;

  const _AboutPoint(this.text);

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 7, 14, 7),
      decoration: BoxDecoration(
        color: ink.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: brand.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: brand.accent.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, size: 14, color: brand.accentText),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(text, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: ink.heading)),
          ),
        ],
      ),
    );
  }
}

/// One fact about Health Pro: its icon on a softly lit tile, the fact, and
/// what it means. Beside the words on a phone ([inRow]).
class _AboutFact extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final bool inRow;

  const _AboutFact({required this.icon, required this.value, required this.label, this.inRow = false});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final brand = context.brand;
    final tile = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [brand.accent.withValues(alpha: 0.18), brand.accent.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: brand.accent.withValues(alpha: 0.18)),
      ),
      child: Icon(icon, size: 21, color: brand.accentText),
    );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.25, letterSpacing: -0.3, color: ink.heading)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12.5, height: 1.4, color: brand.muted)),
      ],
    );
    if (inRow) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [tile, const SizedBox(width: 14), Expanded(child: words)]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [tile, const SizedBox(height: 14), words],
      ),
    );
  }
}

/// A gym's floor in a rounded frame, graded to navy at its foot with the
/// page's stripes over its corner; a slim orange outline set off behind it,
/// and Health Pro's promise floating over its edge. Smaller on a phone
/// ([compact]).
class _AboutArt extends StatelessWidget {
  final double height;
  final bool compact;

  const _AboutArt({required this.height, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final brand = context.brand;
    const radius = 28.0;
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: compact ? -10 : -18,
              top: compact ? 14 : 22,
              right: compact ? 14 : 22,
              bottom: compact ? -10 : -18,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius + 4),
                  border: Border.all(color: brand.highlight.withValues(alpha: 0.85), width: 2),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: [
                    BoxShadow(
                      color: ink.pick(LightColors.navy.withValues(alpha: 0.22), Colors.black.withValues(alpha: 0.4)),
                      blurRadius: 44,
                      spreadRadius: -6,
                      offset: const Offset(0, 22),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const GymPhoto('about'),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00081428), Color(0x8C081428)],
                            stops: [0.4, 1],
                          ),
                        ),
                      ),
                      CustomPaint(painter: GymStripesPainter.of(context)),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(radius),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // As wide as its words, and never past the picture's edge: the
            // tagline wraps first.
            Positioned(
              left: compact ? 14 : 28,
              right: compact ? 14 : 28,
              bottom: compact ? 16 : 30,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: GentleFloat(
                  phase: 0.3,
                  distance: 5,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 10, 18, 10),
                    decoration: BoxDecoration(
                      color: ink.dark ? const Color(0xF216213C) : const Color(0xF7FFFFFF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: brand.glassBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: ink.dark ? 0.4 : 0.18),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HealthProLogo(markOnly: true, height: compact ? 30 : 36),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Health Pro',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: ink.heading)),
                              Text('All your well-being, all in one place.',
                                  style: TextStyle(fontSize: 12, color: brand.muted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ─── How it works ──────────────────────────────────────────────────────────

class _Step {
  final IconData icon;
  final String title;
  final String text;

  const _Step(this.icon, this.title, this.text);
}

/// Five steps from signing up to training, on a line from the first to the
/// goal: side by side on a wide window, down the page on a narrow one.
///
/// Once the section is in view the light walks through them, one step on
/// every beat of the page (_Beat), then starts again: a spark runs along the
/// line to the next step, whose circle fills and breathes and whose card
/// lifts, its title in orange. The dots underneath show where it is; tapping
/// one goes there. With less motion it stands still on the goal.
class _Steps extends StatefulWidget {
  final _Layout layout;

  const _Steps({super.key, required this.layout});

  static const steps = [
    _Step(Icons.person_add_alt_1_rounded, 'Sign Up', 'Create your account in minutes'),
    _Step(Icons.event_note_rounded, 'Choose a Plan', 'Pick a gym and a membership plan'),
    _Step(Icons.payments_outlined, 'Make Payment', 'Pay the gym in cash or by mBoB'),
    _Step(Icons.qr_code_2_rounded, 'Check In', 'Show your QR code at the desk'),
    _Step(Icons.emoji_events_outlined, 'Achieve Goals', 'Train on, and renew before it ends'),
  ];

  @override
  State<_Steps> createState() => _StepsState();
}

class _StepsState extends State<_Steps> with SingleTickerProviderStateMixin {
  static final _last = _Steps.steps.length - 1;

  /// The lit step; those before it are passed.
  int _active = _last;

  /// The beat the walk was on the first step; none until the section is seen.
  int? _from;
  late final AnimationController _breath = AnimationController(vsync: this, duration: _Beat.settle);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = _Revealed.of(context);
    final beat = _Beat.of(context);
    if (reduceMotion(context)) {
      _from = null;
      _breath.value = 0;
      _active = _last;
    } else if (shown) {
      if (_from == null) {
        // Seen at last: the walk starts from the first step, on a fresh beat.
        _from = beat;
        _Beat.restartOf(context);
      }
      final step = (beat - _from!) % _Steps.steps.length;
      if (step != _active) _light(step);
    }
  }

  /// Lights [step], its breath starting now.
  void _light(int step) {
    _active = step;
    _breath.forward(from: 0);
  }

  /// Moves the light to [step], to walk on from there a whole beat later.
  void _pick(int step) {
    if (reduceMotion(context)) return setState(() => _active = step);
    _from = _Beat.peek(context) - step;
    _Beat.restartOf(context);
    setState(() => _light(step));
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    const steps = _Steps.steps;
    final active = _active;
    final ink = _Ink.of(context);
    final title = TextStyle(
      fontSize: layout.titleSize,
      fontWeight: FontWeight.w800,
      height: 1.12,
      letterSpacing: -layout.titleSize * 0.03,
      color: ink.heading,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: layout.section),
      child: _Frame(
        layout: layout,
        child: Column(
          children: [
            const _Eyebrow('HOW IT WORKS', lineBefore: true, lineAfter: true),
            const SizedBox(height: 16),
            // Breaks between the two halves when it must, never mid-promise.
            Wrap(
              alignment: WrapAlignment.center,
              children: [Text('Get Started in ', style: title), _AccentText('5 Simple Steps', style: title)],
            ),
            SizedBox(height: layout.stepsInRow ? 60 : 40),
            if (layout.stepsInRow)
              LayoutBuilder(
                builder: (context, box) {
                  final each = box.maxWidth / steps.length;
                  final along = (box.maxWidth - each) * active / _last;
                  final accent = context.brand.accent;
                  final move = reduceMotion(context) ? Duration.zero : Motion.card;
                  const middle = _StepColumn.circle / 2;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // The line through the steps, from the first to the goal.
                      Positioned(
                        left: each / 2,
                        right: each / 2,
                        top: middle - 1,
                        height: 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: LinearGradient(
                              colors: [accent.withValues(alpha: 0.1), accent.withValues(alpha: 0.24), accent.withValues(alpha: 0.1)],
                            ),
                          ),
                        ),
                      ),
                      // How far the light has come, and the spark running at its head.
                      AnimatedPositioned(
                        duration: move,
                        curve: Motion.easeInOut,
                        left: each / 2,
                        width: along,
                        top: middle - 1,
                        height: 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: LinearGradient(colors: [accent.withValues(alpha: 0.55), accent]),
                          ),
                        ),
                      ),
                      AnimatedPositioned(
                        duration: move,
                        curve: Motion.easeInOut,
                        left: each / 2 + along - 5,
                        top: middle - 5,
                        width: 10,
                        height: 10,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent,
                            boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.6), blurRadius: 12, spreadRadius: 1)],
                          ),
                        ),
                      ),
                      // The cards stand level, as tall as the tallest.
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < steps.length; i++)
                              Expanded(
                                child: _RevealItem(
                                  order: i,
                                  child: _StepColumn(number: i + 1, step: steps[i], lit: i == active, breath: _breath),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    for (var i = 0; i < steps.length; i++)
                      _RevealItem(
                        order: i,
                        child: _StepRow(
                          number: i + 1,
                          step: steps[i],
                          lit: i == active,
                          reached: i <= active,
                          passed: i < active,
                          last: i == _last,
                          breath: _breath,
                        ),
                      ),
                  ],
                ),
              ),
            SizedBox(height: layout.stepsInRow ? 44 : 28),
            _StepDots(active: active, onPick: _pick),
          ],
        ),
      ),
    );
  }
}

/// How far along a lit step's [breath] (0 to 1) it has swelled: in, then
/// out again.
double _swell(double breath) => math.sin(math.pi * breath);

/// How a step lights up or goes dark: going dark starts at once, lighting
/// waits for the spark to run along the line to it.
({Duration duration, Curve curve}) _lighting(BuildContext context, bool lit) {
  if (reduceMotion(context)) return (duration: Duration.zero, curve: Motion.ease);
  return lit
      ? (duration: Motion.card * 2, curve: const Interval(0.5, 1, curve: Motion.ease))
      : (duration: Motion.card, curve: Motion.ease);
}

/// A little wiggle, 3° each way, a third of the way into a [breath].
double _wiggle(double breath) {
  const from = 0.3, length = 0.25;
  if (breath < from || breath > from + length) return 0;
  return math.sin(2 * math.pi * (breath - from) / length) * 3 * math.pi / 180;
}

/// A step's icon in a card-coloured ring, on a soft orange disc. Lit, the
/// disc fills with the brand's orange and the ring glows; the whole circle
/// takes one slow [breath], a halo swelling in the ring and the icon giving a
/// little wiggle. Under the pointer ([hover]) it lifts and its ring warms.
class _StepCircle extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool lit;
  final bool hover;
  final Animation<double> breath;

  const _StepCircle({required this.icon, required this.size, required this.breath, this.lit = false, this.hover = false});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final brand = context.brand;
    final accent = brand.accent;
    final still = reduceMotion(context);
    final ring = hover ? accent.withValues(alpha: 0.55) : brand.glassBorder;
    final soft = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [accent.withValues(alpha: 0.16), accent.withValues(alpha: 0.04)],
    );
    final filled = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color.lerp(brand.highlight, Colors.white, 0.2)!, brand.highlight],
    );
    return AnimatedSlide(
      offset: Offset(0, hover ? -3 / size : 0),
      duration: still ? Duration.zero : Motion.hover,
      curve: Motion.ease,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: lit ? 1 : 0),
        duration: _lighting(context, lit).duration,
        curve: _lighting(context, lit).curve,
        builder: (context, l, _) => AnimatedBuilder(
          animation: breath,
          builder: (context, _) {
            final b = lit ? _swell(breath.value) : 0.0;
            return Transform.scale(
              scale: 1 + 0.05 * b,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ink.card,
                  border: Border.all(color: Color.lerp(ring, accent.withValues(alpha: 0.45), l)!, width: 1.5),
                  boxShadow: BoxShadow.lerpList(
                    ink.shadow(light: hover ? 0.12 : 0.08, dark: 0.3, blur: 24, dy: 10),
                    [BoxShadow(color: brand.highlight.withValues(alpha: 0.32), blurRadius: 26, offset: const Offset(0, 10))],
                    l,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // A glow round the disc that swells with the breath.
                    Opacity(
                      opacity: ((0.35 + 0.5 * b) * l).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: 1 + 0.2 * b,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [accent.withValues(alpha: 0.5), accent.withValues(alpha: 0)],
                              stops: const [0.6, 1],
                            ),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                    Container(
                      margin: EdgeInsets.all(size * 0.1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient.lerp(soft, filled, l),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25 * l)),
                      ),
                      alignment: Alignment.center,
                      child: Transform.rotate(
                        angle: lit ? _wiggle(breath.value) : 0,
                        child: Icon(icon, size: size * 0.38, color: Color.lerp(brand.accentText, Colors.white, l)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// "STEP 01" in small orange capitals.
class _StepLabel extends StatelessWidget {
  final int number;

  const _StepLabel(this.number);

  @override
  Widget build(BuildContext context) {
    return Text(
      'STEP ${number.toString().padLeft(2, '0')}',
      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: context.brand.accentText),
    );
  }
}

/// A step's words on a card. Lit, the card lifts a little, its edge and title
/// warm to orange and, when [centred], a small dot breathes at its foot.
class _StepCard extends StatelessWidget {
  final int number;
  final _Step step;
  final bool lit;
  final bool hover;
  final bool centred;
  final Animation<double> breath;

  const _StepCard({
    required this.number,
    required this.step,
    required this.breath,
    this.lit = false,
    this.hover = false,
    this.centred = true,
  });

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final brand = context.brand;
    final accent = brand.accent;
    final move = reduceMotion(context) ? Duration.zero : Motion.card;
    final light = _lighting(context, lit);
    final hairline = ink.pick(LightColors.navy.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.08));
    final align = centred ? TextAlign.center : TextAlign.start;
    return AnimatedContainer(
      duration: hover && !lit ? move : light.duration,
      curve: hover && !lit ? Motion.ease : light.curve,
      transform: Matrix4.translationValues(0, lit || hover ? -4 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(centred ? 18 : 16),
        color: lit ? Color.alphaBlend(accent.withValues(alpha: 0.05), ink.card) : ink.card.withValues(alpha: 0.75),
        border: Border.all(color: lit || hover ? accent.withValues(alpha: 0.3) : hairline),
        boxShadow: lit ? ink.shadow(light: 0.1, dark: 0.35, blur: 26, dy: 12) : ink.shadow(light: 0.03, dark: 0.15, blur: 16, dy: 6),
      ),
      child: Stack(
        alignment: centred ? Alignment.topCenter : AlignmentDirectional.topStart,
        children: [
          Padding(
            padding: centred ? const EdgeInsets.fromLTRB(14, 18, 14, 26) : const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: centred ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                _StepLabel(number),
                SizedBox(height: centred ? 6 : 4),
                // Over the page's own text style, so it keeps the brand's font.
                AnimatedDefaultTextStyle(
                  duration: light.duration,
                  curve: light.curve,
                  style: DefaultTextStyle.of(context).style.merge(TextStyle(
                    fontSize: centred ? 17 : 16.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: centred ? -0.3 : -0.2,
                    color: lit ? brand.accentText : ink.heading,
                  )),
                  child: Text(step.title, textAlign: align),
                ),
                SizedBox(height: centred ? 6 : 3),
                Text(step.text, textAlign: align, style: TextStyle(fontSize: 13.5, height: 1.5, color: brand.muted)),
              ],
            ),
          ),
          if (centred)
            Positioned(
              left: 0,
              right: 0,
              bottom: 11,
              child: Center(
                child: AnimatedOpacity(
                  opacity: lit ? 1 : 0,
                  duration: light.duration,
                  curve: light.curve,
                  child: AnimatedBuilder(
                    animation: breath,
                    builder: (context, child) {
                      final b = lit ? _swell(breath.value) : 0.0;
                      return Opacity(
                        opacity: 0.45 + 0.45 * b,
                        child: Transform.scale(scale: 1 + 0.4 * b, child: child),
                      );
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
                      child: const SizedBox.square(dimension: 5),
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

/// A step: its circle on the line, its card under it.
class _StepColumn extends StatefulWidget {
  /// The circle's size; the line runs through its middle.
  static const circle = 80.0;

  final int number;
  final _Step step;
  final bool lit;
  final Animation<double> breath;

  const _StepColumn({required this.number, required this.step, required this.breath, this.lit = false});

  @override
  State<_StepColumn> createState() => _StepColumnState();
}

class _StepColumnState extends State<_StepColumn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hover = _hover && !reduceMotion(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: _StepCircle(
                icon: widget.step.icon,
                size: _StepColumn.circle,
                lit: widget.lit,
                hover: hover,
                breath: widget.breath,
              ),
            ),
            const SizedBox(height: 22),
            Expanded(
              child: _StepCard(number: widget.number, step: widget.step, lit: widget.lit, hover: hover, breath: widget.breath),
            ),
          ],
        ),
      ),
    );
  }
}

/// A step beside its circle, one under the other, the line running down from
/// each circle to the next; it warms from the top once the light has
/// [reached] the step, and all the way down once it has [passed] it.
class _StepRow extends StatelessWidget {
  final int number;
  final _Step step;
  final bool lit;
  final bool reached;
  final bool passed;

  /// The goal, with no line under it.
  final bool last;
  final Animation<double> breath;

  const _StepRow({
    required this.number,
    required this.step,
    required this.breath,
    this.lit = false,
    this.reached = false,
    this.passed = false,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.brand.accent;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              _StepCircle(icon: step.icon, size: 58, lit: lit, breath: breath),
              if (!last)
                Expanded(
                  child: AnimatedContainer(
                    duration: reduceMotion(context) ? Duration.zero : Motion.card,
                    curve: Motion.easeInOut,
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          accent.withValues(alpha: reached ? 0.5 : 0.14),
                          accent.withValues(alpha: passed ? 0.9 : 0.14),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 2, bottom: last ? 0 : 18),
              child: _StepCard(number: number, step: step, lit: lit, centred: false, breath: breath),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the light is: a dot for each step, joined by hairlines, the lit one
/// drawn out into a bar. Tapping a dot moves the light there.
class _StepDots extends StatelessWidget {
  final int active;
  final ValueChanged<int> onPick;

  const _StepDots({required this.active, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final accent = context.brand.accent;
    final move = reduceMotion(context) ? Duration.zero : Motion.card;
    const steps = _Steps.steps;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) Container(width: 28, height: 1, color: accent.withValues(alpha: 0.18)),
          Semantics(
            button: true,
            selected: i == active,
            label: 'Step ${i + 1}: ${steps[i].title}',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onPick(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  child: AnimatedContainer(
                    duration: move,
                    curve: Motion.ease,
                    width: i == active ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: i == active ? accent : accent.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Plans ─────────────────────────────────────────────────────────────────

class _PlanKind {
  final IconData icon;
  final String name;
  final String tagline;

  /// The lengths gyms offer, " · " between them.
  final String lengths;
  final List<String> points;
  final bool featured;

  const _PlanKind(this.icon, this.name, this.tagline, this.lengths, this.points, {this.featured = false});
}

/// The plan lengths gyms offer. Each gym sets its own plans and prices, so
/// there are no prices here: Find a gym shows them.
class _Plans extends StatelessWidget {
  final _Layout layout;
  final VoidCallback onFindGym;

  const _Plans({super.key, required this.layout, required this.onFindGym});

  static const kinds = [
    _PlanKind(Icons.bolt_rounded, 'Short Stay', 'Try a gym first', 'Day pass · 1 week',
        ['QR check-in from day one', 'No long commitment']),
    _PlanKind(
      Icons.calendar_month_rounded,
      'Monthly',
      'The everyday choice',
      '1 month · 3 months',
      ['Reminder 3 days before the end', 'Renew without losing days'],
      featured: true,
    ),
    _PlanKind(Icons.workspace_premium_rounded, 'Long Term', 'For the committed', '6 months · 1 year',
        ['Your card and visits in one place', 'Fewer renewals to think of']),
  ];

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final title = TextStyle(
      fontSize: layout.titleSize,
      fontWeight: FontWeight.w800,
      height: 1.08,
      letterSpacing: -layout.titleSize * 0.03,
      color: ink.heading,
    );
    final seePlans = _PillButton(label: 'See plans at gyms', icon: Icons.arrow_forward_rounded, onPressed: onFindGym);
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow('MEMBERSHIP PLANS', lineBefore: true),
        const SizedBox(height: 16),
        Text('Choose Your', style: title),
        _AccentText('Perfect Plan', style: title),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470),
          child: Text(
            'Flexible plans for every fitness goal. Each gym sets its own plans and prices in Ngultrum.',
            style: TextStyle(fontSize: layout.wide ? 16.5 : 16, height: 1.65, color: ink.body),
          ),
        ),
        const SizedBox(height: 28),
        if (layout.medium) seePlans else SizedBox(width: double.infinity, child: seePlans),
      ],
    );
    // Laid across where the cards stand one over another, but there's room.
    final across = layout.medium && !layout.wide;
    final cards = [
      for (final (i, k) in kinds.indexed)
        _RevealItem(
          order: i + 1,
          child: HoverLift(radius: 24, lift: 4, child: _PlanCard(kind: k, onFindGym: onFindGym, wide: across)),
        ),
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: layout.section),
      child: _Frame(
        layout: layout,
        child: layout.wide
            ? Row(
                children: [
                  Expanded(flex: 3, child: intro),
                  const SizedBox(width: 44),
                  // Side by side the cards share a height, and the buttons
                  // line up at the foot.
                  Expanded(
                    flex: 9,
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < cards.length; i++) ...[
                            if (i > 0) const SizedBox(width: 16),
                            Expanded(child: cards[i]),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  intro,
                  const SizedBox(height: 36),
                  for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: 16), cards[i]],
                ],
              ),
      ),
    );
  }
}

/// A kind of plan on its card: its icon, name and who it's for, the lengths
/// gyms offer (each gym sets the prices), what it brings, and the way to a
/// gym. The everyday choice ([_PlanKind.featured]) leads the row: deep navy
/// with a warm light in the light, tinted orange and ringed in the dark.
/// Laid across on a tablet ([wide]), where the cards stand one over another.
class _PlanCard extends StatelessWidget {
  final _PlanKind kind;
  final VoidCallback onFindGym;
  final bool wide;

  const _PlanCard({required this.kind, required this.onFindGym, this.wide = false});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final brand = context.brand;
    final featured = kind.featured;
    final tinted = Color.alphaBlend(brand.accent.withValues(alpha: ink.dark ? 0.12 : 0.05), ink.card);
    // On the navy card, white words in the light; the page's own in the dark.
    Color on(Color navy, Color page) => featured ? ink.pick(navy, page) : page;
    final heading = on(Colors.white, ink.heading);
    final body = on(Colors.white.withValues(alpha: 0.88), ink.body);
    final muted = on(Colors.white.withValues(alpha: 0.66), brand.muted);
    final rule = on(Colors.white.withValues(alpha: 0.14), brand.glassBorder);
    final orange = on(brand.highlight, brand.accentText);
    final [first, ...rest] = kind.lengths.split(' · ');
    // Its icon, name and who it's for, then the lengths gyms offer.
    final about = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [brand.accent.withValues(alpha: featured ? 0.26 : 0.18), brand.accent.withValues(alpha: 0.05)],
                ),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: brand.accent.withValues(alpha: featured ? 0.3 : 0.18)),
              ),
              child: Icon(kind.icon, size: 22, color: orange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kind.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: heading)),
                  Text(kind.tagline, style: TextStyle(fontSize: 12.5, color: muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (!wide) ...[Divider(height: 1, color: rule), const SizedBox(height: 20)],
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: first),
              for (final length in rest) ...[
                TextSpan(text: ' · ', style: TextStyle(color: orange)),
                TextSpan(text: length),
              ],
            ],
          ),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.25, color: heading),
        ),
        const SizedBox(height: 4),
        Text('Prices set by each gym', style: TextStyle(fontSize: 12.5, color: muted)),
      ],
    );
    final points = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, point) in kind.points.indexed)
          Padding(
            padding: EdgeInsets.only(top: i > 0 ? 10 : 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: brand.accent.withValues(alpha: featured ? (ink.dark ? 0.22 : 0.34) : 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_rounded, size: 13, color: orange),
                ),
                const SizedBox(width: 9),
                Expanded(child: Text(_noWidow(point), style: TextStyle(fontSize: 13.5, height: 1.4, color: body))),
              ],
            ),
          ),
      ],
    );
    final button = SizedBox(
      width: double.infinity,
      child: featured
          ? _PillButton(label: 'Services', compact: true, onPressed: onFindGym)
          : _PillButton(label: 'Services', compact: true, outlined: true, onPressed: onFindGym),
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: featured ? null : ink.card,
        gradient: featured
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [ink.pick(const Color(0xFF0B1530), tinted), ink.pick(const Color(0xFF1B3F8A), tinted)],
              )
            : null,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: featured ? ink.pick(Colors.white.withValues(alpha: 0.1), brand.accent) : brand.glassBorder,
          width: featured && ink.dark ? 1.6 : 1,
        ),
        boxShadow: featured ? ink.shadow(light: 0.3, dark: 0.4, blur: 44, dy: 22) : ink.shadow(light: 0.07, blur: 32, dy: 14),
      ),
      child: Stack(
        children: [
          if (featured)
            Positioned(
              right: -70,
              top: -90,
              child: GymGlow(color: brand.highlight.withValues(alpha: ink.dark ? 0.12 : 0.3), size: 240),
            ),
          Padding(
            padding: wide ? const EdgeInsets.all(26) : const EdgeInsets.fromLTRB(22, 24, 20, 22),
            child: wide ? _across(rule, about, points, button) : _down(about, points, button),
          ),
        ],
      ),
    );
  }

  /// One part under the next, the button at the foot (side by side the
  /// cards share a height, so the buttons line up).
  Widget _down(Widget about, Widget points, Widget button) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [about, const SizedBox(height: 18), points, const SizedBox(height: 14)],
        ),
        button,
      ],
    );
  }

  /// The plan on the left; what it brings and the button on the right.
  Widget _across(Color rule, Widget about, Widget points, Widget button) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 5, child: about),
          const SizedBox(width: 26),
          VerticalDivider(width: 1, color: rule),
          const SizedBox(width: 26),
          Expanded(
            flex: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [points, const SizedBox(height: 14), button],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Questions ─────────────────────────────────────────────────────────────

/// What people ask, opening one at a time, and where to turn when the answer
/// isn't here: the front desk at a gym.
class _Faq extends StatefulWidget {
  final _Layout layout;
  final VoidCallback onFindGym;

  const _Faq({super.key, required this.layout, required this.onFindGym});

  // As the gyms work today: ask to join in the app, or at the front desk
  // (no account needed there). Health Pro's assistant answers from the same
  // facts (supabase/functions/ask-health-pro/reply.ts): change both together.
  static const questions = [
    (
      'How do I join a gym?',
      "Scan the gym's QR code (or open its page) and tap Ask to join: the front desk gets your details and "
          'lets you know. Or go to the gym: the front desk registers you, sells you a package for 1 to 24 months '
          'and takes your payment. Either way you get one Health Pro QR code that works at every gym.',
    ),
    (
      'What payment methods are accepted?',
      'You pay the gym: cash at the front desk, or online. To pay online, open your dashboard, tap Pay online, scan '
          "the gym's payment QR code in your bank app and enter the journal number (JRN). The gym checks it "
          'with the bank and confirms it; your package starts then.',
    ),
    (
      'When does my membership start and end?',
      'It starts on the day you join and ends on the same date that many months later: join on 8 November '
          'for 3 months and it ends on 8 February, and you can still come that day. Renew early and the new '
          'package starts the day the current one ends, so you never lose days.',
    ),
    (
      'How do I check in?',
      'Show your QR card at the counter. The staff scan it, or type your 6-character member code or your '
          'phone number. It works while your package covers that day.',
    ),
    (
      'What if I lose my card?',
      'Ask the front desk for a new card. Your old one stops working, so nobody else can use it.',
    ),
    (
      'Can I cancel my membership?',
      'Talk to your gym: changes and refunds are up to them.',
    ),
    (
      'How do I put my gym on Health Pro?',
      'Sign up, then Register your venue, choose Gym and add your packages and prices. Once the Health Pro '
          'team has verified your gym, add your staff and start registering members at the front desk.',
    ),
  ];

  @override
  State<_Faq> createState() => _FaqState();
}

class _FaqState extends State<_Faq> {
  /// The question open, if one is.
  int? _open;

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final ink = _Ink.of(context);
    final title = TextStyle(
      fontSize: layout.titleSize,
      fontWeight: FontWeight.w800,
      height: 1.08,
      letterSpacing: -layout.titleSize * 0.03,
      color: ink.heading,
    );
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow('FREQUENTLY ASKED QUESTIONS', lineBefore: true),
        const SizedBox(height: 16),
        Wrap(children: [Text('Have ', style: title), _AccentText('Questions?', style: title)]),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470),
          child: Text(
            _noWidow('Answers about joining, paying and checking in.'),
            style: TextStyle(fontSize: layout.wide ? 16.5 : 16, height: 1.65, color: ink.body),
          ),
        ),
      ],
    );
    final help = _FaqHelp(onFindGym: widget.onFindGym, compact: !layout.medium);
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, (question, answer)) in _Faq.questions.indexed) ...[
          if (i > 0) const SizedBox(height: 12),
          _RevealItem(
            order: i + 1,
            child: _Question(
              number: i + 1,
              question: question,
              answer: answer,
              open: _open == i,
              compact: !layout.medium,
              onTap: () => setState(() => _open = _open == i ? null : i),
            ),
          ),
        ],
      ],
    );
    return Padding(
      padding: EdgeInsets.only(bottom: layout.section),
      child: _Frame(
        layout: layout,
        child: layout.wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [intro, const SizedBox(height: 36), help],
                    ),
                  ),
                  const SizedBox(width: 56),
                  Expanded(flex: 7, child: list),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [intro, const SizedBox(height: 32), list, const SizedBox(height: 24), help],
              ),
      ),
    );
  }
}

/// One question on its own card: its number, the question and a round
/// toggle. Open, the answer unfolds under it, the number fills orange and
/// the plus turns to a cross.
class _Question extends StatefulWidget {
  final int number;
  final String question;
  final String answer;
  final bool open;
  final VoidCallback onTap;

  /// Tighter, for a phone.
  final bool compact;

  const _Question({
    required this.number,
    required this.question,
    required this.answer,
    required this.open,
    required this.onTap,
    this.compact = false,
  });

  @override
  State<_Question> createState() => _QuestionState();
}

class _QuestionState extends State<_Question> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final brand = context.brand;
    final accent = brand.accent;
    final open = widget.open;
    final hover = _hover && !reduceMotion(context);
    final compact = widget.compact;
    final pad = compact ? 16.0 : 20.0;
    final tile = compact ? 34.0 : 38.0;
    final gap = compact ? 12.0 : 16.0;
    final unfold = Motion.of(context, Motion.page);
    final number = AnimatedContainer(
      duration: Motion.hover,
      curve: Motion.ease,
      width: tile,
      height: tile,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: open ? brand.highlight : null,
        gradient: open
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent.withValues(alpha: 0.18), accent.withValues(alpha: 0.05)],
              ),
        borderRadius: BorderRadius.circular(compact ? 11 : 12),
        border: Border.all(color: accent.withValues(alpha: open ? 0 : 0.18)),
      ),
      child: Text(
        widget.number.toString().padLeft(2, '0'),
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: open ? BrandColors.navy : brand.accentText,
        ),
      ),
    );
    final toggle = AnimatedContainer(
      duration: Motion.hover,
      curve: Motion.ease,
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: open ? accent : (hover ? accent.withValues(alpha: 0.16) : ink.tint),
      ),
      child: AnimatedRotation(
        turns: open ? 0.125 : 0,
        duration: unfold,
        curve: Motion.ease,
        child: Icon(
          Icons.add_rounded,
          size: 20,
          color: open ? BrandColors.navy : (hover ? brand.accentText : ink.heading),
        ),
      ),
    );
    final header = Padding(
      padding: EdgeInsets.fromLTRB(pad, compact ? 14 : 16, compact ? 14 : 18, compact ? 14 : 16),
      child: Row(
        children: [
          number,
          SizedBox(width: gap),
          Expanded(
            child: Text(
              widget.question,
              style: TextStyle(
                fontSize: compact ? 15 : 16,
                fontWeight: FontWeight.w700,
                height: 1.35,
                letterSpacing: -0.2,
                color: ink.heading,
              ),
            ),
          ),
          const SizedBox(width: 12),
          toggle,
        ],
      ),
    );
    // Only there while open, so a closed question holds no hidden answer.
    final answer = AnimatedSwitcher(
      duration: unfold,
      switchInCurve: Motion.ease,
      switchOutCurve: Motion.ease,
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.topLeft, children: [...previous, if (current != null) current]),
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        axisAlignment: -1,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: open
          ? Padding(
              key: const ValueKey(true),
              padding: EdgeInsets.fromLTRB(pad + tile + gap, 0, compact ? 16 : 26, compact ? 16 : 20),
              child: Text(
                _noWidow(widget.answer),
                style: TextStyle(fontSize: compact ? 14 : 14.5, height: 1.65, color: ink.body),
              ),
            )
          : const SizedBox(key: ValueKey(false), width: double.infinity),
    );
    final warm = Color.alphaBlend(accent.withValues(alpha: ink.dark ? 0.08 : 0.04), ink.card);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: Motion.hover,
        curve: Motion.ease,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: open ? warm : ink.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: open
                ? accent.withValues(alpha: 0.45)
                : (hover ? accent.withValues(alpha: 0.3) : brand.glassBorder),
          ),
          boxShadow: open ? ink.shadow(light: 0.1, blur: 36, dy: 16) : ink.shadow(light: 0.05, blur: 22, dy: 8),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                expanded: open,
                child: InkWell(
                  onTap: widget.onTap,
                  hoverColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  splashColor: accent.withValues(alpha: 0.08),
                  focusColor: accent.withValues(alpha: 0.08),
                  child: header,
                ),
              ),
              answer,
            ],
          ),
        ),
      ),
    );
  }
}

/// Where to turn when the answer isn't here: the front desk at a gym. Deep
/// navy with a warm light, like the everyday plan; on the page's card in the
/// dark.
class _FaqHelp extends StatelessWidget {
  final VoidCallback onFindGym;

  /// Its button the full width, for a phone.
  final bool compact;

  const _FaqHelp({required this.onFindGym, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final brand = context.brand;
    final tinted = Color.alphaBlend(brand.accent.withValues(alpha: ink.dark ? 0.08 : 0.05), ink.card);
    final button = _PillButton(label: 'Services', icon: Icons.arrow_forward_rounded, compact: true, onPressed: onFindGym);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ink.pick(const Color(0xFF0B1530), tinted), ink.pick(const Color(0xFF1B3F8A), tinted)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ink.pick(Colors.white.withValues(alpha: 0.1), brand.glassBorder)),
        boxShadow: ink.shadow(light: 0.24, dark: 0.35, blur: 40, dy: 18),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -80,
            top: -100,
            child: GymGlow(color: brand.highlight.withValues(alpha: ink.dark ? 0.1 : 0.28), size: 240),
          ),
          Padding(
            padding: EdgeInsets.all(compact ? 22 : 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ink.pick(Colors.white.withValues(alpha: 0.1), brand.accent.withValues(alpha: 0.14)),
                        border: Border.all(
                          color: ink.pick(Colors.white.withValues(alpha: 0.18), brand.accent.withValues(alpha: 0.25)),
                        ),
                      ),
                      child: Icon(
                        Icons.support_agent_rounded,
                        size: 22,
                        color: ink.pick(brand.highlight, brand.accentText),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Still have a question?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: ink.pick(Colors.white, ink.heading),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _noWidow('The front desk at your gym can help with packages, payments and your card.'),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: ink.pick(Colors.white.withValues(alpha: 0.78), ink.body),
                  ),
                ),
                const SizedBox(height: 20),
                if (compact) SizedBox(width: double.infinity, child: button) else button,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── The last call ─────────────────────────────────────────────────────────

/// Join Now on navy, and registering a gym.
class _LastCall extends StatelessWidget {
  final _Layout layout;
  final VoidCallback onJoin;
  final VoidCallback onRegisterGym;

  const _LastCall({required this.layout, required this.onJoin, required this.onRegisterGym});

  @override
  Widget build(BuildContext context) {
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ready to transform your fitness journey?',
          style: TextStyle(
            color: Colors.white,
            fontSize: layout.wide ? 32 : 25,
            fontWeight: FontWeight.w800,
            fontStyle: FontStyle.italic,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Join Health Pro today and take the first step towards a healthier you.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 17, height: 1.5),
        ),
      ],
    );
    final actions = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: layout.medium ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        _PillButton(label: 'Join Now', icon: Icons.arrow_forward_rounded, onPressed: onJoin),
        const SizedBox(height: 6),
        TextButton(
          onPressed: onRegisterGym,
          style: TextButton.styleFrom(foregroundColor: Colors.white.withValues(alpha: 0.85)),
          child: const Text('Run a gym? Register it'),
        ),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(bottom: layout.section * 0.75),
      child: _Frame(
        layout: layout,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [BrandColors.navy, BrandColors.slateNavy],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: Stack(
              children: [
                // Snow peaks on the right, the navy deepening to the left
                // under the words.
                const Positioned.fill(child: GymPhoto('mountains', alignment: Alignment(0, -0.2))),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFA0A1C45),
                          const Color(0xE00A1C45),
                          BrandColors.navy.withValues(alpha: layout.medium ? 0.35 : 0.75),
                        ],
                        stops: const [0, 0.45, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                    right: -60, top: -120, child: GymGlow(color: context.brand.highlight.withValues(alpha: 0.3), size: 320)),
                Padding(
                  padding: EdgeInsets.all(layout.wide ? 48 : 28),
                  child: layout.medium
                      ? Row(children: [Expanded(child: words), const SizedBox(width: 28), actions])
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [words, const SizedBox(height: 22), actions],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Footer ────────────────────────────────────────────────────────────────

/// On navy: the logo, the links, Bhutan's mountains and the copyright.
class _Footer extends StatelessWidget {
  final _Layout layout;
  final List<(String, VoidCallback)> links;

  const _Footer({required this.layout, required this.links});

  @override
  Widget build(BuildContext context) {
    final dim = Colors.white.withValues(alpha: 0.7);
    final linkRow = Wrap(
      alignment: layout.medium ? WrapAlignment.end : WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < links.length; i++) ...[
          if (i > 0) Text('|', style: TextStyle(color: Colors.white.withValues(alpha: 0.25))),
          TextButton(
            onPressed: links[i].$2,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.85),
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
            ),
            child: Text(links[i].$1),
          ),
        ],
      ],
    );
    // The white-lettered logo, straight on the footer's navy, light theme
    // or dark.
    const logo = HealthProLogo(height: 60, onDark: true);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [BrandColors.navy, BrandColors.night],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: layout.wide ? 130 : 90,
            child: CustomPaint(
              painter: _MountainsPainter(
                far: Colors.white.withValues(alpha: 0.04),
                near: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: layout.wide ? 48 : 36, bottom: 22),
            child: Column(
              children: [
                _Frame(
                  layout: layout,
                  child: layout.medium
                      ? Row(children: [logo, const SizedBox(width: 24), Expanded(child: linkRow)])
                      : Column(children: [logo, const SizedBox(height: 18), linkRow]),
                ),
                SizedBox(height: layout.wide ? 56 : 40),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
                const SizedBox(height: 18),
                Text(
                  '© ${BhutanTime.today().year} Health Pro. All rights reserved.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: dim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Two ranges of mountains, [far] behind [near].
class _MountainsPainter extends CustomPainter {
  final Color far;
  final Color near;

  const _MountainsPainter({required this.far, required this.near});

  static const _far = [
    (0.0, 0.62),
    (0.07, 0.34),
    (0.14, 0.56),
    (0.23, 0.18),
    (0.32, 0.5),
    (0.41, 0.3),
    (0.5, 0.56),
    (0.6, 0.12),
    (0.7, 0.46),
    (0.79, 0.24),
    (0.89, 0.52),
    (1.0, 0.3),
  ];
  static const _near = [
    (0.0, 0.82),
    (0.1, 0.6),
    (0.2, 0.8),
    (0.3, 0.54),
    (0.42, 0.84),
    (0.55, 0.6),
    (0.66, 0.86),
    (0.78, 0.62),
    (0.9, 0.82),
    (1.0, 0.66),
  ];

  void _range(Canvas canvas, Size size, List<(double, double)> peaks, Color color) {
    final path = Path()..moveTo(0, size.height);
    for (final (x, y) in peaks) {
      path.lineTo(x * size.width, y * size.height);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _range(canvas, size, _far, far);
    _range(canvas, size, _near, near);
  }

  @override
  bool shouldRepaint(_MountainsPainter oldDelegate) => oldDelegate.far != far || oldDelegate.near != near;
}

// ─── Small parts ───────────────────────────────────────────────────────────

/// [text] with its last two words held together, so a line that wraps never
/// leaves one word alone.
String _noWidow(String text) {
  final at = text.lastIndexOf(' ');
  return at < 0 ? text : '${text.substring(0, at)} ${text.substring(at + 1)}';
}

/// [text] in the brand's orange, warming along the line: the part of a title
/// that promises.
class _AccentText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _AccentText(this.text, {required this.style});

  @override
  Widget build(BuildContext context) {
    final accent = context.brand.accentText;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        colors: [accent, Color.lerp(accent, context.brand.highlight, 0.5)!],
      ).createShader(bounds),
      child: Text(text, style: style),
    );
  }
}

/// Small capitals over a title, with orange rules before and/or after.
class _Eyebrow extends StatelessWidget {
  final String text;
  final bool lineBefore;
  final bool lineAfter;

  const _Eyebrow(this.text, {this.lineBefore = false, this.lineAfter = false});

  @override
  Widget build(BuildContext context) {
    final rule = Container(
      width: 34,
      height: 2.5,
      decoration: BoxDecoration(color: context.brand.highlight, borderRadius: BorderRadius.circular(2)),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lineBefore) ...[rule, const SizedBox(width: 10)],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              color: _Ink.of(context).heading,
            ),
          ),
        ),
        if (lineAfter) ...[const SizedBox(width: 10), rule],
      ],
    );
  }
}

/// A round-ended button: filled with [color] (the brand's orange unless
/// given) in [foreground] (navy unless given), or [outlined]. It gives a
/// little under a press, and its arrow nudges forward under the mouse.
class _PillButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool outlined;
  final Color? color;
  final Color foreground;

  /// Smaller, for the bar.
  final bool compact;

  const _PillButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
    this.color,
    this.foreground = BrandColors.navy,
    this.compact = false,
  });

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Pressable(child: _button(context)),
    );
  }

  Widget _button(BuildContext context) {
    final label = widget.label;
    final onPressed = widget.onPressed;
    final icon = widget.icon;
    final outlined = widget.outlined;
    final compact = widget.compact;
    final color = widget.color ?? context.brand.accent;
    final ink = _Ink.of(context);
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 18, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 26, vertical: 18);
    final minimumSize = compact ? const Size(0, 40) : const Size(0, 54);
    final textStyle = (Theme.of(context).textTheme.labelLarge ?? const TextStyle())
        .copyWith(fontSize: compact ? 14 : 16, fontWeight: FontWeight.w700);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (icon != null) ...[
          const SizedBox(width: 8),
          AnimatedSlide(
            offset: Offset(_hover && !reduceMotion(context) ? 0.2 : 0, 0),
            duration: Motion.hover,
            curve: Motion.ease,
            child: Icon(icon, size: 19),
          ),
        ],
      ],
    );
    if (outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: ink.heading,
          side: BorderSide(color: ink.heading, width: 1.4),
          shape: const StadiumBorder(),
          padding: padding,
          minimumSize: minimumSize,
          textStyle: textStyle,
        ),
        child: child,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          if (!compact)
            BoxShadow(
                color: color.withValues(alpha: ink.dark ? 0.35 : 0.26), blurRadius: ink.dark ? 20 : 16, offset: const Offset(0, 8)),
        ],
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: widget.foreground,
          shape: const StadiumBorder(),
          padding: padding,
          minimumSize: minimumSize,
          textStyle: textStyle,
        ),
        child: child,
      ),
    );
  }
}
