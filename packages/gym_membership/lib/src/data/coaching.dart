import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Body progress, and workout and diet plans
// (20261118000012_gym_progress_and_plans.sql).

double? _num(Object? v) => v == null ? null : (v as num).toDouble();

/// '2026-11-18'.
String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One day's measurements of a member: any of weight, height, body fat and
/// the tape measurements; who recorded them.
class BodyMeasurement {
  final String id;
  final String gymMemberId;
  final DateTime measuredOn;
  final double? weightKg;
  final double? heightCm;
  final double? bodyFatPct;
  final double? chestCm;
  final double? waistCm;
  final double? hipsCm;
  final double? armCm;
  final double? thighCm;
  final String? note;
  final String? recordedBy;
  final String? recordedByName;
  final DateTime createdAt;

  const BodyMeasurement({
    required this.id,
    required this.gymMemberId,
    required this.measuredOn,
    this.weightKg,
    this.heightCm,
    this.bodyFatPct,
    this.chestCm,
    this.waistCm,
    this.hipsCm,
    this.armCm,
    this.thighCm,
    this.note,
    this.recordedBy,
    this.recordedByName,
    required this.createdAt,
  });

  /// The tape measurements and body fat in a line: 'Waist 80 cm · Body fat 22%'.
  String get others => [
        if (heightCm != null) 'Height ${_cm(heightCm!)}',
        if (bodyFatPct != null) 'Body fat ${oneDecimal(bodyFatPct!)}%',
        if (chestCm != null) 'Chest ${_cm(chestCm!)}',
        if (waistCm != null) 'Waist ${_cm(waistCm!)}',
        if (hipsCm != null) 'Hips ${_cm(hipsCm!)}',
        if (armCm != null) 'Arm ${_cm(armCm!)}',
        if (thighCm != null) 'Thigh ${_cm(thighCm!)}',
      ].join(' · ');

  Map<String, dynamic> toJson() => {
        'measured_on': _iso(measuredOn),
        'weight_kg': weightKg,
        'height_cm': heightCm,
        'body_fat_pct': bodyFatPct,
        'chest_cm': chestCm,
        'waist_cm': waistCm,
        'hips_cm': hipsCm,
        'arm_cm': armCm,
        'thigh_cm': thighCm,
        'note': note == null || note!.trim().isEmpty ? null : note!.trim(),
      };

