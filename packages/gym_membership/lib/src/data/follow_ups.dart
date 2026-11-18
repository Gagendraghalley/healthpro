import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'gym_models.dart';
import 'registered_member.dart';

// ─── Enquiries and free trials (20261118000007_gym_enquiries.sql) ──────────

/// Where an enquiry stands.
enum EnquiryStatus {
  open('open', 'Following up'),
  trial('trial', 'Free trial'),
  joined('joined', 'Joined'),
  lost('lost', 'Not joining');

  const EnquiryStatus(this.value, this.label);
  final String value;
  final String label;

  static EnquiryStatus from(String? value) => values.firstWhere((s) => s.value == value, orElse: () => open);
}

/// How they heard of the gym.
enum EnquirySource {
  walkIn('walk_in', 'Walked in'),
  phone('phone', 'Phoned'),
  social('social', 'Social media'),
  friend('friend', 'A friend'),
  other('other', 'Other');

  const EnquirySource(this.value, this.label);
  final String value;
  final String label;

  static EnquirySource from(String? value) => values.firstWhere((s) => s.value == value, orElse: () => walkIn);
}

/// Someone who asked about the gym and hasn't joined yet (or has, or won't):
/// what they're after, a free trial, and when to follow them up.
class GymEnquiry {
  final String id;
  final String venueId;
  final String fullName;
  final String phone;
  final EnquirySource source;
  final String? interest;
  final EnquiryStatus status;
  final DateTime? trialStartsOn;
  final DateTime? trialEndsOn;
  final DateTime? followUpOn;
  final String? notes;
  final String? gymMemberId;
  final DateTime createdAt;

  const GymEnquiry({
    required this.id,
    required this.venueId,
    required this.fullName,
    required this.phone,
    this.source = EnquirySource.walkIn,
    this.interest,
    this.status = EnquiryStatus.open,
    this.trialStartsOn,
    this.trialEndsOn,
    this.followUpOn,
    this.notes,
    this.gymMemberId,
    required this.createdAt,
  });

  /// Still to win: following up, or on a free trial.
  bool get isOpen => status == EnquiryStatus.open || status == EnquiryStatus.trial;

  /// Their follow-up is today or was missed.
  bool isDueOn(DateTime today) => isOpen && followUpOn != null && !followUpOn!.isAfter(today);

  /// Marked on a trial that ended before [today]: time to ask how it went.
  bool trialOverOn(DateTime today) => status == EnquiryStatus.trial && trialEndsOn != null && trialEndsOn!.isBefore(today);

  /// Needs the desk today: a follow-up due, or a trial over.
  bool needsActionOn(DateTime today) => isDueOn(today) || trialOverOn(today);

  /// Their days of free trial, if they had one.
  int? get trialDays => trialStartsOn == null || trialEndsOn == null ? null : BhutanTime.daysBetween(trialStartsOn!, trialEndsOn!) + 1;

  EnquiryDetails get details => EnquiryDetails(
        fullName: fullName,
        phone: phone,
        source: source,
        interest: interest,
        status: status,
        trialStartsOn: trialStartsOn,
        trialEndsOn: trialEndsOn,
        followUpOn: followUpOn,
        notes: notes,
      );

  static DateTime? _date(Object? v) => v == null ? null : BhutanTime.parseDate(v as String);

