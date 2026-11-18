import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Group classes: the weekly timetable and booking a place
// (20261118000013_gym_classes.sql).

const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// '2026-11-18'.
String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// '7:00 AM', '6:30 PM'.
String clockTime(int hour, int minute) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h:${minute.toString().padLeft(2, '0')} ${hour < 12 ? 'AM' : 'PM'}';
}

/// A class on the gym's weekly timetable: on [weekday] (1 Monday to 7
/// Sunday, as DateTime.weekday) at [hour]:[minute], Bhutan time.
class GymClass {
  final String id;
  final String venueId;
  final String name;
  final String? description;
  final String? trainerName;
  final int weekday;
  final int hour;
  final int minute;
  final int durationMinutes;
  final int capacity;
  final bool isActive;

  const GymClass({
    required this.id,
    required this.venueId,
    required this.name,
    this.description,
    this.trainerName,
    required this.weekday,
    required this.hour,
    required this.minute,
    this.durationMinutes = 60,
    required this.capacity,
    this.isActive = true,
  });

  /// '7:00 AM'.
  String get time => clockTime(hour, minute);

  /// '7:00 AM to 8:00 AM'.
  String get span {
    final end = hour * 60 + minute + durationMinutes;
    return '$time to ${clockTime((end ~/ 60) % 24, end % 60)}';
  }

  /// When it starts on [day], in Bhutan time.
  DateTime startOn(DateTime day) => DateTime(day.year, day.month, day.day, hour, minute);

