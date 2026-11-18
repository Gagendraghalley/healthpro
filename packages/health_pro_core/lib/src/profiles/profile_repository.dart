import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_repository.dart';
import '../supabase/supabase_provider.dart';
import 'profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(supabaseProvider)));

/// The signed-in user's profile; null when nobody is signed in.
final myProfileProvider = FutureProvider<Profile?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  return ref.watch(profileRepositoryProvider).get(userId);
});

class ProfileRepository {
  ProfileRepository(this._client);
  final SupabaseClient _client;

  Future<Profile?> get(String userId) async {
    final row = await _client.from('profiles').select().eq('id', userId).maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  /// Only these can be changed by the user (the role can't). [avatarUrl] is
  /// their photo's address (from [uploadPhoto]); null takes it off.
  Future<void> update(String userId,
          {required String fullName, String? phone, String? dzongkhag, required String? avatarUrl}) =>
      _client.from('profiles').update({
        'full_name': fullName.trim(),
        'phone': phone,
        'dzongkhag': dzongkhag,
        'avatar_url': avatarUrl,
      }).eq('id', userId);

  /// Where profile photos are kept: public, a folder per account that only
  /// its owner changes.
  static const photoBucket = 'profile-photos';

  /// A new profile photo in their own folder; returns its public address.
  Future<String> uploadPhoto(String userId, ({Uint8List bytes, String contentType}) photo) async {
    final ext = switch (photo.contentType) { 'image/png' => 'png', 'image/webp' => 'webp', _ => 'jpg' };
    final path = '$userId/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await _client.storage
        .from(photoBucket)
        .uploadBinary(path, photo.bytes, fileOptions: FileOptions(contentType: photo.contentType, upsert: false));
    return _client.storage.from(photoBucket).getPublicUrl(path);
  }

  /// Takes their old photo at [url] out of storage once it's been replaced
  /// or removed. Anything that isn't in their own folder is left alone.
  Future<void> removePhoto(String userId, String url) async {
    const marker = '/$photoBucket/';
    final at = url.indexOf(marker);
    if (at < 0) return;
    final path = Uri.decodeComponent(url.substring(at + marker.length).split('?').first);
    if (!path.startsWith('$userId/')) return;
    try {
      await _client.storage.from(photoBucket).remove([path]);
    } catch (_) {
      // An old picture left behind is harmless; their profile is saved.
    }
  }

  /// Their app colours on their account (Account -> Appearance): palette ids,
  /// null for Health Pro's own. Null when there's no profile.
  Future<({String? primary, String? accent})?> theme(String userId) async {
    final row = await _client.from('profiles').select('theme_primary, theme_accent').eq('id', userId).maybeSingle();
    if (row == null) return null;
    return (primary: row['theme_primary'] as String?, accent: row['theme_accent'] as String?);
  }

  Future<void> setTheme(String userId, {String? primary, String? accent}) =>
      _client.from('profiles').update({'theme_primary': primary, 'theme_accent': accent}).eq('id', userId);
}
