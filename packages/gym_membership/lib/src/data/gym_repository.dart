import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:typed_data';

import 'exports.dart';
import 'follow_ups.dart';
import 'gym_models.dart';
import 'joining.dart';
import 'online_payments.dart';
import 'receipts.dart';
import 'trainers.dart';
import 'member_qr.dart';
import 'registered_member.dart';

/// venue_types.key for gyms.
const gymVenueType = 'gym';

/// app_modules.key and payments.module_key.
const gymModuleKey = 'gym_membership';

final gymRepositoryProvider = Provider<GymRepository>(
    (ref) => GymRepository(ref.watch(supabaseProvider)));

/// A gym's plans: those on sale ([all] false, for members) or every one
/// (for its owner and managers).
final gymPlansProvider =
    FutureProvider.family<List<GymPlan>, ({String venueId, bool all})>(
  (ref, q) =>
      ref.watch(gymRepositoryProvider).plans(q.venueId, includeInactive: q.all),
);

/// Every membership at a gym, for its staff.
final gymSubscriptionsProvider =
    FutureProvider.family<List<GymSubscription>, String>(
  (ref, venueId) =>
      ref.watch(gymRepositoryProvider).venueSubscriptions(venueId),
);

/// Today's check-ins at a gym (Bhutan time), newest first.
final gymCheckInsTodayProvider =
    FutureProvider.family<List<GymCheckIn>, String>(
  (ref, venueId) => ref
      .watch(gymRepositoryProvider)
      .venueCheckIns(venueId, since: bhutanMidnightUtc(BhutanTime.today())),
);

/// The past week's check-ins at a gym (today and the 6 days before),
/// newest first, for the dashboard's Recent activity.
final gymRecentCheckInsProvider =
    FutureProvider.family<List<GymCheckIn>, String>(
  (ref, venueId) => ref.watch(gymRepositoryProvider).venueCheckIns(
        venueId,
        since: bhutanMidnightUtc(
            BhutanTime.today().subtract(const Duration(days: 6))),
      ),
);

/// A gym's check-ins since a Bhutan date (up to 5,000), for its reports.
final gymCheckInsSinceProvider =
    FutureProvider.family<List<GymCheckIn>, ({String venueId, DateTime since})>(
  (ref, q) => ref
      .watch(gymRepositoryProvider)
      .venueCheckIns(q.venueId, since: bhutanMidnightUtc(q.since), limit: 5000),
);

final gymDashboardProvider = FutureProvider.family<GymDashboard, String>(
  (ref, venueId) => ref.watch(gymRepositoryProvider).dashboard(venueId),
);

/// The members a gym registered at its front desk, by name.
final gymMembersProvider = FutureProvider.family<List<GymMember>, String>(
  (ref, venueId) => ref.watch(gymRepositoryProvider).registeredMembers(venueId),
);

/// One registered member, with their place's names.
final gymMemberProvider = FutureProvider.autoDispose.family<GymMember?, String>(
  (ref, id) => ref.watch(gymRepositoryProvider).registeredMember(id),
);

/// A registered member's visits, newest first.
final gymMemberCheckInsProvider =
    FutureProvider.autoDispose.family<List<GymCheckIn>, String>(
  (ref, id) => ref.watch(gymRepositoryProvider).registeredMemberCheckIns(id),
);

/// A member's photo (private: only the gym's staff may see it), kept while
/// the app runs.
final gymMemberPhotoProvider = FutureProvider.family<Uint8List?, String>(
  (ref, path) => ref.watch(gymRepositoryProvider).memberPhoto(path),
);

/// A gym's requests to join (waiting first), for its front desk.
final gymJoinRequestsProvider =
    FutureProvider.autoDispose.family<List<JoinRequest>, String>(
  (ref, venueId) => ref.watch(gymRepositoryProvider).joinRequests(venueId),
);

/// How many people are waiting to hear back from a gym's desk.
final gymWaitingRequestsProvider = FutureProvider.family<int, String>(
  (ref, venueId) => ref.watch(gymRepositoryProvider).waitingRequests(venueId),
);

/// Someone already on Health Pro, to add to a gym: by their QR code or their
/// request to join.
final gymPersonDetailsProvider = FutureProvider.autoDispose.family<
    PersonDetails, ({String venueId, String? qrToken, String? requestId})>(
  (ref, q) => ref
      .watch(gymRepositoryProvider)
      .personDetails(q.venueId, qrToken: q.qrToken, requestId: q.requestId),
);

/// What gyms often have: ticks on the gym's form (it adds its own too).
const gymFacilities = [
  'Shower',
  'Changing rooms',
  'Lockers',
  'Massage',
  'Sauna',
  'Steam room',
  'Personal training',
  'Group classes',
  'Yoga',
  'Cardio machines',
  'Free weights',
  'Air conditioning',
  'Drinking water',
  'Parking',
  'Wi-Fi',
];

/// Each verified gym's lowest and highest package price, for the list.
final gymPriceRangesProvider =
    FutureProvider<Map<String, ({int low, int high})>>(
  (ref) => ref.watch(gymRepositoryProvider).priceRanges(),
);

/// 'Nu. 2,000 – 10,000', 'Nu. 1,500'.
String priceRangeText(int low, int high) => low == high
    ? formatNu(low)
    : '${formatNu(low)} – ${formatNu(high).replaceFirst('Nu. ', '')}';

