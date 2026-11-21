import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_repository.dart';
import '../profiles/profile_repository.dart';
import '../supabase/supabase_provider.dart';
import 'venue.dart';

final venueRepositoryProvider = Provider<VenueRepository>((ref) => VenueRepository(ref.watch(supabaseProvider)));

/// Verified venues of one type, for everyone (visitors too).
final publicVenuesProvider = FutureProvider.family<List<Venue>, ({String type, String? dzongkhag})>(
  (ref, q) => ref.watch(venueRepositoryProvider).listPublic(type: q.type, dzongkhag: q.dzongkhag),
);

/// One venue: verified ones for everyone; any status for its staff and admins.
final venueProvider = FutureProvider.family<Venue?, String>((ref, id) => ref.watch(venueRepositoryProvider).get(id));

/// The venues the signed-in user runs (venue_staff), with their role at each.
final myVenuesProvider = FutureProvider<List<MyVenue>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  return ref.watch(venueRepositoryProvider).myVenues();
});

/// The venue and the signed-in user's place there: their venue_staff role
/// and its permissions, or 'admin' (everything) for super admins; null when
/// they don't run it.
final venueAccessProvider = FutureProvider.family<VenueAccess?, String>((ref, venueId) async {
  final mine = await ref.watch(myVenuesProvider.future);
  for (final v in mine) {
    if (v.venue.id == venueId) return v.access;
  }
  final profile = await ref.watch(myProfileProvider.future);
  if ((profile?.isAdmin ?? false) && (profile?.isActive ?? false)) {
    final venue = await ref.watch(venueProvider(venueId).future);
    if (venue != null) return VenueAccess(venue, VenueRole.admin);
  }
  return null;
});

final venueStaffProvider = FutureProvider.family<List<VenueStaffMember>, String>(
  (ref, venueId) => ref.watch(venueRepositoryProvider).staff(venueId),
);

final venueReviewsProvider = FutureProvider.family<List<VenueReview>, String>(
  (ref, venueId) => ref.watch(venueRepositoryProvider).reviews(venueId),
);

class VenueRepository {
  VenueRepository(this._client);
  final SupabaseClient _client;

  static const photoBucket = 'venue-photos';

  /// Promotional videos: public, one clip in a folder per venue.
  static const videoBucket = 'venue-videos';

  /// The biggest clip a venue can upload (the bucket refuses more): 20 MB,
  /// about a minute from a phone.
  static const maxPromoVideoBytes = 20 * 1024 * 1024;

  Future<List<Venue>> listPublic({required String type, String? dzongkhag}) async {
    var query = _client.from('venues').select().eq('type', type).eq('verification_status', VerificationStatus.verified);
    if (dzongkhag != null) query = query.eq('dzongkhag', dzongkhag);
    final rows = await query.order('name');
    return rows.map(Venue.fromJson).toList();
  }

  Future<Venue?> get(String id) async {
    final row = await _client.from('venues').select().eq('id', id).maybeSingle();
    return row == null ? null : Venue.fromJson(row);
  }

  /// The venues the signed-in user runs, by name, with what their role lets
  /// them do there (as each venue's organisation has the role). None while
  /// their account is turned off; roles that are turned off are left out.
  Future<List<MyVenue>> myVenues() async {
    final rows = await _client.rpc('my_venues') as List;
    return [for (final r in rows) MyVenue.fromJson(r as Map<String, dynamic>)];
  }

  /// A new venue, waiting for the Health Pro team; the caller becomes its
  /// owner. Returns its id.
  Future<String> register(VenueDraft draft) async =>
      await _client.rpc('register_venue', params: {'details': draft.toJson()}) as String;

  Future<void> update(String venueId, VenueDraft draft) =>
      _client.rpc('update_venue', params: {'venue_id': venueId, 'details': draft.toJson()});

  Future<void> setPhotos(String venueId, List<String> photos) =>
      _client.rpc('update_venue', params: {'venue_id': venueId, 'details': {'photos': photos}});

