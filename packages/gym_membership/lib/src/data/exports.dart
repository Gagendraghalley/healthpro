import 'package:health_pro_core/health_pro_core.dart';

import 'gym_models.dart';
import 'receipts.dart';
import 'registered_member.dart';

// What a gym's staff export to Excel: its members, its payments, its visits.
// Each is a Spreadsheet the app saves (a download, or the share sheet).

/// Everything the members export needs.
class MembersExport {
  final List<GymMember> members;
  final List<GymSubscription> subscriptions;
  final List<GymPause> pauses;

  const MembersExport({required this.members, required this.subscriptions, required this.pauses});
}

/// One payment, with the package it paid for when the reader may see it.
class ExportedPayment {
  final Payment payment;
  final String? planName;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? memberCode;

  const ExportedPayment({required this.payment, this.planName, this.startDate, this.endDate, this.memberCode});

  /// A payments row with `package:gym_subscriptions(plan_name, start_date,
  /// end_date, registered:gym_members(code))`, a list (one at most).
  factory ExportedPayment.fromJson(Map<String, dynamic> json) {
    final packages = json['package'];
    final package = (packages is List ? packages.firstOrNull : packages) as Map<String, dynamic>?;
    DateTime? date(String key) => package?[key] == null ? null : BhutanTime.parseDate(package![key] as String);
    return ExportedPayment(
      payment: Payment.fromJson(json),
      planName: package?['plan_name'] as String?,
      startDate: date('start_date'),
      endDate: date('end_date'),
      memberCode: (package?['registered'] as Map<String, dynamic>?)?['code'] as String?,
    );
  }
}

/// One visit: when, and who (a registered member, or an account's).
class ExportedVisit {
  final DateTime checkedInAt;
  final String name;
  final String? code;
  final String? phone;

  const ExportedVisit({required this.checkedInAt, required this.name, this.code, this.phone});

  factory ExportedVisit.fromJson(Map<String, dynamic> json) {
    final who = (json['registered'] ?? json['member']) as Map<String, dynamic>?;
    final name = (who?['full_name'] as String?)?.trim();
    return ExportedVisit(
      checkedInAt: DateTime.parse(json['checked_in_at'] as String),
      name: name == null || name.isEmpty ? 'Member' : name,
      code: (who?['code'] ?? who?['member_code']) as String?,
      phone: who?['phone'] as String?,
    );
  }
}

/// A date as Excel shows it (midnight: a date, not a time).
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// A moment in Bhutan's time, to the minute.
DateTime _bhutan(DateTime moment) {
  final b = BhutanTime.toBhutan(moment);
  return DateTime(b.year, b.month, b.day, b.hour, b.minute);
}

/// Where a member stands on [today], in words: 'Active', 'Paused until 3 Dec
/// 2026', 'Starts 1 Dec 2026', 'Ended', 'No package'.
String standingText(MemberStanding standing, {GymPause? pause, DateTime? startsOn}) => switch (standing) {
      MemberStanding.active => 'Active',
      MemberStanding.paused => pause == null ? 'Paused' : 'Paused until ${formatDate(pause.endDate)}',
      MemberStanding.upcoming => startsOn == null ? 'Starts soon' : 'Starts ${formatDate(startsOn)}',
      MemberStanding.ended => 'Ended',
      MemberStanding.none => 'No package',
    };

/// The members, by name: their details, their package and where they stand.
Spreadsheet membersSheet(MembersExport data, DateTime today) {
  final byMember = <String, List<GymSubscription>>{};
  for (final s in data.subscriptions) {
    if (s.gymMemberId != null) byMember.putIfAbsent(s.gymMemberId!, () => []).add(s);
  }
  return Spreadsheet(
    sheetName: 'Members',
    headings: const [
      'Member code', 'Name', 'Phone', 'Email', 'Date of birth', 'Blood group', 'Occupation', 'Place',
      'Emergency contact', 'Emergency phone', 'Medical issues', 'Joined on', 'Package', 'Valid until', 'Standing',
    ],
    rows: [
      for (final m in data.members)
        () {
          final subs = byMember[m.id] ?? const <GymSubscription>[];
          final pause = openPauseOf(data.pauses, m.id, today);
          final standing = standingOf(subs, today, pause: pause);
          final live = subs.where((s) => s.isCurrentOn(today) || s.isUpcomingOn(today)).toList()
            ..sort((a, b) => a.startDate!.compareTo(b.startDate!));
          final last = live.isNotEmpty
              ? live.last
              : (subs.where((s) => s.endDate != null).toList()..sort((a, b) => a.endDate!.compareTo(b.endDate!)))
                  .lastOrNull;
          return <Object?>[
            m.code, m.fullName, m.phone, m.email,
            m.dateOfBirth == null ? null : _day(m.dateOfBirth!),
            m.bloodGroup, m.occupation, m.placeName, m.emergencyContactName, m.emergencyContactPhone, m.medicalNotes,
            _day(m.joinedOn),
            (live.firstOrNull ?? last)?.planName,
            last?.endDate == null ? null : _day(last!.endDate!),
            standingText(standing, pause: pause, startsOn: live.firstOrNull?.startDate),
          ];
        }(),
    ],
  );
}

/// The payments, oldest first: receipt, when, who, what for, how much, how.
Spreadsheet paymentsSheet(List<ExportedPayment> payments) => Spreadsheet(
      sheetName: 'Payments',
      headings: const [
        'Receipt', 'Date', 'Paid by', 'Member code', 'Package', 'From', 'Until', 'Amount (Nu.)', 'Paid with',
        'Reference (JRN)', 'Status',
      ],
      rows: [
        for (final e in payments)
          <Object?>[
            e.payment.receiptNo == null ? null : receiptNumber(e.payment.receiptNo!),
            _bhutan(e.payment.createdAt),
            (e.payment.payerName ?? '').trim().isEmpty ? 'Member' : e.payment.payerName!.trim(),
            e.memberCode,
            e.planName,
            e.startDate == null ? null : _day(e.startDate!),
            e.endDate == null ? null : _day(e.endDate!),
            e.payment.amount,
            e.payment.method.label,
            e.payment.reference,
            e.payment.isCompleted ? 'Received' : 'Refunded',
          ],
      ],
    );

/// The visits, oldest first: when, and who.
Spreadsheet visitsSheet(List<ExportedVisit> visits) => Spreadsheet(
      sheetName: 'Visits',
      headings: const ['Date and time', 'Name', 'Member code', 'Phone'],
      rows: [
        for (final v in visits) <Object?>[_bhutan(v.checkedInAt), v.name, v.code, v.phone],
      ],
    );
