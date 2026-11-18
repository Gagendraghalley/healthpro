import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Group classes: the weekly timetable and booking a place
// (20261118000013_gym_classes.sql); open to anyone on Health Pro, members or
// not, unless the gym keeps a class for members (20261118000016).

const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// '2026-11-18'.
String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// '7:00 AM', '6:30 PM'.
String clockTime(int hour, int minute) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h:${minute.toString().padLeft(2, '0')} ${hour < 12 ? 'AM' : 'PM'}';
}

/// A class on the gym's weekly timetable: on [weekday] (1 Monday to 7
/// Sunday, as DateTime.weekday) at [hour]:[minute], Bhutan time. Anyone
/// on Health Pro books it when [openToAll]; only members otherwise.
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
  final bool openToAll;

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
    this.openToAll = true,
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
      openToAll: json['open_to_all'] as bool? ?? true,
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
  bool openToAll = true,
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
      'open_to_all': openToAll,
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

/// Someone booked into a class on a day, for the desk's list
/// (gym_class_bookings_on): a member registered at the gym ([isMember], with
/// [gymMemberId] and [memberCode] once the desk has registered them), or a
/// non-member on Health Pro who isn't ([userId]); and whether the desk booked them.
class ClassBooking {
  final String id;
  final String classId;
  final DateTime classDate;
  final String? gymMemberId;
  final String? userId;
  final String memberName;
  final String? memberCode;
  final String? memberPhone;
  final String? memberEmail;
  final bool isMember;
  final bool bookedByDesk;

  const ClassBooking({
    required this.id,
    required this.classId,
    required this.classDate,
    this.gymMemberId,
    this.userId,
    required this.memberName,
    this.memberCode,
    this.memberPhone,
    this.memberEmail,
    this.isMember = true,
    this.bookedByDesk = false,
  });

  /// Not registered at the gym: booked an open class on their Health Pro account.
  bool get isNonMember => !isMember;

  /// '+97517700001 · tashi@x.bt', what the desk can reach them by.
  String get contact => [memberPhone, memberEmail].nonNulls.join(' · ');

  factory ClassBooking.fromJson(Map<String, dynamic> json) {
    final name = (json['full_name'] as String?)?.trim();
    return ClassBooking(
      id: json['id'] as String,
      classId: json['class_id'] as String,
      classDate: BhutanTime.parseDate(json['class_date'] as String),
      gymMemberId: json['gym_member_id'] as String?,
      userId: json['user_id'] as String?,
      memberName: name == null || name.isEmpty ? 'Member' : name,
      memberCode: json['member_code'] as String?,
      memberPhone: json['phone'] as String?,
      memberEmail: json['email'] as String?,
      isMember: json['is_member'] as bool? ?? true,
      bookedByDesk: json['booked_by_desk'] as bool? ?? false,
    );
  }
}

/// A place the signed-in person has booked, from today, at any gym
/// (my_class_bookings): on My dashboard.
class MyClassBooking {
  final String id;
  final String classId;
  final String venueId;
  final String venueName;
  final DateTime date;
  final String name;
  final String? trainerName;
  final int hour;
  final int minute;
  final int durationMinutes;

  const MyClassBooking({
    required this.id,
    required this.classId,
    required this.venueId,
    required this.venueName,
    required this.date,
    required this.name,
    this.trainerName,
    required this.hour,
    required this.minute,
    this.durationMinutes = 60,
  });

  /// '7:00 AM'.
  String get time => clockTime(hour, minute);
  DateTime get startsAt => DateTime(date.year, date.month, date.day, hour, minute);
  DateTime get endsAt => startsAt.add(Duration(minutes: durationMinutes));

  factory MyClassBooking.fromJson(Map<String, dynamic> json) {
    final parts = (json['starts_at'] as String).split(':');
    return MyClassBooking(
      id: json['id'] as String,
      classId: json['class_id'] as String,
      venueId: json['venue_id'] as String,
      venueName: json['venue_name'] as String? ?? 'Gym',
      date: BhutanTime.parseDate(json['class_date'] as String),
      name: json['name'] as String,
      trainerName: json['trainer_name'] as String?,
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 60,
    );
  }
}

/// How many have registered for the gym's classes to date
/// (gym_class_registrations): places booked and not cancelled, the people
/// behind them (members of the gym or not), each workout's and each person's.
class ClassRegistrations {
  final int bookings;
  final int people;
  final int members;
  final int nonMembers;
  final int upcoming;
  final int cancelled;
  final List<ClassTally> classes;
  final List<ClassRegistrant> registrants;

  const ClassRegistrations({
    this.bookings = 0,
    this.people = 0,
    this.members = 0,
    this.nonMembers = 0,
    this.upcoming = 0,
    this.cancelled = 0,
    this.classes = const [],
    this.registrants = const [],
  });