/// A gym's settings: its bank account, reminder days, who answers joins.
final gymSettingsProvider = FutureProvider.family<GymSettings, String>(
  (ref, venueId) => ref.watch(gymRepositoryProvider).settings(venueId),
);

/// A gym's online payments: waiting ones first, then the latest answered.
final gymPaymentClaimsProvider =
    FutureProvider.autoDispose.family<List<PaymentClaim>, String>(
  (ref, venueId) => ref.watch(gymRepositoryProvider).paymentClaims(venueId),
);

/// How many online payments wait for a gym to confirm them.
final gymWaitingPaymentsProvider = FutureProvider.family<int, String>(
  (ref, venueId) => ref.watch(gymRepositoryProvider).waitingPayments(venueId),
);

/// One member's online payments, newest first.
final gymMemberClaimsProvider =
    FutureProvider.autoDispose.family<List<PaymentClaim>, String>(
  (ref, gymMemberId) =>
      ref.watch(gymRepositoryProvider).memberClaims(gymMemberId),
);

/// A gym's pauses running or planned (one per member at most).
final gymOpenPausesProvider = FutureProvider.family<List<GymPause>, String>(
  (ref, venueId) => ref.watch(gymRepositoryProvider).openPauses(venueId),
);

/// One registered member's pauses, latest first.
final gymMemberPausesProvider =
    FutureProvider.autoDispose.family<List<GymPause>, String>(
  (ref, gymMemberId) =>
      ref.watch(gymRepositoryProvider).memberPauses(gymMemberId),
);

/// A payment's receipt.
final gymReceiptProvider = FutureProvider.autoDispose.family<Receipt, String>(
  (ref, paymentId) => ref.watch(gymRepositoryProvider).receipt(paymentId),
);

/// The signed-in trainer's profile, gyms, attendance and reviews.
final myTrainingProvider = FutureProvider<MyTraining>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return const MyTraining();
  return ref.watch(gymRepositoryProvider).myTraining();
});

/// A gym's trainers, for its staff (verify, timings, attendance).
final gymTrainersProvider =
    FutureProvider.autoDispose.family<List<GymTrainer>, String>(
  (ref, venueId) => ref.watch(gymRepositoryProvider).gymTrainers(venueId),
);

/// A gym's verified trainers: on its page, and to choose from.
final gymVerifiedTrainersProvider =
    FutureProvider.family<List<TrainerProfile>, String>(
  (ref, venueId) => ref.watch(gymRepositoryProvider).verifiedTrainers(venueId),
);

/// The trainer [gymMemberId] has now, by account id; null: none.
final memberTrainerProvider =
    FutureProvider.autoDispose.family<String?, String>(
  (ref, gymMemberId) =>
      ref.watch(gymRepositoryProvider).memberTrainer(gymMemberId),
);

/// A trainer's public profile; null when it isn't public.
final trainerProfileProvider =
    FutureProvider.autoDispose.family<TrainerProfile?, String>(
  (ref, userId) => ref.watch(gymRepositoryProvider).trainerProfile(userId),
);

final trainerCertificatesProvider =
    FutureProvider.autoDispose.family<List<TrainerCertificate>, String>(
  (ref, userId) => ref.watch(gymRepositoryProvider).trainerCertificates(userId),
);

/// The gyms that verified a trainer: (id, name, place).
final trainerGymsProvider = FutureProvider.autoDispose
    .family<List<({String id, String name, String place})>, String>(
  (ref, userId) => ref.watch(gymRepositoryProvider).trainerGyms(userId),
);

/// A trainer's week; seen from gym [venueId], the others are Not available.
final trainerTimingsProvider = FutureProvider.autoDispose
    .family<List<TrainerSlot>, ({String trainerId, String? venueId})>(
  (ref, q) => ref
      .watch(gymRepositoryProvider)
      .trainerTimings(q.trainerId, venueId: q.venueId),
);

final trainerReviewsProvider =
    FutureProvider.autoDispose.family<List<TrainerReview>, String>(
  (ref, userId) => ref.watch(gymRepositoryProvider).trainerReviews(userId),
);

/// The signed-in person trained with them, so may review them.
final canReviewTrainerProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, userId) async {
  if (ref.watch(currentUserIdProvider) == null) return false;
  return ref.watch(gymRepositoryProvider).canReviewTrainer(userId);
});

/// The signed-in person's gyms, requests to join and visits.
final myMembershipsProvider = FutureProvider<MyMemberships>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return MyMemberships.none;
  return ref.watch(gymRepositoryProvider).myMemberships();
});

/// The moment Bhutan's [date] begins, in UTC.
DateTime bhutanMidnightUtc(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day).subtract(BhutanTime.offset);

