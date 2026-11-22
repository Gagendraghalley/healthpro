import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/exports.dart';
import '../data/follow_ups.dart';
import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../data/joining.dart';
import '../data/registered_member.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import '../widgets/coaching_widgets.dart';
import '../widgets/delete_member_dialog.dart';
import '../widgets/export_button.dart';
import '../widgets/follow_up_widgets.dart';
import '../widgets/gym_widgets.dart';
import '../widgets/member_card.dart';
import '../widgets/member_photo.dart';
import '../widgets/package_fields.dart';
import '../widgets/pause_widgets.dart';
import '../widgets/receipt_view.dart';
import '../widgets/trainer_widgets.dart';
import 'activity_screen.dart';
import 'payment_screens.dart';

/// [member]'s memberships at the gym, newest first.
List<GymSubscription> membershipsOf(Iterable<GymSubscription> all, String gymMemberId) =>
    all.where((s) => s.gymMemberId == gymMemberId).toList()..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

/// The last day their packages (renewals included) cover, if any is
/// current or still to start.
DateTime? paidUntil(Iterable<GymSubscription> subs, DateTime today) {
  DateTime? until;
  for (final s in subs) {
    if ((s.isCurrentOn(today) || s.isUpcomingOn(today)) && (until == null || s.endDate!.isAfter(until))) until = s.endDate;
  }
  return until;
}

/// Their paid package that ends last (running, to come or ended), if any.
GymSubscription? latestPackage(Iterable<GymSubscription> subs) {
  GymSubscription? latest;
  for (final s in subs) {
    if ((s.status == SubscriptionStatus.active || s.status == SubscriptionStatus.expired) &&
        s.endDate != null &&
        (latest == null || s.endDate!.isAfter(latest.endDate!))) {
      latest = s;
    }
  }
  return latest;
}

/// Their package in a line: 'Gym · until 7 Feb 2027', 'Gym from 1 Dec',
/// 'Gym ended 3 Oct', 'No package yet'.
String packageLine(List<GymSubscription> subs, DateTime today) {
  final current = subs.where((s) => s.isCurrentOn(today)).firstOrNull;
  final until = paidUntil(subs, today);
  if (current != null) return '${current.planName} · until ${formatDate(until!)}';
  final upcoming = subs.where((s) => s.isUpcomingOn(today)).firstOrNull;
  if (upcoming != null) return '${upcoming.planName} · from ${formatDate(upcoming.startDate!)}';
  final ended = subs.where((s) => s.endDate != null).toList()..sort((a, b) => b.endDate!.compareTo(a.endDate!));
  if (ended.isNotEmpty) return '${ended.first.planName} · ended ${formatDate(ended.first.endDate!)}';
  return 'No package yet';
}

/// Their standing as a chip.
class StandingChip extends StatelessWidget {
  final MemberStanding standing;
  final int? daysLeft;

  /// The last paused day, while [standing] is paused.
  final DateTime? pausedUntil;

  const StandingChip({super.key, required this.standing, this.daysLeft, this.pausedUntil});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return switch (standing) {
      MemberStanding.active => StatusChip(
          label: daysLeft == null ? 'Active' : (daysLeft == 1 ? 'Last day' : '$daysLeft days left'),
          color: (daysLeft ?? 99) <= 7 ? brand.warning : brand.success,
          icon: Icons.check_circle_rounded,
        ),
      MemberStanding.paused => StatusChip(
          label: pausedUntil == null ? 'Paused' : 'Paused to ${formatShortDate(pausedUntil!)}',
          color: brand.warning,
          icon: Icons.pause_circle_rounded,
        ),
      MemberStanding.upcoming => StatusChip(label: 'Starts soon', color: context.colors.tertiary, icon: Icons.event_rounded),
      MemberStanding.ended => StatusChip(label: 'Ended', color: brand.danger, icon: Icons.history_rounded),
      MemberStanding.none => StatusChip(label: 'No package', color: brand.muted),
    };
  }
}

/// What they told the desk: email, birthday, blood group, work, address,
/// date of joining, emergency contact; their phone too with [withPhone].
class MemberDetailsCard extends StatelessWidget {
  final GymMember member;
  final bool withPhone;

  const MemberDetailsCard({super.key, required this.member, this.withPhone = false});

  @override
  Widget build(BuildContext context) {
    final m = member;
    final today = BhutanTime.today();
    String? age() {
      final dob = m.dateOfBirth;
      if (dob == null) return null;
      var years = today.year - dob.year;
      if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) years--;
      return '${formatDate(dob)} (age $years)';
    }

    return SectionCard(
      padding: const EdgeInsets.all(18),
      child: ResponsiveGrid(
        minItemWidth: 260,
        maxColumns: 2,
        spacing: 16,
        runSpacing: 2,
        equalHeight: false,
        children: [
          if (withPhone) InfoRow(icon: Icons.call_outlined, text: m.phone),
          if (m.email != null) InfoRow(icon: Icons.mail_outline_rounded, text: m.email!),
          if (age() != null) InfoRow(icon: Icons.cake_outlined, text: age()!),
          if (m.bloodGroup != null) InfoRow(icon: Icons.bloodtype_outlined, text: 'Blood group ${m.bloodGroup}'),
          if (m.occupation != null) InfoRow(icon: Icons.work_outline_rounded, text: m.occupation!),
          if (m.placeName != null) InfoRow(icon: Icons.place_outlined, text: m.placeName!),
          InfoRow(icon: Icons.event_available_outlined, text: 'Joined ${formatDate(m.joinedOn)}'),
          if (m.emergencyContactName != null || m.emergencyContactPhone != null)
            InfoRow(
              icon: Icons.contact_emergency_outlined,
              text: 'Emergency: ${[m.emergencyContactName, m.emergencyContactPhone].whereType<String>().join(' · ')}',
            ),
        ],
      ),
    );
  }
}

/// Their medical issues, for the desk and trainers to see first.
class MedicalNotice extends StatelessWidget {
  final String notes;

  const MedicalNotice(this.notes, {super.key});

  @override
  Widget build(BuildContext context) {
    final warning = context.brand.warning;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.medical_information_outlined, color: warning),
          const SizedBox(width: 12),
          Expanded(child: Text(notes)),
        ],
      ),
    );
  }
}

enum _Filter {
  all('All'),
  active('Active'),
  ending('Ending in 7 days'),
  paused('Paused'),
  ended('Ended'),
  none('No package');

  const _Filter(this.label);
  final String label;
}

enum _Sort {
  name('Name, A to Z'),
  expiry('Expiry date, soonest first'),
  newest('Newest first');

  const _Sort(this.label);
  final String label;
}

