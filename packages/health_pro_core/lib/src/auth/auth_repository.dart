import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show closeInAppWebView;

import '../config/env.dart';
import '../push/push_notifications.dart';
import '../router/core_routes.dart';
import '../supabase/supabase_provider.dart';
import 'sign_in_return.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(supabaseProvider)));

/// Whether 'Continue with Google' shows, on the website and in the apps: once
/// Google is switched on for the project (supabase/config.toml, README: Sign
/// in with Google). Until then the button stays hidden rather than leading
/// to Supabase's error page.
final googleSignInProvider = FutureProvider<bool>((ref) async {
  try {
    final res = await http
        .get(Uri.parse('${Env.supabaseUrl}/auth/v1/settings'), headers: {'apikey': Env.supabaseAnonKey})
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return false;
    final external = (jsonDecode(res.body) as Map<String, dynamic>)['external'];
    return external is Map && external['google'] == true;
  } catch (_) {
    return false;
  }
});

/// The web address of [page] ('/sign-in?next=...') on the site at [base]:
/// after the '#', where its pages are. Coming back from Google, Supabase puts
/// '?code=' before the '#', and Supabase.initialize signs them in with it
/// before the app opens the page.
String webReturnUrl(Uri base, String page) => '${base.origin}${base.path.isEmpty ? '/' : base.path}#$page';

/// Every sign-in, sign-out and token refresh.
final authChangesProvider = StreamProvider<void>((ref) => ref.watch(authRepositoryProvider).changes);

/// The signed-in user's id, or null. Whatever watches it rebuilds when
/// someone signs in or out (not on token refreshes).
final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authChangesProvider);
  return ref.watch(authRepositoryProvider).userId;
});

