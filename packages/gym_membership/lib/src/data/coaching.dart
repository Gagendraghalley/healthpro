import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'nutrition.dart';

// Body progress, and workout and diet plans
// (20261118000012_gym_progress_and_plans.sql).

double? _num(Object? v) => v == null ? null : (v as num).toDouble();

/// '2026-11-18'.
String isoDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
        'measured_on': isoDay(measuredOn),
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

/// How a reading reads: fine, worth watching, needs a look, or just a fact.
enum ReadingTone { good, watch, alert, neutral }

/// BMI bands for Asian people (WHO expert consultation, 2004): the risk to
/// health starts at 23, not 25, and is high from 27.5, not 30.
enum BmiBand {
  under('Underweight', ReadingTone.alert),
  healthy('Healthy weight', ReadingTone.good),
  over('Overweight', ReadingTone.watch),
  obese('Obese', ReadingTone.alert);

  const BmiBand(this.label, this.tone);
  final String label;
  final ReadingTone tone;

  static BmiBand of(double bmi) => bmi < 18.5
      ? under
      : bmi < 23
          ? healthy
          : bmi < 27.5
              ? over
              : obese;
}

String bmiBand(double bmi) => BmiBand.of(bmi).label;

/// Waist over height: under 0.5 is healthy for men and women alike, at any
/// age (Ashwell's boundaries: 0.4, 0.5, 0.6).
enum WaistBand {
  lean('Very lean', ReadingTone.watch),
  healthy('Healthy', ReadingTone.good),
  raised('Raised risk', ReadingTone.watch),
  high('High risk', ReadingTone.alert);

  const WaistBand(this.label, this.tone);
  final String label;
  final ReadingTone tone;

  static WaistBand of(double ratio) => ratio < 0.4
      ? lean
      : ratio < 0.5
          ? healthy
          : ratio < 0.6
              ? raised
              : high;
}

/// Lean mass for the height (fat-free mass index). Under 11 or over 30 the
/// weight, height and body fat can't all be right.
double leanIndexOf(double weightKg, double bodyFatPct, double heightCm) =>
    weightKg * (1 - bodyFatPct / 100) / ((heightCm / 100) * (heightCm / 100));
bool _likelyLean(double index) => index >= 11 && index <= 30;

/// The measures that can be followed over time.
enum BodyMeasure {
  weight('Weight', 'kg'),
  bodyFat('Body fat', '%'),
  waist('Waist', 'cm'),
  chest('Chest', 'cm'),
  hips('Hips', 'cm'),
  arm('Arm', 'cm'),
  thigh('Thigh', 'cm');

  const BodyMeasure(this.label, this.unit);
  final String label;
  final String unit;

  double? of(BodyMeasurement m) => switch (this) {
        weight => m.weightKg,
        bodyFat => m.bodyFatPct,
        waist => m.waistCm,
        chest => m.chestCm,
        hips => m.hipsCm,
        arm => m.armCm,
        thigh => m.thighCm,
      };

  /// '70.5 kg', '22%'.
  String show(double v) => unit == '%' ? '${oneDecimal(v)}%' : '${oneDecimal(v)} $unit';
}

/// One measure's readings, oldest first.
typedef MeasurePoint = ({DateTime on, double value});

/// Where a member stands, from their measurements (newest first): their
/// weight now and at the first one, the change, their BMI and waist over
/// height from the latest height, their fat and lean mass, and the pace of
/// their weight over the last 8 weeks.
class ProgressSummary {
  final double? weightNow;
  final double? weightFirst;
  final DateTime? firstOn;
  final double? heightCm;
  final DateTime? heightOn;
  final double? bmi;

  /// From the latest measurement with weight and body fat, when they add up.
  final double? bodyFatPct;
  final double? fatKg;
  final double? leanKg;

  /// The latest body fat, when it can't be right for the weight and height.
  final BodyMeasurement? unlikely;

  /// Fat and lean mass now against the first measurement with both.
  final double? fatChange;
  final double? leanChange;
  final DateTime? compositionSince;

  final double? waistToHeight;

  /// Kilograms a week (less than 0: losing) and over how many weeks.
  final double? pacePerWeek;
  final int? paceWeeks;

  final DateTime? lastOn;
  final Map<BodyMeasure, List<MeasurePoint>> trends;

