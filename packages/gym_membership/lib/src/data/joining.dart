import 'package:health_pro_core/health_pro_core.dart';

import 'online_payments.dart';
import 'receipts.dart';
import 'registered_member.dart';

/// A scanned QR code whose person isn't a member of this gym yet: the desk
/// can add them by [personToken] (their Health Pro QR code), without typing
/// their details again.
class NotMemberHere implements Exception {
  final String name;
  final String? personToken;

  const NotMemberHere({required this.name, this.personToken});

  @override
  String toString() => "$name isn't a member here yet.";
}

/// Someone asking to join a gym, from its QR code.
enum JoinRequestStatus {
  pending('pending', 'Waiting'),
  approved('approved', 'Added'),
  declined('declined', 'Declined'),
  cancelled('cancelled', 'Taken back');

  final String value;
  final String label;

  const JoinRequestStatus(this.value, this.label);

  static JoinRequestStatus of(String? value) =>
      JoinRequestStatus.values.where((s) => s.value == value).firstOrNull ??
      JoinRequestStatus.pending;
}

/// A request to join, as the gym's desk sees it.
class JoinRequest {
  final String id;
  final String venueId;
  final JoinRequestStatus status;
  final String name;
  final String? email;
  final String? phone;
  final String? planId;
  final String? planName;
  final int? planPrice;
  final String? message;
  final String? decisionNote;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final String? gymMemberId;

  const JoinRequest({
    required this.id,
    required this.venueId,
    required this.status,
    required this.name,
    required this.createdAt,
    this.email,
    this.phone,
    this.planId,
    this.planName,
    this.planPrice,
    this.message,
    this.decisionNote,
    this.decidedAt,
    this.gymMemberId,
  });

  bool get isPending => status == JoinRequestStatus.pending;

  /// A gym_join_requests row with `person:people(full_name, email, phone)`
  /// and `plan:gym_plans(name, price)`.
  factory JoinRequest.fromJson(Map<String, dynamic> json) {
    final person = json['person'] as Map<String, dynamic>?;
    final plan = json['plan'] as Map<String, dynamic>?;
    final name = (person?['full_name'] as String?)?.trim();
    return JoinRequest(
      id: json['id'] as String,
      venueId: json['venue_id'] as String,
      status: JoinRequestStatus.of(json['status'] as String?),
      name: name == null || name.isEmpty ? 'Health Pro member' : name,
      email: person?['email'] as String?,
      phone: person?['phone'] as String?,
      planId: json['plan_id'] as String?,
      planName: plan?['name'] as String?,
      planPrice: (plan?['price'] as num?)?.toInt(),
      message: json['message'] as String?,
      decisionNote: json['decision_note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      decidedAt: json['decided_at'] == null
          ? null
          : DateTime.parse(json['decided_at'] as String),
      gymMemberId: json['gym_member_id'] as String?,
    );
  }
}

/// What the desk needs to add someone already on Health Pro to its gym:
/// the details they gave their last gym (or their account), the package
/// they asked for, and whether they're registered here already.
class PersonDetails {
  final String personId;
  final String name;
  final MemberDetails details;
  final String? gymMemberIdHere;
  final String? planId;
  final String? message;

  const PersonDetails({
    required this.personId,
    required this.name,
    required this.details,
    this.gymMemberIdHere,
    this.planId,
    this.message,
  });

  factory PersonDetails.fromJson(Map<String, dynamic> json) => PersonDetails(
        personId: json['person_id'] as String,
        name: json['full_name'] as String? ?? 'Member',
        details: MemberDetails.fromJson(
            Map<String, dynamic>.from(json['details'] as Map? ?? const {}),
            joinedOn: BhutanTime.today()),
        gymMemberIdHere: json['gym_member_id'] as String?,
        planId: json['plan_id'] as String?,
        message: json['message'] as String?,
      );
}

/// A gym the signed-in person belongs to, with their latest package.
class MyGym {
  final String venueId;
  final String venueName;
  final String place;
  final String? phone;
  final String? memberCode;
  final String? planName;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? lastVisit;

  /// Their registration at the gym; null for an account membership from
  /// before, which can't be paid online.
  final String? gymMemberId;

  /// How to pay online: the gym's bank account (null until it sets it up),
  /// and its own note.
  final PaymentAccount? paymentAccount;
  final String? paymentQrUrl;
  final String? paymentInfo;

  /// Their payment waiting, or the last one the gym answered.
  final MyClaim? claim;

  /// Their trainer there, if they have one.
  final ({String id, String name, String? photoUrl})? trainer;

  /// Their pause there, running or planned; their package's [endDate]
  /// already counts it.
  final GymPause? pause;

  /// Their last payments there, latest first.
  final List<ReceiptLine> receipts;

