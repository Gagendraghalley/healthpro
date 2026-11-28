import 'package:flutter/material.dart';

import '../theme/brand.dart';

/// The Health Pro logo, as it is in the brand file, with no card behind it.
/// On dark backgrounds 'Health' and the tagline are white (the
/// `logo_on_dark` picture); the heart and the green 'Pro' are the same.
///
/// One picture each: the heart with the cross (the mark), the name and the
/// tagline, "All your well-being, all in one place"; and the mark alone, the
/// same on light and dark. The pictures are made from the brand file in
/// tool/brand/ by tool/brand_images.dart, which also prints the size below.
class HealthProLogo extends StatelessWidget {
  final double height;

  /// Just the mark (the heart with the cross), without the name.
  final bool markOnly;

  /// Whether it sits on something dark: the white lettering. Null
  /// follows the theme; true for places that are navy in both themes (the
  /// side menu, the splash screen).
  final bool? onDark;

  const HealthProLogo({super.key, this.height = 56, this.markOnly = false, this.onDark});

  /// Width over height of the whole logo, and of the mark alone.
  static const aspectRatio = 1141 / 388;
  static const markAspectRatio = 1.0;

  /// The package the pictures are in, and each picture: 'mark', and 'logo'
  /// or 'logo_on_dark'.
  static const package = 'health_pro_core';
  static const parts = ['mark', 'logo', 'logo_on_dark'];
  static String assetFor(String part) => 'assets/images/$part.webp';
  static String logoFor({required bool onDark}) => assetFor(onDark ? 'logo_on_dark' : 'logo');

  @override
  Widget build(BuildContext context) {
    final dark = onDark ?? Theme.of(context).brightness == Brightness.dark;
    Widget fallback(BuildContext context, Object error, StackTrace? stack) => Text(
          'Health Pro',
          style: TextStyle(
            fontSize: height * 0.4,
            fontWeight: FontWeight.w900,
            color: dark ? Colors.white : BrandColors.navy,
          ),
        );
    if (markOnly) {
      return Image.asset(
        assetFor('mark'),
        package: package,
        height: height,
        fit: BoxFit.contain,
        semanticLabel: 'Health Pro',
        errorBuilder: fallback,
      );
    }
    final width = height * aspectRatio;
    return Semantics(
      label: 'Health Pro',
      image: true,
      child: SizedBox(
        width: width,
        height: height,
        child: FittedBox(
          child: SizedBox(
            width: width,
            height: height,
            child: Image.asset(
              logoFor(onDark: dark),
              package: package,
              fit: BoxFit.fill,
              excludeFromSemantics: true,
              errorBuilder: fallback,
            ),
          ),
        ),
      ),
    );
  }
}
