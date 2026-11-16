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

  @override
  Widget build(BuildContext context) {
    return GymStaffPage(
      venueId: widget.venueId,
      title: 'Gym QR code',
      builder: (context, access) {
        final gym = access.venue;
        final link = gymJoinLink(gym.id);
        const ink = Color(0xFF0B1530);
        final poster = RepaintBoundary(
          key: _poster,
          child: Container(
            width: 340,
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const HealthProLogo(height: 46, onDark: false),
                const SizedBox(height: 14),
                Text(gym.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: ink, fontSize: 22, fontWeight: FontWeight.w800, fontFamily: brandFont)),
                const SizedBox(height: 4),
                const Text('Scan to join this gym',
                    style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600, fontFamily: brandFont)),
                const SizedBox(height: 16),
                QrImageView(
                  data: link,
                  size: 240,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: ink),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: ink),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Open your phone camera and point it here. Members: show your own Health Pro QR code at the desk.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF3A4860), fontSize: 12.5, height: 1.35, fontFamily: brandFont),
                ),
              ],
            ),
          ),
        );
        return AppPage(
          title: 'Gym QR code',
          body: ListView(
            padding: pagePadding(context),
            children: [
              ResponsiveColumns(
                first: [
                  Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), boxShadow: context.brand.cardShadow),
                      child: FittedBox(fit: BoxFit.scaleDown, child: poster),
                    ),
                  ),
                ],
                second: [
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _download(gym.name),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Download to print'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: link));
                          if (context.mounted) showFeedback(context, 'Link copied');
                        },
                        icon: const Icon(Icons.link_rounded),
                        label: const Text('Copy link'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (!gym.isVerified)
                    InfoRow(
                      icon: Icons.hourglass_top_rounded,
                      text: 'Requests start once the Health Pro team has checked ${gym.name}.',
                    ),
                  const InfoRow(
                    icon: Icons.notifications_active_outlined,
                    text: 'When someone asks to join, the front desk, managers and owner are told, and the request '
                        'waits under Join requests until someone adds or declines them.',
                  ),
                  const InfoRow(
                    icon: Icons.qr_code_scanner_rounded,
                    text: 'This code is for joining. Members check in with their own QR code, which the desk scans.',
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
