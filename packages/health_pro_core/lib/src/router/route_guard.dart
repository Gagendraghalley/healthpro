import 'core_routes.dart';

/// Where to send someone opening [uri] instead, or null to let them in.
///
/// - '/' is home for signed-in users and Welcome for visitors.
/// - A module's pages are closed while it's turned off ([moduleKey] not in
///   [enabledModuleKeys]; null while app_modules is still loading).
/// - Someone still on the code their account was made with
///   ([mustChooseCode]) chooses their own before anything else opens.
/// - Someone just signed up with Google ([mustAddPhone]) is asked for their
///   phone once, then goes on to the page they were opening (?next=).
/// - Sign-in pages send signed-in users on (to ?next= when it's one of ours).
/// - Everything not in [publicPatterns] needs an account: visitors sign in
///   first and come back. Except right after signing out ([justSignedOut]):
///   that goes to Welcome, so whoever signs in next on this device isn't
///   sent to the last person's page (another gym's, say).
///
/// [pattern] is the matched route's pattern ('/gyms/:id'), so public pages
/// with ids match.
String? guardRoute({
  required Uri uri,
  required String pattern,
  required bool signedIn,
  required Set<String> publicPatterns,
  String? moduleKey,
  Set<String>? enabledModuleKeys,
  bool mustChooseCode = false,
  bool mustAddPhone = false,
  bool justSignedOut = false,
}) {
  if (signedIn && mustChooseCode) return uri.path == CoreRoutes.setCode ? null : CoreRoutes.setCode;
  if (signedIn && mustAddPhone && uri.path != CoreRoutes.addPhone) {
    final arriving = uri.path == CoreRoutes.root || uri.path.isEmpty || CoreRoutes.signedOutOnly.contains(pattern);
    return CoreRoutes.addPhoneFor(arriving ? safeNext(uri.queryParameters['next']) ?? CoreRoutes.home : uri.toString());
  }
  final start = signedIn ? CoreRoutes.home : CoreRoutes.welcome;
  if (uri.path == CoreRoutes.root || uri.path.isEmpty) return start;
  if (moduleKey != null && enabledModuleKeys != null && !enabledModuleKeys.contains(moduleKey)) return start;
  if (signedIn && CoreRoutes.signedOutOnly.contains(pattern)) {
    return safeNext(uri.queryParameters['next']) ?? CoreRoutes.home;
  }
  if (!signedIn && !publicPatterns.contains(pattern)) {
    return justSignedOut ? CoreRoutes.welcome : CoreRoutes.signInFor(uri.toString());
  }
  return null;
}

/// Whether the web address carries something other than a page after the '#',
/// such as Supabase's '#error=access_denied&...' when an email link has
/// expired. Pages are '#/...'; the router can't open anything else.
bool hasNonPageFragment(Uri uri) => uri.fragment.isNotEmpty && !uri.fragment.startsWith('/');

/// [next] when it's a page of this app ('/gyms/1'), not another site.
String? safeNext(String? next) =>
    next != null && next.startsWith('/') && !next.startsWith('//') && !next.contains('://') ? next : null;