  factory BodyMeasurement.fromJson(Map<String, dynamic> json) => BodyMeasurement(
        id: json['id'] as String,
        gymMemberId: json['gym_member_id'] as String,
        measuredOn: BhutanTime.parseDate(json['measured_on'] as String),
        weightKg: _num(json['weight_kg']),
        heightCm: _num(json['height_cm']),
        bodyFatPct: _num(json['body_fat_pct']),
        chestCm: _num(json['chest_cm']),
        waistCm: _num(json['waist_cm']),
        hipsCm: _num(json['hips_cm']),
        armCm: _num(json['arm_cm']),
        thighCm: _num(json['thigh_cm']),
        note: json['note'] as String?,
        recordedBy: json['recorded_by'] as String?,
        recordedByName: json['recorded_by_name'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// '70', '70.5'.
String oneDecimal(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
String kgText(double v) => '${oneDecimal(v)} kg';
String _cm(double v) => '${oneDecimal(v)} cm';

/// Body mass index: weight over height squared.
double bmiOf(double weightKg, double heightCm) => weightKg / ((heightCm / 100) * (heightCm / 100));

/// The WHO's names for a BMI.
String bmiBand(double bmi) => bmi < 18.5
    ? 'Underweight'
    : bmi < 25
        ? 'Healthy weight'
        : bmi < 30
            ? 'Overweight'
            : 'Obese';

/// Where a member stands, from their measurements (newest first): their
/// weight now and at the first one, the change, and their BMI from the
/// latest height.
class ProgressSummary {
  final double? weightNow;
  final double? weightFirst;
  final DateTime? firstOn;
  final double? bmi;

  const ProgressSummary({this.weightNow, this.weightFirst, this.firstOn, this.bmi});

  double? get change => weightNow == null || weightFirst == null ? null : weightNow! - weightFirst!;

  factory ProgressSummary.of(List<BodyMeasurement> newestFirst) {
    final weighed = newestFirst.where((m) => m.weightKg != null).toList();
    final height = newestFirst.where((m) => m.heightCm != null).firstOrNull?.heightCm;
    final now = weighed.firstOrNull?.weightKg;
    return ProgressSummary(
      weightNow: now,
      weightFirst: weighed.length > 1 ? weighed.last.weightKg : null,
      firstOn: weighed.length > 1 ? weighed.last.measuredOn : null,
      bmi: now == null || height == null ? null : bmiOf(now, height),
    );
  }
}

enum PlanKind {
  workout('workout', 'Workout'),
  diet('diet', 'Diet');

  const PlanKind(this.value, this.label);
  final String value;
  final String label;

  static PlanKind from(String? v) => v == 'diet' ? diet : workout;
}

/// A workout or diet plan written for one member: a title and the plan in
/// words, by whom, and whether it's still the one to follow.
class MemberPlan {
  final String id;
  final String gymMemberId;
  final PlanKind kind;
  final String title;
  final String content;
  final bool isActive;
  final String? authorName;
  final DateTime updatedAt;

  const MemberPlan({
    required this.id,
    required this.gymMemberId,
    required this.kind,
    required this.title,
    required this.content,
    this.isActive = true,
    this.authorName,
    required this.updatedAt,
  });

  factory MemberPlan.fromJson(Map<String, dynamic> json) => MemberPlan(
        id: json['id'] as String,
        gymMemberId: json['gym_member_id'] as String,
        kind: PlanKind.from(json['kind'] as String?),
        title: json['title'] as String,
        content: json['content'] as String,
        isActive: json['is_active'] as bool? ?? true,
        authorName: json['author_name'] as String?,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}

/// One of a trainer's members (trainer_my_members()).
class TrainerMember {
  final String gymMemberId;
  final String venueId;
  final String venueName;
  final String fullName;
  final String code;
  final String phone;
  final DateTime since;
  final DateTime? paidUntil;
  final double? latestWeight;
  final int activePlans;

  const TrainerMember({
    required this.gymMemberId,
    required this.venueId,
    required this.venueName,
    required this.fullName,
    required this.code,
    required this.phone,
    required this.since,
    this.paidUntil,
    this.latestWeight,
    this.activePlans = 0,
  });

  factory TrainerMember.fromJson(Map<String, dynamic> json) => TrainerMember(
        gymMemberId: json['gym_member_id'] as String,
        venueId: json['venue_id'] as String,
        venueName: json['venue_name'] as String,
        fullName: json['full_name'] as String,
        code: json['code'] as String,
        phone: json['phone'] as String,
        since: DateTime.parse(json['since'] as String),
        paidUntil: json['paid_until'] == null ? null : BhutanTime.parseDate(json['paid_until'] as String),
        latestWeight: _num(json['latest_weight']),
        activePlans: (json['active_plans'] as num?)?.toInt() ?? 0,
      );
}

// ─── Reading and saving ─────────────────────────────────────────────────────

final gymCoachingRepositoryProvider = Provider<GymCoachingRepository>((ref) => GymCoachingRepository(ref.watch(supabaseProvider)));

/// A member's measurements, newest first.
final memberMeasurementsProvider = FutureProvider.autoDispose.family<List<BodyMeasurement>, String>(
  (ref, gymMemberId) => ref.watch(gymCoachingRepositoryProvider).measurements(gymMemberId),
);

/// A member's plans, the ones to follow first, newest first.
final memberPlansProvider = FutureProvider.autoDispose.family<List<MemberPlan>, String>(
  (ref, gymMemberId) => ref.watch(gymCoachingRepositoryProvider).plans(gymMemberId),
);

/// The signed-in trainer's members.
final trainerMembersProvider = FutureProvider.autoDispose<List<TrainerMember>>(
  (ref) => ref.watch(gymCoachingRepositoryProvider).trainerMembers(),
);

class GymCoachingRepository {
  GymCoachingRepository(this._client);
  final SupabaseClient _client;

  Future<List<BodyMeasurement>> measurements(String gymMemberId) async {
    final rows = await _client
        .from('gym_body_measurements')
        .select()
        .eq('gym_member_id', gymMemberId)
        .order('measured_on', ascending: false)
        .order('created_at', ascending: false)
        .limit(200);
    return rows.map(BodyMeasurement.fromJson).toList();
  }

  /// A new measurement ([measurementId] null) or changes to one.
  Future<void> saveMeasurement(String gymMemberId, BodyMeasurement m, {String? measurementId}) =>
      _client.rpc('gym_save_measurement', params: {'gym_member_id': gymMemberId, 'measurement_id': measurementId, 'details': m.toJson()});

  Future<void> deleteMeasurement(String id) => _client.rpc('gym_delete_measurement', params: {'measurement_id': id});

  Future<List<MemberPlan>> plans(String gymMemberId) async {
    final rows = await _client
        .from('gym_member_plans')
        .select()
        .eq('gym_member_id', gymMemberId)
        .order('is_active', ascending: false)
        .order('updated_at', ascending: false);
    return rows.map(MemberPlan.fromJson).toList();
  }

  /// A new plan ([planId] null) or changes to one.
  Future<void> savePlan(String gymMemberId,
          {String? planId, required PlanKind kind, required String title, required String content, bool isActive = true}) =>
      _client.rpc('gym_save_member_plan', params: {
        'gym_member_id': gymMemberId,
        'plan_id': planId,
        'details': {'kind': kind.value, 'title': title.trim(), 'content': content.trim(), 'is_active': isActive},
      });

  Future<void> deletePlan(String id) => _client.rpc('gym_delete_member_plan', params: {'plan_id': id});

  Future<List<TrainerMember>> trainerMembers() async {
    final rows = await _client.rpc('trainer_my_members') as List? ?? const [];
    return [for (final r in rows) TrainerMember.fromJson(Map<String, dynamic>.from(r as Map))];
  }
}