/// After a change to a gym's memberships: everything that shows them.
void refreshGym(WidgetRef ref, String venueId) {
  ref.invalidate(gymMembersProvider(venueId));
  ref.invalidate(gymSubscriptionsProvider(venueId));
  ref.invalidate(gymDashboardProvider(venueId));
  ref.invalidate(gymCheckInsTodayProvider(venueId));
  ref.invalidate(gymRecentCheckInsProvider(venueId));
  ref.invalidate(gymCheckInsSinceProvider);
  ref.invalidate(gymJoinRequestsProvider(venueId));
  ref.invalidate(gymWaitingRequestsProvider(venueId));
  ref.invalidate(gymPaymentClaimsProvider(venueId));
  ref.invalidate(gymWaitingPaymentsProvider(venueId));
  ref.invalidate(gymMemberClaimsProvider);
  ref.invalidate(gymTrainersProvider(venueId));
  ref.invalidate(gymVerifiedTrainersProvider(venueId));
  ref.invalidate(memberTrainerProvider);
  ref.invalidate(gymOpenPausesProvider(venueId));
  ref.invalidate(gymMemberPausesProvider);
  // Registering someone marks their enquiry joined; every change is logged.
  ref.invalidate(gymEnquiriesProvider(venueId));
  ref.invalidate(gymAuditLogProvider);
}

/// Gym data. Plans, memberships and check-ins change only through the
/// database's gym_* functions, which check who is calling.
class GymRepository {
  GymRepository(this._client);
  final SupabaseClient _client;

  static const _memberFields = 'full_name, phone, member_code';
  static const _registeredFields = 'full_name, phone, code';
  static const _gymMemberColumns =
      '*, village:villages(name), gewog:gewogs(name), dzongkhag:dzongkhags(name), person:people(qr_token, avatar_url)';

  /// Members' photos: private, in a folder per gym.
  static const photoBucket = 'gym-member-photos';

  Future<List<GymPlan>> plans(String venueId,
      {bool includeInactive = false}) async {
    var query = _client.from('gym_plans').select().eq('venue_id', venueId);
    if (!includeInactive) query = query.eq('is_active', true);
    final rows = await query.order('sort_order').order('price');
    return rows.map(GymPlan.fromJson).toList();
  }

  /// A new plan ([planId] null) or changes to one; owners and managers only.
  Future<String> savePlan({
    required String venueId,
    String? planId,
    required String name,
    String? description,
    required int durationDays,
    required int price,
    bool isActive = true,
  }) async =>
      await _client.rpc('gym_save_plan', params: {
        'venue_id': venueId,
        'plan_id': planId,
        'name': name.trim(),
        'description': (description == null || description.trim().isEmpty)
            ? null
            : description.trim(),
        'duration_days': durationDays,
        'price': price,
        'is_active': isActive,
      }) as String;

  Future<List<GymSubscription>> venueSubscriptions(String venueId) async {
    final rows = await _client
        .from('gym_subscriptions')
        .select(
            '*, member:profiles!gym_subscriptions_member_id_fkey($_memberFields), '
            'registered:gym_members!gym_subscriptions_gym_member_id_fkey($_registeredFields)')
        .eq('venue_id', venueId)
        .order('requested_at', ascending: false)
        .limit(1000);
    return rows.map(GymSubscription.fromJson).toList();
  }

  Future<List<GymCheckIn>> venueCheckIns(String venueId,
      {required DateTime since, int limit = 200}) async {
    final rows = await _client
        .from('gym_check_ins')
        .select('*, member:profiles!gym_check_ins_member_id_fkey(full_name), '
            'registered:gym_members!gym_check_ins_gym_member_id_fkey(full_name)')
        .eq('venue_id', venueId)
        .gte('checked_in_at', since.toUtc().toIso8601String())
        .order('checked_in_at', ascending: false)
        .limit(limit);
    return rows.map(GymCheckIn.fromJson).toList();
  }

  /// Checks a member in; fails (with the reason) unless they have a
  /// membership at this gym covering today. Someone on Health Pro who isn't
  /// a member here yet: [NotMemberHere], to add them.
  ///
  /// A trainer verified here arrives instead ([TrainerArrival]); with
  /// [asMember], a trainer who is also a member here is checked in as one.
  Future<CheckInOutcome> checkIn(String venueId, MemberRef member,
      {bool asMember = false}) async {
    final result = member.id != null
        ? await _client.rpc('gym_check_in_account',
            params: {'venue_id': venueId, 'member_id': member.id})
        : member.cardToken != null
            ? await _client.rpc('gym_check_in_member', params: {
                'venue_id': venueId,
                'qr_token': member.cardToken,
                'as_member': asMember
              })
            : await _client.rpc('gym_check_in_by_code',
                params: {'venue_id': venueId, 'code': member.code});
    final json = Map<String, dynamic>.from(result as Map);
    if (json['trainer'] == true) return TrainerArrival.fromJson(json);
    if (json['not_member'] == true) {
      throw NotMemberHere(
          name: json['member_name'] as String? ?? 'This person',
          personToken: json['person_token'] as String?);
    }
    return CheckInResult.fromJson(json);
  }

