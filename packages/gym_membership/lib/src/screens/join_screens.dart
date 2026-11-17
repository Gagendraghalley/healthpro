import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_repository.dart';
import '../data/joining.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import '../widgets/gym_widgets.dart';

/// Requests to join, from the gym's QR code: people with Health Pro asked
/// to become members. The desk adds them (the registration form, filled in
/// from what they gave before, with the package they asked for) or declines,
/// and they're told either way.
class JoinRequestsScreen extends ConsumerWidget {
  final String venueId;

  const JoinRequestsScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GymStaffPage(
      venueId: venueId,
      title: 'Join requests',
      permission: GymPermission.register,
      builder: (context, access) {
        final requests = ref.watch(gymJoinRequestsProvider(venueId));
        return AppPage(
          title: 'Join requests',
          actions: [
            TextButton.icon(
              onPressed: () => context.go(GymRoutes.gymQrFor(venueId)),
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('Gym QR code'),
            ),
          ],
          body: AsyncValueView<List<JoinRequest>>(
            value: requests,
            onRetry: () => ref.invalidate(gymJoinRequestsProvider(venueId)),
            data: (list) {
              final waiting = list.where((r) => r.isPending).toList();
              final answered = list.where((r) => !r.isPending).take(30).toList();
              return RefreshIndicator(
                onRefresh: () => ref.refresh(gymJoinRequestsProvider(venueId).future),
                child: ListView(
                  padding: pagePadding(context),
                  children: [
                    if (waiting.isEmpty)
                      EmptyState(
                        icon: Icons.mark_email_read_outlined,
                        title: 'No one is waiting',
                        message: 'People with Health Pro scan your gym\'s QR code to ask to join. '
                            'Put it up at the desk or the entrance.',
                        actionLabel: 'Show the gym QR code',
                        onAction: () => context.go(GymRoutes.gymQrFor(venueId)),
                      )
                    else ...[
                      SectionTitle('Waiting (${waiting.length})'),
                      ResponsiveGrid(
                        minItemWidth: 340,
                        maxColumns: 3,
                        equalHeight: false,
                        children: [for (final r in waiting) _RequestCard(request: r, venueId: venueId)],
                      ),
                    ],
                    if (answered.isNotEmpty) ...[
                      const SectionTitle('Answered'),
                      SectionCard(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            for (final r in answered)
                              ListTile(
                                title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  [timeAgo(r.decidedAt ?? r.createdAt), if (r.decisionNote != null) r.decisionNote!]
                                      .join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: _StatusChip(status: r.status),
                                onTap: r.gymMemberId == null
                                    ? null
                                    : () => context.go(GymRoutes.memberFor(venueId, r.gymMemberId!)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _RequestCard extends ConsumerWidget {
  final JoinRequest request;
  final String venueId;

  const _RequestCard({required this.request, required this.venueId});

  Future<void> _decline(BuildContext context, WidgetRef ref) async {
    final note = await askText(
      context,
      title: 'Decline ${request.name}?',
      hint: 'Why, for them (optional): e.g. we\'re full until March',
      confirmLabel: 'Decline',
    );
    if (note == null || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(gymRepositoryProvider).declineJoinRequest(request.id, note: note),
      success: '${request.name} is told',
    );
    if (ok) refreshGym(ref, venueId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final contact = [if (request.phone != null) request.phone!, if (request.email != null) request.email!].join(' · ');
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: BrandColors.blue.withValues(alpha: 0.12),
                child: Text(
                  request.name.trim().isEmpty ? '?' : request.name.trim()[0].toUpperCase(),
                  style: const TextStyle(color: BrandColors.blue, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('Asked ${timeAgo(request.createdAt)}', style: TextStyle(color: brand.muted, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (contact.isNotEmpty) InfoRow(icon: Icons.contact_phone_outlined, text: contact),
          InfoRow(
            icon: Icons.sell_outlined,
            text: request.planName == null
                ? 'No package chosen yet'
                : 'Would like ${request.planName}${request.planPrice == null ? '' : ' (${formatNu(request.planPrice!)})'}',
          ),
          if (request.message != null) InfoRow(icon: Icons.chat_bubble_outline_rounded, text: '"${request.message}"'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.go(GymRoutes.addPersonFor(venueId, requestId: request.id)),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Add to gym'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => _decline(context, ref), child: const Text('Decline')),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final JoinRequestStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final color = switch (status) {
      JoinRequestStatus.approved => brand.success,
      JoinRequestStatus.declined => brand.danger,
      JoinRequestStatus.pending => brand.warning,
      JoinRequestStatus.cancelled => brand.muted,
    };
    return StatusChip(label: status.label, color: color);
  }
}

/// The address a gym's QR code opens: its public page, asking to join.
/// The website's own address in a browser.
String gymJoinLink(String venueId) {
  final base = Uri.base;
  final origin = base.hasScheme && base.scheme.startsWith('http') ? '${base.origin}${base.path}' : 'https://sporthubs.pages.dev/';
  return '$origin#${GymRoutes.gymJoinFor(venueId)}';
}

/// The gym's QR code, to print and put up at the desk or entrance. Scanned
/// with any phone camera, it opens the gym's page on Health Pro, where
/// people with an account ask to join.
class GymQrScreen extends ConsumerStatefulWidget {
  final String venueId;

  const GymQrScreen({super.key, required this.venueId});

  @override
  ConsumerState<GymQrScreen> createState() => _GymQrScreenState();
}

class _GymQrScreenState extends ConsumerState<GymQrScreen> {
  final _poster = GlobalKey();

  Future<Uint8List> _picture() async {
    final boundary = _poster.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 4);
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> _download(String gymName) async {
    await runAction(context, () async {
      final name = '${gymName.trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}-QR.png';
      await XFile.fromData(await _picture(), mimeType: 'image/png', name: name).saveTo(name);
    }, success: 'Saved: print it and put it up');
  }

  Future<void> _copy(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) showFeedback(context, 'Link copied');
  }

  @override
  Widget build(BuildContext context) {
    return GymStaffPage(
      venueId: widget.venueId,
      title: 'Gym QR code',
      builder: (context, access) {
        final gym = access.venue;
        final link = gymJoinLink(gym.id);
        final brand = context.brand;
        final ink = ConsoleInk.of(context);
        return AppPage(
          title: 'Gym QR code',
          body: ListView(
            padding: pagePadding(context),
            children: [
              ResponsiveColumns(
                flex: (5, 6),
                first: [
                  FadeSlideIn(
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            ...brand.cardShadow,
                            BoxShadow(color: brand.pick(const Color(0x12142B52), const Color(0x33000000)), blurRadius: 32, offset: const Offset(0, 10)),
                          ],
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: RepaintBoundary(key: _poster, child: _GymPoster(gym: gym, link: link, accent: brand.highlight)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                second: [
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 80),
                    child: ConsoleCard(
                      icon: Icons.ios_share_rounded,
                      title: 'Share this code',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Print it for the front desk or the entrance, or send the link to people who want to join.',
                              style: TextStyle(color: ink.body, height: 1.45)),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: ink.tint,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: brand.fieldBorder),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.link_rounded, size: 18, color: brand.muted),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(link,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: ink.body, fontSize: 13.5, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(builder: (context, constraints) {
                            final download = FilledButton.icon(
                              onPressed: () => _download(gym.name),
                              icon: const Icon(Icons.download_rounded),
                              label: const Text('Download to print'),
                            );
                            final copy = OutlinedButton.icon(
                              onPressed: () => _copy(link),
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              label: const Text('Copy link'),
                            );
                            // Side by side when they fit, one above the other, full width, on a phone.
                            if (constraints.maxWidth < 380) {
                              return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [download, const SizedBox(height: 10), copy]);
                            }
                            return Row(children: [download, const SizedBox(width: 10), copy]);
                          }),
                        ],
                      ),
                    ),
                  ),
                  if (!gym.isVerified) ...[
                    const SizedBox(height: 16),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 120),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: brand.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: brand.warning.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.hourglass_top_rounded, size: 20, color: brand.readable(brand.warning)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text('Requests start once the Health Pro team has checked ${gym.name}.',
                                  style: TextStyle(color: ink.heading, fontWeight: FontWeight.w600, height: 1.4)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 160),
                    child: ConsoleCard(
                      icon: Icons.tips_and_updates_outlined,
                      title: 'How it works',
                      child: Column(
                        children: [
                          const SettingRow(
                            icon: Icons.print_outlined,
                            title: 'Put it up',
                            subtitle: 'Print it and place it at the front desk or the entrance. Any phone camera can scan it.',
                          ),
                          const SettingRow(
                            icon: Icons.notifications_active_outlined,
                            title: 'Your team is told',
                            subtitle: 'When someone asks to join, the front desk, managers and owner are told, and the request '
                                'waits under Join requests until someone adds or declines them.',
                          ),
                          SettingRow(
                            icon: Icons.qr_code_scanner_rounded,
                            title: 'For joining, not check-in',
                            subtitle: 'Members check in with their own QR code, which the desk scans.',
                            color: brand.success,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The poster that's downloaded and printed: always light, whatever the
/// theme, in the gym's [accent] (the colour they picked, orange until then).
class _GymPoster extends StatelessWidget {
  final Venue gym;
  final String link;
  final Color accent;

  const _GymPoster({required this.gym, required this.link, required this.accent});

  static const _ink = Color(0xFF0B1530);

  @override
  Widget build(BuildContext context) {
    final accentText = Color.lerp(accent, LightColors.ink, 0.34)!;
    final place = gym.place.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: 360,
        color: Colors.white,
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: LightColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [BrandColors.navy, LightColors.navy],
                ),
              ),
              child: const Center(child: HealthProLogo(height: 50, onDark: true, animate: false)),
            ),
            Container(height: 4, color: accent),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 0),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
                    child: Text('SCAN TO JOIN',
                        style: TextStyle(
                            color: accentText, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.6, fontFamily: brandFont)),
                  ),
                  const SizedBox(height: 12),
                  Text(gym.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _ink, fontSize: 25, height: 1.15, letterSpacing: -0.3, fontWeight: FontWeight.w800, fontFamily: brandFont)),
                  if (place.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.place_outlined, size: 15, color: LightColors.muted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(place,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: LightColors.muted, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: brandFont)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  CustomPaint(
                    painter: _ScanCorners(accent),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // H keeps it readable with the mark over the middle.
                          QrImageView(
                            data: link,
                            size: 220,
                            padding: EdgeInsets.zero,
                            errorCorrectionLevel: QrErrorCorrectLevel.H,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _ink),
                            dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _ink),
                          ),
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                            child: const HealthProLogo(height: 36, markOnly: true, onDark: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, (icon, label)) in const [
                        (Icons.photo_camera_outlined, 'Open your\ncamera'),
                        (Icons.center_focus_strong_outlined, 'Point it at\nthis code'),
                        (Icons.how_to_reg_outlined, 'Ask to join\nthe gym'),
                      ].indexed)
                        Expanded(
                          child: Column(
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
                                    child: Icon(icon, size: 19, color: accentText),
                                  ),
                                  Positioned(
                                    top: -3,
                                    right: -5,
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: accentText,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                      child: Text('${i + 1}',
                                          style: const TextStyle(
                                              color: Colors.white, fontSize: 9, height: 1, fontWeight: FontWeight.w800, fontFamily: brandFont)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(label,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: _ink, fontSize: 11.5, height: 1.3, fontWeight: FontWeight.w700, fontFamily: brandFont)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              color: LightColors.background,
              padding: const EdgeInsets.fromLTRB(22, 13, 22, 15),
              child: Row(
                children: [
                  Icon(Icons.qr_code_2_rounded, size: 22, color: accentText),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: 'Already a member? ', style: TextStyle(color: _ink, fontWeight: FontWeight.w800)),
                        TextSpan(text: 'Show your own Health Pro QR code at the desk to check in.'),
                      ]),
                      style: TextStyle(color: LightColors.body, fontSize: 11.5, height: 1.35, fontFamily: brandFont),
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

/// A scanner's four corner brackets around the code.
class _ScanCorners extends CustomPainter {
  final Color color;

  const _ScanCorners(this.color);

  static const _arm = 30.0;
  static const _radius = 12.0;
  static const _stroke = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    final corner = Path()
      ..moveTo(0, _arm)
      ..lineTo(0, _radius)
      ..arcToPoint(const Offset(_radius, 0), radius: const Radius.circular(_radius))
      ..lineTo(_arm, 0);
    const inset = _stroke / 2;
    for (final (right, bottom) in const [(false, false), (true, false), (false, true), (true, true)]) {
      canvas
        ..save()
        ..translate(right ? size.width - inset : inset, bottom ? size.height - inset : inset)
        ..scale(right ? -1 : 1, bottom ? -1 : 1)
        ..drawPath(corner, paint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ScanCorners old) => old.color != color;
}
