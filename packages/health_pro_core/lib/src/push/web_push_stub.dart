/// Push notifications are the website's (an installed web app); outside a
/// browser there are none, and notifications stay inside the app.
abstract final class WebPush {
  static bool get supported => false;
  static String get permission => 'unsupported';
  static Future<String?> current() async => null;
  static Future<String?> subscribe(String vapidKey) async => null;
  static Future<String?> unsubscribe() async => null;
}
