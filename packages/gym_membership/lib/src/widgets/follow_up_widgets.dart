import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/follow_ups.dart';
import '../gym_routes.dart';
import 'member_photo.dart';

/// 'today', 'yesterday', 'on 12 Nov'.
String sentWhen(DateTime at, DateTime today) {
  final day = BhutanTime.dateOnly(BhutanTime.toBhutan(at));
  final ago = BhutanTime.daysBetween(day, today);
  return ago <= 0 ? 'today' : (ago == 1 ? 'yesterday' : 'on ${formatShortDate(day)}');
}

/// Opens WhatsApp on this phone with [message] for [phone], ready to send,
/// and notes that the desk sent [gymMemberId] a [kind] message (so the desk
/// sees it, and it's in the activity log).
Future<void> sendWhatsAppFollowUp(BuildContext context, WidgetRef ref,
    {required String venueId, required String gymMemberId, required String phone, required String message, required MessageKind kind}) async {
  await openWhatsApp(context, phone, message: message);
  if (!context.mounted) return;
  final ok = await runAction(context, () => ref.read(gymFollowUpRepositoryProvider).noteMessage(gymMemberId, kind));
  if (ok) ref.invalidate(gymMemberMessagesProvider(venueId));
}

/// A renewal reminder or birthday wish on WhatsApp, for one member: a
/// button with words, or a round icon in a list ([compact]). Sent lately, it
/// says when (a reminder in the last 7 days, a wish today) and can be sent
/// again.
class WhatsAppFollowUpButton extends ConsumerWidget {
  final String venueId;
  final String gymMemberId;
  final String phone;
  final String message;
  final MessageKind kind;
  final bool compact;

  const WhatsAppFollowUpButton({
    super.key,
    required this.venueId,
    required this.gymMemberId,
    required this.phone,
    required this.message,
    required this.kind,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = BhutanTime.today();
    final messages = ref.watch(gymMemberMessagesProvider(venueId)).valueOrNull ?? const <MemberMessage>[];
    final last = lastSent(messages, gymMemberId, kind);
    final lately = last != null &&
        BhutanTime.daysBetween(BhutanTime.dateOnly(BhutanTime.toBhutan(last)), today) < (kind == MessageKind.renewal ? 7 : 1);
    final done = kind == MessageKind.renewal ? 'Reminded' : 'Wished';
    final label = lately ? '$done ${sentWhen(last, today)}' : (kind == MessageKind.renewal ? 'Remind on WhatsApp' : 'Wish on WhatsApp');
    final brand = context.brand;
    void send() => sendWhatsAppFollowUp(context, ref, venueId: venueId, gymMemberId: gymMemberId, phone: phone, message: message, kind: kind);
    final icon = lately
        ? Icons.mark_chat_read_rounded
        : (kind == MessageKind.renewal ? Icons.chat_outlined : Icons.cake_outlined);
    if (compact) {
      return IconButton(
        tooltip: lately ? '$label. Send again' : label,
        onPressed: send,
        icon: Icon(icon, size: 20, color: lately ? brand.success : brand.muted),
      );
    }
    return OutlinedButton.icon(
      onPressed: send,
      icon: Icon(icon, color: lately ? brand.success : null),
      label: Text(label),
    );
  }
}

/// On the dashboard: members' birthdays in the next 7 days, today's with a
/// wish on WhatsApp. A row opens the member.
class BirthdaysCard extends StatelessWidget {
  final String venueId;
  final String gymName;
  final List<Birthday> birthdays;
  final DateTime today;

  const BirthdaysCard({super.key, required this.venueId, required this.gymName, required this.birthdays, required this.today});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    final brand = context.brand;
    final todays = birthdays.where((b) => b.day == today).length;
    return ConsoleCard(
      icon: Icons.cake_outlined,
      title: 'Birthdays',
      trailing: Text(todays > 0 ? '$todays today' : 'Next 7 days', style: TextStyle(fontSize: 12.5, color: brand.muted)),
      child: Column(
        children: [
          for (final b in birthdays.take(6))
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.push(GymRoutes.memberFor(venueId, b.member.id)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    MemberPhoto(path: b.member.photoPath, photoUrl: b.member.avatarUrl, name: b.member.fullName, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.member.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink.heading),
                          ),
                          Text(
                            '${b.day == today ? 'Today' : _weekdayDate(b.day)} · turns ${b.age}',
                            style: TextStyle(fontSize: 12.5, color: b.day == today ? brand.readable(brand.highlight) : brand.muted),
                          ),
                        ],
                      ),
                    ),
                    if (b.day == today)
                      WhatsAppFollowUpButton(
                        venueId: venueId,
                        gymMemberId: b.member.id,
                        phone: b.member.phone,
                        message: birthdayMessage(name: b.member.fullName, gym: gymName),
                        kind: MessageKind.birthday,
                        compact: true,
                      ),
                  ],
                ),
              ),
            ),
          if (birthdays.length > 6)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('and ${birthdays.length - 6} more this week', style: TextStyle(fontSize: 12.5, color: brand.muted)),
            ),
        ],
      ),
    );
  }

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static String _weekdayDate(DateTime d) => '${_days[d.weekday - 1]} ${formatShortDate(d)}';
}