  factory GymClass.fromJson(Map<String, dynamic> json) {
    final parts = (json['starts_at'] as String).split(':');
    return GymClass(
      id: json['id'] as String,
      venueId: json['venue_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      trainerName: json['trainer_name'] as String?,
      weekday: (json['weekday'] as num).toInt(),
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
      durationMinutes: (json['duration_minutes'] as num).toInt(),
      capacity: (json['capacity'] as num).toInt(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

/// What the timetable editor sends (gym_save_class's details).
Map<String, dynamic> classDetails({
  required String name,
  String? description,
  String? trainerName,
  required int weekday,
  required int hour,
  required int minute,
  required int durationMinutes,
  required int capacity,
  bool isActive = true,
}) =>
    {
      'name': name.trim(),
      'description': description == null || description.trim().isEmpty ? null : description.trim(),
      'trainer_name': trainerName == null || trainerName.trim().isEmpty ? null : trainerName.trim(),
      'weekday': weekday,
      'starts_at': '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
      'duration_minutes': durationMinutes,
      'capacity': capacity,
      'is_active': isActive,
    };

/// How many places are booked in a class on a day, and the signed-in
/// member's own booking.
class ClassPlaces {
  final String classId;
  final DateTime date;
  final int booked;
  final String? myBookingId;

  const ClassPlaces({required this.classId, required this.date, required this.booked, this.myBookingId});

  factory ClassPlaces.fromJson(Map<String, dynamic> json) => ClassPlaces(
        classId: json['class_id'] as String,
        date: BhutanTime.parseDate(json['class_date'] as String),
        booked: (json['booked'] as num).toInt(),
        myBookingId: json['my_booking_id'] as String?,
      );
}

/// A class on a day: places booked and left, and the member's booking.
class ClassSession {
  final GymClass gymClass;
  final DateTime date;
  final int booked;
  final String? myBookingId;

  const ClassSession({required this.gymClass, required this.date, this.booked = 0, this.myBookingId});

  int get left => (gymClass.capacity - booked).clamp(0, gymClass.capacity);
  bool get isFull => left == 0;
  DateTime get startsAt => gymClass.startOn(date);

  /// Started by [nowInBhutan]: too late to book or cancel online.
  bool startedBy(DateTime nowInBhutan) => !startsAt.isAfter(nowInBhutan);
}

/// The classes on each of the [days] days from [today], in time order, with
/// their places.
List<ClassSession> sessionsFrom(Iterable<GymClass> classes, Iterable<ClassPlaces> places, DateTime today, {int days = 7}) {
  final out = <ClassSession>[];
  for (var i = 0; i < days; i++) {
    final date = DateTime(today.year, today.month, today.day + i);
    final those = classes.where((c) => c.isActive && c.weekday == date.weekday).toList()
      ..sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    for (final c in those) {
      final p = places.where((p) => p.classId == c.id && p.date == date).firstOrNull;
      out.add(ClassSession(gymClass: c, date: date, booked: p?.booked ?? 0, myBookingId: p?.myBookingId));
    }
  }
  return out;
}

/// Someone booked into a class on a day, for the desk's list: a member
/// registered at the desk ([gymMemberId]), or one whose membership is on
/// their account (20261118000014).
class ClassBooking {
  final String id;
  final String classId;
  final DateTime classDate;
  final String? gymMemberId;
  final String memberName;
  final String? memberCode;
  final String? memberPhone;

  const ClassBooking({
    required this.id,
    required this.classId,
    required this.classDate,
    this.gymMemberId,
    required this.memberName,
    this.memberCode,
    this.memberPhone,
  });

  factory ClassBooking.fromJson(Map<String, dynamic> json) {
    final m = json['member'] as Map<String, dynamic>? ?? json['account'] as Map<String, dynamic>?;
    final name = (m?['full_name'] as String?)?.trim();
    return ClassBooking(
      id: json['id'] as String,
      classId: json['class_id'] as String,
      classDate: BhutanTime.parseDate(json['class_date'] as String),
      gymMemberId: json['gym_member_id'] as String?,
      memberName: name == null || name.isEmpty ? 'Member' : name,
      memberCode: (m?['code'] ?? m?['member_code']) as String?,
      memberPhone: m?['phone'] as String?,
    );
  }
}

// ─── Reading and saving ─────────────────────────────────────────────────────

final gymClassRepositoryProvider = Provider<GymClassRepository>((ref) => GymClassRepository(ref.watch(supabaseProvider)));

/// A gym's timetable (those off it too, for who keeps it).
final gymClassesProvider = FutureProvider.autoDispose.family<List<GymClass>, String>(
  (ref, venueId) => ref.watch(gymClassRepositoryProvider).classes(venueId),
);

/// Places booked in a gym's classes over the next two weeks.
final gymClassPlacesProvider = FutureProvider.autoDispose.family<List<ClassPlaces>, String>(
  (ref, venueId) => ref.watch(gymClassRepositoryProvider).places(venueId, BhutanTime.today()),
);

/// Who's booked into a gym's classes on a day (the desk).
final gymClassBookingsProvider = FutureProvider.autoDispose.family<List<ClassBooking>, ({String venueId, DateTime date})>(
  (ref, q) => ref.watch(gymClassRepositoryProvider).bookings(q.venueId, q.date),
);

class GymClassRepository {
  GymClassRepository(this._client);
  final SupabaseClient _client;

  Future<List<GymClass>> classes(String venueId) async {
    final rows = await _client.from('gym_classes').select().eq('venue_id', venueId).order('weekday').order('starts_at');
    return rows.map(GymClass.fromJson).toList();
  }

  /// A new class ([classId] null) or changes to one.
  Future<void> saveClass(String venueId, Map<String, dynamic> details, {String? classId}) =>
      _client.rpc('gym_save_class', params: {'venue_id': venueId, 'class_id': classId, 'details': details});

  Future<List<ClassPlaces>> places(String venueId, DateTime from) async {
    final rows = await _client.rpc('gym_class_places', params: {'venue_id': venueId, 'from_date': _iso(from), 'days': 14}) as List? ??
        const [];
    return [for (final r in rows) ClassPlaces.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  Future<List<ClassBooking>> bookings(String venueId, DateTime date) async {
    final rows = await _client
        .from('gym_class_bookings')
        .select('*, member:gym_members!gym_class_bookings_gym_member_id_fkey(full_name, code, phone), '
            'account:profiles!gym_class_bookings_user_id_fkey(full_name, phone, member_code)')
        .eq('venue_id', venueId)
        .eq('class_date', _iso(date))
        .eq('status', 'booked')
        .order('booked_at');
    return rows.map(ClassBooking.fromJson).toList();
  }

  /// Books the signed-in member, or [gymMemberId] (the desk), into
  /// [classId] on [date].
  Future<void> book(String classId, DateTime date, {String? gymMemberId}) => _client.rpc('gym_book_class', params: {
        'class_id': classId,
        'class_date': _iso(date),
        if (gymMemberId != null) 'gym_member_id': gymMemberId,
      });

  Future<void> cancel(String bookingId) => _client.rpc('gym_cancel_class_booking', params: {'booking_id': bookingId});
}
