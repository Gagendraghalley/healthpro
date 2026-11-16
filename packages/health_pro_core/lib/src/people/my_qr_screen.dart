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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modules = ref.watch(enabledModulesProvider).valueOrNull ?? const <HealthProModule>[];
    final sections = [
      for (final m in modules)
        if (m.buildMemberDashboard(context) case final section?) section,
    ];
    final ink = ConsoleInk.of(context);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${greeting(BhutanTime.now())}, ${firstName(me.name)}',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: ink.heading, height: 1.2),
          ),
          const SizedBox(height: 4),
          Text(
            '${formatDate(BhutanTime.today())} · Your memberships, visits and updates in one place.',
            style: TextStyle(color: context.brand.muted, fontSize: 14.5),
          ),
        ],
      ),
    );
    const gap = SizedBox(height: 18);
    return ListView(
      padding: pagePadding(context),
      children: [
        FadeSlideIn(child: header),
        LayoutBuilder(
          builder: (context, constraints) {
            final pass = _QrPass(me: me);
            if (constraints.maxWidth < _besideFrom) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340), child: pass)),
                  for (final s in sections) ...[gap, s],
                  gap,
                  const _Updates(),
                  gap,
                  const _MyDetails(),
                  gap,
                  const _QrTips(),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 320,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [pass, gap, const _MyDetails(), gap, const _QrTips()],
                  ),
                ),
                const SizedBox(width: 22),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final s in sections) ...[s, gap],
                      const _Updates(),
                    ],
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

/// Their QR code as a small pass (the logo, the code, their name), and under
/// it what they can do with it: enlarge it for the scanner, copy, share or
/// save its picture.
class _QrPass extends StatefulWidget {
  final MyPerson me;

  const _QrPass({required this.me});

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
    return Container(
      // White in both themes: scanners read dark on light.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: context.brand.cardShadow,
      ),
      child: Column(
        children: [
          RepaintBoundary(
            key: _passKey,
            child: Container(
              color: Colors.white,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                children: [
                  const HealthProLogo(height: 36, onDark: false),
                  const SizedBox(height: 14),
                  Semantics(
                    label: 'Your Health Pro QR code',
                    image: true,
                    child: Tooltip(
                      message: 'Enlarge',
                      child: InkWell(onTap: _enlarge, child: SizedBox(width: 176, height: 176, child: _code(me))),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    me.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF17243B), fontSize: 17.5, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Health Pro member',
                    style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF5F7FB),
              border: Border(top: BorderSide(color: Color(0xFFE4E9F1))),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
        ],
      ),
    );
  }
}

/// One of the buttons under the pass: its icon over its name. Dark on the
/// pass's pale foot in both themes.
class _PassAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _PassAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? const Color(0xFF94A3B8) : const Color(0xFF17243B);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
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
    return ConsoleCard(
      icon: Icons.person_outline_rounded,
      title: 'My details',
      trailing: ConsoleLink(label: 'Edit', onPressed: () => context.go(CoreRoutes.editProfile)),
      child: Column(
        children: [
          _Detail(icon: Icons.badge_outlined, label: 'Name', value: profile.displayName),
          _Detail(icon: Icons.mail_outline_rounded, label: 'Email', value: profile.email),
          _Detail(icon: Icons.phone_outlined, label: 'Phone', value: profile.phone),
          _Detail(icon: Icons.place_outlined, label: 'Dzongkhag', value: profile.dzongkhag),
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
    final muted = context.brand.muted;
    final has = value != null && value!.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: ink.tint, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 17, color: muted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600)),
                Text(
                  has ? value!.trim() : 'Not added',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: has ? ink.heading : muted, fontWeight: has ? FontWeight.w700 : FontWeight.w500),
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
/// a request answered), newest first; all of them are behind the bell.
class _Updates extends ConsumerWidget {
  const _Updates();

  static const _shown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider).valueOrNull ?? const <AppNotification>[];
    final unread = ref.watch(unreadCountProvider);
    final muted = context.brand.muted;
    return ConsoleCard(
      icon: Icons.notifications_none_rounded,
      title: unread == 0 ? 'Latest updates' : 'Latest updates · $unread new',
      trailing: ConsoleLink(label: 'View all', onPressed: () => context.go(CoreRoutes.notifications)),
      child: items.isEmpty
          ? Text(
              'Nothing yet. Updates about your memberships, payments and requests to join show here.',
              style: TextStyle(color: muted, height: 1.4),
            )
          : Material(
              type: MaterialType.transparency,
              child: Column(children: [for (final item in items.take(_shown)) _UpdateRow(item: item)]),
            ),
    );
  }
}

class _UpdateRow extends ConsumerWidget {
  final AppNotification item;

  const _UpdateRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = ConsoleInk.of(context);
    final brand = context.brand;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (!item.isRead) ref.read(notificationRepositoryProvider).markRead(item.id).ignore();
        final link = item.link;
        if (link != null && link.startsWith('/')) context.push(link);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Icon(
                item.isRead ? Icons.circle_outlined : Icons.circle,
                size: 9,
                color: item.isRead ? brand.muted : brand.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ink.heading, fontWeight: item.isRead ? FontWeight.w600 : FontWeight.w800),
                  ),
                  if (item.body != null)
                    Text(
                      item.body!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: ink.body, fontSize: 13, height: 1.35),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(timeAgo(item.createdAt), style: TextStyle(color: brand.muted, fontSize: 12.5)),
          ],
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
    return ConsoleCard(
      icon: Icons.qr_code_2_rounded,
      title: 'Using your QR code',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InfoRow(
            icon: Icons.storefront_outlined,
            text: 'Show it at the front desk of any Health Pro gym. It checks you in where you\'re a member, '
                'and a new gym can add you without filling in your details again.',
          ),
          const InfoRow(
            icon: Icons.brightness_high_rounded,
            text: "If it doesn't scan, turn your screen's brightness up.",
          ),
          const InfoRow(
            icon: Icons.lock_outline_rounded,
            text: 'It holds no personal details. Share it only with people you trust: it works like a key.',
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _renew(context, ref),
              style: TextButton.styleFrom(foregroundColor: context.brand.muted),
              icon: const Icon(Icons.autorenew_rounded, size: 18),
              label: const Text('Get a new QR code'),
            ),
          ),
        ],
      ),
    );
  }
}
