import 'dart:js_interop';

import 'package:flutter/foundation.dart';

/// web/index.html's `healthProPwa`: it keeps the browser's install offer
/// (beforeinstallprompt) until the Install app button uses it.
@JS('healthProPwa')
external _Pwa? get _pwa;

extension type _Pwa._(JSObject _) implements JSObject {
  external bool canPrompt();
  external bool isInstalled();
  external bool isIos();
  external JSPromise<JSString> prompt();
  external void onChange(JSFunction listener);
}

/// Installing Health Pro to the home screen, in a browser.
abstract final class PwaInstall {
  /// Ticks when the browser offers to install, or it's installed.
  static final changes = ValueNotifier<int>(0);
  static bool _listening = false;

  static void listen() {
    if (_listening) return;
    _listening = true;
    _pwa?.onChange((() => changes.value++).toJS);
  }

  /// The browser can show its install window now (Android, desktop Chrome
  /// and Edge).
  static bool get canPrompt => _pwa?.canPrompt() ?? false;

  /// Opened from the home screen: already installed.
  static bool get isInstalled => _pwa?.isInstalled() ?? false;

  /// An iPhone or iPad: installed by hand, from the Share menu.
  static bool get isIos => _pwa?.isIos() ?? false;

  /// Shows the browser's install window: 'accepted', 'dismissed' or
  /// 'unavailable'.
  static Future<String> prompt() async {
    final pwa = _pwa;
    if (pwa == null) return 'unavailable';
    return (await pwa.prompt().toDart).toDart;
  }
}
