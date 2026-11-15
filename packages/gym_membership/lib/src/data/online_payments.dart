/// A gym's settings for its members: its bank's payment QR code (for paying
/// online), the days before a package ends that members are reminded, and
/// who answers requests to join.
class GymSettings {
  final String venueId;

  /// The payment QR image, `<venue id>/<file>` in the public gym-payment-qr
  /// bucket; null when the gym takes payments at the desk only.
  final String? paymentQrPath;

  /// Days before the end, most first: [7, 3].
  final List<int> reminderDays;

  /// The front desk ('desk'), or only the owner and managers ('managers').
  final String joinApproval;

  const GymSettings({
    required this.venueId,
    this.paymentQrPath,
    this.reminderDays = const [3],
    this.joinApproval = JoinApproval.desk,
  });

  /// Before a gym has saved any: what the database uses then.
  factory GymSettings.defaults(String venueId) => GymSettings(venueId: venueId);

  factory GymSettings.fromJson(Map<String, dynamic> json) => GymSettings(
        venueId: json['venue_id'] as String,
        paymentQrPath: json['payment_qr_path'] as String?,
        reminderDays: [for (final d in (json['reminder_days'] as List? ?? const [3])) (d as num).toInt()],
        joinApproval: json['join_approval'] as String? ?? JoinApproval.desk,
      );

  bool get managersAnswerJoins => joinApproval == JoinApproval.managers;
}

abstract final class JoinApproval {
  static const desk = 'desk';
  static const managers = 'managers';
}

/// Days a gym can choose to remind members before a package ends.
const reminderDayOptions = [1, 3, 7, 14, 30];

/// Where a member's online payment is.
enum ClaimStatus {
  pending('pending', 'Waiting'),
  confirmed('confirmed', 'Confirmed'),
  rejected('rejected', 'Not found'),
  cancelled('cancelled', 'Taken back');

  final String value;
  final String label;

  const ClaimStatus(this.value, this.label);

  static ClaimStatus of(String? value) =>
      ClaimStatus.values.where((s) => s.value == value).firstOrNull ?? ClaimStatus.pending;
}

/// A member paid online (the gym's payment QR in their bank app) and gave
/// the journal number (JRN): the gym checks it with the bank and confirms
/// it, which starts their package, or says it couldn't find it.
class PaymentClaim {
  final String id;
  final String venueId;
  final String gymMemberId;
  final String memberName;
  final String? memberCode;
  final String? planId;
  final String planName;
  final int months;
  final int amount;
  final String jrn;
  final ClaimStatus status;
  final String? decisionNote;
  final DateTime createdAt;
  final DateTime? decidedAt;

  const PaymentClaim({
    required this.id,
    required this.venueId,
    required this.gymMemberId,
    required this.memberName,
    required this.planName,
    required this.months,
    required this.amount,
    required this.jrn,
    required this.status,
    required this.createdAt,
    this.memberCode,
    this.planId,
    this.decisionNote,
    this.decidedAt,
  });

  bool get isPending => status == ClaimStatus.pending;

  String get monthsLabel => months == 1 ? '1 month' : '$months months';

  /// A gym_payment_claims row, with `member:gym_members(full_name, code)`.
  factory PaymentClaim.fromJson(Map<String, dynamic> json) {
    final member = json['member'] as Map<String, dynamic>?;
    return PaymentClaim(
      id: json['id'] as String,
      venueId: json['venue_id'] as String,
      gymMemberId: json['gym_member_id'] as String,
      memberName: member?['full_name'] as String? ?? 'Member',
      memberCode: member?['code'] as String?,
      planId: json['plan_id'] as String?,
      planName: json['plan_name'] as String,
      months: (json['months'] as num).toInt(),
      amount: (json['amount'] as num).toInt(),
      jrn: json['jrn'] as String,
      status: ClaimStatus.of(json['status'] as String?),
      decisionNote: json['decision_note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      decidedAt: json['decided_at'] == null ? null : DateTime.parse(json['decided_at'] as String),
    );
  }
}

/// The signed-in member's payment at one of their gyms, from my_gyms().
class MyClaim {
  final String id;
  final ClaimStatus status;
  final String planName;
  final int months;
  final int amount;
  final String jrn;
  final String? decisionNote;
  final DateTime createdAt;

  const MyClaim({
    required this.id,
    required this.status,
    required this.planName,
    required this.months,
    required this.amount,
    required this.jrn,
    required this.createdAt,
    this.decisionNote,
  });

  factory MyClaim.fromJson(Map<String, dynamic> json) => MyClaim(
        id: json['id'] as String,
        status: ClaimStatus.of(json['status'] as String?),
        planName: json['plan_name'] as String,
        months: (json['months'] as num).toInt(),
        amount: (json['amount'] as num).toInt(),
        jrn: json['jrn'] as String,
        decisionNote: json['decision_note'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
