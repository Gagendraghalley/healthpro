import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_repository.dart';
import '../supabase/supabase_provider.dart';

/// A person's Health Pro QR code: one code that works at every gym. It holds
/// only `healthpro:member:<token>`, nothing about them; the front desk scans
/// it to check them in, or to add them to its gym.
abstract final class PersonQr {
  static const prefix = 'healthpro:member:';

  static final _token = RegExp(r'^[0-9a-f]{32}$');

  static String encode(String token) => '$prefix$token';

  /// The token in a scanned [raw] personal QR code; null when it isn't one.
  static String? tokenIn(String raw) {
    final text = raw.trim();
    if (!text.toLowerCase().startsWith(prefix)) return null;
    final token = text.substring(prefix.length).toLowerCase();
    return _token.hasMatch(token) ? token : null;
  }
}

/// The signed-in person: their QR code and name.
class MyPerson {
  final String id;
  final String qrToken;
  final String name;

  const MyPerson({required this.id, required this.qrToken, required this.name});

  factory MyPerson.fromJson(Map<String, dynamic> json) => MyPerson(
        id: json['person_id'] as String,
        qrToken: json['qr_token'] as String,
        name: (json['full_name'] as String?)?.trim().isNotEmpty == true ? json['full_name'] as String : 'Member',
      );

  String get qrData => PersonQr.encode(qrToken);
}

/// The signed-in person's QR code (made the first time it's asked for; it
/// takes in what a gym's desk registered with their confirmed email).
final myPersonProvider = FutureProvider<MyPerson?>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return null;
  final result = await ref.watch(supabaseProvider).rpc('my_person');
  return MyPerson.fromJson(Map<String, dynamic>.from(result as Map));
});

/// A new QR code for the signed-in person; the old one stops working at
/// every gym. Returns the new one.
Future<void> renewMyQr(WidgetRef ref) async {
  await ref.read(supabaseProvider).rpc('my_person_new_qr');
  ref.invalidate(myPersonProvider);
}