  /// Uploads a photo into the venue's folder (only its owner and managers
  /// can); returns its public address.
  Future<String> uploadPhoto(String venueId, Uint8List bytes, {String contentType = 'image/jpeg'}) async {
    final ext = switch (contentType) { 'image/png' => 'png', 'image/webp' => 'webp', _ => 'jpg' };
    final path = '$venueId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage
        .from(photoBucket)
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: false));
    return _client.storage.from(photoBucket).getPublicUrl(path);
  }

  /// Where everyone can watch the clip at [path] (Venue.promoVideo).
  String? promoVideoUrl(String? path) =>
      path == null || path.isEmpty ? null : _client.storage.from(videoBucket).getPublicUrl(path);

  /// Uploads [bytes] as the venue's promotional video, in place of the one
  /// it had: a venue keeps one clip, so the old file is removed (and any
  /// left behind by an upload that didn't finish). Returns its path.
  Future<String> setPromoVideo(String venueId, Uint8List bytes, {required String contentType}) async {
    if (bytes.length > maxPromoVideoBytes) throw StateError(promoVideoTooBig);
    final ext = switch (contentType) { 'video/webm' => 'webm', 'video/quicktime' => 'mov', _ => 'mp4' };
    final path = '$venueId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final current = (await get(venueId))?.promoVideo;
    final storage = _client.storage.from(videoBucket);
    try {
      await _removeVideosExcept(venueId, keep: current);
      await storage.uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: false));
    } on StorageException catch (e) {
      throw StateError(e.statusCode == '413' ? promoVideoTooBig : 'The video could not be uploaded. Please try again.');
    }
    await _client.rpc('set_venue_promo_video', params: {'venue_id': venueId, 'path': path});
    await _removeVideosExcept(venueId, keep: path);
    return path;
  }

  /// Takes the venue's promotional video away, and its file.
  Future<void> removePromoVideo(String venueId) async {
    await _client.rpc('set_venue_promo_video', params: {'venue_id': venueId, 'path': null});
    await _removeVideosExcept(venueId, keep: null);
  }

  static const promoVideoTooBig = 'That video is too big. Choose one of up to 20 MB.';

  /// Removes the files in the venue's video folder, but for [keep].
  Future<void> _removeVideosExcept(String venueId, {required String? keep}) async {
    try {
      final storage = _client.storage.from(videoBucket);
      final files = await storage.list(path: venueId);
      final old = [for (final f in files) '$venueId/${f.name}'].where((p) => p != keep).toList();
      if (old.isNotEmpty) await storage.remove(old);
    } catch (_) {
      // A leftover file is harmless: the venue points at its clip, and the
      // folder is tidied the next time one is uploaded.
    }
  }

  /// Owners first, then the roles that come with Health Pro, then the rest;
  /// by name within each.
  Future<List<VenueStaffMember>> staff(String venueId) async {
    final rows = await _client
        .from('venue_staff')
        .select('venue_id, user_id, role, profile:profiles!venue_staff_user_id_fkey(full_name, email, phone, avatar_url), '
            'role_info:roles!venue_staff_role_fkey(name)')
        .eq('venue_id', venueId);
    return rows.map(VenueStaffMember.fromJson).toList()..sort(compareStaff);
  }

  /// Adds someone with a Health Pro account (by their email) as [role].
  Future<void> addStaff(String venueId, String email, String role) => _client.rpc('add_venue_staff', params: {
        'venue_id': venueId,
        'email': email.trim().toLowerCase(),
        'staff_role': role,
      });

  /// Gives [userId] the venue role [role] there (or changes it).
  Future<void> setStaffRole(String venueId, String userId, String role) =>
      _client.rpc('set_venue_staff_role', params: {'venue_id': venueId, 'user_id': userId, 'role_key': role});

  Future<void> removeStaff(String venueId, String userId) =>
      _client.rpc('remove_venue_staff', params: {'venue_id': venueId, 'staff_user_id': userId});

  Future<List<VenueReview>> reviews(String venueId) async {
    final rows =
        await _client.from('reviews').select().eq('venue_id', venueId).order('created_at', ascending: false).limit(50);
    return rows.map(VenueReview.fromJson).toList();
  }

  /// Only people who have used the venue (paid there) can review it.
  Future<void> saveReview(String venueId, int rating, String? comment) =>
      _client.rpc('save_review', params: {'venue_id': venueId, 'rating': rating, 'comment': comment});

  Future<void> deleteMyReview(String venueId) => _client.rpc('delete_my_review', params: {'venue_id': venueId});
}

/// Staff list order: owners, then the roles that come with Health Pro, then
/// the venue's other roles; by name within each.
int compareStaff(VenueStaffMember a, VenueStaffMember b) {
  const order = [VenueRole.owner, VenueRole.manager, VenueRole.staff, VenueRole.trainer];
  int rank(String role) => order.contains(role) ? order.indexOf(role) : order.length;
  final byRole = rank(a.role).compareTo(rank(b.role));
  return byRole != 0 ? byRole : a.name.toLowerCase().compareTo(b.name.toLowerCase());
}
