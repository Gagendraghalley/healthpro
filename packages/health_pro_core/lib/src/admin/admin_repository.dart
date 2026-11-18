import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_provider.dart';
import '../venues/venue.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) => AdminRepository(ref.watch(supabaseProvider)));

/// Venues waiting for the Health Pro team, oldest first.
final pendingVenuesProvider = FutureProvider<List<Venue>>((ref) => ref.watch(adminRepositoryProvider).pendingVenues());

/// Admin-only actions; the database checks profiles.role = 'admin'.
class AdminRepository {
  AdminRepository(this._client);
  final SupabaseClient _client;

  Future<List<Venue>> pendingVenues() async {
    final rows = await _client
        .from('venues')
        .select()
        .eq('verification_status', VerificationStatus.pending)
        .order('created_at');
    return rows.map(Venue.fromJson).toList();
  }

  /// Verifies the venue (it goes live) or sends it back with [note].
  Future<void> reviewVenue(String venueId, {required bool approve, String? note}) =>
      _client.rpc('review_venue', params: {'venue_id': venueId, 'approve': approve, 'note': note});

  Future<void> setModuleEnabled(String key, bool enabled) =>
      _client.rpc('set_module_enabled', params: {'module_key': key, 'enabled': enabled});

  /// The errors the app hit, the latest first ('errors.view').
  Future<List<AppError>> appErrors() async {
    final rows =
        await _client.from('app_errors').select('*, profiles(full_name, email)').order('last_seen', ascending: false).limit(300);
    return rows.map(AppError.fromJson).toList();
  }

  /// Clears one the team has put right; it comes back if it happens again.
  Future<void> clearAppError(int id) => _client.from('app_errors').delete().eq('id', id);
}

/// Admin -> App errors.
final appErrorsProvider = FutureProvider<List<AppError>>((ref) => ref.watch(adminRepositoryProvider).appErrors());

/// One kind of error the app hit (app_errors): how often, when, and where.
class AppError {
  final int id;
  final String message;
  final String? stack;
  final String? page;
  final String? platform;
  final int times;
  final DateTime firstSeen;
  final DateTime lastSeen;

  /// The last signed-in person it happened to, when the viewer may see who
  /// (super admins, and those who manage users); null for a visitor.
  final String? userId;
  final String? userName;
  final String? userEmail;

  const AppError({
    required this.id,
    required this.message,
    this.stack,
    this.page,
    this.platform,
    required this.times,
    required this.firstSeen,
    required this.lastSeen,
    this.userId,
    this.userName,
    this.userEmail,
  });

  factory AppError.fromJson(Map<String, dynamic> json) {
    final who = json['profiles'] as Map<String, dynamic>?;
    final name = (who?['full_name'] as String?)?.trim();
    return AppError(
      id: (json['id'] as num).toInt(),
      message: json['message'] as String,
      stack: json['stack'] as String?,
      page: json['page'] as String?,
      platform: json['platform'] as String?,
      times: (json['times'] as num).toInt(),
      firstSeen: DateTime.parse(json['first_seen'] as String),
      lastSeen: DateTime.parse(json['last_seen'] as String),
      userId: json['user_id'] as String?,
      userName: name == null || name.isEmpty ? null : name,
      userEmail: who?['email'] as String?,
    );
  }

  /// Who it happened to last, as far as the viewer may see.
  String get who => userId == null ? 'A visitor' : (userName ?? userEmail ?? 'Someone signed in');
}