/// Whether [r] (one member's packages and pause) passes [filter] on [today].
/// A paused member still counts as active (they've paid).
bool _passes(_Filter filter, _MemberRow r, DateTime today) {
  final subs = r.subs;
  final standing = standingOf(subs, today, pause: r.pause);
  return switch (filter) {
    _Filter.all => true,
    _Filter.active =>
      standing == MemberStanding.active || standing == MemberStanding.upcoming || standing == MemberStanding.paused,
    _Filter.ending => standing == MemberStanding.active &&
        !subs.any((s) => s.isUpcomingOn(today)) &&
        BhutanTime.daysBetween(today, paidUntil(subs, today)!) < 7,
    _Filter.paused => standing == MemberStanding.paused,
    _Filter.ended => standing == MemberStanding.ended,
    _Filter.none => standing == MemberStanding.none,
  };
}

// ─── The register ─────────────────────────────────────────────────────────

/// Everyone registered at the gym's front desk: found by name, phone or
/// member code; filtered by where their package stands (with how many in
/// each); sorted by name, expiry or joining; as a table on a computer and
/// cards on a phone.
class MembersScreen extends ConsumerStatefulWidget {
  final String venueId;

  const MembersScreen({super.key, required this.venueId});

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.name;
  String _search = '';

  /// Cards even where a table fits.
  bool _cards = false;