  const ProgressSummary({
    this.weightNow,
    this.weightFirst,
    this.firstOn,
    this.heightCm,
    this.heightOn,
    this.bmi,
    this.bodyFatPct,
    this.fatKg,
    this.leanKg,
    this.unlikely,
    this.fatChange,
    this.leanChange,
    this.compositionSince,
    this.waistToHeight,
    this.pacePerWeek,
    this.paceWeeks,
    this.lastOn,
    this.trends = const {},
  });

  double? get change => weightNow == null || weightFirst == null ? null : weightNow! - weightFirst!;
  BmiBand? get bmiBand => bmi == null ? null : BmiBand.of(bmi!);
  WaistBand? get waistBand => waistToHeight == null ? null : WaistBand.of(waistToHeight!);

  factory ProgressSummary.of(List<BodyMeasurement> newestFirst) {
    final weighed = newestFirst.where((m) => m.weightKg != null).toList();
    final tall = newestFirst.where((m) => m.heightCm != null).firstOrNull;
    final height = tall?.heightCm;
    final now = weighed.firstOrNull?.weightKg;

    // Fat and lean mass, from measurements with both weight and body fat whose
    // numbers add up (with the height then, or the latest). None while the
    // latest can't be right.
    bool likely(BodyMeasurement m) {
      final h = m.heightCm ?? height;
      return h == null || _likelyLean(leanIndexOf(m.weightKg!, m.bodyFatPct!, h));
    }

    final withFat = newestFirst.where((m) => m.weightKg != null && m.bodyFatPct != null).toList();
    final unlikely = withFat.isNotEmpty && !likely(withFat.first) ? withFat.first : null;
    final composed = unlikely != null ? <BodyMeasurement>[] : withFat.where(likely).toList();
    final latest = composed.firstOrNull;
    final oldest = composed.length > 1 ? composed.last : null;
    double fat(BodyMeasurement m) => m.weightKg! * m.bodyFatPct! / 100;
    double lean(BodyMeasurement m) => m.weightKg! - fat(m);

    final waist = newestFirst.where((m) => m.waistCm != null).firstOrNull?.waistCm;

    // The pace: the trend through the weighings of the last 8 weeks, once
    // they span 2 weeks or more.
    double? pace;
    int? paceWeeks;
    if (weighed.length > 1) {
      final since = weighed.first.measuredOn.subtract(const Duration(days: 56));
      final recent = weighed.where((m) => !m.measuredOn.isBefore(since)).toList();
      final span = weighed.first.measuredOn.difference(recent.last.measuredOn).inDays;
      if (recent.length > 1 && span >= 14) {
        final xs = [for (final m in recent) m.measuredOn.difference(recent.last.measuredOn).inDays.toDouble()];
        final ys = [for (final m in recent) m.weightKg!];
        final mx = xs.reduce((a, b) => a + b) / xs.length;
        final my = ys.reduce((a, b) => a + b) / ys.length;
        var top = 0.0, bottom = 0.0;
        for (var i = 0; i < xs.length; i++) {
          top += (xs[i] - mx) * (ys[i] - my);
          bottom += (xs[i] - mx) * (xs[i] - mx);
        }
        pace = top / bottom * 7;
        paceWeeks = (span / 7).round();
      }
    }

    final trends = <BodyMeasure, List<MeasurePoint>>{};
    for (final measure in BodyMeasure.values) {
      final points = [
        for (final m in newestFirst.reversed)
          if (measure.of(m) != null) (on: m.measuredOn, value: measure.of(m)!),
      ];
      if (points.length > 1) trends[measure] = points;
    }

    return ProgressSummary(
      weightNow: now,
      weightFirst: weighed.length > 1 ? weighed.last.weightKg : null,
      firstOn: weighed.length > 1 ? weighed.last.measuredOn : null,
      heightCm: height,
      heightOn: tall?.measuredOn,
      bmi: now == null || height == null ? null : bmiOf(now, height),
      bodyFatPct: latest?.bodyFatPct,
      fatKg: latest == null ? null : fat(latest),
      leanKg: latest == null ? null : lean(latest),
      unlikely: unlikely,
      fatChange: oldest == null ? null : fat(latest!) - fat(oldest),
      leanChange: oldest == null ? null : lean(latest!) - lean(oldest),
      compositionSince: oldest?.measuredOn,
      waistToHeight: waist == null || height == null ? null : waist / height,
      pacePerWeek: pace,
      paceWeeks: paceWeeks,
      lastOn: newestFirst.firstOrNull?.measuredOn,
      trends: trends,
    );
  }
}