  /// Checks in a member by the phone number they gave this gym. Bhutanese
  /// eight-digit numbers and international numbers are accepted.
  Future<CheckInResult> checkInByPhone(String venueId, String phone) async {
    final result = await _client.rpc('gym_check_in_by_phone',
        params: {'venue_id': venueId, 'phone': phone});
    return CheckInResult.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<GymDashboard> dashboard(String venueId) async {
    final result =
        await _client.rpc('gym_dashboard', params: {'venue_id': venueId});
    return GymDashboard.fromJson(Map<String, dynamic>.from(result as Map));
  }

  // ─── Members registered at the front desk ─────────────────────────────

  Future<List<GymMember>> registeredMembers(String venueId) async {
    final rows = await _client
        .from('gym_members')
        .select(_gymMemberColumns)
        .eq('venue_id', venueId)
        .order('full_name');
    return rows.map(GymMember.fromJson).toList();
  }

  /// A few members at [venueIds] with [search] in their name, phone, card
  /// code or email, by name: the search in the bar's.
  Future<List<GymMember>> searchMembers(List<String> venueIds, String search,
      {int limit = 8}) async {
    // A phone number typed with spaces or dashes, as it's kept: without.
    final digits = search.replaceAll(RegExp(r'[\s-]'), '');
    final pattern = userSearchPattern(
        RegExp(r'^\+?\d{3,}$').hasMatch(digits) ? digits : search);
    if (venueIds.isEmpty || pattern.isEmpty) return const [];
    final rows = await _client
        .from('gym_members')
        .select(_gymMemberColumns)
        .inFilter('venue_id', venueIds)
        .or('full_name.ilike.%$pattern%,phone.ilike.%$pattern%,'
            'code.ilike.%$pattern%,email.ilike.%$pattern%')
        .order('full_name')
        .limit(limit);
    return rows.map(GymMember.fromJson).toList();
  }

  Future<GymMember?> registeredMember(String id) async {
    final row = await _client
        .from('gym_members')
        .select(_gymMemberColumns)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : GymMember.fromJson(row);
  }

  /// The registered member whose card holds [qrToken], if this gym's.
  Future<GymMember?> registeredMemberByCard(
      String venueId, String qrToken) async {
    final row = await _client
        .from('gym_members')
        .select(_gymMemberColumns)
        .eq('venue_id', venueId)
        .eq('qr_token', qrToken)
        .maybeSingle();
    return row == null ? null : GymMember.fromJson(row);
  }

  Future<List<GymCheckIn>> registeredMemberCheckIns(String gymMemberId) async {
    final rows = await _client
        .from('gym_check_ins')
        .select()
        .eq('gym_member_id', gymMemberId)
        .order('checked_in_at', ascending: false)
        .limit(120);
    return rows.map(GymCheckIn.fromJson).toList();
  }

  /// Registers a member, and sells them [sale] (from their date of joining)
  /// if given. Returns their id. Someone already on Health Pro, by the QR
  /// code they showed ([personQr]) or their request to join
  /// ([joinRequestId], which this approves), keeps their QR code.
  Future<String> registerMember(String venueId, MemberDetails details,
      {PackageSale? sale, String? personQr, String? joinRequestId}) async {
    final discount = sale?.discountDetails;
    final result = await _client.rpc('gym_register_member', params: {
      'venue_id': venueId,
      'details': {...details.toJson(), if (discount != null) 'discount': discount},
      'plan_id': sale?.plan.id,
      'months': sale?.months,
      'amount': sale?.amount ?? 0,
      'method': sale?.method?.value,
      'reference': _clean(sale?.reference),
      'person_qr': personQr,
      'join_request_id': joinRequestId,
    });
    return (result as Map)['gym_member_id'] as String;
  }

  // ─── Joining: people already on Health Pro ────────────────────────────

  /// Their details from their last gym (or account), to add them here.
  Future<PersonDetails> personDetails(String venueId,
      {String? qrToken, String? requestId}) async {
    final result = await _client.rpc('gym_person_details', params: {
      'venue_id': venueId,
      'qr_token': qrToken,
      'join_request_id': requestId,
    });
    return PersonDetails.fromJson(Map<String, dynamic>.from(result as Map));
  }

  static const _requestColumns =
      '*, person:people(full_name, email, phone), plan:gym_plans(name, price)';

  /// The gym's requests to join: waiting ones, then the latest answered.
  Future<List<JoinRequest>> joinRequests(String venueId) async {
    final rows = await _client
        .from('gym_join_requests')
        .select(_requestColumns)
        .eq('venue_id', venueId)
        .order('created_at', ascending: false)
        .limit(200);
    final list = rows.map(JoinRequest.fromJson).toList();
    return [
      ...list.where((r) => r.isPending).toList().reversed,
      ...list.where((r) => !r.isPending)
    ];
  }

  Future<int> waitingRequests(String venueId) async {
    final rows = await _client
        .from('gym_join_requests')
        .select('id')
        .eq('venue_id', venueId)
        .eq('status', 'pending');
    return rows.length;
  }

  Future<void> declineJoinRequest(String requestId, {String? note}) =>
      _client.rpc('gym_decline_join_request',
          params: {'request_id': requestId, 'note': _clean(note)});

  /// Asks to join [venueId] (from its QR code), with the package they'd like.
  Future<void> requestToJoin(String venueId,
          {String? planId, String? message}) =>
      _client.rpc('gym_request_to_join', params: {
        'venue_id': venueId,
        'plan_id': planId,
        'message': _clean(message)
      });

  Future<void> cancelJoinRequest(String requestId) =>
      _client.rpc('gym_cancel_join_request', params: {'request_id': requestId});

  Future<MyMemberships> myMemberships() async {
    final result =
        Map<String, dynamic>.from(await _client.rpc('my_gyms') as Map);
    final gyms = (result['gyms'] as List? ?? const []).map((row) {
      final gym = Map<String, dynamic>.from(row as Map);
      final account = gym['payment_account'];
      final path = gym['payment_qr_path'] as String? ??
          (account is Map ? account['payment_qr_path'] as String? : null);
      if (path != null && path.isNotEmpty) {
        gym['payment_qr_url'] = paymentQrUrl(path);
      }
      return gym;
    }).toList();
    return MyMemberships.fromJson({...result, 'gyms': gyms});
  }

  Future<Map<String, ({int low, int high})>> priceRanges() async {
    final rows = await _client.rpc('gym_price_ranges') as List;
    return {
      for (final r in rows.cast<Map>())
        r['venue_id'] as String: (
          low: (r['lowest'] as num).toInt(),
          high: (r['highest'] as num).toInt()
        ),
    };
  }

  // ─── Trainers ─────────────────────────────────────────────────────────

  /// Trainers' photos and certificates: public, a folder per trainer.
  static const trainerBucket = 'trainer-media';

  Future<MyTraining> myTraining() async =>
      MyTraining.fromJson(Map<String, dynamic>.from(
          await _client.rpc('my_trainer_overview') as Map));

  Future<void> saveTrainerProfile(TrainerProfile profile) => _client
      .rpc('trainer_save_profile', params: {'details': profile.toJson()});

  /// Uploads a photo or certificate into the signed-in trainer's folder;
  /// returns its public address.
  Future<String> uploadTrainerFile(Uint8List bytes, String contentType) async {
    final uid = _client.auth.currentUser!.id;
    final ext = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'application/pdf' => 'pdf',
      _ => 'jpg',
    };
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from(trainerBucket).uploadBinary(path, bytes,
        fileOptions: FileOptions(contentType: contentType, upsert: false));
    return _client.storage.from(trainerBucket).getPublicUrl(path);
  }

