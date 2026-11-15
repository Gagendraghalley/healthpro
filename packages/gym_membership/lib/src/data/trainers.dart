import 'package:health_pro_core/health_pro_core.dart';

/// A trainer's public profile: one on Health Pro, whatever gyms they train at.
class TrainerProfile {
  final String userId;
  final String name;
  final String? headline;
  final String? bio;
  final List<String> specialties;
  final int? experienceYears;
  final String? photoUrl;
  final double? ratingAverage;
  final int ratingCount;

  const TrainerProfile({
    required this.userId,
    required this.name,
    this.headline,
    this.bio,
    this.specialties = const [],
    this.experienceYears,
    this.photoUrl,
    this.ratingAverage,
    this.ratingCount = 0,
  });

  factory TrainerProfile.fromJson(Map<String, dynamic> json) => TrainerProfile(
        userId: json['user_id'] as String,
        name: json['display_name'] as String,
        headline: json['headline'] as String?,
        bio: json['bio'] as String?,
        specialties: (json['specialties'] as List?)?.cast<String>() ?? const [],
        experienceYears: (json['experience_years'] as num?)?.toInt(),
        photoUrl: json['photo_url'] as String?,
        ratingAverage: (json['rating_average'] as num?)?.toDouble(),
        ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
      );

  /// What trainer_save_profile takes.
  Map<String, dynamic> toJson() => {
        'display_name': name.trim(),
        'headline': headline?.trim(),
        'bio': bio?.trim(),
        'specialties': specialties,
        'experience_years': experienceYears,
        'photo_url': photoUrl,
      };
}

class TrainerCertificate {
  final String id;
  final String title;
  final String? issuer;
  final DateTime? issuedOn;
  final String? fileUrl;

  const TrainerCertificate({required this.id, required this.title, this.issuer, this.issuedOn, this.fileUrl});

  factory TrainerCertificate.fromJson(Map<String, dynamic> json) => TrainerCertificate(
        id: json['id'] as String,
        title: json['title'] as String,
        issuer: json['issuer'] as String?,
        issuedOn: json['issued_on'] == null ? null : BhutanTime.parseDate(json['issued_on'] as String),
        fileUrl: json['file_url'] as String?,
      );
}

/// A time a trainer is at a gym each week. Seen from one gym, a time at
/// another has no [venueName]: 'Not available'.
class TrainerSlot {
  final int weekday;
  final int starts;
  final int ends;
  final String? venueId;
  final String? venueName;

  /// At the gym it's seen from.
  final bool here;

  const TrainerSlot({
    required this.weekday,
    required this.starts,
    required this.ends,
    this.venueId,
    this.venueName,
    this.here = true,
  });

  /// '11 am–12 pm'.
  String get time => OpenPeriod(starts, ends).text;

  factory TrainerSlot.fromJson(Map<String, dynamic> json) => TrainerSlot(
        weekday: (json['weekday'] as num).toInt(),
        starts: OpenPeriod.parse(json['starts'] as String? ?? json['starts_at'] as String?) ?? 0,
        ends: OpenPeriod.parse(json['ends'] as String? ?? json['ends_at'] as String?) ?? 0,
        venueId: json['venue_id'] as String?,
        venueName: json['venue_name'] as String?,
        here: json['here'] as bool? ?? true,
      );

  /// What trainer_save_slots takes.
  Map<String, dynamic> toJson() => {'weekday': weekday, 'starts': OpenPeriod.hhmm(starts), 'ends': OpenPeriod.hhmm(ends)};

  TrainerSlot withHere(bool here) =>
      TrainerSlot(weekday: weekday, starts: starts, ends: ends, venueId: venueId, venueName: venueName, here: here);
}

/// Where a trainer stands at a gym.
enum TrainerStatus {
  pending('pending', 'Waiting to be checked'),
  verified('verified', 'Verified'),
  rejected('rejected', 'Not verified'),
  left('left', 'Left');

  final String value;
  final String label;

  const TrainerStatus(this.value, this.label);

  static TrainerStatus of(String? value) =>
      TrainerStatus.values.where((s) => s.value == value).firstOrNull ?? TrainerStatus.pending;
}

/// A trainer at a gym, as its staff see them: their profile and
/// certificates (to check), their week, their attendance there and how many
/// members they have there.
class GymTrainer {
  final TrainerProfile profile;
  final TrainerStatus status;
  final String? message;
  final String? decisionNote;
  final DateTime requestedAt;
  final List<TrainerCertificate> certificates;
  final List<TrainerSlot> slots;
  final List<DateTime> attendance;
  final int attendance30Days;
  final int members;