/// One account for the website and the apps: email and a 6-digit sign-in
/// code of their own choosing (no passwords), with 6-digit emailed codes to
/// sign up, sign in without their own code, or choose a new one.
/// (Supabase -> Authentication -> Email templates must include {{ .Token }}:
/// see the README.)
class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  bool get isLoggedIn => _auth.currentSession != null;
  String? get userId => _auth.currentUser?.id;
  String? get email => _auth.currentUser?.email;

  /// The code an account made for someone by an admin or a gym owner starts
  /// with (the admin-users Edge Function), until they choose their own.
  static const defaultCode = '123456';

  /// Whether they still have [defaultCode]: nothing opens until they have
  /// chosen their own (guardRoute).
  bool get mustChooseCode => _auth.currentUser?.userMetadata?['must_choose_code'] == true;

  /// Signed up with Google, which doesn't share a phone number, and not yet
  /// asked for one: asked once, before anything else opens (guardRoute,
  /// AddPhoneScreen). Accounts that began with email + code, Google added
  /// later or not, gave theirs at sign-up.
  bool get mustAddPhone {
    final user = _auth.currentUser;
    return user != null && user.appMetadata['provider'] == 'google' && user.userMetadata?['phone_asked'] != true;
  }

  /// They've been asked for their phone (saved or skipped): not again.
  Future<void> markPhoneAsked() => _auth.updateUser(UserAttributes(data: {'phone_asked': true}));

  /// A tick for each change; whether someone is signed in is read from the
  /// session. Supabase also sends a sign-in that came back unfinished (Google
  /// with an account that's turned off, or cancelled) as an error here: the
  /// sign-in page says why (SignInReturn), so it isn't an app error.
  Stream<void> get changes => _auth.onAuthStateChange.map((_) {}).handleError((Object _) {});

  /// Signs in with the email and the 6-digit code they chose. Supabase Auth
  /// keeps it as the account's password (6 is the shortest it takes:
  /// minimum_password_length in supabase/config.toml).
  Future<void> signIn({required String email, required String code}) =>
      _auth.signInWithPassword(email: email.trim().toLowerCase(), password: code.trim());

  /// Emails a code that makes the account when it's entered.
  Future<void> sendSignUpCode({required String email, required String fullName, String? phone}) =>
      _auth.signInWithOtp(
        email: email.trim().toLowerCase(),
        shouldCreateUser: true,
        data: {'full_name': fullName.trim(), if (phone != null) 'phone': phone},
      );

  /// Emails a code to sign in (or to choose a new sign-in code); no new
  /// account.
  Future<void> sendLoginCode(String email) =>
      _auth.signInWithOtp(email: email.trim().toLowerCase(), shouldCreateUser: false);

  /// Signs in with the emailed code.
  Future<void> verifyCode({required String email, required String code}) =>
      _auth.verifyOTP(email: email.trim().toLowerCase(), token: code.trim(), type: OtpType.email);

  /// Where Google sends the apps back: this link opens the app (Android's
  /// intent filter, iOS's URL type) and Supabase signs them in from it.
  /// Allowed in supabase/config.toml (additional_redirect_urls).
  static const appReturnUrl = 'bt.healthpro.app://login-callback';

  /// Off to Google and back, then on to [next]. A Gmail that already has an
  /// account signs in to that same account (Supabase links them by the
  /// email); a new one gets an account and profile with Google's name for
  /// them (handle_new_user). No sign-in code until they choose one (Forgot
  /// code?).
  ///
  /// Website: in this tab, back to the sign-in page, which sends them on.
  /// Apps: in a browser over the app (Android's own, iPhone's in the app),
  /// back through [appReturnUrl] to the page they left; [next] waits here
  /// meanwhile (takeNextAfterGoogle).
  Future<void> signInWithGoogle({String? next}) async {
    if (!kIsWeb) {
      _nextAfterGoogle = next;
      _closeBrowserOnReturn();
    }
    await _auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? webReturnUrl(Uri.base, next == null ? CoreRoutes.signIn : CoreRoutes.signInFor(next)) : appReturnUrl,
      // Shared computers (a gym's front desk): always ask which Google account.
      queryParams: const {'prompt': 'select_account'},
    );
  }

  String? _nextAfterGoogle;

  /// In the apps: where to go now that Google has brought them back signed
  /// in; once (guardRoute, from the router).
  String? takeNextAfterGoogle() {
    final next = _nextAfterGoogle;
    _nextAfterGoogle = null;
    return next;
  }

  StreamSubscription<AuthState>? _browserOpen;

  /// iPhone opens Google in a browser over the app, and it stays there after
  /// Google sends them back; it closes then, signed in or not.
  void _closeBrowserOnReturn() {
    _browserOpen?.cancel();
    _browserOpen = _auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn) _closeBrowser();
    }, onError: (Object _) => _closeBrowser());
  }

  void _closeBrowser() {
    _browserOpen?.cancel();
    _browserOpen = null;
    if (defaultTargetPlatform == TargetPlatform.iOS) unawaited(closeInAppWebView());
  }

  /// In the apps: why a Google sign-in came back unfinished (an account
  /// that's turned off, cancelled), for the sign-in pages to show. The
  /// website reads it from the address instead (SignInReturn).
  Stream<String> get unfinishedSignIns => _auth.onAuthStateChange.transform(
      StreamTransformer.fromHandlers(handleData: (_, __) {}, handleError: (e, _, sink) => sink.add(unfinishedSignInMessage(e))));

  /// Sets the signed-in person's 6-digit sign-in code.
  Future<void> setSignInCode(String code) =>
      _auth.updateUser(UserAttributes(password: code.trim(), data: {'must_choose_code': false}));

  /// Signs out; first, this device stops getting their push notifications.
  Future<void> signOut() async {
    await PushNotifications.forgetThisDevice(_client);
    await _auth.signOut();
  }

  /// The delete-account Edge Function removes the login and everything that
  /// is only theirs (supabase/functions/delete-account).
  Future<void> deleteAccount() async {
    await _client.functions.invoke('delete-account');
    await _auth.signOut();
  }
}