/// One thing worth saying about a member's progress.
enum ReadingKind { check, pace, composition, due }

class ProgressReading {
  final ReadingKind kind;
  final ReadingTone tone;
  final String text;

  const ProgressReading(this.kind, this.tone, this.text);

  @override
  String toString() => text;
}

/// '1.8 kg less fat', 'no change in lean mass'.
String _moreLess(double change, String what) =>
    change.abs() < 0.05 ? 'no change in $what' : '${kgText(change.abs())} ${change > 0 ? 'more' : 'less'} $what';

/// What a member's progress says, most pressing first: a body fat that can't
/// be right, the pace of their weight, where it came from (fat or lean), and
/// whether a measurement is due. [self]: said to the member.
List<ProgressReading> progressReadings(ProgressSummary s, {required DateTime today, bool self = false}) {
  final readings = <ProgressReading>[];
  final odd = s.unlikely;
  if (odd != null) {
    readings.add(ProgressReading(ReadingKind.check, ReadingTone.alert,
        'Body fat ${oneDecimal(odd.bodyFatPct!)}% at ${kgText(odd.weightKg!)} isn\'t likely. '
        'Check the ${formatShortDate(odd.measuredOn)} measurement.'));
  }

  final pace = s.pacePerWeek;
  if (pace != null) {
    final over = 'over ${s.paceWeeks} weeks';
    final rate = kgText(pace.abs());
    final band = s.bmiBand;
    if (pace.abs() < 0.1) {
      readings.add(ProgressReading(ReadingKind.pace, ReadingTone.neutral, 'Weight steady $over.'));
    } else if (pace < 0) {
      readings.add(band == BmiBand.under
          ? ProgressReading(ReadingKind.pace, ReadingTone.alert, 'Losing $rate a week $over while underweight.')
          : pace < -1
              ? ProgressReading(ReadingKind.pace, ReadingTone.watch,
                  'Losing $rate a week $over: faster than 1 kg a week, so some may be muscle.')
              : ProgressReading(ReadingKind.pace, ReadingTone.good, 'Losing $rate a week $over: a steady pace.'));
    } else {
      readings.add(band == BmiBand.under
          ? ProgressReading(ReadingKind.pace, ReadingTone.good, 'Gaining $rate a week $over.')
          : pace > 0.5
              ? ProgressReading(ReadingKind.pace, ReadingTone.watch, 'Gaining $rate a week $over: quick, so much of it may be fat.')
              : ProgressReading(ReadingKind.pace, ReadingTone.neutral, 'Gaining $rate a week $over.'));
    }
  }

  final fat = s.fatChange, lean = s.leanChange;
  if (fat != null && lean != null) {
    final text = '${_moreLess(fat, 'fat')} and ${_moreLess(lean, 'lean mass')} since ${formatShortDate(s.compositionSince!)}.';
    final tone = fat <= -0.1 && lean >= -0.5
        ? ReadingTone.good
        : lean < -0.5 && -lean > -fat
            ? ReadingTone.watch
            : ReadingTone.neutral;
    readings.add(ProgressReading(ReadingKind.composition, tone, '${text[0].toUpperCase()}${text.substring(1)}'));
  }

  final last = s.lastOn;
  if (last != null) {
    final days = today.difference(last).inDays;
    if (days > 30) {
      readings.add(ProgressReading(ReadingKind.due, ReadingTone.watch,
          self ? 'Last logged $days days ago. Time to log your weight.' : 'Last measured $days days ago. Time for a new measurement.'));
    }
  }
  return readings;
}

