import 'dart:typed_data';

import 'package:health_pro_core/health_pro_core.dart';

import 'registered_member.dart';

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
  inactive('inactive', 'Inactive'),
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

  /// The gym added them itself (with their details), rather than them asking.
  final bool addedByGym;

  /// How to reach them: their account's.
  final String? email;
  final String? phone;

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
    this.addedByGym = false,
    this.email,
    this.phone,
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
        addedByGym: json['source'] == 'gym',
        email: json['email'] as String?,
        phone: json['phone'] as String?,
      );
}

/// A certificate typed at the desk for a trainer the gym is adding; [file]
/// is a photo of it, uploaded when the trainer is saved.
class NewCertificate {
  final String title;
  final String? issuer;
  final DateTime? issuedOn;
  final ({Uint8List bytes, String contentType})? file;

  const NewCertificate({required this.title, this.issuer, this.issuedOn, this.file});
}

/// A trainer the gym adds itself, with all their details: who they are and
/// how to reach them (their account is made from the email, or found by
/// it), their profile, certificates and week here.
class NewTrainer {
  final String name;
  final String email;
  final String? phone;
  final String? headline;
  final String? bio;
  final List<String> specialties;
  final int? experienceYears;
  final ({Uint8List bytes, String contentType})? photo;
  final List<NewCertificate> certificates;
  final List<TrainerSlot> slots;

  const NewTrainer({
    required this.name,
    required this.email,
    this.phone,
    this.headline,
    this.bio,
    this.specialties = const [],
    this.experienceYears,
    this.photo,
    this.certificates = const [],
    this.slots = const [],
  });

  /// What gym_add_trainer takes, once the files are uploaded.
  Map<String, dynamic> toJson({String? photoUrl, List<String?> certificateUrls = const []}) => {
        'display_name': name.trim(),
        'headline': headline?.trim(),
        'bio': bio?.trim(),
        'specialties': specialties,
        'experience_years': experienceYears,
        'photo_url': photoUrl,
        'certificates': [
          for (final (i, c) in certificates.indexed)
            {
              'title': c.title.trim(),
              'issuer': c.issuer?.trim(),
              'issued_on': c.issuedOn == null ? null : isoDate(c.issuedOn!),
              'file_url': i < certificateUrls.length ? certificateUrls[i] : null,
            },
        ],
        'slots': [for (final s in slots) s.toJson()],
      };
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
  final bool joinedPublicly;
  final List<TrainerCertificate> certificates;
  final List<MyTrainerGym> gyms;
  final List<TrainerReview> reviews;

  const MyTraining({
    this.profile,
    this.joinedPublicly = false,
    this.certificates = const [],
    this.gyms = const [],
    this.reviews = const [],
  });

  factory MyTraining.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> rows(String key) => [for (final r in (json[key] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
    return MyTraining(
      profile: json['profile'] == null ? null : TrainerProfile.fromJson(Map<String, dynamic>.from(json['profile'] as Map)),
      joinedPublicly: json['joined_publicly'] as bool? ?? false,
      certificates: rows('certificates').map(TrainerCertificate.fromJson).toList(),
      gyms: rows('gyms').map(MyTrainerGym.fromJson).toList(),
      reviews: rows('reviews').map(TrainerReview.fromJson).toList(),
    );
  }
}

/// Days of the week for trainer times: 'Mon'...'Sun'.
String weekdayName(int weekday) => OpeningHours.names[weekday - 1];

/// Attendance dates in Bhutan time, newest first, with duplicate scans on a
/// single day counted once.
List<DateTime> uniqueTrainerAttendanceEntries(Iterable<DateTime> attendance) {
  final ordered = attendance.toList()..sort((a, b) => b.compareTo(a));
  final dates = <DateTime>{};
  final entries = <DateTime>[];
  for (final at in ordered) {
    final local = BhutanTime.toBhutan(at);
    if (dates.add(DateTime(local.year, local.month, local.day))) entries.add(at);
  }
  return entries;
}

List<DateTime> uniqueTrainerAttendanceDays(Iterable<DateTime> attendance) => [
      for (final at in uniqueTrainerAttendanceEntries(attendance))
        DateTime(BhutanTime.toBhutan(at).year, BhutanTime.toBhutan(at).month, BhutanTime.toBhutan(at).day),
    ];

int trainerAttendanceDaysLast30(Iterable<DateTime> attendance, DateTime today) {
  final start = DateTime(today.year, today.month, today.day - 29);
  return uniqueTrainerAttendanceDays(attendance)
      .where((day) => !day.isBefore(start) && !day.isAfter(DateTime(today.year, today.month, today.day)))
      .length;
}

/// A week of times, by day: 'Mon 11 am–12 pm, Wed 6–8 am'.
String slotsText(Iterable<TrainerSlot> slots) =>
    slots.map((s) => '${weekdayName(s.weekday)} ${s.time}').join(', ');
