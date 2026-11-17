import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:clipboard/clipboard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../module/health_pro_module.dart';
import '../module/module_providers.dart';
import '../notifications/app_notification.dart';
import '../notifications/notification_repository.dart';
import '../profiles/profile_repository.dart';
import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../utils/bhutan_time.dart';
import '../utils/formatters.dart';
import '../utils/friendly_error.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/dashboard_kit.dart';
import '../widgets/feedback.dart';
import '../widgets/logo.dart';
import '../widgets/motion.dart';
import '../widgets/welcome_band.dart';
import 'person_qr.dart';

/// The signed-in person's own dashboard, where members and trainers start,
/// for their own reference: their Health Pro QR code (to show at the front
/// desk of any gym, enlarge, copy, share or save), their details, what each
/// service keeps for them ([HealthProModule.buildMemberDashboard]: their
/// gyms, packages and visits) and their latest updates.
class MyQrScreen extends ConsumerWidget {
  const MyQrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppPage(
      title: 'My dashboard',
      body: AsyncValueView<MyPerson?>(
        value: ref.watch(myPersonProvider),
        onRetry: () => ref.invalidate(myPersonProvider),
        data: (me) => me == null ? const SizedBox.shrink() : _Dashboard(me: me),
      ),
    );
  }
}

class _Dashboard extends ConsumerWidget {
  final MyPerson me;

  const _Dashboard({required this.me});

  /// From this width the QR code stays at the side, the rest beside it.
  static const _besideFrom = 1000.0;

  /// [items] arriving one after another from [from], a gap between them.
  static List<Widget> _arriving(List<Widget> items, {Duration from = Duration.zero}) => [
        for (final (i, item) in items.indexed) ...[
          if (i > 0) const SizedBox(height: 20),
          FadeSlideIn(delay: from + Motion.stagger * 1.3 * math.min(i, 6), child: item),
        ],
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modules = ref.watch(enabledModulesProvider).valueOrNull ?? const <HealthProModule>[];
    final sections = [
      for (final m in modules)
        if (m.buildMemberDashboard(context) case final section?) section,
    ];
    const start = Duration(milliseconds: 120);
    final deep = DeepTone.of(context);
    return ListView(
      padding: pagePadding(context),
      children: [
        FadeSlideIn(child: _Hero(me: me)),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final pass = _QrPass(me: me, deep: deep);
            if (constraints.maxWidth < _besideFrom) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _arriving(from: start, [
                  Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: pass)),
                  ...sections,
                  const _Updates(),
                  const _MyDetails(),
                  const _QrTips(),
                ]),
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 330,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _arriving(from: start, [pass, const _MyDetails(), const _QrTips()]),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _arriving(from: start + Motion.stagger, [...sections, const _Updates()]),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// The top of their dashboard: the deep band with their initial, today's
/// date, the greeting, and how many of their updates are new (a tap opens
/// them all).
class _Hero extends ConsumerWidget {
  final MyPerson me;

  const _Hero({required this.me});

  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    final now = BhutanTime.now();
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return WelcomeBand(
      eyebrow: '${_weekdays[now.weekday - 1]}, ${formatDate(now)}',
      title: '${greeting(now)}, ${firstName(me.name)}',
      subtitle: 'Your memberships, visits and updates in one place.',
      leading: BandAvatar(initial: BandAvatar.initialOf(me.name), size: wide ? 68 : 52),
      trailing: BandPill(
        icon: unread == 0 ? Icons.notifications_none_rounded : Icons.notifications_active_rounded,
        label: switch (unread) { 0 => 'All caught up', 1 => '1 new update', _ => '$unread new updates' },
        dot: unread > 0,
        onTap: () => context.go(CoreRoutes.notifications),
      ),
    );
  }
}

/// Their QR code as a membership pass (the logo, the code on a white
/// plate, their name), and under it what they can do with it: enlarge it
/// for the scanner, copy, share or save its picture.
class _QrPass extends StatefulWidget {
  final MyPerson me;
  final DeepTone deep;

  const _QrPass({required this.me, required this.deep});

  @override
  State<_QrPass> createState() => _QrPassState();
}

class _QrPassState extends State<_QrPass> {
  /// Around the pass alone (not its buttons): what's copied, shared, saved.
  final _passKey = GlobalKey();
  bool _busy = false;

