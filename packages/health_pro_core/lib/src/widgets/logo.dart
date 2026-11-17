import 'package:flutter/material.dart';

import '../theme/brand.dart';

/// The Health Pro logo (assets/images/), in two versions: blue lettering for
/// light backgrounds, and white lettering for dark ones (the `_on_dark`
/// files), so it sits straight on the navy without a white tile. Made from
/// the brand files in tool/brand/ by tool/brand_images.dart.
class HealthProLogo extends StatelessWidget {
  final double height;

  /// Just the mark (the cross with the runner), without the name.
  final bool markOnly;

  /// Whether it sits on something dark: the white-lettered version. Null
  /// follows the theme; true for places that are navy in both themes (the
  /// side menu, the splash screen).
  final bool? onDark;

  const HealthProLogo({super.key, this.height = 56, this.markOnly = false, this.onDark});

  /// Width over height of the whole logo, and of the mark alone.
  static const aspectRatio = 2048 / 598;
  static const markAspectRatio = 1.0;

  /// The package the images are in, and the image for each version.
  static const package = 'health_pro_core';
  static String assetFor({required bool markOnly, required bool onDark}) =>
      'assets/images/${markOnly ? 'mark' : 'logo'}${onDark ? '_on_dark' : ''}.webp';

  @override
  Widget build(BuildContext context) {
    final dark = onDark ?? Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      assetFor(markOnly: markOnly, onDark: dark),
      package: package,
      height: height,
      fit: BoxFit.contain,
      semanticLabel: 'Health Pro',
      errorBuilder: (_, __, ___) => Text(
        'Health Pro',
        style: TextStyle(
          fontSize: height * 0.4,
          fontWeight: FontWeight.w900,
          color: dark ? Colors.white : BrandColors.navy,
        ),
      ),
    );
  }
}
