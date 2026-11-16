import 'package:flutter/material.dart';

import '../pwa/pwa_stub.dart' if (dart.library.js_interop) '../pwa/pwa_web.dart';
import '../theme/brand.dart';
import '../theme/phone_size.dart';
import '../widgets/feedback.dart';
import 'auth_layout.dart';

/// Install app, at the top of the sign-in card (above the email): Health Pro
/// is a web app people put on
/// their home screen, where it opens full screen with its own icon (and, on
/// an iPhone, can send notifications). It's there until Health Pro is
/// installed (opened from the home screen, or installed from this browser).
///
/// - Android, and Chrome or Edge on a computer, once the browser offers to
///   install: its own install window, in one tap.
/// - Otherwise (an iPhone or iPad, Safari on a Mac, or a browser that hasn't
///   offered yet): the steps for this browser.
/// - The phone apps: nothing (they're installed already).
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
      if (outcome != 'unavailable') return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => InstallSteps(browser: InstallBrowser.from(PwaInstall.browser)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: PwaInstall.changes,
      builder: (context, _, __) {
        if (PwaInstall.isInstalled) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
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

/// The browser Health Pro is open in, for the steps to install it by hand
/// (PwaInstall.browser).
enum InstallBrowser {
  /// Safari on an iPhone or iPad, Chrome there, and the others there (they
  /// all add to the home screen from the Share menu).
  ios,
  iosChrome,
  iosOther,

  /// Chrome, Edge and the like on Android.
  android,
  samsung,
  androidFirefox,

  /// On a computer.
  chrome,
  edge,
  macSafari,

  /// Firefox on a computer: it can't install apps.
  firefox,
  other;

  static InstallBrowser from(String name) => switch (name) {
        'ios' => ios,
        'ios-chrome' => iosChrome,
        'ios-other' => iosOther,
        'android' => android,
        'samsung' => samsung,
        'android-firefox' => androidFirefox,
        'chrome' => chrome,
        'edge' => edge,
        'mac-safari' => macSafari,
        'firefox' => firefox,
        _ => other,
      };

  /// Where the steps are, what to tap, and what to know after.
  ({String where, List<(IconData, String)> steps, String? after}) get guide => switch (this) {
        ios => (
            where: 'In Safari, three taps:',
            steps: [
              (Icons.ios_share_rounded, 'Tap Share. Don\'t see it? Tap ••• beside the address first.'),
              (Icons.add_box_outlined, 'Scroll down and tap Add to Home Screen.'),
              (Icons.check_circle_outline_rounded, 'Tap Add.'),
            ],
            after: 'Then open Health Pro from your home screen. Notifications work from there (iOS 16.4 or later).',
          ),
        iosChrome => (
            where: 'In Chrome, three taps:',
            steps: [
              (Icons.ios_share_rounded, 'Tap Share, in the address bar.'),
              (Icons.add_box_outlined, 'Scroll down and tap Add to Home Screen.'),
              (Icons.check_circle_outline_rounded, 'Tap Add.'),
            ],
            after: 'Then open Health Pro from your home screen. Needs iOS 16.4 or later; on an older iPhone, use '
                'Safari.',
          ),
        iosOther => (
            where: 'In your browser:',
            steps: [
              (Icons.menu_rounded, 'Open its menu (☰ in Firefox, ••• in Edge) and tap Share.'),
              (Icons.add_box_outlined, 'Tap Add to Home Screen.'),
              (Icons.check_circle_outline_rounded, 'Tap Add.'),
            ],
            after: 'Needs iOS 16.4 or later. Not there? Open Health Pro in Safari and add it from there.',
          ),
        android => (
            where: 'In your browser:',
            steps: [
              (Icons.more_vert_rounded, 'Open the menu (⋮ at the top right in Chrome).'),
              (Icons.add_to_home_screen_rounded, 'Tap Install app, or Add to Home screen.'),
              (Icons.check_circle_outline_rounded, 'Tap Install.'),
            ],
            after: 'Health Pro then opens from its own icon, full screen.',
          ),
        samsung => (
            where: 'In Samsung Internet:',
            steps: [
              (Icons.menu_rounded, 'Tap the menu (☰ at the bottom right).'),
              (Icons.add_to_home_screen_rounded, 'Tap Add page to, then Home screen.'),
              (Icons.check_circle_outline_rounded, 'Tap Add.'),
            ],
            after: 'Health Pro then opens from its own icon, full screen.',
          ),
        androidFirefox => (
            where: 'In Firefox:',
            steps: [
              (Icons.more_vert_rounded, 'Tap the menu (⋮).'),
              (Icons.add_to_home_screen_rounded, 'Tap Add app to Home screen.'),
              (Icons.check_circle_outline_rounded, 'Tap Add.'),
            ],
            after: 'Health Pro then opens from its own icon.',
          ),
        chrome => (
            where: 'In Chrome:',
            steps: [
              (Icons.more_vert_rounded, 'Open Chrome\'s menu (⋮ at the top right).'),
              (Icons.install_desktop_rounded, 'Choose Cast, save, and share, then Install Health Pro.'),
              (Icons.check_circle_outline_rounded, 'Click Install.'),
            ],
            after: 'Or click the install icon at the right of the address bar. Health Pro then opens in its own '
                'window.',
          ),
        edge => (
            where: 'In Edge:',
            steps: [
              (Icons.more_horiz_rounded, 'Open Edge\'s menu (… at the top right).'),
              (Icons.install_desktop_rounded, 'Choose Apps, then Install Health Pro.'),
              (Icons.check_circle_outline_rounded, 'Click Install.'),
            ],
            after: 'Or click the install icon in the address bar. Health Pro then opens in its own window.',
          ),
        macSafari => (
            where: 'In Safari on a Mac:',
            steps: [
              (Icons.menu_open_rounded, 'Open the File menu, at the top of the screen.'),
              (Icons.add_box_outlined, 'Choose Add to Dock.'),
              (Icons.check_circle_outline_rounded, 'Click Add.'),
            ],
            after: 'Needs macOS Sonoma (14) or later. Health Pro then opens from the Dock, in its own window.',
          ),
        firefox => (
            where: 'Firefox on a computer can\'t install apps.',
            steps: [
              (Icons.open_in_browser_rounded, 'Open Health Pro in Chrome or Edge (or Safari on a Mac).'),
              (Icons.install_desktop_rounded, 'Click Install app there.'),
            ],
            after: null,
          ),
        other => (
            where: 'In your browser:',
            steps: [
              (Icons.more_vert_rounded, 'Open its menu.'),
              (Icons.install_desktop_rounded, 'Choose Install app, or Add to Home screen.'),
            ],
            after: 'Not there? Open Health Pro in Chrome or Edge (Safari on an iPhone or a Mac) and install it '
                'from there.',
          ),
      };
}

/// How to install Health Pro by hand in [browser].
class InstallSteps extends StatelessWidget {
  final InstallBrowser browser;

  const InstallSteps({super.key, required this.browser});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final guide = browser.guide;
    // On a phone, tighter (its text is smaller already: PhoneSized).
    final phone = PhoneSize.isPhone(MediaQuery.sizeOf(context));
    Widget step(int n, IconData icon, String text) => Padding(
          padding: EdgeInsets.only(bottom: phone ? 11 : 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: phone ? 13 : 15,
                backgroundColor: brand.accent.withValues(alpha: 0.14),
                child: Text('$n', style: TextStyle(color: brand.accent, fontWeight: FontWeight.w800)),
              ),
              SizedBox(width: phone ? 10 : 12),
              Icon(icon, color: brand.ink, size: phone ? 21 : 24),
              SizedBox(width: phone ? 8 : 10),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 14.5, height: 1.35))),
            ],
          ),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(phone ? 18 : 22, 0, phone ? 18 : 22, phone ? 12 : 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Install Health Pro', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(guide.where, style: TextStyle(color: brand.muted)),
            SizedBox(height: phone ? 14 : 18),
            for (final (i, (icon, text)) in guide.steps.indexed) step(i + 1, icon, text),
            if (guide.after case final after?) Text(after, style: TextStyle(color: brand.muted, fontSize: 12.5)),
            SizedBox(height: phone ? 10 : 14),
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