  Future<void> addCertificate(
          {required String title,
          String? issuer,
          DateTime? issuedOn,
          String? fileUrl}) =>
      _client.rpc('trainer_add_certificate', params: {
        'title': title.trim(),
        'issuer': _clean(issuer),
        'issued_on': issuedOn == null ? null : isoDate(issuedOn),
        'file_url': fileUrl,
      });

  Future<void> removeCertificate(String id) =>
      _client.rpc('trainer_remove_certificate', params: {'certificate_id': id});

  Future<void> requestGym(String venueId, {String? message}) =>
      _client.rpc('trainer_request_gym',
          params: {'venue_id': venueId, 'message': _clean(message)});

  Future<void> leaveGym(String venueId) =>
      _client.rpc('trainer_leave_gym', params: {'venue_id': venueId});

  Future<void> saveSlots(String venueId, List<TrainerSlot> slots) =>
      _client.rpc('trainer_save_slots', params: {
        'venue_id': venueId,
        'slots': [for (final s in slots) s.toJson()]
      });

  Future<List<GymTrainer>> gymTrainers(String venueId) async {
    final result = await _client
        .rpc('gym_trainers_overview', params: {'venue_id': venueId}) as List;
    return [
      for (final r in result)
        GymTrainer.fromJson(Map<String, dynamic>.from(r as Map))
    ];
  }

  Future<void> decideTrainer(String venueId, String userId,
          {required bool approve, String? note}) =>
      _client.rpc('gym_decide_trainer', params: {
        'venue_id': venueId,
        'user_id': userId,
        'approve': approve,
        'note': _clean(note)
      });

  Future<void> deactivateTrainer(String venueId, String userId) =>
      _client.rpc('gym_deactivate_trainer', params: {
        'venue_id': venueId,
        'user_id': userId,
      });

  Future<void> reactivateTrainer(String venueId, String userId) =>
      _client.rpc('gym_reactivate_trainer', params: {
        'venue_id': venueId,
        'user_id': userId,
      });

  /// The gym adds [trainer] itself: their account is made from their email
  /// (or found by it), their photo and certificates uploaded, and they're
  /// verified here straight away. Returns their name, and whether they were
  /// on Health Pro as a trainer already (then their own profile is kept).
  Future<({String name, bool alreadyTrainer})> addTrainer(
      String venueId, NewTrainer trainer) async {
    final Map<String, dynamic> account;
    try {
      final response = await _client.functions.invoke('admin-users', body: {
        'action': 'trainer_account',
        'venue_id': venueId,
        'email': trainer.email.trim().toLowerCase(),
        'full_name': trainer.name.trim(),
        if (_clean(trainer.phone) != null) 'phone': trainer.phone,
      });
      account = (response.data as Map?)?.cast<String, dynamic>() ?? const {};
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map ? details['error'] as String? : null;
      if (message != null) throw StateError(message);
      rethrow;
    }
    final photoUrl = trainer.photo == null
        ? null
        : await _uploadGymTrainerFile(venueId, trainer.photo!);
    final certificateUrls = [
      for (final c in trainer.certificates)
        c.file == null ? null : await _uploadGymTrainerFile(venueId, c.file!),
    ];
    final result = await _client.rpc('gym_add_trainer', params: {
      'venue_id': venueId,
      'user_id': account['user_id'],
      'details':
          trainer.toJson(photoUrl: photoUrl, certificateUrls: certificateUrls),
    }) as Map;
    return (
      name: result['name'] as String? ?? trainer.name,
      alreadyTrainer: result['profile_made'] != true
    );
  }

