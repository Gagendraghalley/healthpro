import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sends report_app_error's parameters.
typedef ErrorSender = Future<void> Function(Map<String, String?> params);

/// Errors the app didn't handle, sent to Health Pro's own database
/// (report_app_error) for the team to put right: Admin -> App errors. Only
/// in a release build (while developing they show in the console, as
/// always). Each kind goes once a run, at most [maxPerRun] in all, and a lost
/// connection isn't something to fix, so it isn't sent.
class ErrorReporter {
  ErrorReporter(this._send, {required this.platform, this.page});

  final ErrorSender _send;

  /// 'web', 'android', 'iOS'.
  final String platform;

  /// The page on screen when it happened.
  final String? Function()? page;

  /// The router sets it: the path on screen (app_router).
  static String? Function()? currentPage;

  static const maxPerRun = 10;

  final _sent = <String>{};

  /// Catches what the app didn't (in a release build): Flutter's own errors
  /// (a page that couldn't be drawn) and the rest (a tap's failed future).
  /// Both still go where they went before.
  static void install(SupabaseClient client) {
    if (!kReleaseMode) return;
    final reporter = ErrorReporter(
      (params) async => await client.rpc('report_app_error', params: params),
      platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
      page: () => currentPage?.call(),
    );
    final flutterBefore = FlutterError.onError;
    FlutterError.onError = (details) {
      flutterBefore?.call(details);
      reporter.report(details.exception, details.stack);
    };
    final platformBefore = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      reporter.report(error, stack);
      return platformBefore?.call(error, stack) ?? false;
    };
  }

  /// Sends [error] unless it's a lost connection, was sent already, or this
  /// run has sent [maxPerRun]. Whether it went.
  bool report(Object error, StackTrace? stack) {
    final message = '$error'.trim();
    if (message.isEmpty || isConnectionTrouble(message) || _sent.length >= maxPerRun) return false;
    final lines = '${stack ?? ''}'.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (!_sent.add('$message\n${lines.take(3).join('\n')}')) return false;
    String? where;
    try {
      where = page?.call();
    } catch (_) {
      // No page yet.
    }
    final params = {
      'error_message': _cut(message, 1000),
      'error_stack': lines.isEmpty ? null : _cut(lines.take(60).join('\n'), 8000),
      'at_page': where,
      'on_platform': platform,
    };
    // A report that can't go (offline) is let go: never an error of its own.
    runZonedGuarded(() => _send(params).catchError((_) {}), (_, __) {});
    return true;
  }

  /// No internet, a timeout, a picture that didn't load: the network, not
  /// the app. Their words, since class names are shortened on the web.
  static bool isConnectionTrouble(String message) => _connection.any(message.contains);

  static const _connection = [
    'SocketException',
    'ClientException',
    'Failed to fetch',
    'XMLHttpRequest error',
    'TimeoutException',
    'Connection closed',
    'Connection refused',
    'Connection reset',
    'Network is unreachable',
    'HandshakeException',
    'HTTP request failed',
    'AuthRetryableFetchException',
  ];

  static String _cut(String text, int max) => text.length <= max ? text : text.substring(0, max);
}