  const MyGym({
    required this.venueId,
    required this.venueName,
    required this.place,
    this.phone,
    this.memberCode,
    this.planName,
    this.startDate,
    this.endDate,
    this.lastVisit,
    this.gymMemberId,
    this.paymentAccount,
    this.paymentQrUrl,
    this.paymentInfo,
    this.claim,
    this.trainer,
    this.pause,
    this.receipts = const [],
  });

  /// Paused on [today]: they can't check in until the pause ends.
  bool isPausedOn(DateTime today) => pause?.coversOn(today) ?? false;

  /// They can pay this gym online: registered here, the gym has set up its
  /// bank account, and nothing is waiting already.
  bool get canPayOnline =>
      gymMemberId != null &&
      paymentAccount != null &&
      paymentQrUrl != null &&
      claim?.status != ClaimStatus.pending;

  /// Their package covers [today] (Bhutan dates, both ends included).
  bool isActiveOn(DateTime today) =>
      startDate != null &&
      endDate != null &&
      !startDate!.isAfter(today) &&
      !endDate!.isBefore(today);

  bool hasEndedBy(DateTime today) =>
      endDate != null && endDate!.isBefore(today);

  factory MyGym.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) =>
        json[key] == null ? null : BhutanTime.parseDate(json[key] as String);
    final town = (json['town'] as String?)?.trim();
    return MyGym(
      venueId: json['venue_id'] as String,
      venueName: json['venue_name'] as String,
      place: [
        if (town != null && town.isNotEmpty) town,
        json['dzongkhag'] as String
      ].join(', '),
      phone: json['phone'] as String?,
      memberCode: json['member_code'] as String?,
      planName: json['plan_name'] as String?,
      startDate: date('start_date'),
      endDate: date('end_date'),
      lastVisit: json['last_visit'] == null
          ? null
          : DateTime.parse(json['last_visit'] as String),
      gymMemberId: json['gym_member_id'] as String?,
      paymentAccount: json['payment_account'] is Map
          ? PaymentAccount.fromJson(
              Map<String, dynamic>.from(json['payment_account'] as Map))
          : null,
      paymentQrUrl: json['payment_qr_url'] as String?,
      paymentInfo: (json['payment_info'] as String?)?.trim().isNotEmpty == true
          ? json['payment_info'] as String
          : null,
      claim: json['claim'] == null
          ? null
          : MyClaim.fromJson(Map<String, dynamic>.from(json['claim'] as Map)),
      trainer: json['trainer'] is Map
          ? (
              id: (json['trainer'] as Map)['id'] as String,
              name: (json['trainer'] as Map)['name'] as String,
              photoUrl: (json['trainer'] as Map)['photo_url'] as String?,
            )
          : null,
      pause: json['pause'] is Map
          ? GymPause.fromJson(Map<String, dynamic>.from(json['pause'] as Map))
          : null,
      receipts: [
        for (final r in (json['receipts'] as List? ?? const []))
          ReceiptLine.fromJson(Map<String, dynamic>.from(r as Map)),
      ],
    );
  }
}

/// One of the signed-in person's requests to join.
class MyJoinRequest {
  final String id;
  final String venueId;
  final String venueName;
  final JoinRequestStatus status;
  final String? planName;
  final String? decisionNote;
  final DateTime createdAt;

  const MyJoinRequest({
    required this.id,
    required this.venueId,
    required this.venueName,
    required this.status,
    required this.createdAt,
    this.planName,
    this.decisionNote,
  });

  factory MyJoinRequest.fromJson(Map<String, dynamic> json) => MyJoinRequest(
        id: json['id'] as String,
        venueId: json['venue_id'] as String,
        venueName: json['venue_name'] as String,
        status: JoinRequestStatus.of(json['status'] as String?),
        planName: json['plan_name'] as String?,
        decisionNote: json['decision_note'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// The signed-in person's gyms, requests to join and recent visits.
class MyMemberships {
  final List<MyGym> gyms;
  final List<MyJoinRequest> requests;
  final List<({String gym, DateTime at})> visits;

  const MyMemberships(
      {this.gyms = const [], this.requests = const [], this.visits = const []});

  static const none = MyMemberships();

  /// Their membership at [venueId], if any.
  MyGym? at(String venueId) =>
      gyms.where((g) => g.venueId == venueId).firstOrNull;

  /// Their request to join [venueId] that's waiting, if any.
  MyJoinRequest? waitingAt(String venueId) => requests
      .where(
          (r) => r.venueId == venueId && r.status == JoinRequestStatus.pending)
      .firstOrNull;

  factory MyMemberships.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> rows(String key) => [
          for (final r in (json[key] as List? ?? const []))
            Map<String, dynamic>.from(r as Map)
        ];
    return MyMemberships(
      gyms: rows('gyms').map(MyGym.fromJson).toList(),
      requests: rows('requests').map(MyJoinRequest.fromJson).toList(),
      visits: [
        for (final v in rows('visits'))
          (
            gym: v['venue_name'] as String,
            at: DateTime.parse(v['checked_in_at'] as String)
          ),
      ],
    );
  }
}