  /// A file of a trainer the gym is adding, in the gym's folder of
  /// trainer-media; returns its public address.
  Future<String> _uploadGymTrainerFile(
      String venueId, ({Uint8List bytes, String contentType}) file) async {
    final ext = switch (file.contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'application/pdf' => 'pdf',
      _ => 'jpg'
    };
    final path = 'gym/$venueId/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await _client.storage.from(trainerBucket).uploadBinary(path, file.bytes,
        fileOptions: FileOptions(contentType: file.contentType, upsert: false));
    return _client.storage.from(trainerBucket).getPublicUrl(path);
  }

  /// The gym changes a trainer's times here; they're told.
  Future<void> saveTrainerSlots(
          String venueId, String userId, List<TrainerSlot> slots) =>
      _client.rpc('gym_save_trainer_slots', params: {
        'venue_id': venueId,
        'user_id': userId,
        'slots': [for (final s in slots) s.toJson()]
      });

  /// Records a trainer's arrival without their QR code.
  Future<bool> markTrainerArrived(String venueId, String userId) async {
    final result = await _client.rpc('gym_trainer_mark_arrived',
        params: {'venue_id': venueId, 'user_id': userId});
    return (result as Map)['already_marked'] as bool? ?? false;
  }

  Future<List<TrainerProfile>> verifiedTrainers(String venueId) async {
    final rows = await _client
        .from('gym_trainers')
        .select('trainer:trainer_profiles(*)')
        .eq('venue_id', venueId)
        .eq('status', 'verified');
    final list = [
      for (final r in rows)
        if (r['trainer'] is Map)
          TrainerProfile.fromJson(
              Map<String, dynamic>.from(r['trainer'] as Map)),
    ];
    return list
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<String?> memberTrainer(String gymMemberId) async {
    final row = await _client
        .from('trainer_links')
        .select('trainer_id')
        .eq('gym_member_id', gymMemberId)
        .isFilter('ended_at', null)
        .maybeSingle();
    return row?['trainer_id'] as String?;
  }

  /// [gymMemberId]'s trainer becomes [trainerId] (null: none).
  Future<void> setMemberTrainer(String gymMemberId, String? trainerId) =>
      _client.rpc('gym_set_member_trainer',
          params: {'gym_member_id': gymMemberId, 'trainer_id': trainerId});

  Future<TrainerProfile?> trainerProfile(String userId) async {
    final row = await _client
        .from('trainer_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? null : TrainerProfile.fromJson(row);
  }

  Future<List<TrainerCertificate>> trainerCertificates(String userId) async {
    final rows = await _client
        .from('trainer_certificates')
        .select()
        .eq('user_id', userId)
        .order('issued_on', ascending: false);
    return rows.map(TrainerCertificate.fromJson).toList();
  }

  Future<List<({String id, String name, String place})>> trainerGyms(
      String userId) async {
    final rows = await _client
        .from('gym_trainers')
        .select('venue:venues(id, name, town, dzongkhag)')
        .eq('user_id', userId)
        .eq('status', 'verified');
    return [
      for (final r in rows)
        if (r['venue'] case final Map v)
          (
            id: v['id'] as String,
            name: v['name'] as String,
            place: [
              if ((v['town'] as String?)?.trim().isNotEmpty == true)
                v['town'] as String,
              v['dzongkhag'] as String
            ].join(', '),
          ),
    ];
  }

  Future<List<TrainerSlot>> trainerTimings(String trainerId,
      {String? venueId}) async {
    final rows = await _client.rpc('trainer_timings',
        params: {'trainer': trainerId, 'venue': venueId}) as List;
    return [
      for (final r in rows)
        TrainerSlot.fromJson(Map<String, dynamic>.from(r as Map))
            .withHere(venueId == null || (r['venue_id'] == venueId)),
    ];
  }

  Future<List<TrainerReview>> trainerReviews(String userId) async {
    final rows = await _client
        .from('trainer_reviews')
        .select()
        .eq('trainer_id', userId)
        .order('created_at', ascending: false);
    return rows.map(TrainerReview.fromJson).toList();
  }

  Future<bool> canReviewTrainer(String userId) async =>
      await _client.rpc('can_review_trainer', params: {'trainer': userId})
          as bool? ??
      false;

  Future<void> saveTrainerReview(
          String trainerId, int rating, String? comment) =>
      _client.rpc('save_trainer_review', params: {
        'trainer_id': trainerId,
        'rating': rating,
        'comment': _clean(comment)
      });

  Future<void> deleteTrainerReview(String trainerId) => _client
      .rpc('delete_my_trainer_review', params: {'trainer_id': trainerId});

  // ─── Settings and paying online ───────────────────────────────────────

  Future<GymSettings> settings(String venueId) async {
    final row = await _client
        .from('gym_settings')
        .select()
        .eq('venue_id', venueId)
        .maybeSingle();
    return row == null
        ? GymSettings.defaults(venueId)
        : GymSettings.fromJson(row);
  }

  static const paymentQrBucket = 'gym-payment-qr';

  String? paymentQrUrl(String? path) => path == null || path.isEmpty
      ? null
      : _client.storage.from(paymentQrBucket).getPublicUrl(path);

  Future<String> uploadPaymentQr(
      String venueId, Uint8List bytes, String contentType) async {
    final ext = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg'
    };
    final path = '$venueId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from(paymentQrBucket).uploadBinary(path, bytes,
        fileOptions: FileOptions(contentType: contentType, upsert: false));
    return path;
  }

  Future<void> removePaymentQr(String path) =>
      _client.storage.from(paymentQrBucket).remove([path]);

  /// Saves the gym's bank account (or none: payments at the desk only),
  /// reminder days and who answers requests to join.
  Future<void> saveSettings(GymSettings settings) =>
      _client.rpc('gym_save_settings', params: {
        'venue_id': settings.venueId,
        'bank_name': settings.account?.bankName,
        'account_number': settings.account?.accountNumber,
        'account_name': settings.account?.accountName,
        'payment_qr_path': settings.paymentQrPath,
        'reminder_days': settings.reminderDays,
        'join_approval': settings.joinApproval,
      });

  static const _claimColumns = '*, member:gym_members(full_name, code)';

  Future<List<PaymentClaim>> paymentClaims(String venueId) async {
    final rows = await _client
        .from('gym_payment_claims')
        .select(_claimColumns)
        .eq('venue_id', venueId)
        .neq('status', 'cancelled')
        .order('created_at', ascending: false)
        .limit(200);
    final list = rows.map(PaymentClaim.fromJson).toList();
    return [
      ...list.where((c) => c.isPending).toList().reversed,
      ...list.where((c) => !c.isPending)
    ];
  }

  Future<int> waitingPayments(String venueId) async {
    final rows = await _client
        .from('gym_payment_claims')
        .select('id')
        .eq('venue_id', venueId)
        .eq('status', 'pending');
    return rows.length;
  }

  Future<List<PaymentClaim>> memberClaims(String gymMemberId) async {
    final rows = await _client
        .from('gym_payment_claims')
        .select(_claimColumns)
        .eq('gym_member_id', gymMemberId)
        .order('created_at', ascending: false)
        .limit(20);
    return rows.map(PaymentClaim.fromJson).toList();
  }

  /// The gym found the payment: the package starts. Returns its last day.
  Future<DateTime> confirmClaim(String claimId) async {
    final result = await _client
        .rpc('gym_confirm_payment_claim', params: {'claim_id': claimId});
    return BhutanTime.parseDate((result as Map)['end_date'] as String);
  }

  Future<void> rejectClaim(String claimId, {String? note}) =>
      _client.rpc('gym_reject_payment_claim',
          params: {'claim_id': claimId, 'note': _clean(note)});

  /// The member paid [months] of [planId] online, Nu. [amount], journal
  /// number [jrn].
  Future<void> claimPayment(String venueId,
          {required String planId,
          required int months,
          required int amount,
          required String jrn}) =>
      _client.rpc('gym_claim_payment', params: {
        'venue_id': venueId,
        'plan_id': planId,
        'months': months,
        'amount': amount,
        'jrn': jrn
      });

  Future<void> cancelClaim(String claimId) =>
      _client.rpc('gym_cancel_payment_claim', params: {'claim_id': claimId});

  Future<void> updateMember(String gymMemberId, MemberDetails details) =>
      _client.rpc('gym_update_member',
          params: {'gym_member_id': gymMemberId, 'details': details.toJson()});

  /// Sells a registered member another package: from the day after their
  /// current one ends, or today.
  /// Sells [sale]; the payment's id (for its receipt), when they paid.
  Future<String?> renewMember(String gymMemberId, PackageSale sale) async {
    final result = await _client.rpc('gym_renew_member', params: {
      'gym_member_id': gymMemberId,
      'plan_id': sale.plan.id,
      'months': sale.months,
      'amount': sale.amount,
      'method': sale.method?.value,
      'reference': _clean(sale.reference),
      if (sale.discountDetails != null) 'discount': sale.discountDetails,
    });
    return (result as Map?)?['payment_id'] as String?;
  }

  /// Pauses their membership for [days] days from [start]; until when it
  /// runs now.
  Future<DateTime> pauseMember(String gymMemberId,
      {required DateTime start, required int days, String? reason}) async {
    final result = await _client.rpc('gym_pause_member', params: {
      'gym_member_id': gymMemberId,
      'start_on': isoDate(start),
      'days': days,
      'reason': _clean(reason),
    });
    return BhutanTime.parseDate((result as Map)['runs_until'] as String);
  }

  /// Ends [pauseId] now (or takes it back, not begun); until when their
  /// membership runs now.
  Future<DateTime> resumeMember(String pauseId) async {
    final result = await _client
        .rpc('gym_resume_member', params: {'pause_id': pauseId});
    return BhutanTime.parseDate((result as Map)['runs_until'] as String);
  }

  /// Deletes them from the gym's register (20261122000005_gym_delete_member.sql):
  /// they lose access to this gym and are told; their Health Pro account
  /// stays, and so do the gym's payments. [evenIfActive] once the desk has
  /// confirmed deleting a membership still paid for. True when they have an
  /// account (and so were told).
  Future<bool> deleteMember(String gymMemberId,
      {bool evenIfActive = false}) async {
    final result = await _client.rpc('gym_delete_member', params: {
      'gym_member_id': gymMemberId,
      'even_if_active': evenIfActive,
    }) as Map;
    final photo = result['photo_path'] as String?;
    if (photo != null) {
      try {
        await _client.storage.from(photoBucket).remove([photo]);
      } catch (_) {
        // A leftover file is harmless; nothing points at it now.
      }
    }
    return result['told'] == true;
  }

  /// A gym's pauses running or planned, for its members list.
  Future<List<GymPause>> openPauses(String venueId) async {
    final rows = await _client
        .from('gym_membership_pauses')
        .select()
        .eq('venue_id', venueId)
        .gte('end_date', isoDate(BhutanTime.today()))
        .order('start_date');
    return rows.map(GymPause.fromJson).toList();
  }

  /// One member's pauses, latest first.
  Future<List<GymPause>> memberPauses(String gymMemberId) async {
    final rows = await _client
        .from('gym_membership_pauses')
        .select()
        .eq('gym_member_id', gymMemberId)
        .order('start_date', ascending: false)
        .limit(20);
    return rows.map(GymPause.fromJson).toList();
  }

  /// [paymentId]'s receipt.
  Future<Receipt> receipt(String paymentId) async {
    final result = await _client
        .rpc('gym_payment_receipt', params: {'payment_id': paymentId});
    return Receipt.fromJson(Map<String, dynamic>.from(result as Map));
  }

  /// Every row [page] gives, 1,000 at a time (the most the server sends at
  /// once): for exports, which take everything.
  Future<List<T>> _everyRow<T>(
      Future<List<Map<String, dynamic>>> Function(int from, int to) page,
      T Function(Map<String, dynamic>) parse) async {
    const size = 1000;
    final all = <T>[];
    for (var from = 0;; from += size) {
      final rows = await page(from, from + size - 1);
      all.addAll(rows.map(parse));
      if (rows.length < size) return all;
    }
  }

  /// Everything a gym's members export needs: every member, their packages
  /// and the pauses running or planned.
  Future<MembersExport> membersExport(String venueId) async {
    final members = _everyRow(
        (from, to) => _client
            .from('gym_members')
            .select(_gymMemberColumns)
            .eq('venue_id', venueId)
            .order('full_name')
            .order('id')
            .range(from, to),
        GymMember.fromJson);
    final subs = _everyRow(
        (from, to) => _client
            .from('gym_subscriptions')
            .select()
            .eq('venue_id', venueId)
            .not('gym_member_id', 'is', null)
            .order('requested_at', ascending: false)
            .order('id')
            .range(from, to),
        GymSubscription.fromJson);
    return MembersExport(
        members: await members,
        subscriptions: await subs,
        pauses: await openPauses(venueId));
  }

  /// A gym's payments from [from] up to (not including) [to], with the
  /// package each paid for.
  Future<List<ExportedPayment>> paymentsExport(
          String venueId, DateTime from, DateTime to) =>
      _everyRow(
          (start, end) => _client
              .from('payments')
              .select('*, payer:profiles!payments_user_id_fkey(full_name), '
                  'package:gym_subscriptions!gym_subscriptions_payment_id_fkey(plan_name, start_date, end_date, '
                  'registered:gym_members!gym_subscriptions_gym_member_id_fkey(code))')
              .eq('venue_id', venueId)
              .eq('module_key', gymModuleKey)
              .gte('created_at', from.toUtc().toIso8601String())
              .lt('created_at', to.toUtc().toIso8601String())
              .order('created_at')
              .order('id')
              .range(start, end),
          ExportedPayment.fromJson);

  /// A gym's visits from [from] up to (not including) [to], oldest first.
  Future<List<ExportedVisit>> visitsExport(
          String venueId, DateTime from, DateTime to) =>
      _everyRow(
          (start, end) => _client
              .from('gym_check_ins')
              .select('checked_in_at, '
                  'member:profiles!gym_check_ins_member_id_fkey(full_name, member_code, phone), '
                  'registered:gym_members!gym_check_ins_gym_member_id_fkey(full_name, code, phone)')
              .eq('venue_id', venueId)
              .gte('checked_in_at', from.toUtc().toIso8601String())
              .lt('checked_in_at', to.toUtc().toIso8601String())
              .order('checked_in_at')
              .order('id')
              .range(start, end),
          ExportedVisit.fromJson);

  /// A new QR card for them; the old one stops working.
  Future<String> reissueCard(String gymMemberId) async => await _client
          .rpc('gym_reissue_member_qr', params: {'gym_member_id': gymMemberId})
      as String;

  /// Uploads [bytes] as the photo of member [memberId] of gym [venueId] and
  /// makes it theirs; their [oldPath] one is removed. Returns its path.
  Future<String> setMemberPhoto({
    required String venueId,
    required String memberId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
    String? oldPath,
  }) async {
    final ext = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg'
    };
    final path =
        '$venueId/$memberId-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from(photoBucket).uploadBinary(path, bytes,
        fileOptions: FileOptions(contentType: contentType, upsert: true));
    await _client.rpc('gym_set_member_photo',
        params: {'gym_member_id': memberId, 'photo_path': path});
    if (oldPath != null && oldPath != path) {
      try {
        await _client.storage.from(photoBucket).remove([oldPath]);
      } catch (_) {
        // A leftover file is harmless; the member points at the new one.
      }
    }
    return path;
  }

  Future<Uint8List?> memberPhoto(String path) async {
    try {
      return await _client.storage.from(photoBucket).download(path);
    } on StorageException {
      return null;
    }
  }

  static String? _clean(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v.trim();
}