  @override
  Widget build(BuildContext context) {
    final id = widget.venueId;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return GymStaffPage(
      venueId: id,
      title: 'Members',
      permission: GymPermission.members,
      builder: (context, access) {
        final members = ref.watch(gymMembersProvider(id));
        final subs = ref.watch(gymSubscriptionsProvider(id)).valueOrNull ?? const <GymSubscription>[];
        final pauses = ref.watch(gymOpenPausesProvider(id)).valueOrNull ?? const <GymPause>[];
        final today = BhutanTime.today();
        final canRegister = access.can(GymPermission.register);
        // The gym's New menu as buttons on the band; registering has its own.
        final shortcuts = [
          for (final s in AppShellScope.maybeOf(context)?.service?.actions ?? const <ServiceAction>[])
            if (s.route != GymRoutes.registerMemberFor(id)) s,
        ];
        return AppPage(
          title: 'Members',
          floatingActionButton: canRegister && !wide
              ? FloatingActionButton.extended(
                  onPressed: () => context.go(GymRoutes.registerMemberFor(id)),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Register member'),
                )
              : null,
          body: AsyncValueView<List<GymMember>>(
            value: members,
            onRetry: () => ref.invalidate(gymMembersProvider(id)),
            data: (all) {
              final everyone = [
                for (final m in all)
                  (member: m, subs: membershipsOf(subs, m.id), pause: openPauseOf(pauses, m.id, today)),
              ];
              final counts = {
                for (final f in _Filter.values) f: everyone.where((r) => _passes(f, r, today)).length,
              };
              final rows = everyone.where((r) => _matches(r.member) && _passes(_filter, r, today)).toList();
              rows.sort((a, b) => switch (_sort) {
                    _Sort.name => a.member.fullName.toLowerCase().compareTo(b.member.fullName.toLowerCase()),
                    _Sort.newest => b.member.joinedOn.compareTo(a.member.joinedOn),
                    _Sort.expiry => (paidUntil(a.subs, today) ?? DateTime(9999))
                        .compareTo(paidUntil(b.subs, today) ?? DateTime(9999)),
                  });
              final active = counts[_Filter.active]!;
              return RefreshIndicator(
                onRefresh: () async => refreshGym(ref, id),
                child: ListView(
                  padding: pagePadding(context, bottom: 96),
                  children: [
                    // Registering is on the band where there's room; a phone
                    // has the floating button instead.
                    FadeSlideIn(
                      child: WelcomeBand(
                        eyebrow: access.venue.name,
                        title: 'Members',
                        subtitle: all.isEmpty
                            ? 'No members yet.'
                            : '${all.length} registered  ·  $active active now',
                        // With the gym's other shortcuts (the New menu), here
                        // under the bar rather than in it.
                        bottom: (canRegister && wide) || shortcuts.isNotEmpty
                            ? Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  if (canRegister && wide)
                                    BandAction(
                                      icon: Icons.person_add_alt_1_rounded,
                                      label: 'Register member',
                                      main: true,
                                      onPressed: () => context.go(GymRoutes.registerMemberFor(id)),
                                    ),
                                  for (final s in shortcuts)
                                    BandAction(icon: s.icon, label: s.label, onPressed: () => context.go(s.route)),
                                ],
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (all.isEmpty)
                      EmptyState(
                        icon: Icons.groups_rounded,
                        title: 'Register your first member',
                        message: 'Register members at the front desk: their details, photo and package. '
                            'They get a QR card to show when they come in.',
                        actionLabel: canRegister ? 'Register a member' : null,
                        onAction: () => context.go(GymRoutes.registerMemberFor(id)),
                      )
                    else ...[
                      LayoutBuilder(
                          builder: (context, c) => _toolbar(context, wide: c.maxWidth >= 760, gymName: access.venue.name)),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final f in _Filter.values)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text('${f.label}  ${counts[f]}'),
                                  selected: _filter == f,
                                  onSelected: (_) => setState(() => _filter = f),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // A new filter or view cross-fades in; typing in the
                      // search just narrows the list, without a flicker.
                      AnimatedSwitcher(
                        duration: Motion.of(context, Motion.dropdown),
                        switchInCurve: Motion.ease,
                        switchOutCurve: Motion.easeIn,
                        layoutBuilder: (current, previous) =>
                            Stack(alignment: Alignment.topCenter, children: [...previous, if (current != null) current]),
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                            position: Tween(begin: const Offset(0, 0.01), end: Offset.zero).animate(a),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey('$_filter-$_cards-${rows.isEmpty}'),
                          child: rows.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Center(
                                    child: Text(
                                      _search.isEmpty ? 'Nobody here.' : 'Nobody matches "$_search".',
                                      style: TextStyle(color: context.brand.muted),
                                    ),
                                  ),
                                )
                              // A table at every width (its columns step
                              // aside on a phone); cards when they ask.
                              : !_cards
                                  ? _MembersTable(
                                      rows: rows,
                                      today: today,
                                      onOpen: (m) => context.go(GymRoutes.memberFor(id, m.id)),
                                      venueId: id,
                                      gymName: access.venue.name,
                                      remind: _filter == _Filter.ending || _filter == _Filter.ended,
                                    )
                                  : ResponsiveGrid(
                                      minItemWidth: 360,
                                      maxColumns: 3,
                                      children: staggered([
                                        for (final r in rows)
                                          _MemberTile(
                                            member: r.member,
                                            subs: r.subs,
                                            pause: r.pause,
                                            today: today,
                                            onTap: () => context.go(GymRoutes.memberFor(id, r.member.id)),
                                          ),
                                      ], step: const Duration(milliseconds: 30)),
                                    ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Search, sort, (on a computer) table or cards, and exporting everyone.
  Widget _toolbar(BuildContext context, {required bool wide, required String gymName}) {
    final search = TextField(
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        hintText: 'Search by name, phone or member code',
        suffixIcon: _search.isEmpty ? null : const Icon(Icons.manage_search_rounded),
      ),
      onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
    );
    final sort = PopupMenuButton<_Sort>(
      tooltip: 'Sort',
      initialValue: _sort,
      onSelected: (s) => setState(() => _sort = s),
      itemBuilder: (_) => [for (final s in _Sort.values) CheckedPopupMenuItem(value: s, checked: s == _sort, child: Text(s.label))],
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: context.brand.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.brand.fieldBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, size: 20),
            const SizedBox(width: 8),
            Text(wide ? _sort.label : 'Sort', style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
    final view = SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: false, icon: Icon(Icons.table_rows_rounded), tooltip: 'Table'),
        ButtonSegment(value: true, icon: Icon(Icons.grid_view_rounded), tooltip: 'Cards'),
      ],
      selected: {_cards},
      onSelectionChanged: (v) => setState(() => _cards = v.first),
    );
    final today = BhutanTime.today();
    final export = ExportButton(
      compact: !wide,
      label: 'Export members',
      fileName: '$gymName members ${isoDate(today)}',
      load: () async =>
          membersSheet(await ref.read(gymRepositoryProvider).membersExport(widget.venueId), BhutanTime.today()),
    );
    return Row(
      children: [
        Expanded(child: search),
        const SizedBox(width: 10),
        sort,
        const SizedBox(width: 10),
        export,
        if (MediaQuery.sizeOf(context).width >= 1300) ...[const SizedBox(width: 10), view],
      ],
    );
  }

  bool _matches(GymMember m) {
    if (_search.isEmpty) return true;
    final digits = _search.replaceAll(RegExp(r'\D'), '');
    return m.fullName.toLowerCase().contains(_search) ||
        m.code.toLowerCase().contains(_search) ||
        (digits.isNotEmpty && m.phone.replaceAll(RegExp(r'\D'), '').contains(digits));
  }
}

typedef _MemberRow = ({GymMember member, List<GymSubscription> subs, GymPause? pause});

/// The register as a table: who (photo, name, code), phone, package, expiry
/// date and standing, 25 to a page; a row opens the member. The headers sort
/// it too (the toolbar's order otherwise). On a phone the member's cell
/// carries their package and standing.
class _MembersTable extends StatelessWidget {
  final List<_MemberRow> rows;
  final DateTime today;
  final ValueChanged<GymMember> onOpen;
  final String venueId;
  final String gymName;

  /// A renewal reminder on WhatsApp in each row (ending soon, or ended).
  final bool remind;

  const _MembersTable({
    required this.rows,
    required this.today,
    required this.onOpen,
    required this.venueId,
    required this.gymName,
    this.remind = false,
  });

  String _package(_MemberRow r) =>
      r.subs.firstWhere((s) => s.isCurrentOn(today), orElse: () => r.subs.isEmpty ? _none : r.subs.first).planName;

  /// Paid until, or when the last one ended; null with none.
  DateTime? _expiry(_MemberRow r) {
    final until = paidUntil(r.subs, today);
    if (until != null) return until;
    return r.subs.where((s) => s.endDate != null).map((s) => s.endDate!).fold<DateTime?>(
        null, (a, b) => a == null || b.isAfter(a) ? b : a);
  }

  Widget _standing(_MemberRow r) {
    final until = paidUntil(r.subs, today);
    return StandingChip(
      standing: standingOf(r.subs, today, pause: r.pause),
      daysLeft: until == null ? null : BhutanTime.daysBetween(today, until) + 1,
      pausedUntil: r.pause?.endDate,
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return DataGrid<_MemberRow>(
      rows: rows,
      noun: 'members',
      pageSizes: const [25, 50, 100],
      rowLabel: (r) => 'Open ${r.member.fullName}',
      onRowTap: (r) => onOpen(r.member),
      columns: [
        GridColumn(
          key: 'member',
          label: 'Member',
          flex: 4,
          sortBy: (r) => r.member.fullName.toLowerCase(),
          cell: (context, r) {
            final carry = [
              if (!DataGrid.shows(context, 'package') && _package(r) != '—') _package(r),
              if (!DataGrid.shows(context, 'phone')) r.member.phone,
            ];
            return Row(
              children: [
                MemberPhoto(path: r.member.photoPath, photoUrl: r.member.avatarUrl, name: r.member.fullName, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(r.member.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                      Text(r.member.code, style: TextStyle(color: brand.muted, fontSize: 12.5, letterSpacing: 1)),
                      if (carry.isNotEmpty)
                        Text(carry.join(' · '),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 13)),
                      if (!DataGrid.shows(context, 'status'))
                        Padding(padding: const EdgeInsets.only(top: 4), child: _standing(r)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        GridColumn(
          key: 'phone',
          label: 'Phone',
          flex: 2,
          showFrom: 900,
          sortBy: (r) => r.member.phone,
          cell: (context, r) => Text(r.member.phone, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.body)),
        ),
        GridColumn(
          key: 'package',
          label: 'Package',
          flex: 3,
          showFrom: 700,
          sortBy: (r) => _package(r).toLowerCase(),
          cell: (context, r) => Text(_package(r),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _package(r) == '—' ? brand.muted : brand.body)),
        ),
        GridColumn(
          key: 'expiry',
          label: 'Expiry date',
          flex: 2,
          showFrom: 1000,
          sortBy: (r) => _expiry(r) ?? DateTime(9999),
          cell: (context, r) {
            final d = _expiry(r);
            return Text(d == null ? '—' : formatDate(d),
                style: TextStyle(fontWeight: FontWeight.w600, color: d == null ? brand.muted : brand.ink));
          },
        ),
        GridColumn(
          key: 'status',
          label: 'Status',
          width: 150,
          showFrom: 520,
          // The soonest to run out first; then those with none.
          sortBy: (r) => paidUntil(r.subs, today) ?? DateTime(9999),
          cell: (context, r) => _standing(r),
        ),
        if (remind)
          GridColumn(
            key: 'remind',
            label: '',
            width: 48,
            alignEnd: true,
            cell: (context, r) {
              final last = latestPackage(r.subs);
              final end = paidUntil(r.subs, today) ?? last?.endDate;
              if (last == null || end == null) return const SizedBox.shrink();
              return WhatsAppFollowUpButton(
                venueId: venueId,
                gymMemberId: r.member.id,
                phone: r.member.phone,
                message: renewalMessage(name: r.member.fullName, gym: gymName, plan: last.planName, end: end, today: today),
                kind: MessageKind.renewal,
                compact: true,
              );
            },
          ),
        GridColumn.actions(cell: (context, r) => GridOpenButton(onPressed: () => onOpen(r.member))),
      ],
    );
  }

  static final _none = GymSubscription(
    id: '',
    venueId: '',
    memberId: '',
    planName: '—',
    durationDays: 1,
    price: 0,
    status: SubscriptionStatus.cancelled,
    requestedAt: DateTime(2000),
  );
}

class _MemberTile extends StatelessWidget {
  final GymMember member;
  final List<GymSubscription> subs;
  final GymPause? pause;
  final DateTime today;
  final VoidCallback onTap;

  const _MemberTile({required this.member, required this.subs, this.pause, required this.today, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final standing = standingOf(subs, today, pause: pause);
    final until = paidUntil(subs, today);
    return SectionCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          MemberPhoto(path: member.photoPath, photoUrl: member.avatarUrl, name: member.fullName, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.fullName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5), overflow: TextOverflow.ellipsis),
                Text('${member.code} · ${member.phone}', style: TextStyle(color: context.brand.muted)),
                const SizedBox(height: 2),
                Text(packageLine(subs, today), style: context.text.bodySmall, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StandingChip(
            standing: standing,
            daysLeft: until == null ? null : BhutanTime.daysBetween(today, until) + 1,
            pausedUntil: pause?.endDate,
          ),
        ],
      ),
    );
  }
}

// ─── Registering, and changing details ────────────────────────────────────

/// The front desk's registration form (the client's: name, phone, email,
/// dzongkhag and village, occupation, emergency contact, blood group, date of
/// joining, package and months, expiry, date of birth, medical issues), the
/// member's photo from the webcam, and the package sold. With [memberId], it
/// changes a registered member's details instead.
class RegisterMemberScreen extends ConsumerWidget {
  final String venueId;
  final String? memberId;

  /// Someone already on Health Pro: the QR code they showed at the desk...
  final String? personQr;

  /// ...or their request to join, which saving approves. Their details fill
  /// the form, from their last gym (or their account).
  final String? requestId;

  /// From an enquiry: their name and phone, to start the form with.
  final String? prefillName;
  final String? prefillPhone;

  const RegisterMemberScreen({
    super.key,
    required this.venueId,
    this.memberId,
    this.personQr,
    this.requestId,
    this.prefillName,
    this.prefillPhone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editing = memberId != null;
    final existing = !editing && (personQr != null || requestId != null);
    return GymStaffPage(
      venueId: venueId,
      title: editing ? 'Edit member' : 'Register member',
      permission: GymPermission.register,
      // Someone new, as a non-member who booked a class: Classes too (20261121000003).
      orPermission: editing || existing ? null : GymPermission.classes,
      builder: (context, access) {
        if (existing) {
          final query = (venueId: venueId, qrToken: personQr, requestId: requestId);
          return AsyncValueView<PersonDetails>(
            value: ref.watch(gymPersonDetailsProvider(query)),
            onRetry: () => ref.invalidate(gymPersonDetailsProvider(query)),
            data: (person) => person.gymMemberIdHere != null
                ? AppPage(
                    title: 'Register member',
                    body: EmptyState(
                      icon: Icons.how_to_reg_rounded,
                      title: '${person.name} is a member here already',
                      message: 'Open their page to renew their package.',
                      actionLabel: 'Open their page',
                      onAction: () => context.go(GymRoutes.memberFor(venueId, person.gymMemberIdHere!)),
                    ),
                  )
                : _MemberForm(venueId: venueId, access: access, person: person, personQr: personQr, requestId: requestId),
          );
        }
        if (!editing) return _MemberForm(venueId: venueId, access: access, prefillName: prefillName, prefillPhone: prefillPhone);
        return AsyncValueView<GymMember?>(
          value: ref.watch(gymMemberProvider(memberId!)),
          onRetry: () => ref.invalidate(gymMemberProvider(memberId!)),
          data: (m) => m == null
              ? const AppPage(title: 'Edit member', body: EmptyState(icon: Icons.person_off_outlined, title: 'This member is not registered here'))
              : _MemberForm(venueId: venueId, access: access, member: m),
        );
      },
    );
  }
}

class _MemberForm extends ConsumerStatefulWidget {
  final String venueId;
  final VenueAccess access;
  final GymMember? member;

  /// Someone already on Health Pro, being added here: their details so far,
  /// and how they came (their QR code, or their request to join).
  final PersonDetails? person;
  final String? personQr;
  final String? requestId;

  /// A new member's name and phone, from their enquiry.
  final String? prefillName;
  final String? prefillPhone;

  const _MemberForm({
    required this.venueId,
    required this.access,
    this.member,
    this.person,
    this.personQr,
    this.requestId,
    this.prefillName,
    this.prefillPhone,
  });

  @override
  ConsumerState<_MemberForm> createState() => _MemberFormState();
}

class _MemberFormState extends ConsumerState<_MemberForm> {
  final _form = GlobalKey<FormState>();

  /// Each section of the form, to scroll to it from the summary.
  final _sectionKeys = List.generate(5, (_) => GlobalKey());
  late final MemberDetails? _old = widget.member?.details ?? widget.person?.details;
  late final _name = TextEditingController(text: _old?.fullName ?? widget.prefillName ?? '');
  late final _phone = TextEditingController(text: _old?.phone ?? widget.prefillPhone ?? '');
  late final _email = TextEditingController(text: _old?.email ?? '');
  final _emailFocus = FocusNode();
  late final _occupation = TextEditingController(text: _old?.occupation ?? '');
  late final _contactName = TextEditingController(text: _old?.emergencyContactName ?? '');
  late final _contactPhone = TextEditingController(text: _old?.emergencyContactPhone ?? '');
  late final _medical = TextEditingController(text: _old?.medicalNotes ?? '');
  late DateTime? _dob = _old?.dateOfBirth;
  late DateTime _joined = _old?.joinedOn ?? BhutanTime.today();
  late String? _bloodGroup = _old?.bloodGroup;
  late LocationSelection _place = _old?.place ?? LocationSelection.empty;
  late bool _sell = widget.member == null && widget.access.can(GymPermission.payments);
  PackageSale? _sale;
  PickedPhoto? _photo;
  bool _saving = false;

  bool get _editing => widget.member != null;

  String? _activePhoneConflict(String? value, DateTime today, List<GymSubscription> subscriptions) {
    final phone = Validators.normalizePhone(value ?? '');
    if (phone == null) return null;
    final conflict = subscriptions
        .where((subscription) =>
            Validators.normalizePhone(subscription.memberPhone ?? '') == phone &&
            subscription.gymMemberId != widget.member?.id &&
            subscription.status == SubscriptionStatus.active &&
            subscription.endDate != null &&
            !subscription.endDate!.isBefore(today))
        .toList()
      ..sort((a, b) => b.endDate!.compareTo(a.endDate!));
    if (conflict.isEmpty) return null;
    return 'This number is already used by ${conflict.first.memberDisplayName} until ${formatDate(conflict.first.endDate!)}.';
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _occupation, _contactName, _contactPhone, _medical]) {
      c.dispose();
    }
    _emailFocus.dispose();
    super.dispose();
  }

  MemberDetails get _details => MemberDetails(
        fullName: _name.text,
        phone: _phone.text,
        email: _email.text,
        dateOfBirth: _dob,
        bloodGroup: _bloodGroup,
        occupation: _occupation.text,
        place: _place,
        emergencyContactName: _contactName.text,
        emergencyContactPhone: _contactPhone.text,
        medicalNotes: _medical.text,
        joinedOn: _joined,
      );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_sell && _sale == null) return;
    setState(() => _saving = true);
    final repo = ref.read(gymRepositoryProvider);
    String? id;
    String? photoProblem;
    final ok = await runAction(context, () async {
      if (_editing) {
        await repo.updateMember(widget.member!.id, _details);
        id = widget.member!.id;
      } else {
        id = await repo.registerMember(widget.venueId, _details,
            sale: _sell ? _sale : null, personQr: widget.personQr, joinRequestId: widget.requestId);
      }
      if (_photo != null) {
        try {
          await repo.setMemberPhoto(
            venueId: widget.venueId,
            memberId: id!,
            bytes: _photo!.bytes,
            contentType: _photo!.contentType,
            oldPath: widget.member?.photoPath,
          );
        } catch (_) {
          photoProblem = "Saved, but the photo didn't upload. Add it again with Edit details.";
        }
      }
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok || id == null) return;
    refreshGym(ref, widget.venueId);
    ref.invalidate(gymMemberProvider(id!));
    if (photoProblem != null || _editing) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(photoProblem ?? 'Saved')));
    }
    // Registered from Classes by a role that doesn't see the members: back to Classes.
    if (!_editing && !widget.access.can(GymPermission.members)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_name.text.trim()} is registered as a member')));
      context.go(GymRoutes.classesFor(widget.venueId));
      return;
    }
    // A new member: the page that says so, with their QR card to send.
    context.go(_editing ? GymRoutes.memberFor(widget.venueId, id!) : GymRoutes.memberRegisteredFor(widget.venueId, id!));
  }

  @override
  Widget build(BuildContext context) {
    final today = BhutanTime.today();
    final subscriptions = ref.watch(gymSubscriptionsProvider(widget.venueId)).valueOrNull ?? const <GymSubscription>[];
    final canSell = widget.access.can(GymPermission.payments);
    Widget fields(List<Widget> children) =>
        ResponsiveGrid(minItemWidth: 260, maxColumns: 3, spacing: 14, runSpacing: 14, equalHeight: false, children: children);

    void changed(_) => setState(() {});
    final personal = fields([
      TextFormField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Full name *', prefixIcon: Icon(Icons.badge_outlined)),
        validator: (v) => (v ?? '').trim().length < 2 ? 'Enter their name' : null,
        onChanged: changed,
      ),
      TextFormField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        onFieldSubmitted: (_) => _emailFocus.requestFocus(),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: const InputDecoration(labelText: 'Phone *', hintText: '17123456', prefixIcon: Icon(Icons.call_outlined)),
        validator: (v) => Validators.phone(v, required: true) ?? _activePhoneConflict(v, today, subscriptions),
        onChanged: changed,
      ),
      TextFormField(
        controller: _email,
        focusNode: _emailFocus,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
        validator: (v) => (v ?? '').trim().isEmpty ? null : Validators.email(v),
        onChanged: changed,
      ),
      DateField(
        label: 'Date of birth',
        value: _dob,
        clearable: true,
        firstDate: DateTime(1920),
        lastDate: today,
        onChanged: (d) => setState(() => _dob = d),
      ),
      SearchableDropdown<String?>(
        value: _bloodGroup,
        decoration: const InputDecoration(labelText: 'Blood group', prefixIcon: Icon(Icons.bloodtype_outlined)),
        options: [
          const DropdownOption<String?>(null, 'Not known'),
          for (final g in bloodGroups) DropdownOption<String?>(g, g),
        ],
        onChanged: (g) => setState(() => _bloodGroup = g),
      ),
      TextFormField(
        controller: _occupation,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Occupation', prefixIcon: Icon(Icons.work_outline_rounded)),
        onChanged: changed,
      ),
      DateField(
        label: 'Date of joining',
        value: _joined,
        required: true,
        firstDate: today.subtract(const Duration(days: 3650)),
        lastDate: today.add(const Duration(days: 60)),
        onChanged: (d) => setState(() => _joined = d ?? today),
      ),
    ]);

    final address = LocationFields(value: _place, inRow: true, onChanged: (v) => setState(() => _place = v));

    final emergencyAndHealth = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        fields([
          TextFormField(
            controller: _contactName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Emergency contact name', prefixIcon: Icon(Icons.contact_emergency_outlined)),
            onChanged: changed,
          ),
          TextFormField(
            controller: _contactPhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Emergency contact number', prefixIcon: Icon(Icons.phone_in_talk_outlined)),
            validator: Validators.phone,
            onChanged: changed,
          ),
        ]),
        const SizedBox(height: 14),
        TextFormField(
          controller: _medical,
          minLines: 2,
          maxLines: 5,
          maxLength: 1000,
          onChanged: changed,
          decoration: const InputDecoration(
            labelText: 'Any medical issues',
            hintText: 'Asthma, a heart condition, injuries... Trainers and the desk see this.',
            prefixIcon: Icon(Icons.medical_information_outlined),
          ),
        ),
      ],
    );

    final package = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sell a package now', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(canSell
              ? 'From the date of joining. Leave it off to register them first.'
              : "Your role can't take payments: someone who can adds their package from their page."),
          value: _sell,
          onChanged: canSell ? (v) => setState(() => _sell = v) : null,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _sell
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: PackageFields(
                    venueId: widget.venueId,
                    start: _joined,
                    initialPlanId: widget.person?.planId,
                    onChanged: (s) => setState(() => _sale = s),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );

    final photo = Column(
      children: [
        MemberPhotoField(
          picked: _photo,
          currentPath: widget.member?.photoPath,
          name: _name.text,
          onChanged: (p) => setState(() => _photo = p),
        ),
        const SizedBox(height: 10),
        const FormHint('The desk sees it when they check in, so they know it is them.'),
      ],
    );

    // Where the form stands: what's done in each section, and how far along.
    final hasPhoto = _photo != null || widget.member?.photoPath != null;
    final named = _name.text.trim().length >= 2;
    final phoned = Validators.phone(_phone.text, required: true) == null;
    final done = [
      hasPhoto,
      named && phoned,
      _place.dzongkhagId != null,
      _contactName.text.trim().isNotEmpty || _contactPhone.text.trim().isNotEmpty,
      !_sell || _sale != null,
    ];
    final filled = [
      hasPhoto, named, phoned, _email.text.trim().isNotEmpty, _dob != null, _bloodGroup != null,
      _occupation.text.trim().isNotEmpty, _place.dzongkhagId != null, _contactName.text.trim().isNotEmpty,
      _contactPhone.text.trim().isNotEmpty, _medical.text.trim().isNotEmpty, if (_sell) _sale != null,
    ];
    final progress = filled.where((f) => f).length / filled.length;
    final ready = named && phoned && (!_sell || _sale != null);

    final sections = [
      (Icons.photo_camera_outlined, 'Photo', 'Snap it with the webcam, or upload one', photo),
      (Icons.person_outline_rounded, 'Personal details', 'Who they are and how to reach them', personal),
      (Icons.place_outlined, 'Address', 'Dzongkhag, gewog and village', address),
      (Icons.health_and_safety_outlined, 'Emergency contact & health', 'Who to call, and what the desk should know', emergencyAndHealth),
      if (!_editing) (Icons.sell_outlined, 'Package', 'What they signed up for; the expiry date is worked out', package),
    ];

    final cancel = TextButton(
      onPressed: _saving
          ? null
          : () => context.go(_editing
              ? GymRoutes.memberFor(widget.venueId, widget.member!.id)
              : widget.access.can(GymPermission.members)
                  ? GymRoutes.membersFor(widget.venueId)
                  : GymRoutes.classesFor(widget.venueId)),
      child: const Text('Cancel'),
    );
    final submit = FilledButton.icon(
      onPressed: _saving ? null : _save,
      icon: _saving
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(_editing ? Icons.save_outlined : Icons.how_to_reg_rounded),
      label: Text(_editing ? 'Save changes' : 'Register member', overflow: TextOverflow.ellipsis),
    );

    final wide = MediaQuery.sizeOf(context).width >= 1280;
    // Every section is built up front (not lazily), so Tab can reach each
    // field, the summary can scroll to any section, and Save checks them all.
    final form = SingleChildScrollView(
      padding: pagePadding(context, bottom: wide ? 40 : 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.person != null) _AddingPerson(person: widget.person!, fromRequest: widget.requestId != null),
          for (final (i, (icon, title, subtitle, child)) in sections.indexed)
            FadeSlideIn(
              key: _sectionKeys[i],
              delay: Duration(milliseconds: 50 * i),
              child: _FormSection(number: i + 1, icon: icon, title: title, subtitle: subtitle, done: done[i], child: child),
            ),
          if (wide)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [cancel, const SizedBox(width: 8), SizedBox(width: 220, child: submit)],
              ),
            ),
        ],
      ),
    );

    return AppPage(
      title: _editing
          ? 'Edit ${widget.member!.fullName}'
          : widget.person != null
              ? 'Add ${widget.person!.name}'
              : 'Register a member',
      bottomBar: wide
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ready ? 'Ready to save' : 'Name and phone are needed${_sell ? ', and the package' : ''}',
                      maxLines: 2,
                      style: TextStyle(color: ready ? context.brand.success : context.brand.muted, fontWeight: FontWeight.w600),
                    ),
                  ),
                  cancel,
                  const SizedBox(width: 8),
                  Flexible(child: submit),
                ],
              ),
            ),
      body: Form(
        key: _form,
        // The form and the summary are separate Tab groups: Tab goes through
        // every field (then Cancel and Register) before the summary's links.
        // Otherwise Tab follows screen position and jumps from a field into
        // the summary link beside it.
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: FocusTraversalGroup(child: form)),
                  SizedBox(
                    width: 360,
                    child: FocusTraversalGroup(
                      child: SingleChildScrollView(
                        padding: pagePadding(context, horizontal: 0).copyWith(right: 28),
                        child: _RegisterSummary(
                          name: _name.text,
                          phone: _phone.text,
                          photoPath: widget.member?.photoPath,
                          photo: _photo?.bytes,
                          joined: _joined,
                          sale: _sell ? _sale : null,
                          selling: _sell,
                          progress: progress,
                          sections: [for (final (i, s) in sections.indexed) (title: s.$2, done: done[i])],
                          onSection: (i) => Scrollable.ensureVisible(
                            _sectionKeys[i].currentContext!,
                            duration: const Duration(milliseconds: 420),
                            curve: Curves.easeOutCubic,
                            alignment: 0.05,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : form,
      ),
    );
  }
}

/// Over the form when adding someone already on Health Pro: who, that their
/// details came from before, and what they asked for.
class _AddingPerson extends StatelessWidget {
  final PersonDetails person;
  final bool fromRequest;

  const _AddingPerson({required this.person, required this.fromRequest});

  @override
  Widget build(BuildContext context) {
    const color = BrandColors.blue;
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.verified_user_outlined, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fromRequest ? '${person.name} asked to join' : '${person.name} is on Health Pro',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Their details are filled in from before: check them with them, take their photo and choose '
                    'their package. Their Health Pro QR code works here once you save.',
                    style: TextStyle(color: brand.body, height: 1.4),
                  ),
                  if (person.message != null) ...[
                    const SizedBox(height: 8),
                    Text('"${person.message}"', style: TextStyle(color: brand.body, fontStyle: FontStyle.italic)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A numbered part of the registration form: its number (a tick once it's
/// done), title, what it's for, and its fields on a card.
class _FormSection extends StatelessWidget {
  final int number;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool done;
  final Widget child;

  const _FormSection({
    required this.number,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final success = context.brand.success;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: SectionCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? success : context.brand.highlight.withValues(alpha: 0.12),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: done
                        ? const Icon(Icons.check_rounded, key: ValueKey('done'), color: Colors.white, size: 20)
                        : Text('$number',
                            key: const ValueKey('n'),
                            style: TextStyle(color: context.brand.highlight, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.text.titleMedium),
                      Text(subtitle, style: TextStyle(color: context.brand.muted, fontSize: 13)),
                    ],
                  ),
                ),
                Icon(icon, color: context.brand.muted),
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

/// Beside the form on a computer: the member as they'll be registered (photo,
/// name, package, expiry date, amount), how complete the form is, and a way to
/// each section.
class _RegisterSummary extends StatelessWidget {
  final String name;
  final String phone;
  final String? photoPath;
  final Uint8List? photo;
  final DateTime joined;
  final PackageSale? sale;
  final bool selling;
  final double progress;
  final List<({String title, bool done})> sections;
  final ValueChanged<int> onSection;

  const _RegisterSummary({
    required this.name,
    required this.phone,
    required this.photoPath,
    required this.photo,
    required this.joined,
    required this.sale,
    required this.selling,
    required this.progress,
    required this.sections,
    required this.onSection,
  });

  @override
  Widget build(BuildContext context) {
    final muted = context.brand.muted;
    final sale = this.sale;
    Widget fact(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(color: muted))),
              Flexible(
                child: Text(value,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, color: color)),
              ),
            ],
          ),
        );
    return SectionCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Summary', style: context.text.titleMedium),
          const SizedBox(height: 14),
          Row(
            children: [
              MemberPhoto(path: photoPath, name: name, bytes: photo, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.trim().isEmpty ? 'New member' : name.trim(),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(phone.trim().isEmpty ? 'No phone yet' : phone.trim(), style: TextStyle(color: muted)),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          fact('Joining', formatDate(joined)),
          if (!selling)
            fact('Package', 'Not now')
          else if (sale == null)
            fact('Package', 'Choose one', color: context.brand.readable(context.brand.warning))
          else ...[
            fact('Package', '${sale.plan.name} · ${sale.months == 1 ? '1 month' : '${sale.months} months'}'),
            fact('Expiry date', formatDate(packageEnd(joined, sale.months)), color: context.brand.readable(context.brand.success)),
            fact('Amount', sale.amount == 0 ? 'Free' : '${formatNu(sale.amount)}${sale.method == null ? '' : ' · ${sale.method!.label}'}'),
          ],
          const Divider(height: 28),
          Row(
            children: [
              Expanded(child: Text('Form complete', style: TextStyle(color: muted))),
              Text('${(progress * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                color: context.brand.highlight,
                backgroundColor: context.brand.highlight.withValues(alpha: 0.12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final (i, s) in sections.indexed)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onSection(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                child: Row(
                  children: [
                    Icon(s.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 18, color: s.done ? context.brand.success : muted),
                    const SizedBox(width: 10),
                    Expanded(child: Text(s.title)),
                    Icon(Icons.arrow_forward_rounded, size: 16, color: muted),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── One member ──────────────────────────────────────────────────────────

/// A registered member: who they are, their package (and renewing it), their
/// QR card to send on WhatsApp, their details, memberships and visits.
class GymMemberScreen extends ConsumerWidget {
  final String venueId;
  final String memberId;

  const GymMemberScreen({super.key, required this.venueId, required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GymStaffPage(
      venueId: venueId,
      title: 'Member',
      permission: GymPermission.members,
      builder: (context, access) => AsyncValueView<GymMember?>(
        value: ref.watch(gymMemberProvider(memberId)),
        onRetry: () => ref.invalidate(gymMemberProvider(memberId)),
        data: (m) => m == null || m.venueId != venueId
            ? const AppPage(title: 'Member', body: EmptyState(icon: Icons.person_off_outlined, title: 'This member is not registered here'))
            : _MemberPage(member: m, access: access),
      ),
    );
  }
}

class _MemberPage extends ConsumerStatefulWidget {
  final GymMember member;
  final VenueAccess access;

  const _MemberPage({required this.member, required this.access});

  @override
  ConsumerState<_MemberPage> createState() => _MemberPageState();
}

class _MemberPageState extends ConsumerState<_MemberPage> {
  GymMember get m => widget.member;
  String get _venueId => widget.access.venue.id;

  @override
  Widget build(BuildContext context) {
    final today = BhutanTime.today();
    final all = ref.watch(gymSubscriptionsProvider(_venueId)).valueOrNull ?? const <GymSubscription>[];
    final subs = membershipsOf(all, m.id);
    final pauses = ref.watch(gymMemberPausesProvider(m.id)).valueOrNull ?? const <GymPause>[];
    final pause = openPauseOf(pauses, m.id, today);
    final standing = standingOf(subs, today, pause: pause);
    final until = paidUntil(subs, today);
    final visits = ref.watch(gymMemberCheckInsProvider(m.id)).valueOrNull ?? const <GymCheckIn>[];
    final a = widget.access;
    // A package runs today or later, and nothing's paused or planned.
    final canPause = a.can(GymPermission.payments) && pause == null && until != null;
    // Off the register; a membership still paid for also needs payments.
    final canDelete = a.can(GymPermission.register) && (until == null || a.can(GymPermission.payments));

    final header = SectionCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MemberPhoto(path: m.photoPath, photoUrl: m.avatarUrl, name: m.fullName, size: 96),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.fullName, style: context.text.headlineSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    StatusChip(label: 'Member code ${m.code}', color: context.colors.tertiary),
                    StandingChip(
                      standing: standing,
                      daysLeft: until == null ? null : BhutanTime.daysBetween(today, until) + 1,
                      pausedUntil: pause?.endDate,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => callPhone(context, m.phone),
                      icon: const Icon(Icons.call_outlined),
                      label: Text(m.phone),
                    ),
                    _whatsApp(today, subs, standing, until),
                    if (a.can(GymPermission.register))
                      OutlinedButton.icon(
                        onPressed: () => context.go(GymRoutes.editMemberFor(_venueId, m.id)),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit details'),
                      ),
                    if (canDelete)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: context.brand.danger),
                        onPressed: () => _delete(context, until),
                        icon: const Icon(Icons.person_remove_outlined),
                        label: const Text('Delete member'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final package = SectionCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 200),
                child: Text(packageLine(subs, today), style: context.text.titleMedium),
              ),
              if (canPause)
                OutlinedButton.icon(
                  onPressed: () => _pause(context),
                  icon: const Icon(Icons.pause_circle_outline_rounded),
                  label: const Text('Pause'),
                ),
              if (a.can(GymPermission.payments))
                FilledButton.icon(
                  onPressed: () => _renew(context),
                  icon: const Icon(Icons.autorenew_rounded),
                  label: Text(standing == MemberStanding.none ? 'Sell a package' : 'Renew'),
                ),
            ],
          ),
          MemberPauses(
            venueId: _venueId,
            gymMemberId: m.id,
            memberName: m.fullName,
            canChange: a.can(GymPermission.payments),
          ),
          if (subs.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final s in subs.take(6))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${s.planName} · ${s.price == 0 ? 'Free' : formatNu(s.price)}'),
                subtitle: Text(s.startDate == null ? 'Not started' : '${formatDate(s.startDate!)} to ${formatDate(s.endDate!)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SubscriptionStatusChip(subscription: s),
                    if (s.paymentId != null) ReceiptButton(paymentId: s.paymentId!),
                  ],
                ),
              ),
          ],
        ],
      ),
    );

    final details = MemberDetailsCard(member: m);
    final medical = m.medicalNotes == null ? null : MedicalNotice(m.medicalNotes!);

    final card = MemberCardPanel(
      gymName: widget.access.venue.name,
      member: m,
      until: until,
      noPackage: packageLine(subs, today),
      canReissue: a.can(GymPermission.register),
    );

    return AppPage(
      title: m.fullName,
      body: RefreshIndicator(
        onRefresh: () async {
          refreshGym(ref, _venueId);
          ref.invalidate(gymMemberProvider(m.id));
          ref.invalidate(gymMemberCheckInsProvider(m.id));
        },
        child: ListView(
          padding: pagePadding(context),
          children: [
            ResponsiveColumns(
              breakpoint: 1000,
              flex: (3, 2),
              first: [
                header,
                if (medical != null) ...[const SizedBox(height: 12), medical],
                MemberPaymentsWaiting(gymMemberId: m.id, canConfirm: a.can(GymPermission.payments)),
                const SizedBox(height: 12),
                MemberTrainerPicker(venueId: _venueId, gymMemberId: m.id, canChange: a.can(GymPermission.checkIn)),
                const SectionTitle('Package'),
                package,
                const SectionTitle('Details'),
                details,
                const SectionTitle('Progress'),
                MemberProgress(gymMemberId: m.id, coach: true),
                const SectionTitle('Workout & diet plans'),
                MemberPlans(gymMemberId: m.id, venueId: _venueId, coach: true),
                SectionTitle('Visits', trailing: Text('${visits.length} recorded', style: TextStyle(color: context.brand.muted))),
                if (visits.isEmpty)
                  const FormHint('No visits yet.')
                else
                  SectionCard(
                    padding: const EdgeInsets.all(14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final v in visits.take(30))
                          Chip(
                            avatar: const Icon(Icons.login_rounded, size: 16),
                            label: Text('${formatShortDate(BhutanTime.toBhutan(v.checkedInAt))} ${formatTime(v.checkedInAt)}'),
                          ),
                      ],
                    ),
                  ),
                if (a.can(GymPermission.activity)) ...[
                  const SectionTitle('History'),
                  MemberActivity(venueId: _venueId, gymMemberId: m.id),
                ],
              ],
              second: [const SectionTitle('Member card'), card],
            ),
          ],
        ),
      ),
    );
  }

  /// WhatsApp: a birthday wish on their birthday; a renewal reminder when
  /// their package ends within 7 days or has ended; a plain chat otherwise.
  Widget _whatsApp(DateTime today, List<GymSubscription> subs, MemberStanding standing, DateTime? until) {
    final gym = widget.access.venue.name;
    final dob = m.dateOfBirth;
    if (dob != null && birthdayIn(dob, today.year) == today) {
      return WhatsAppFollowUpButton(
        venueId: _venueId,
        gymMemberId: m.id,
        phone: m.phone,
        message: birthdayMessage(name: m.fullName, gym: gym),
        kind: MessageKind.birthday,
      );
    }
    final last = latestPackage(subs);
    final end = until ?? last?.endDate;
    final due = last != null &&
        end != null &&
        (standing == MemberStanding.ended || (standing == MemberStanding.active && BhutanTime.daysBetween(today, end) < 7));
    if (due) {
      return WhatsAppFollowUpButton(
        venueId: _venueId,
        gymMemberId: m.id,
        phone: m.phone,
        message: renewalMessage(name: m.fullName, gym: gym, plan: last.planName, end: end, today: today),
        kind: MessageKind.renewal,
      );
    }
    return OutlinedButton.icon(
      onPressed: () => openWhatsApp(context, m.phone),
      icon: const Icon(Icons.chat_outlined),
      label: const Text('WhatsApp'),
    );
  }

  Future<void> _renew(BuildContext context) async {
    final subs = membershipsOf(ref.read(gymSubscriptionsProvider(_venueId)).valueOrNull ?? const [], m.id);
    final start = renewalStart(subs, BhutanTime.today());
    // The new payment, or '' for a package given free.
    final paid = await showAppDialog<String>(
      context: context,
      builder: (_) => _RenewDialog(member: m, venueId: _venueId, start: start),
    );
    if (paid == null) return;
    refreshGym(ref, _venueId);
    // Its receipt, to print or send while they're at the desk.
    if (paid.isNotEmpty && context.mounted) await showReceipt(context, paid);
  }

  Future<void> _pause(BuildContext context) async {
    final subs = membershipsOf(ref.read(gymSubscriptionsProvider(_venueId)).valueOrNull ?? const [], m.id);
    final done = await showPauseDialog(context, member: m, subscriptions: subs);
    if (done == true) refreshGym(ref, _venueId);
  }

  /// Off the register, after a warning when [activeUntil] says they've paid.
  Future<void> _delete(BuildContext context, DateTime? activeUntil) async {
    final done = await showDeleteMemberDialog(context, member: m, gymName: widget.access.venue.name, activeUntil: activeUntil);
    if (done != true || !context.mounted) return;
    context.go(GymRoutes.membersFor(_venueId));
    refreshGym(ref, _venueId);
    ref.invalidate(gymMemberProvider(m.id));
  }
}

class _RenewDialog extends ConsumerStatefulWidget {
  final GymMember member;
  final String venueId;
  final DateTime start;

  const _RenewDialog({required this.member, required this.venueId, required this.start});

  @override
  ConsumerState<_RenewDialog> createState() => _RenewDialogState();
}

class _RenewDialogState extends ConsumerState<_RenewDialog> {
  final _form = GlobalKey<FormState>();
  PackageSale? _sale;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final today = BhutanTime.today();
    return AlertDialog(
      title: Text('Package for ${widget.member.fullName}'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InfoRow(
                  icon: Icons.event_available_rounded,
                  text: widget.start == today
                      ? 'Starts today'
                      : 'Starts ${formatDate(widget.start)}, the day their current package expires',
                ),
                const SizedBox(height: 12),
                PackageFields(venueId: widget.venueId, start: widget.start, onChanged: (s) => _sale = s),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  if (!_form.currentState!.validate() || _sale == null) return;
                  setState(() => _saving = true);
                  String? paymentId;
                  final ok = await runAction(
                    context,
                    () async => paymentId = await ref.read(gymRepositoryProvider).renewMember(widget.member.id, _sale!),
                    success: 'Package added',
                  );
                  if (!context.mounted) return;
                  setState(() => _saving = false);
                  if (ok) Navigator.pop(context, paymentId ?? '');
                },
          child: const Text('Save package'),
        ),
      ],
    );
  }
}
