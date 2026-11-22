import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Push notifications on the Android and iOS apps, through Firebase Cloud
/// Messaging (the website has web push instead: web_push_web.dart). The phone
/// shows each one even when Health Pro is closed; a tap opens its page.
///
/// A phone's address at FCM (its "token" here and in push_devices) is its
/// Firebase Installation ID, FCM's replacement for registration tokens: the
/// apps turn it on (firebase_messaging_installation_id_enabled in
/// AndroidManifest.xml, FirebaseMessagingInstallationIdEnabled in Info.plist).
abstract final class NativePush {
  /// The Android or iOS app (never the website, nor a computer's app).
  static bool get isPhoneApp =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  /// What push_devices calls this phone.
  static String get platform => _ios ? 'ios' : 'android';

  /// This phone's app in the Firebase project (env.json); null: not set up,
  /// and notifications stay inside the app.
  static FirebaseOptions? get _options {
    final (apiKey, appId) = _ios ? (Env.firebaseIosApiKey, Env.firebaseIosAppId) : (Env.firebaseAndroidApiKey, Env.firebaseAndroidAppId);
    if (apiKey.isEmpty || appId.isEmpty || Env.firebaseProjectId.isEmpty || Env.firebaseSenderId.isEmpty) return null;
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: Env.firebaseSenderId,
      projectId: Env.firebaseProjectId,
      iosBundleId: _ios ? 'bt.healthpro.app' : null,
    );
  }

  static bool get configured => isPhoneApp && _options != null;

  static Future<FirebaseApp>? _starting;

  /// Firebase, once.
  static Future<void> _start() async {
    if (Firebase.apps.isNotEmpty) return;
    await (_starting ??= Firebase.initializeApp(options: _options).whenComplete(() => _starting = null));
  }

  static FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  /// 'granted'; 'denied' (blocked: only the phone's settings can allow them
  /// now); or 'default' (not asked yet, or Android may still ask again).
  static Future<String> permission() async {
    await _start();
    return permissionOf((await _fcm.getNotificationSettings()).authorizationStatus, ios: _ios);
  }

  @visibleForTesting
  static String permissionOf(AuthorizationStatus status, {required bool ios}) => switch (status) {
        AuthorizationStatus.authorized || AuthorizationStatus.provisional => 'granted',
        AuthorizationStatus.deniedPermanently => 'denied',
        // iOS asks only once; Android 13 and later may ask again.
        AuthorizationStatus.denied => ios ? 'denied' : 'default',
        AuthorizationStatus.notDetermined => 'default',
      };

  /// This phone's token, when its notifications are on for [userId].
  static Future<String?> current(String? userId) async {
    final saved = await _saved();
    return saved != null && userId != null && saved.user == userId ? saved.token : null;
  }

  /// Asks to show notifications; once they allow it, registers this phone
  /// with FCM and gives its token. Null when they don't allow it.
  static Future<String?> subscribe() async {
    await _start();
    final settings = await _fcm.requestPermission();
    if (permissionOf(settings.authorizationStatus, ios: _ios) != 'granted') return null;
    return _register();
  }

  /// Registers this phone with FCM; its token (Firebase Installation ID).
  static Future<String> _register() async {
    if (_ios) {
      // On iOS, FCM needs Apple's own push token (APNs) first.
      for (var i = 0; i < 10 && await _fcm.getAPNSToken() == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    final registered = _fcm.onRegistered.first.timeout(const Duration(seconds: 30));
    try {
      await _fcm.register();
    } catch (_) {
      registered.ignore();
      rethrow;
    }
    return registered;
  }

  static const _savedKey = 'push_device';

  /// This phone is on for [userId], with [token].
  static Future<void> remember(String userId, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedKey, jsonEncode({'user': userId, 'token': token}));
  }

  static Future<({String user, String token})?> _saved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_savedKey);
      if (json == null) return null;
      final saved = jsonDecode(json) as Map<String, dynamic>;
      return (user: saved['user'] as String, token: saved['token'] as String);
    } catch (_) {
      return null;
    }
  }

  /// This phone stops getting notifications: forgotten here, and unregistered
  /// at FCM (it answers "gone" for anything still sent to it, and send-push
  /// forgets it).
  static Future<void> unsubscribe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_savedKey);
    } catch (_) {}
    try {
      await _start();
      await _fcm.unregister();
    } catch (_) {}
  }

  static void Function(String link)? _open;
  static void Function(String title, String body, String link)? _show;
  static bool _listening = false;
  static bool _openedFirst = false;

  /// After signing in (each time the menu opens): keeps this phone's token
  /// current, and a tapped notification opens its page through [open]
  /// (Health Pro was closed, or in the background). One that comes while
  /// Health Pro is open goes to [show], since the phone shows nothing then.
  static Future<void> listen(SupabaseClient client,
      {required void Function(String link) open, required void Function(String title, String body, String link) show}) async {
    if (!configured) return;
    _open = open;
    _show = show;
    await _start();
    final saved = await _saved();
    if (saved != null && saved.user != client.auth.currentUser?.id) {
      // Someone else's, left from before (their session ended without
      // signing out): this phone stops getting theirs.
      await unsubscribe();
    } else if (saved != null) {
      unawaited(_keep(client));
    }
    if (!_listening) {
      _listening = true;
      _fcm.onRegistered.listen((token) => _keep(client, token));
      FirebaseMessaging.onMessageOpenedApp.listen((message) => _open?.call(linkOf(message.data)));
      FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        _show?.call(notification?.title ?? 'Health Pro', notification?.body ?? '', linkOf(message.data));
      });
    }
    if (!_openedFirst) {
      _openedFirst = true;
      final first = await _fcm.getInitialMessage();
      if (first != null) _open?.call(linkOf(first.data));
    }
  }

  /// Still on: registered again (as FCM asks, each time the app starts), and
  /// Health Pro gets the token this phone has now.
  static Future<void> _keep(SupabaseClient client, [String? token]) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null || await current(userId) == null) return;
    try {
      token ??= await _register();
      await client.rpc('save_push_device', params: {'token': token, 'platform': platform});
      await remember(userId, token);
    } catch (_) {}
  }

  /// The page a notification opens: its own, when it's one of Health Pro's.
  @visibleForTesting
  static String linkOf(Map<String, dynamic> data) {
    final link = data['link'];
    return link is String && link.startsWith('/') && !link.startsWith('//') ? link : '/notifications';
  }
}