  factory ClassRegistrations.fromJson(Map<String, dynamic> json) {
    final t = Map<String, dynamic>.from(json['totals'] as Map? ?? const {});
    int n(String k) => (t[k] as num?)?.toInt() ?? 0;
    return ClassRegistrations(
      bookings: n('bookings'),
      people: n('people'),
      members: n('members'),
      nonMembers: n('non_members'),
      upcoming: n('upcoming'),
      cancelled: n('cancelled'),
      classes: [for (final c in json['classes'] as List? ?? const []) ClassTally.fromJson(Map<String, dynamic>.from(c as Map))],
      registrants: [
        for (final p in json['people'] as List? ?? const []) ClassRegistrant.fromJson(Map<String, dynamic>.from(p as Map)),
      ],
    );
  }
}

/// One class's registrations to date.
class ClassTally {
  final String classId;
  final String name;
  final int weekday;
  final int hour;
  final int minute;
  final bool isActive;
  final int bookings;
  final int people;
  final int members;
  final int nonMembers;
  final int upcoming;
  final DateTime? lastDate;

  const ClassTally({
    required this.classId,
    required this.name,
    required this.weekday,
    required this.hour,
    required this.minute,
    this.isActive = true,
    this.bookings = 0,
    this.people = 0,
    this.members = 0,
    this.nonMembers = 0,
    this.upcoming = 0,
    this.lastDate,
  });

  /// 'Monday 7:00 AM'.
  String get when => '${weekdayNames[weekday - 1]} ${clockTime(hour, minute)}';

  factory ClassTally.fromJson(Map<String, dynamic> json) {
    final parts = (json['starts_at'] as String).split(':');
    final last = json['last_date'] as String?;
    return ClassTally(
      classId: json['class_id'] as String,
      name: json['name'] as String,
      weekday: (json['weekday'] as num).toInt(),
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
      isActive: json['is_active'] as bool? ?? true,
      bookings: (json['bookings'] as num?)?.toInt() ?? 0,
      people: (json['people'] as num?)?.toInt() ?? 0,
      members: (json['members'] as num?)?.toInt() ?? 0,
      nonMembers: (json['non_members'] as num?)?.toInt() ?? 0,
      upcoming: (json['upcoming'] as num?)?.toInt() ?? 0,
      lastDate: last == null ? null : BhutanTime.parseDate(last),
    );
  }
}

/// Someone who has booked the gym's classes: a member of the gym or
/// not, how to reach them, how many times, and their latest.
class ClassRegistrant {
  final String key;
  final String name;
  final bool isMember;
  final String? memberCode;
  final String? phone;
  final String? email;
  final int bookings;
  final int upcoming;
  final DateTime firstDate;
  final DateTime lastDate;
  final String? lastClass;

  const ClassRegistrant({
    required this.key,
    required this.name,
    this.isMember = true,
    this.memberCode,
    this.phone,
    this.email,
    this.bookings = 1,
    this.upcoming = 0,
    required this.firstDate,
    required this.lastDate,
    this.lastClass,
  });

  bool get isNonMember => !isMember;

  /// '+97517700001 · tashi@x.bt'.
  String get contact => [phone, email].nonNulls.join(' · ');

  factory ClassRegistrant.fromJson(Map<String, dynamic> json) {
    final name = (json['full_name'] as String?)?.trim();
    return ClassRegistrant(
      key: json['key'] as String,
      name: name == null || name.isEmpty ? 'Member' : name,
      isMember: json['is_member'] as bool? ?? true,
      memberCode: json['member_code'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      bookings: (json['bookings'] as num?)?.toInt() ?? 0,
      upcoming: (json['upcoming'] as num?)?.toInt() ?? 0,
      firstDate: BhutanTime.parseDate(json['first_date'] as String),
      lastDate: BhutanTime.parseDate(json['last_date'] as String),
      lastClass: json['last_class'] as String?,
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

/// Who has registered for a gym's classes to date (the desk).
final gymClassRegistrationsProvider = FutureProvider.autoDispose.family<ClassRegistrations, String>(
  (ref, venueId) => ref.watch(gymClassRepositoryProvider).registrations(venueId),
);

/// The signed-in person's places from today, at every gym (My dashboard).
final myClassBookingsProvider = FutureProvider.autoDispose<List<MyClassBooking>>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  return ref.watch(gymClassRepositoryProvider).mine();
});

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
    final rows = await _client.rpc('gym_class_bookings_on', params: {'venue_id': venueId, 'class_date': _iso(date)}) as List? ??
        const [];
    return [for (final r in rows) ClassBooking.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  /// Books the signed-in person (a member, or anyone for an open class), or
  /// [gymMemberId] (the desk), into [classId] on [date].
  Future<void> book(String classId, DateTime date, {String? gymMemberId}) => _client.rpc('gym_book_class', params: {
        'class_id': classId,
        'class_date': _iso(date),
        if (gymMemberId != null) 'gym_member_id': gymMemberId,
      });

  Future<ClassRegistrations> registrations(String venueId) async {
    final json = await _client.rpc('gym_class_registrations', params: {'venue_id': venueId});
    return json == null ? const ClassRegistrations() : ClassRegistrations.fromJson(Map<String, dynamic>.from(json as Map));
  }

  Future<List<MyClassBooking>> mine() async {
    final rows = await _client.rpc('my_class_bookings') as List? ?? const [];
    return [for (final r in rows) MyClassBooking.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  Future<void> cancel(String bookingId) => _client.rpc('gym_cancel_class_booking', params: {'booking_id': bookingId});
}
