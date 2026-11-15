import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/brand.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/feedback.dart';
import '../widgets/logo.dart';
import 'person_qr.dart';

/// The signed-in person's Health Pro QR code, big, to show at the front desk
/// of any gym: it checks them in where they're a member, and lets a new gym
/// add them without their details being typed again. Members and trainers
/// start here, so it's one tap away.
class MyQrScreen extends ConsumerWidget {
  const MyQrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppPage(
      title: 'My QR code',
      maxWidth: AppPage.readableWidth,
      body: AsyncValueView<MyPerson?>(
        value: ref.watch(myPersonProvider),
        onRetry: () => ref.invalidate(myPersonProvider),
        data: (me) => me == null ? const SizedBox.shrink() : _MyQr(me: me),
      ),
    );
  }
}

class _MyQr extends ConsumerWidget {
  final MyPerson me;

  const _MyQr({required this.me});

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
    final muted = context.brand.muted;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              // White in both themes: scanners read dark on light.
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: context.brand.cardShadow,
              ),
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
              child: Column(
                children: [
                  const HealthProLogo(height: 44, onDark: false),
                  const SizedBox(height: 18),
                  Semantics(
                    label: 'Your Health Pro QR code',
                    image: true,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: QrImageView(
                        data: me.qrData,
                        padding: EdgeInsets.zero,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0B1530)),
                        dataModuleStyle:
                            const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF0B1530)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    me.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF17243B), fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Health Pro member',
                    style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        const InfoRow(
          icon: Icons.storefront_outlined,
          text: 'Show this at the front desk of any Health Pro gym. It checks you in where you\'re a member, '
              'and a new gym can add you without filling in your details again.',
        ),
        const InfoRow(
          icon: Icons.brightness_high_rounded,
          text: "If it doesn't scan, turn your screen's brightness up.",
        ),
        const InfoRow(
          icon: Icons.lock_outline_rounded,
          text: 'It holds no personal details. Keep it to yourself, like a key.',
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: () => _renew(context, ref),
            style: TextButton.styleFrom(foregroundColor: muted),
            icon: const Icon(Icons.autorenew_rounded, size: 18),
            label: const Text('Get a new QR code'),
          ),
        ),
      ],
    );
  }
}