  const GymTrainer({
    required this.profile,
    required this.status,
    required this.requestedAt,
    this.message,
    this.decisionNote,
    this.certificates = const [],
    this.slots = const [],
    this.attendance = const [],
    this.attendance30Days = 0,
    this.members = 0,
  });

  factory GymTrainer.fromJson(Map<String, dynamic> json) => GymTrainer(
        profile: TrainerProfile.fromJson(Map<String, dynamic>.from(json['profile'] as Map)),
        status: TrainerStatus.of(json['status'] as String?),
        message: json['message'] as String?,
        decisionNote: json['decision_note'] as String?,
        requestedAt: DateTime.parse(json['requested_at'] as String),
        certificates: [
          for (final c in (json['certificates'] as List? ?? const [])) TrainerCertificate.fromJson(Map<String, dynamic>.from(c as Map)),
        ],
        slots: [for (final s in (json['slots'] as List? ?? const [])) TrainerSlot.fromJson(Map<String, dynamic>.from(s as Map))],
        attendance: [for (final a in (json['attendance'] as List? ?? const [])) DateTime.parse(a as String)],
        attendance30Days: (json['attendance_30_days'] as num?)?.toInt() ?? 0,
        members: (json['members'] as num?)?.toInt() ?? 0,
      );
}

/// One of the signed-in trainer's gyms: where they stand, their week,
/// their attendance there and their members there.
class MyTrainerGym {
  final String venueId;
  final String venueName;
  final String place;
  final TrainerStatus status;
  final String? decisionNote;
  final List<TrainerSlot> slots;
  final List<DateTime> attendance;
  final int attendance30Days;
  final List<({String name, DateTime since})> members;

  const MyTrainerGym({
    required this.venueId,
    required this.venueName,
    required this.place,
    required this.status,
    this.decisionNote,
    this.slots = const [],
    this.attendance = const [],
    this.attendance30Days = 0,
    this.members = const [],
  });

  factory MyTrainerGym.fromJson(Map<String, dynamic> json) => MyTrainerGym(
        venueId: json['venue_id'] as String,
        venueName: json['venue_name'] as String,
        place: json['place'] as String? ?? '',
        status: TrainerStatus.of(json['status'] as String?),
        decisionNote: json['decision_note'] as String?,
        slots: [for (final s in (json['slots'] as List? ?? const [])) TrainerSlot.fromJson(Map<String, dynamic>.from(s as Map))],
        attendance: [for (final a in (json['attendance'] as List? ?? const [])) DateTime.parse(a as String)],
        attendance30Days: (json['attendance_30_days'] as num?)?.toInt() ?? 0,
        members: [
          for (final m in (json['members'] as List? ?? const []))
            (name: (m as Map)['name'] as String, since: DateTime.parse(m['since'] as String)),
        ],
      );
}

class TrainerReview {
  final String id;
  final String trainerId;
  final String userId;
  final String reviewerName;
  final int rating;
  final String? comment;
  final DateTime createdAt;

  const TrainerReview({
    required this.id,
    required this.trainerId,
    required this.userId,
    required this.reviewerName,
    required this.rating,
    required this.createdAt,
    this.comment,
  });

  factory TrainerReview.fromJson(Map<String, dynamic> json) => TrainerReview(
        id: json['id'] as String,
        trainerId: json['trainer_id'] as String,
        userId: json['user_id'] as String,
        reviewerName: (json['reviewer_name'] as String?)?.trim().isNotEmpty == true ? json['reviewer_name'] as String : 'Member',
        rating: (json['rating'] as num).toInt(),
        comment: json['comment'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Everything the signed-in trainer has; [profile] null: not a trainer yet.
class MyTraining {
  final TrainerProfile? profile;
  final List<TrainerCertificate> certificates;
  final List<MyTrainerGym> gyms;
  final List<TrainerReview> reviews;

  const MyTraining({this.profile, this.certificates = const [], this.gyms = const [], this.reviews = const []});

  factory MyTraining.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> rows(String key) => [for (final r in (json[key] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
    return MyTraining(
      profile: json['profile'] == null ? null : TrainerProfile.fromJson(Map<String, dynamic>.from(json['profile'] as Map)),
      certificates: rows('certificates').map(TrainerCertificate.fromJson).toList(),
      gyms: rows('gyms').map(MyTrainerGym.fromJson).toList(),
      reviews: rows('reviews').map(TrainerReview.fromJson).toList(),
    );
  }
}

/// Days of the week for trainer times: 'Mon'...'Sun'.
String weekdayName(int weekday) => OpeningHours.names[weekday - 1];

/// A week of times, by day: 'Mon 11 am–12 pm, Wed 6–8 am'.
String slotsText(Iterable<TrainerSlot> slots) =>
    slots.map((s) => '${weekdayName(s.weekday)} ${s.time}').join(', ');