  static const _ink = Color(0xFF0B1530);

  String get _fileName =>
      'Health-Pro-QR-${widget.me.name.trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}.png';

  /// The pass's picture, as a PNG four times its size on screen.
  Future<Uint8List> _picture() async {
    final boundary = _passKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 4);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> _with(Future<void> Function(Uint8List png) act, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await act(await _picture());
      if (mounted && done != null) showFeedback(context, done);
    } catch (e) {
      if (mounted) showFeedback(context, friendlyError(e), problem: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(Uint8List png) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(png, mimeType: 'image/png', name: _fileName)],
      fileNameOverrides: [_fileName],
      subject: 'My Health Pro QR code',
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
  }

  void _enlarge() {
    showAppDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const HealthProLogo(height: 44, onDark: false),
                const SizedBox(height: 16),
                AspectRatio(aspectRatio: 1, child: _code(widget.me)),
                const SizedBox(height: 16),
                Text(
                  widget.me.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF17243B), fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                const Text('Show this at the front desk', style: TextStyle(color: Color(0xFF64748B))),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: _ink),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _code(MyPerson me) => QrImageView(
        data: me.qrData,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _ink),
        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _ink),
      );

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    final deep = widget.deep;
    final brand = context.brand;
    final faint = Colors.white.withValues(alpha: 0.7);
    // Deep in both themes, the code on white: scanners read dark on light.
    final pass = RepaintBoundary(
      key: _passKey,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(gradient: deep.gradient),
        child: Stack(
          children: [
            Positioned(right: -70, top: -80, child: SoftGlow(color: brand.highlight, size: 220, strength: 0.38)),
            Positioned(left: -80, bottom: -110, child: SoftGlow(color: deep.glow, size: 240, strength: 0.24)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      const HealthProLogo(height: 30, onDark: true),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          'MEMBER PASS',
                          style: TextStyle(color: faint, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Semantics(
                    label: 'Your Health Pro QR code',
                    image: true,
                    child: Tooltip(
                      message: 'Enlarge',
                      child: _QrPlate(onTap: _enlarge, child: SizedBox(width: 176, height: 176, child: _code(me))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    me.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_rounded, size: 15, color: brand.highlight),
                      const SizedBox(width: 5),
                      Text('Health Pro member', style: TextStyle(color: faint, fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return _PassFrame(
      shadow: deep.base,
      child: Column(
        children: [
          pass,
          DecoratedBox(
            decoration: BoxDecoration(
              color: deep.shade,
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
              child: Material(
                type: MaterialType.transparency,
                child: Row(
                  children: [
                    _PassAction(icon: Icons.zoom_out_map_rounded, label: 'Enlarge', onTap: _enlarge),
                    _PassAction(
                      icon: Icons.copy_rounded,
                      label: 'Copy',
                      onTap: _busy ? null : () => _with(FlutterClipboard.copyImage, done: 'QR code copied'),
                    ),
                    _PassAction(icon: Icons.ios_share_rounded, label: 'Share', onTap: _busy ? null : () => _with(_share)),
                    _PassAction(
                      icon: Icons.download_rounded,
                      label: 'Save',
                      onTap: _busy
                          ? null
                          : () => _with(
                                (png) => XFile.fromData(png, mimeType: 'image/png', name: _fileName).saveTo(_fileName),
                                done: 'QR code saved',
                              ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The pass's frame: rounded, with a deep shadow. A sheen passes over it
/// once when it shows and again under the mouse, where it also leans a
/// little toward the pointer. Still when motion is reduced.
class _PassFrame extends StatefulWidget {
  final Widget child;

  /// The pass's colour, for its shadow.
  final Color shadow;

  const _PassFrame({required this.child, required this.shadow});

  @override
  State<_PassFrame> createState() => _PassFrameState();
}

class _PassFrameState extends State<_PassFrame> with SingleTickerProviderStateMixin {
  late final AnimationController _sheen = AnimationController(vsync: this, duration: Motion.chart * 1.6);

  /// The first stretch is the wait before the first sheen.
  late final Animation<double> _t =
      CurvedAnimation(parent: _sheen, curve: const Interval(_wait, 1, curve: Curves.easeInOut));
  static const _wait = 0.35;

  /// Where the pointer is, -1 to 1 across and down; zero at rest.
  Offset _lean = Offset.zero;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!reduceMotion(context)) _sheen.forward();
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  void _follow(PointerEvent e) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    setState(() => _lean = Offset(
          (e.localPosition.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
          (e.localPosition.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
        ));
  }

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(24));
    final motion = !reduceMotion(context);
    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: widget.shadow.withValues(alpha: 0.3),
            blurRadius: 36,
            spreadRadius: -8,
            offset: const Offset(0, 20),
          ),
          BoxShadow(
            color: context.brand.highlight.withValues(alpha: 0.1),
            blurRadius: 40,
            spreadRadius: -12,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            widget.child,
            if (motion)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _t,
                    builder: (context, _) => CustomPaint(painter: _Sheen(_t.value)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (!motion) return card;
    return MouseRegion(
      onEnter: (_) {
        if (!_sheen.isAnimating) _sheen.forward(from: _wait);
      },
      onHover: _follow,
      onExit: (_) => setState(() => _lean = Offset.zero),
      child: TweenAnimationBuilder<Offset>(
        tween: Tween(end: _lean),
        duration: Motion.page,
        curve: Motion.ease,
        builder: (context, lean, child) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateX(-lean.dy * 0.05)
            ..rotateY(lean.dx * 0.05),
          child: child,
        ),
        child: card,
      ),
    );
  }
}

/// A band of light crossing the pass from top left to bottom right, [t]
/// (0 to 1) of the way.
class _Sheen extends CustomPainter {
  final double t;

  const _Sheen(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final at = -0.2 + 1.4 * t;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0),
          ],
          stops: [(at - 0.14).clamp(0.0, 1.0), at.clamp(0.0, 1.0), (at + 0.14).clamp(0.0, 1.0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_Sheen old) => old.t != t;
}

/// The code on its white plate, bright corners around it like a scanner's
/// frame. It grows a little under the mouse; a scan line passes over it
/// once when it first shows. A tap enlarges it.
class _QrPlate extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _QrPlate({required this.child, required this.onTap});

  @override
  State<_QrPlate> createState() => _QrPlateState();
}

class _QrPlateState extends State<_QrPlate> with SingleTickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(vsync: this, duration: Motion.chart * 2);
  late final Animation<double> _t =
      CurvedAnimation(parent: _scan, curve: const Interval(0.3, 1, curve: Curves.easeInOutCubic));
  bool _hover = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!reduceMotion(context)) _scan.forward();
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final motion = !reduceMotion(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hover && motion ? 1.035 : 1,
          duration: Motion.hover,
          curve: Motion.ease,
          child: CustomPaint(
            foregroundPainter: _Corners(color: brand.highlight),
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 22, offset: const Offset(0, 10)),
                  ],
                ),
                child: Stack(
                  children: [
                    widget.child,
                    if (motion)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _t,
                            builder: (context, _) => CustomPaint(painter: _ScanLine(t: _t.value, color: brand.highlight)),
                          ),
                        ),
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

/// Rounded corner brackets around the plate.
class _Corners extends CustomPainter {
  final Color color;

  const _Corners({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const len = 26.0;
    const r = 18.0;
    const a = 1.5;
    final w = size.width - a;
    final h = size.height - a;
    final path = Path()
      ..moveTo(a, a + len)
      ..lineTo(a, a + r)
      ..arcToPoint(const Offset(a + r, a), radius: const Radius.circular(r))
      ..lineTo(a + len, a)
      ..moveTo(w - len, a)
      ..lineTo(w - r, a)
      ..arcToPoint(Offset(w, a + r), radius: const Radius.circular(r))
      ..lineTo(w, a + len)
      ..moveTo(w, h - len)
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: const Radius.circular(r))
      ..lineTo(w - len, h)
      ..moveTo(a + len, h)
      ..lineTo(a + r, h)
      ..arcToPoint(Offset(a, h - r), radius: const Radius.circular(r))
      ..lineTo(a, h - len);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_Corners old) => old.color != color;
}

/// A scanner's line [t] (0 to 1) of the way down, a soft trail above it;
/// nothing before it starts or once it's done.
class _ScanLine extends CustomPainter {
  final double t;
  final Color color;

  const _ScanLine({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final fade = math.sin(math.pi * t);
    final y = size.height * t;
    final trail = Rect.fromLTRB(0, math.max(0, y - 28), size.width, y);
    canvas.drawRect(
      trail,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.22 * fade)],
        ).createShader(trail),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, y - 1, size.width, 2.5), const Radius.circular(2)),
      Paint()..color = color.withValues(alpha: 0.9 * fade),
    );
  }

  @override
  bool shouldRepaint(_ScanLine old) => old.t != t || old.color != color;
}

/// One of the buttons under the pass: its icon in a glassy circle that
/// lights up under the mouse, over its name.
class _PassAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _PassAction({required this.icon, required this.label, required this.onTap});

  @override
  State<_PassAction> createState() => _PassActionState();
}

class _PassActionState extends State<_PassAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.onTap != null;
    final lit = _hover && on;
    final highlight = context.brand.highlight;
    final fg = Colors.white.withValues(alpha: on ? 1 : 0.35);
    return Expanded(
      child: Pressable(
        enabled: on,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (v) => setState(() => _hover = v),
          borderRadius: BorderRadius.circular(14),
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.white.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: Motion.hover,
                  curve: Motion.ease,
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: lit ? highlight : Colors.white.withValues(alpha: 0.08),
                    border: Border.all(color: Colors.white.withValues(alpha: lit ? 0 : 0.12)),
                    boxShadow: [
                      BoxShadow(
                        color: highlight.withValues(alpha: lit ? 0.4 : 0),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Icon(widget.icon, size: 19, color: fg),
                ),
                const SizedBox(height: 7),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: on ? 0.85 : 0.35),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

/// What Health Pro knows them by: their name, email, phone and dzongkhag,
/// and the way to change them.
class _MyDetails extends ConsumerWidget {
  const _MyDetails();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).valueOrNull;
    if (profile == null) return const SizedBox.shrink();
    final rows = [
      _Detail(icon: Icons.badge_outlined, label: 'Name', value: profile.displayName),
      _Detail(icon: Icons.mail_outline_rounded, label: 'Email', value: profile.email),
      _Detail(icon: Icons.phone_outlined, label: 'Phone', value: profile.phone),
      _Detail(icon: Icons.place_outlined, label: 'Dzongkhag', value: profile.dzongkhag),
    ];
    return ConsoleCard(
      icon: Icons.person_outline_rounded,
      title: 'My details',
      trailing: ConsoleLink(label: 'Edit', onPressed: () => context.go(CoreRoutes.editProfile)),
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: context.brand.glassBorder),
            row,
          ],
        ],
      ),
    );
  }
}

/// A detail: what it is, small, over its value ('Not added' in grey without
/// one).
class _Detail extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;

  const _Detail({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    final brand = context.brand;
    final has = value != null && value!.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: brand.accent.withValues(alpha: ink.dark ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 18, color: ink.dark ? brand.accent : brand.accentText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: brand.muted, fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.2),
                ),
                const SizedBox(height: 1),
                Text(
                  has ? value!.trim() : 'Not added',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: has ? ink.heading : brand.muted,
                    fontSize: 14.5,
                    fontWeight: has ? FontWeight.w700 : FontWeight.w500,
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

/// Their latest notifications (a membership activated, a payment confirmed,
/// a request answered), newest first, on a timeline; all of them are behind
/// the bell.
class _Updates extends ConsumerWidget {
  const _Updates();

  static const _shown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider).valueOrNull ?? const <AppNotification>[];
    final unread = ref.watch(unreadCountProvider);
    final brand = context.brand;
    final ink = ConsoleInk.of(context);
    final shown = items.take(_shown).toList();
    return ConsoleCard(
      icon: Icons.notifications_none_rounded,
      title: 'Latest updates',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (unread > 0)
            PopIn(
              delay: const Duration(milliseconds: 300),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: brand.accent.withValues(alpha: ink.dark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$unread new',
                  style: TextStyle(color: brand.accentText, fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          const SizedBox(width: 6),
          ConsoleLink(label: 'View all', onPressed: () => context.go(CoreRoutes.notifications)),
        ],
      ),
      child: items.isEmpty
          ? Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: ink.tint, shape: BoxShape.circle),
                  child: Icon(Icons.notifications_paused_outlined, color: brand.muted, size: 21),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Nothing yet. Updates about your memberships, payments and requests to join show here.',
                    style: TextStyle(color: brand.muted, height: 1.4),
                  ),
                ),
              ],
            )
          : Material(
              type: MaterialType.transparency,
              child: Column(
                children: staggered(offset: 12, [
                  for (final (i, item) in shown.indexed)
                    _UpdateRow(item: item, first: i == 0, last: i == shown.length - 1),
                ]),
              ),
            ),
    );
  }
}

/// An update on the timeline: its dot (bright while unread) on the line,
/// what happened, and when. A tap marks it read and opens what it's about.
class _UpdateRow extends ConsumerWidget {
  final AppNotification item;
  final bool first;
  final bool last;

  const _UpdateRow({required this.item, required this.first, required this.last});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = ConsoleInk.of(context);
    final brand = context.brand;
    final unread = !item.isRead;
    final line = brand.glassBorder;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        if (unread) ref.read(notificationRepositoryProvider).markRead(item.id).ignore();
        final link = item.link;
        if (link != null && link.startsWith('/')) context.push(link);
      },
      child: Ink(
        decoration: BoxDecoration(
          color: unread ? brand.accent.withValues(alpha: ink.dark ? 0.08 : 0.045) : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 34,
                child: Column(
                  children: [
                    Container(width: 2, height: 15, color: first ? Colors.transparent : line),
                    unread
                        ? Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(
                              color: brand.accent,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: brand.accent.withValues(alpha: 0.22), spreadRadius: 4)],
                            ),
                          )
                        : Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(
                              color: ink.card,
                              shape: BoxShape.circle,
                              border: Border.all(color: brand.muted.withValues(alpha: 0.55), width: 2),
                            ),
                          ),
                    Expanded(child: Container(width: 2, color: last ? Colors.transparent : line)),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 10, 4, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: ink.heading, fontWeight: unread ? FontWeight.w800 : FontWeight.w700),
                      ),
                      if (item.body != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.body!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: ink.body, fontSize: 13, height: 1.4),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 10, 0),
                child: Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: ink.tint, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      timeAgo(item.createdAt),
                      style: TextStyle(color: brand.muted, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How the QR code works, and getting a new one.
class _QrTips extends ConsumerWidget {
  const _QrTips();

  Future<void> _renew(BuildContext context, WidgetRef ref) async {
    final sure = await confirmAction(
      context,
      title: 'Get a new QR code?',
      message: 'Your current QR code, and any card printed with it, stops working at every gym. '
          'Do this if someone else has a copy of it.',
      confirmLabel: 'New QR code',
      destructive: true,
    );
    if (!sure || !context.mounted) return;
    await runAction(context, () => renewMyQr(ref), success: 'Your new QR code is ready');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = ConsoleInk.of(context);
    return ConsoleCard(
      icon: Icons.qr_code_2_rounded,
      title: 'Using your QR code',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Tip(
            icon: Icons.storefront_outlined,
            text: 'Show it at the front desk of any Health Pro gym. It checks you in where you\'re a member, '
                'and a new gym can add you without filling in your details again.',
          ),
          const SizedBox(height: 12),
          const _Tip(icon: Icons.brightness_high_rounded, text: "If it doesn't scan, turn your screen's brightness up."),
          const SizedBox(height: 12),
          const _Tip(
            icon: Icons.lock_outline_rounded,
            text: 'It holds no personal details. Share it only with people you trust: it works like a key.',
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _renew(context, ref),
              style: OutlinedButton.styleFrom(
                foregroundColor: ink.heading,
                side: BorderSide(color: context.brand.fieldBorder),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.autorenew_rounded, size: 18),
              label: const Text('Get a new QR code'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tip: its icon in a soft square, beside the words.
class _Tip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Tip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: ink.tint, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 17, color: context.brand.muted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(text, style: TextStyle(color: ink.body, fontSize: 13.5, height: 1.45)),
          ),
        ),
      ],
    );
  }
}
