import 'package:flutter/foundation.dart';

/// Installing to the home screen is for the website; the phone apps are
/// installed already.
abstract final class PwaInstall {
  static final changes = ValueNotifier<int>(0);
  static void listen() {}
  static bool get canPrompt => false;
  static bool get isInstalled => true;
  static bool get isIos => false;
  static String get browser => 'other';
  static Future<String> prompt() async => 'unavailable';
}
