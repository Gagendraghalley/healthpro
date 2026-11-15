import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_repository.dart';
import '../config/env.dart';
import '../pwa/pwa_stub.dart' if (dart.library.js_interop) '../pwa/pwa_web.dart';
import '../supabase/supabase_provider.dart';
import '../theme/brand.dart';
import '../widgets/feedback.dart';
import 'web_push_stub.dart' if (dart.library.js_interop) 'web_push_web.dart';

/// Where push notifications stand on this device.
enum PushStatus {
  /// Not set up (no VAPID key), or this browser can't.
  unavailable,

  /// An iPhone or iPad in Safari: install the app first (iOS 16.4+).
  needsInstall,

  /// Blocked in the browser's settings.
  blocked,
  off,
  on,
}

/// Push on this device; reading it never asks the person anything.
final pushStatusProvider = FutureProvider<PushStatus>((ref) async {
  ref.watch(currentUserIdProvider);
  return PushNotifications.status();
});

/// Every notification also arrives as a push on the devices where the person
/// turned them on: Health Pro tells them about join requests, payments,
/// packages ending, trainers and reviews even when it's closed. Asked after
/// signing in, not on first opening; anyone who says no still sees them in
/// the app, under Notifications.
abstract final class PushNotifications {
  static bool get configured => Env.vapidPublicKey.isNotEmpty;

  static Future<PushStatus> status() async {
    if (!configured) return PushStatus.unavailable;
    if (PwaInstall.isIos && !PwaInstall.isInstalled) return PushStatus.needsInstall;
    if (!WebPush.supported) return PushStatus.unavailable;
    if (WebPush.permission == 'denied') return PushStatus.blocked;
    if (WebPush.permission != 'granted') return PushStatus.off;
    try {
      return await WebPush.current() == null ? PushStatus.off : PushStatus.on;
    } catch (_) {
      return PushStatus.off;
    }
  }

  /// Asks to show notifications, subscribes this device and keeps it on
  /// Health Pro. False when they said no.
  static Future<bool> turnOn(SupabaseClient client) async {
    final json = await WebPush.subscribe(Env.vapidPublicKey);
    if (json == null) {
      if (WebPush.permission == 'denied') {
        throw StateError('Notifications are blocked for Health Pro. Allow them in your browser or phone settings.');
      }
      return false;
    }
    final sub = jsonDecode(json) as Map<String, dynamic>;
    final keys = Map<String, dynamic>.from(sub['keys'] as Map);
    await client.rpc('save_push_subscription', params: {
      'endpoint': sub['endpoint'],
      'p256dh': keys['p256dh'],
      'auth': keys['auth'],
      'user_agent': null,
    });
    return true;
  }

  /// This device stops getting notifications.
  static Future<void> turnOff(SupabaseClient client) async {
    final endpoint = await WebPush.unsubscribe();
    if (endpoint != null) await client.rpc('remove_push_subscription', params: {'endpoint': endpoint});
  }

  /// Before signing out: this device stops getting this person's
  /// notifications. Never in the way of signing out.
  static Future<void> forgetThisDevice(SupabaseClient client) async {
    if (!configured || !WebPush.supported) return;
    try {
      await turnOff(client).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  static const _snoozeKey = 'push_prompt_snoozed_until';
  static bool _askedThisSession = false;

  /// After signing in, once a session: asks whether to turn notifications on,
  /// unless they're on, blocked, can't be, or the person said "Not now" in
  /// the last two weeks.
  static Future<void> maybeAsk(BuildContext context, WidgetRef ref) async {
    if (_askedThisSession || !configured) return;
    _askedThisSession = true;
    if (await status() != PushStatus.off) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = prefs.getInt(_snoozeKey);
      if (until != null && DateTime.now().millisecondsSinceEpoch < until) return;
    } catch (_) {}
    if (!context.mounted) return;
    final yes = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.notifications_active_rounded, color: context.brand.accent, size: 36),
        title: const Text('Turn on notifications?'),
        content: const Text(
          'Health Pro tells you about join requests, payments, packages ending, trainers and reviews, '
          'even when the app is closed. You can turn them off any time under Notifications.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Turn on')),
        ],
      ),
    );
    if (yes != true) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_snoozeKey, DateTime.now().add(const Duration(days: 14)).millisecondsSinceEpoch);
      } catch (_) {}
      return;
    }
    if (!context.mounted) return;
    await runAction(context, () => turnOn(ref.read(supabaseProvider)), success: 'Notifications are on');
    ref.invalidate(pushStatusProvider);
  }
}

/// On the Notifications page: push on this device, and turning it on or off.
class PushSettingCard extends ConsumerWidget {
  const PushSettingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(pushStatusProvider).valueOrNull;
    if (status == null || status == PushStatus.unavailable) return const SizedBox.shrink();
    final brand = context.brand;
    final (IconData icon, String title, String text) = switch (status) {
      PushStatus.on => (Icons.notifications_active_rounded, 'On, on this device', 'You get them even when Health Pro is closed.'),
      PushStatus.off => (Icons.notifications_off_outlined, 'Off on this device', 'Turn them on to hear even when Health Pro is closed.'),
      PushStatus.blocked => (
          Icons.block_rounded,
          'Blocked on this device',
          'Allow notifications for Health Pro in your browser or phone settings, then come back.'
        ),
      PushStatus.needsInstall => (
          Icons.install_mobile_rounded,
          'Install Health Pro to get them',
          'On an iPhone: in Safari tap Share, then Add to Home Screen, then Add. Open Health Pro from your home screen '
              'and turn them on here (iOS 16.4 or later).'
        ),
      PushStatus.unavailable => (Icons.notifications_off_outlined, '', ''),
    };
    Future<void> act(Future<void> Function() action, String done) async {
      await runAction(context, action, success: done);
      ref.invalidate(pushStatusProvider);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: brand.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.glassBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: status == PushStatus.on ? brand.success : brand.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Push notifications: $title', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(text, style: TextStyle(color: brand.muted, fontSize: 12.5)),
              ],
            ),
          ),
          if (status == PushStatus.on)
            TextButton(
              onPressed: () => act(() => PushNotifications.turnOff(ref.read(supabaseProvider)), 'Notifications are off on this device'),
              child: const Text('Turn off'),
            )
          else if (status == PushStatus.off)
            FilledButton(
              onPressed: () => act(() async {
                await PushNotifications.turnOn(ref.read(supabaseProvider));
              }, 'Notifications are on'),
              child: const Text('Turn on'),
            ),
        ],
      ),
    );
  }
}