/// What looks wrong in [m] before it's saved, against the member's [others]
/// (any order; [m] itself, when it's being changed, is left out): weight,
/// height and body fat that can't all be right, or a number far from the
/// nearest reading in time. Warnings only: the number may be right.
List<String> measurementWarnings(BodyMeasurement m, List<BodyMeasurement> others) {
  final rest = others.where((o) => o.id != m.id || m.id.isEmpty).toList();
  int apart(BodyMeasurement o) => o.measuredOn.difference(m.measuredOn).inDays.abs();
  BodyMeasurement? nearest(double? Function(BodyMeasurement) of) {
    final having = rest.where((o) => of(o) != null).toList()..sort((a, b) => apart(a).compareTo(apart(b)));
    return having.firstOrNull;
  }

  final warnings = <String>[];
  final known = nearest((o) => o.heightCm);
  final height = m.heightCm ?? known?.heightCm;
  final weight = m.weightKg, fat = m.bodyFatPct;

  if (weight != null && height != null) {
    final bmi = bmiOf(weight, height);
    if (bmi < 12 || bmi > 70) {
      warnings.add('BMI ${bmi.toStringAsFixed(1)} isn\'t likely. Check the weight and height.');
    } else if (fat != null && !_likelyLean(leanIndexOf(weight, fat, height))) {
      final lean = weight * (1 - fat / 100);
      warnings.add('Body fat ${oneDecimal(fat)}% at ${kgText(weight)} leaves ${kgText(lean)} of lean mass, which isn\'t likely. '
          'Check the body fat.');
    }
  }

  void jump(String label, double? value, double? Function(BodyMeasurement) of, String Function(double) show,
      {required double allowed, double perWeek = 0}) {
    if (value == null) return;
    final o = nearest(of);
    if (o == null) return;
    final diff = value - of(o)!;
    if (diff.abs() <= allowed + perWeek * apart(o) / 7) return;
    final by = label == 'Body fat' ? '${oneDecimal(diff.abs())} points' : show(diff.abs());
    warnings.add('$label: $by ${diff > 0 ? 'more' : 'less'} than on ${formatShortDate(o.measuredOn)} (${show(of(o)!)}).');
  }

  jump('Weight', weight, (o) => o.weightKg, kgText, allowed: 2.5, perWeek: 1);
  jump('Height', m.heightCm, (o) => o.heightCm, _cm, allowed: 4);
  jump('Body fat', fat, (o) => o.bodyFatPct, BodyMeasure.bodyFat.show, allowed: 5, perWeek: 1);
  jump('Waist', m.waistCm, (o) => o.waistCm, _cm, allowed: 6, perWeek: 1);
  return warnings;
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
/// words (for a diet plan, also or instead in meals, with the day's
/// calories and protein to aim for), by whom, and whether it's still the one
/// to follow.
class MemberPlan {
  final String id;
  final String gymMemberId;
  final PlanKind kind;
  final String title;
  final String content;
  final List<DietMeal> meals;
  final int? kcalTarget;
  final int? proteinTargetG;
  final bool isActive;
  final String? authorName;
  final DateTime updatedAt;

  const MemberPlan({
    required this.id,
    required this.gymMemberId,
    required this.kind,
    required this.title,
    required this.content,
    this.meals = const [],
    this.kcalTarget,
    this.proteinTargetG,
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
        meals: DietMeal.listFrom(json['meals']),
        kcalTarget: (json['kcal_target'] as num?)?.toInt(),
        proteinTargetG: (json['protein_target_g'] as num?)?.toInt(),
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

  /// A new plan ([planId] null) or changes to one. Meals and targets are for
  /// diet plans.
  Future<void> savePlan(String gymMemberId,
          {String? planId,
          required PlanKind kind,
          required String title,
          required String content,
          List<DietMeal> meals = const [],
          int? kcalTarget,
          int? proteinTargetG,
          bool isActive = true}) =>
      _client.rpc('gym_save_member_plan', params: {
        'gym_member_id': gymMemberId,
        'plan_id': planId,
        'details': {
          'kind': kind.value,
          'title': title.trim(),
          'content': content.trim(),
          'meals': [for (final m in meals) m.toJson()],
          'kcal_target': kcalTarget,
          'protein_target_g': proteinTargetG,
          'is_active': isActive,
        },
      });

  Future<void> deletePlan(String id) => _client.rpc('gym_delete_member_plan', params: {'plan_id': id});

  Future<List<TrainerMember>> trainerMembers() async {
    final rows = await _client.rpc('trainer_my_members') as List? ?? const [];
    return [for (final r in rows) TrainerMember.fromJson(Map<String, dynamic>.from(r as Map))];
  }
}