  factory GymEnquiry.fromJson(Map<String, dynamic> json) => GymEnquiry(
        id: json['id'] as String,
        venueId: json['venue_id'] as String,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String,
        source: EnquirySource.from(json['source'] as String?),
        interest: json['interest'] as String?,
        status: EnquiryStatus.from(json['status'] as String?),
        trialStartsOn: _date(json['trial_starts_on']),
        trialEndsOn: _date(json['trial_ends_on']),
        followUpOn: _date(json['follow_up_on']),
        notes: json['notes'] as String?,
        gymMemberId: json['gym_member_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// What the desk types about an enquiry (gym_save_enquiry's details).
class EnquiryDetails {
  final String fullName;
  final String phone;
  final EnquirySource source;
  final String? interest;
  final EnquiryStatus status;
  final DateTime? trialStartsOn;
  final DateTime? trialEndsOn;
  final DateTime? followUpOn;
  final String? notes;

  const EnquiryDetails({
    required this.fullName,
    required this.phone,
    this.source = EnquirySource.walkIn,
    this.interest,
    this.status = EnquiryStatus.open,
    this.trialStartsOn,
    this.trialEndsOn,
    this.followUpOn,
    this.notes,
  });

  static String? _clean(String? v) => v == null || v.trim().isEmpty ? null : v.trim();

  Map<String, dynamic> toJson() => {
        'full_name': fullName.trim(),
        'phone': Validators.normalizePhone(phone) ?? phone.trim(),
        'source': source.value,
        'interest': _clean(interest),
        'status': status.value,
        'trial_starts_on': trialStartsOn == null ? null : isoDate(trialStartsOn!),
        'trial_ends_on': trialEndsOn == null ? null : isoDate(trialEndsOn!),
        'follow_up_on': followUpOn == null ? null : isoDate(followUpOn!),
        'notes': _clean(notes),
      };
}

/// A month of enquiries: how many came in, and how many of them joined.
({int added, int joined}) enquiriesIn(Iterable<GymEnquiry> enquiries, DateTime month) {
  final those = enquiries.where((e) {
    final day = BhutanTime.toBhutan(e.createdAt);
    return day.year == month.year && day.month == month.month;
  });
  return (added: those.length, joined: those.where((e) => e.status == EnquiryStatus.joined).length);
}

// ─── WhatsApp reminders and wishes (20261118000008_gym_follow_ups.sql) ─────

/// What the desk sent a member on WhatsApp.
enum MessageKind {
  renewal('renewal'),
  birthday('birthday');

  const MessageKind(this.value);
  final String value;
}

class MemberMessage {
  final String gymMemberId;
  final MessageKind kind;
  final DateTime sentAt;

  const MemberMessage({required this.gymMemberId, required this.kind, required this.sentAt});

  factory MemberMessage.fromJson(Map<String, dynamic> json) => MemberMessage(
        gymMemberId: json['gym_member_id'] as String,
        kind: json['kind'] == 'birthday' ? MessageKind.birthday : MessageKind.renewal,
        sentAt: DateTime.parse(json['sent_at'] as String),
      );
}

/// When [gymMemberId] was last sent a [kind] message, of [messages].
DateTime? lastSent(Iterable<MemberMessage> messages, String gymMemberId, MessageKind kind) {
  DateTime? last;
  for (final m in messages) {
    if (m.gymMemberId == gymMemberId && m.kind == kind && (last == null || m.sentAt.isAfter(last))) last = m.sentAt;
  }
  return last;
}

/// The renewal reminder the desk sends, ready to edit in WhatsApp: their
/// package ends on [end] (still to come, today, or past).
String renewalMessage({required String name, required String gym, required String plan, required DateTime end, required DateTime today}) {
  final hello = 'Hello ${firstName(name, fallback: name.trim())}';
  final left = BhutanTime.daysBetween(today, end);
  const renew = 'Renew at the front desk, or pay online in the Health Pro app';
  if (left < 0) return '$hello, your $plan at $gym ended on ${formatDate(end)}. We miss you! $renew, and come back in.';
  if (left == 0) return '$hello, your $plan at $gym ends today. $renew to keep going. Thank you!';
  return '$hello, your $plan at $gym ends on ${formatDate(end)}. $renew to keep going. Thank you!';
}

String birthdayMessage({required String name, required String gym}) =>
    'Happy birthday, ${firstName(name, fallback: name.trim())}! Everyone at $gym wishes you a healthy, happy year ahead. '
    'Enjoy your workout today!';

// ─── Birthdays ──────────────────────────────────────────────────────────────

bool _leap(int year) => (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

/// Someone born on [born]'s birthday in [year]: 29 February is the 28th in a
/// year without one (as gym_is_birthday).
DateTime birthdayIn(DateTime born, int year) =>
    born.month == 2 && born.day == 29 && !_leap(year) ? DateTime(year, 2, 28) : DateTime(year, born.month, born.day);

/// Their next birthday, [today] included.
DateTime nextBirthday(DateTime born, DateTime today) {
  final thisYear = birthdayIn(born, today.year);
  return thisYear.isBefore(today) ? birthdayIn(born, today.year + 1) : thisYear;
}

typedef Birthday = ({GymMember member, DateTime day, int age});

/// Birthdays of [members] in the [days] days from [today] (today first);
/// only [include]d members.
List<Birthday> birthdaysWithin(Iterable<GymMember> members, DateTime today, int days, {bool Function(GymMember)? include}) {
  final last = DateTime(today.year, today.month, today.day + days - 1);
  final found = <Birthday>[];
  for (final m in members) {
    final born = m.dateOfBirth;
    if (born == null || (include != null && !include(m))) continue;
    final day = nextBirthday(born, today);
    if (day.isAfter(last)) continue;
    found.add((member: m, day: day, age: day.year - born.year));
  }
  return found..sort((a, b) => a.day.compareTo(b.day) != 0 ? a.day.compareTo(b.day) : a.member.fullName.compareTo(b.member.fullName));
}

/// A member to wish: a package now or to come, or one that ended in the last
/// 90 days.
bool isRecentMember(Iterable<GymSubscription> subs, DateTime today) {
  final since = DateTime(today.year, today.month, today.day - 90);
  return subs.any((s) =>
      (s.status == SubscriptionStatus.active || s.status == SubscriptionStatus.expired) && s.endDate != null && !s.endDate!.isBefore(since));
}

// ─── The activity log (20261118000006_gym_audit_log.sql) ────────────────────

/// What an entry is about, for the log's filters and icons.
enum AuditArea {
  money('Money'),
  members('Members'),
  memberships('Memberships'),
  setup('Packages & staff');

  const AuditArea(this.label);
  final String label;
}

/// One line of a gym's activity log: who did what, when.
class AuditEntry {
  final int id;
  final String action;
  final String summary;
  final String details;
  final String actorName;
  final String? gymMemberId;
  final String? memberName;
  final int? amount;
  final DateTime createdAt;

  const AuditEntry({
    required this.id,
    required this.action,
    required this.summary,
    this.details = '',
    this.actorName = '',
    this.gymMemberId,
    this.memberName,
    this.amount,
    required this.createdAt,
  });

  AuditArea get area {
    if (action.startsWith('payment.') || action.startsWith('claim.') || action.startsWith('expense.')) return AuditArea.money;
    if (action.startsWith('plan.') || action.startsWith('staff.') || action.startsWith('offer.')) return AuditArea.setup;
    if (action.startsWith('membership.')) return AuditArea.memberships;
    return AuditArea.members;
  }

  /// Money changed hands in it (a sale with its payment counts).
  bool get tookMoney => amount != null && (area == AuditArea.money || action == 'member.registered' || action == 'membership.sold');

  /// Who did it, or 'Someone' for an account with no name.
  String get by => actorName.trim().isEmpty ? 'Someone' : actorName.trim();

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        id: (json['id'] as num).toInt(),
        action: json['action'] as String,
        summary: json['summary'] as String,
        details: (json['details'] as String?) ?? '',
        actorName: (json['actor_name'] as String?) ?? '',
        gymMemberId: json['gym_member_id'] as String?,
        memberName: json['member_name'] as String?,
        amount: (json['amount'] as num?)?.toInt(),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

// ─── Reading and saving ─────────────────────────────────────────────────────

final gymFollowUpRepositoryProvider = Provider<GymFollowUpRepository>((ref) => GymFollowUpRepository(ref.watch(supabaseProvider)));

/// A gym's enquiries, newest first.
final gymEnquiriesProvider = FutureProvider.family<List<GymEnquiry>, String>(
  (ref, venueId) => ref.watch(gymFollowUpRepositoryProvider).enquiries(venueId),
);

/// The WhatsApp messages the desk sent in the last 60 days.
final gymMemberMessagesProvider = FutureProvider.family<List<MemberMessage>, String>(
  (ref, venueId) => ref.watch(gymFollowUpRepositoryProvider).messages(venueId),
);

/// A gym's activity log, the latest [limit] entries; one member's with
/// [gymMemberId].
final gymAuditLogProvider =
    FutureProvider.autoDispose.family<List<AuditEntry>, ({String venueId, String? gymMemberId, int limit})>(
  (ref, q) => ref.watch(gymFollowUpRepositoryProvider).auditLog(q.venueId, gymMemberId: q.gymMemberId, limit: q.limit),
);

class GymFollowUpRepository {
  GymFollowUpRepository(this._client);
  final SupabaseClient _client;

  Future<List<GymEnquiry>> enquiries(String venueId) async {
    final rows = await _client.from('gym_enquiries').select().eq('venue_id', venueId).order('created_at', ascending: false).limit(1000);
    return rows.map(GymEnquiry.fromJson).toList();
  }

  /// A new enquiry ([enquiryId] null) or changes to one; its id.
  Future<String> saveEnquiry(String venueId, EnquiryDetails details, {String? enquiryId}) async {
    final id = await _client.rpc('gym_save_enquiry', params: {'venue_id': venueId, 'enquiry_id': enquiryId, 'details': details.toJson()});
    return id as String;
  }

  Future<void> deleteEnquiry(String enquiryId) => _client.rpc('gym_delete_enquiry', params: {'enquiry_id': enquiryId});

  Future<List<MemberMessage>> messages(String venueId) async {
    final since = DateTime.now().toUtc().subtract(const Duration(days: 60));
    final rows = await _client
        .from('gym_member_messages')
        .select('gym_member_id, kind, sent_at')
        .eq('venue_id', venueId)
        .gte('sent_at', since.toIso8601String())
        .order('sent_at', ascending: false);
    return rows.map(MemberMessage.fromJson).toList();
  }

  /// Notes that the desk sent [gymMemberId] a [kind] message on WhatsApp.
  Future<void> noteMessage(String gymMemberId, MessageKind kind) =>
      _client.rpc('gym_note_message', params: {'gym_member_id': gymMemberId, 'kind': kind.value});

  Future<List<AuditEntry>> auditLog(String venueId, {String? gymMemberId, int limit = 100}) async {
    var query = _client.from('gym_audit_log').select().eq('venue_id', venueId);
    if (gymMemberId != null) query = query.eq('gym_member_id', gymMemberId);
    final rows = await query.order('id', ascending: false).limit(limit);
    return rows.map(AuditEntry.fromJson).toList();
  }
}
