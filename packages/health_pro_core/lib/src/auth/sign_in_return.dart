import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../router/core_routes.dart';
import '../router/route_guard.dart';
import '../utils/friendly_error.dart';
import '../utils/web_address_stub.dart' if (dart.library.js_interop) '../utils/web_address_web.dart';

/// A sign-in that came back to the website unfinished: Google's answer
/// ('?error=access_denied&error_code=user_banned&...' for an account that's
/// turned off), or an old email link's ('#error=...'). Supabase.initialize
/// has already read it and signed nobody in; the sign-in page says why.
abstract final class SignInReturn {
  static bool _captured = false;
  static String? _error;

  /// Once, as the app starts and before the router opens a page: keeps what
  /// went wrong for the sign-in page and takes it out of the address, so a
  /// reload doesn't show it again.
  static void capture() {
    if (_captured || !kIsWeb) return;
    _captured = true;
    final base = Uri.base;
    _error = signInErrorIn(base);
    if (_error != null) replaceWebAddress(withoutSignInError(base));
  }

  /// Whether there's a message waiting: the app then opens on the sign-in page.
  static bool get hasError => _error != null;

  /// The message, once (SignInScreen).
  static String? take() {
    final error = _error;
    _error = null;
    return error;
  }
}

const _errorParams = {'error', 'error_code', 'error_description'};

/// What to tell them about the unfinished sign-in in [uri]; null if there's
/// none. Supabase puts it in the query, after the '#', or both.
String? signInErrorIn(Uri uri) {
  final Map<String, String> params;
  try {
    params = {...uri.queryParameters, if (hasNonPageFragment(uri)) ...Uri.splitQueryString(uri.fragment)};
  } on FormatException {
    return "Signing in didn't finish. Please try again.";
  }
  if (!params.keys.any(_errorParams.contains)) return null;
  final description = params['error_description'] ?? '';
  if (description.isEmpty) {
    return params['error'] == 'access_denied'
        ? 'Signing in with Google was cancelled.'
        : "Signing in didn't finish. Please try again.";
  }
  return friendlyError(AuthException(description, code: params['error_code']));
}

/// What to tell them about a Google sign-in that came back unfinished to
/// the apps: Supabase's [error] from the return link (getSessionFromUrl).
String unfinishedSignInMessage(Object error) {
  if (error is AuthException && error.message.startsWith('Error in URL with unspecified')) {
    return error.code == 'access_denied' ? 'Signing in with Google was cancelled.' : "Signing in didn't finish. Please try again.";
  }
  return friendlyError(error);
}

/// [uri] without the sign-in error: on its own page, or the sign-in page
/// when the error took the place of one after the '#'.
String withoutSignInError(Uri uri) {
  final query = {
    for (final p in uri.queryParameters.entries)
      if (!_errorParams.contains(p.key)) p.key: p.value,
  };
  final page = uri.fragment.startsWith('/') ? uri.fragment : CoreRoutes.signIn;
  return '${uri.origin}${uri.path}${query.isEmpty ? '' : '?${Uri(queryParameters: query).query}'}#$page';
}
