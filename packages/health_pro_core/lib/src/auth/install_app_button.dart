import 'package:flutter/material.dart';

import '../pwa/pwa_stub.dart' if (dart.library.js_interop) '../pwa/pwa_web.dart';
import '../theme/brand.dart';
import '../widgets/feedback.dart';
import 'auth_layout.dart';

/// Install app, on the sign-in page: Health Pro is a web app people put on
/// their home screen, where it opens full screen with its own icon (and, on
/// an iPhone, can send notifications).
///
/// - Android, and Chrome or Edge on a computer: the browser's own install
///   window, in one tap.
/// - iPhone and iPad: Safari can't be asked to install, so the steps (Share,
///   Add to Home Screen, Add).
/// - Installed already, or a browser that can't: nothing.
class InstallAppButton extends StatefulWidget {
  const InstallAppButton({super.key});

  @override
  State<InstallAppButton> createState() => _InstallAppButtonState();
}

class _InstallAppButtonState extends State<InstallAppButton> {
  @override
  void initState() {
    super.initState();
    PwaInstall.listen();
  }

  Future<void> _install() async {
    if (PwaInstall.canPrompt) {
      final outcome = await PwaInstall.prompt();
      if (mounted && outcome == 'accepted') showFeedback(context, 'Health Pro is on your home screen');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const _IosSteps(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: PwaInstall.changes,
      builder: (context, _, __) {
        if (PwaInstall.isInstalled || !(PwaInstall.canPrompt || PwaInstall.isIos)) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthSecondaryButton(label: 'Install app', icon: Icons.install_mobile_rounded, onPressed: _install),
              const SizedBox(height: 6),
              Text(
                'Put Health Pro on your home screen: it opens full screen, like an app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.brand.muted, fontSize: 12.5),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// How to install on an iPhone or iPad, in Safari.
class _IosSteps extends StatelessWidget {
  const _IosSteps();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    Widget step(int n, IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: brand.accent.withValues(alpha: 0.14),
                child: Text('$n', style: TextStyle(color: brand.accent, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Icon(icon, color: brand.ink),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.35))),
            ],
          ),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Install Health Pro', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('In Safari, three taps:', style: TextStyle(color: brand.muted)),
            const SizedBox(height: 18),
            step(1, Icons.ios_share_rounded, 'Tap Share, at the bottom of the screen (at the top on an iPad).'),
            step(2, Icons.add_box_outlined, 'Scroll down and tap Add to Home Screen.'),
            step(3, Icons.check_circle_outline_rounded, 'Tap Add.'),
            Text(
              'Then open Health Pro from your home screen. Notifications work from there (iOS 16.4 or later).',
              style: TextStyle(color: brand.muted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Got it')),
            ),
          ],
        ),
      ),
    );
  }
}
