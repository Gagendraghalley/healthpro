import 'package:flutter/material.dart';

/// Phones: everything a little smaller (text, buttons, fields, list rows),
/// so more fits on a small screen. Tablets and computers stay as they are.
abstract final class PhoneSize {
  /// A phone, upright or on its side.
  static bool isPhone(Size size) => size.shortestSide < 600;

  /// Text on a phone: this much of its size.
  static const textFactor = 0.92;

  /// Buttons, fields and list rows 4 pixels shorter.
  static const density = VisualDensity(horizontal: -1, vertical: -1);

  /// [base] (the phone's own text size) a little smaller; unless they asked
  /// their phone for bigger text, which stays as they chose.
  static TextScaler textScaler(TextScaler base) => base.scale(14) > 14 ? base : _Smaller(base);
}

/// Wraps the app (HealthProApp's builder): on a phone, smaller text and
/// denser controls; elsewhere, nothing.
class PhoneSized extends StatelessWidget {
  final Widget child;

  const PhoneSized({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (!PhoneSize.isPhone(media.size)) return child;
    return MediaQuery(
      data: media.copyWith(textScaler: PhoneSize.textScaler(media.textScaler)),
      child: Theme(data: Theme.of(context).copyWith(visualDensity: PhoneSize.density), child: child),
    );
  }
}

class _Smaller extends TextScaler {
  final TextScaler base;

  const _Smaller(this.base);

  @override
  double scale(double fontSize) => base.scale(fontSize) * PhoneSize.textFactor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * PhoneSize.textFactor;

  @override
  bool operator ==(Object other) => other is _Smaller && other.base == base;

  @override
  int get hashCode => Object.hash(_Smaller, base);
}
