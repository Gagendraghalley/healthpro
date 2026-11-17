import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/brand.dart';
import 'logo.dart';

/// The splash screen, in the app's theme: in light, the blue-lettered logo
/// on white; in dark, the white-lettered logo on the side menu's navy. Its
/// heartbeat traces, and a slim green bar (the logo's green) runs under it.
/// Shown while the app gets ready (the modules load at start).
///
/// Before Flutter starts, the launch screens show the same logo at the same
/// size and place, so the handover doesn't jump. Keep them in step:
/// - web/index.html (#splash) and web/splash/: in the theme the app saved
/// - Android: res/drawable*/launch_background.xml, res/values*-v31/styles.xml
/// - iOS: Runner/Base.lproj/LaunchScreen.storyboard, LaunchImage
/// The phone's launch screens can't read the app's choice, so they show the
/// light one, the app's own until someone picks dark.
class HealthProSplash extends StatelessWidget {
  const HealthProSplash({super.key});

  /// The logo's width: 240 on a phone, 320 on anything bigger. Its middle is
  /// the screen's middle.
  static double logoWidthFor(Size screen) => screen.shortestSide >= 600 ? 320 : 240;

  /// From the logo's foot to the bar.
  static const barGap = 36.0;

  /// The light splash's background (the launch screens' too).
  static const lightBackground = Colors.white;

  /// Reads the logo's pictures for the theme it opens in ([dark] or light)
  /// ahead of the first frame (main, before runApp), so the splash shows it
  /// at once rather than blinking in after the launch screen. Never takes
  /// more than a few seconds, and never fails.
  static Future<void> precacheLogo({required bool dark}) {
    Future<void> read(String part) {
      final done = Completer<void>();
      final image = AssetImage(HealthProLogo.assetFor(part, onDark: dark), package: HealthProLogo.package);
      final stream = image.resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      void finish() {
        if (!done.isCompleted) done.complete();
        stream.removeListener(listener);
      }

      listener = ImageStreamListener((_, __) => finish(), onError: (_, __) => finish());
      stream.addListener(listener);
      return done.future;
    }

    return Future.wait([read('logo_base'), read('logo_heartbeat')])
        .timeout(const Duration(seconds: 3), onTimeout: () => const []);
  }

  @override
  Widget build(BuildContext context) {
    final width = logoWidthFor(MediaQuery.sizeOf(context));
    final height = width / HealthProLogo.aspectRatio;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? null : lightBackground,
          gradient: dark
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [BrandColors.midnight, BrandColors.night],
                )
              : null,
        ),
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              // The heartbeat starts tracing at once: the splash is short.
              Center(child: HealthProLogo(height: height, onDark: dark, delay: Duration.zero)),
              Positioned(
                left: 0,
                right: 0,
                top: box.maxHeight / 2 + height / 2 + barGap,
                child: Center(child: _RunningBar(width: width / 2, dark: dark)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The splash's bar: a green streak, the logo's 'PRO' green, running along
/// a faint track.
class _RunningBar extends StatefulWidget {
  final double width;
  final bool dark;

  const _RunningBar({required this.width, required this.dark});

  @override
  State<_RunningBar> createState() => _RunningBarState();
}

class _RunningBarState extends State<_RunningBar> with SingleTickerProviderStateMixin {
  late final AnimationController _run =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  late final Animation<double> _eased = CurvedAnimation(parent: _run, curve: Curves.easeInOutCubic);

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final streak = widget.width * 0.4;
    return Semantics(
      label: 'Loading',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          width: widget.width,
          height: 4,
          child: ColoredBox(
            color: widget.dark ? Colors.white.withValues(alpha: 0.12) : BrandColors.navy.withValues(alpha: 0.08),
            child: AnimatedBuilder(
              animation: _eased,
              builder: (context, child) => Stack(
                children: [
                  // From just off the left to just off the right.
                  Positioned(
                    left: -streak + (widget.width + streak) * _eased.value,
                    top: 0,
                    bottom: 0,
                    width: streak,
                    child: child!,
                  ),
                ],
              ),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                  gradient: LinearGradient(
                    colors: [Color(0x004FC111), Color(0xFF4FC111), Color(0xFF2AAA17)],
                    stops: [0, 0.4, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [HealthProSplash] until [ready], then the page [builder] makes, faded in.
/// Once ready, the page updates in place like any other.
class SplashGate extends StatelessWidget {
  final bool ready;
  final WidgetBuilder builder;

  const SplashGate({super.key, required this.ready, required this.builder});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, if (current != null) current]),
      child: ready
          ? KeyedSubtree(key: const ValueKey('page'), child: builder(context))
          : const HealthProSplash(key: ValueKey('splash')),
    );
  }
}
