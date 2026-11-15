import 'dart:js_interop';

/// web/index.html's `healthProPush`: the service worker and the browser's
/// push subscription for this device.
@JS('healthProPush')
external _Push? get _push;

extension type _Push._(JSObject _) implements JSObject {
  external bool supported();
  external String permission();
  external JSPromise<JSString?> current();
  external JSPromise<JSString?> subscribe(String vapidKey);
  external JSPromise<JSString?> unsubscribe();
}

/// Push notifications on this device, in a browser (or the installed app).
abstract final class WebPush {
  static bool get supported => _push?.supported() ?? false;

  /// 'default' (not asked yet), 'granted', 'denied', or 'unsupported'.
  static String get permission => _push?.permission() ?? 'unsupported';

  /// This device's subscription (JSON), if it has one.
  static Future<String?> current() async => (await _push?.current().toDart)?.toDart;

  /// Asks to show notifications, then subscribes; the subscription (JSON),
  /// or null when they said no.
  static Future<String?> subscribe(String vapidKey) async => (await _push?.subscribe(vapidKey).toDart)?.toDart;

  /// Unsubscribes this device; the address it had, if it had one.
  static Future<String?> unsubscribe() async => (await _push?.unsubscribe().toDart)?.toDart;
}
