import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/classes.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import '../widgets/class_widgets.dart';
import '../widgets/gym_widgets.dart';

/// Group classes, for the desk: who's booked into each class on a day (the
/// last two weeks and the next two), members of the gym and non-members on Health Pro, booking
/// members in and taking anyone out; how many have registered to date; and
/// the weekly timetable. Every role given Classes (GymPermission.classes:
/// front desk, trainer, manager...) adds and changes classes too.
class ClassesScreen extends ConsumerStatefulWidget {
  final String venueId;

  /// The class to open (a link's `?open=`).
  final String? openId;

  const ClassesScreen({super.key, required this.venueId, this.openId});

  @override
  ConsumerState<ClassesScreen> createState() => _ClassesScreenState();
}

/// The page's three views.
enum _View { bookings, registered, timetable }

class _ClassesScreenState extends ConsumerState<ClassesScreen> {
  /// The day picked; null for the first day with a class from today on.
  DateTime? _picked;
  _View _view = _View.bookings;

  /// The days' row, scrolled once so the latest past day comes first.
  final _days = ScrollController();
  final _lastPast = GlobalKey();
  bool _scrolledToNow = false;

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  void _scrollToNow() {
    if (_scrolledToNow) return;
    _scrolledToNow = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chip = _lastPast.currentContext?.findRenderObject();
      if (chip == null || !_days.hasClients) return;
      final to = RenderAbstractViewport.of(chip).getOffsetToReveal(chip, 0).offset;
      _days.jumpTo(to.clamp(0, _days.position.maxScrollExtent));
    });
  }

  Future<void> _edit([GymClass? c]) async {
    final saved = await showAppDialog<bool>(context: context, builder: (_) => _ClassDialog(venueId: widget.venueId, gymClass: c));
    if (saved == true) {
      ref.invalidate(gymClassesProvider(widget.venueId));
      ref.invalidate(gymClassBookingsProvider);
      ref.invalidate(gymClassPlacesProvider(widget.venueId));
      ref.invalidate(gymClassRegistrationsProvider(widget.venueId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.venueId;
    return GymStaffPage(
      venueId: id,
      title: 'Classes',
      permission: GymPermission.classes,
      builder: (context, access) {
        // Classes covers the whole page: the timetable, booking members in and
        // registering non-members (20261121000002, 20261121000003).
        final canEdit = access.can(GymPermission.classes);
        final canRegister = access.can(GymPermission.register) || access.can(GymPermission.classes);
        final canBook = access.can(GymPermission.members) || access.can(GymPermission.classes);
        return OpenFromLink<GymClass>(
          id: widget.openId,
          items: ref.watch(gymClassesProvider(id)).valueOrNull,
          idOf: (c) => c.id,
          open: (c) => _openClass(c, canEdit: canEdit, canRegister: canRegister, canBook: canBook),
          child: AppPage(
          title: 'Classes',
          body: AsyncValueView<List<GymClass>>(
            value: ref.watch(gymClassesProvider(id)),
            onRetry: () => ref.invalidate(gymClassesProvider(id)),
            data: (classes) {
              final today = BhutanTime.today();
              final active = classes.where((c) => c.isActive).toList();
              final places = ref.watch(gymClassPlacesProvider(id)).valueOrNull ?? const <ClassPlaces>[];
              int bookedOn(DateTime d) => places.where((p) => p.date == d).fold(0, (n, p) => n + p.booked);
              bool bookedIn(GymClass c, DateTime d) => places.any((p) => p.classId == c.id && p.date == d && p.booked > 0);
              // The last two weeks' days and the next two's that have a class (or had
              // bookings, in a class since moved or taken off); the first from today is open to start with.
              final classDays = [
                for (var i = -14; i < 14; i++) DateTime(today.year, today.month, today.day + i),
              ].where((d) => active.any((c) => c.weekday == d.weekday) || bookedOn(d) > 0).toList();
              final lastPast = classDays.lastWhere((d) => d.isBefore(today), orElse: () => today);
              if (_view == _View.bookings && classDays.isNotEmpty) _scrollToNow();
              final day = classDays.contains(_picked)
                  ? _picked!
                  : (classDays.where((d) => !d.isBefore(today)).firstOrNull ?? classDays.lastOrNull ?? today);
              // The day's dates changed or cancelled on their own; each class in order of when it runs that day.
              final changes = (ref.watch(gymClassDaysProvider(id)).valueOrNull ?? const <ClassDay>[]).where((x) => x.date == day).toList();
              int startsOn(GymClass c) {
                final on = c.onDay(changes.where((x) => x.classId == c.id).firstOrNull);
                return on.hour * 60 + on.minute;
              }
              final onDay = classes.where((c) => (c.isActive && c.weekday == day.weekday) || bookedIn(c, day)).toList()
                ..sort((a, b) => startsOn(a).compareTo(startsOn(b)));
              final bookings = ref.watch(gymClassBookingsProvider((venueId: id, date: day))).valueOrNull ?? const <ClassBooking>[];
              // Each view's count: places booked to come, people to date, classes a week.
              final toCome = places.where((p) => !p.date.isBefore(today)).fold(0, (n, p) => n + p.booked);
              final people = ref.watch(gymClassRegistrationsProvider(id)).valueOrNull?.people;
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(gymClassesProvider(id));
                  ref.invalidate(gymClassBookingsProvider);
                  ref.invalidate(gymClassPlacesProvider(id));
                  ref.invalidate(gymClassDaysProvider(id));
                  ref.invalidate(gymClassRegistrationsProvider(id));
                },
                child: ListView(
                  padding: pagePadding(context, bottom: 40),
                  children: [
                    PageActions(
                      text: active.isEmpty
                          ? 'Set up your weekly classes. Members, and anyone with a Health Pro account, book them in the app.'
                          : '${active.length} ${active.length == 1 ? 'class' : 'classes'} a week. Members, and anyone with a '
                              'Health Pro account, book them in the app.',
                      children: [
                        if (canEdit)
                          FilledButton.icon(
                            onPressed: _edit,
                            style: FilledButton.styleFrom(minimumSize: PageActions.buttonSize),
                            icon: const Icon(Icons.add_rounded, size: 20),
                            label: const Text('New class'),
                          ),
                      ],
                    ),
                    if (classes.isEmpty)
                      EmptyState(
                        icon: Icons.event_note_outlined,
                        title: 'No classes yet',
                        message: canEdit
                            ? 'Add the gym\'s classes (yoga, zumba...): the day, time, length and how many places. Members book them on My gym, '
                                'and anyone on Health Pro on your public page.'
                            : 'The gym\'s staff add its classes here.',
                        actionLabel: canEdit ? 'Add a class' : null,
                        onAction: canEdit ? _edit : null,
                      )
                    else ...[
                      ViewTabs<_View>(
                        selected: _view,
                        onChanged: (v) => setState(() => _view = v),
                        tabs: [
                          ViewTab(value: _View.bookings, label: 'Bookings', icon: Icons.event_available_rounded, count: toCome),
                          ViewTab(value: _View.registered, label: 'Registered', icon: Icons.groups_rounded, count: people),
                          ViewTab(value: _View.timetable, label: 'Timetable', icon: Icons.calendar_view_week_rounded, count: active.length),
                        ],
                      ),
                      const SizedBox(height: 18),
                      ...switch (_view) {
                        _View.bookings => [
                            if (classDays.isEmpty)
                              SectionCard(
                                padding: const EdgeInsets.all(16),
                                child: Text('No classes on the timetable in the last two weeks or the next two.',
                                    style: TextStyle(color: context.brand.muted)),
                              )
                            else ...[
                              SizedBox(
                                height: 40,
                                child: ListView(
                                  controller: _days,
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    for (final d in classDays)
                                      Padding(
                                        key: d == lastPast ? _lastPast : null,
                                        padding: const EdgeInsets.only(right: 8),
                                        child: ChoiceChip(
                                          label: Text(bookedOn(d) == 0
                                              ? classDayLabel(d, today)
                                              : '${classDayLabel(d, today)} · ${bookedOn(d)} booked'),
                                          selected: d == day,
                                          onSelected: (_) => setState(() => _picked = d),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              _SessionsTable(
                                venueId: id,
                                day: day,
                                classes: onDay,
                                changes: changes,
                                bookings: bookings,
                                canRegister: canRegister,
                                canBook: canBook,
                                canEdit: canEdit,
                              ),
                            ],
                          ],
                        _View.registered => [_RegisteredToDate(venueId: id, canRegister: canRegister)],
                        _View.timetable => [
                            _TimetableTable(classes: classes, onEdit: canEdit ? _edit : null),
                            if (!canEdit)
                              Padding(
                                padding: const EdgeInsets.only(top: 10, left: 2),
                                child: Text('The gym\'s staff with Classes change the timetable.',
                                    style: TextStyle(color: context.brand.muted, fontSize: 12.5)),
                              ),
                          ],
                      },
                    ],
                  ],
                ),
              );
            },
          ),
          ),
        );
      },
    );
  }

  /// A class a link asks for: its next session, who's booked, on Bookings;
  /// one off the timetable on Timetable, to change for who can.
  void _openClass(GymClass c, {required bool canEdit, required bool canRegister, required bool canBook}) {
    if (!c.isActive) {
      setState(() => _view = _View.timetable);
      if (canEdit) _edit(c);
      return;
    }
    final today = BhutanTime.today();
    final day = DateTime(today.year, today.month, today.day + (c.weekday - today.weekday + 7) % 7);
    setState(() {
      _view = _View.bookings;
      _picked = day;
    });
    _openSession(context, c, venueId: widget.venueId, day: day, canRegister: canRegister, canBook: canBook, canEdit: canEdit);
  }
}

/// Shows class [c] (as the timetable has it) on [day], as it runs that day:
/// who's booked (each can be taken out, and a non-member registered), and
/// books a member in; for who keeps the timetable, changes or cancels that
/// date only.
void _openSession(BuildContext context, GymClass c,
        {required String venueId,
        required DateTime day,
        List<ClassBooking> bookings = const [],
        bool canRegister = false,
        bool canBook = false,
        bool canEdit = false}) =>
    showRowDetails(
      context,
      title: 'Class',
      // Watched, so a booking made or taken out, or the date changed, shows straight away.
      builder: (context) => Consumer(builder: (context, ref, _) {
        final now = ref.watch(gymClassBookingsProvider((venueId: venueId, date: day))).valueOrNull ?? bookings;
        final change = (ref.watch(gymClassDaysProvider(venueId)).valueOrNull ?? const <ClassDay>[])
            .where((x) => x.classId == c.id && x.date == day)
            .firstOrNull;
        final mine = now.where((b) => b.classId == c.id).toList();
        return _SessionCard(
          venueId: venueId,
          weekly: c,
          session: ClassSession(gymClass: c.onDay(change), date: day, booked: mine.length, change: change),
          bookings: mine,
          canRegister: canRegister,
          canBook: canBook,
          canEdit: canEdit,
        );
      }),
    );

/// The chosen day's classes as a table, each as it runs that day, with how
/// many of those booked are members and how many non-members. Open shows
/// who's booked (each can be taken out, and a non-member registered), books
/// a member in, and changes or cancels that date only.
class _SessionsTable extends StatelessWidget {
  final String venueId;
  final DateTime day;

  /// As the timetable has them; [changes]: the day's dates changed or cancelled on their own.
  final List<GymClass> classes;
  final List<ClassDay> changes;
  final List<ClassBooking> bookings;
  final bool canRegister;
  final bool canBook;
  final bool canEdit;

  const _SessionsTable({
    required this.venueId,
    required this.day,
    required this.classes,
    this.changes = const [],
    required this.bookings,
    this.canRegister = false,
    this.canBook = false,
    this.canEdit = false,
  });

  void _open(BuildContext context, GymClass c) => _openSession(context, c,
      venueId: venueId, day: day, bookings: bookings, canRegister: canRegister, canBook: canBook, canEdit: canEdit);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    ClassDay? changeOf(GymClass c) => changes.where((x) => x.classId == c.id).firstOrNull;
    GymClass on(GymClass c) => c.onDay(changeOf(c));
    bool cancelled(GymClass c) => changeOf(c)?.isCancelled ?? false;
    int booked(GymClass c) => bookings.where((b) => b.classId == c.id).length;
    int nonMembers(GymClass c) => bookings.where((b) => b.classId == c.id && b.isNonMember).length;
    Widget places(GymClass c) => cancelled(c)
        ? StatusChip(label: 'Cancelled', color: brand.danger, icon: Icons.event_busy_outlined)
        : StatusChip(
            label: '${booked(c)} / ${on(c).capacity}',
            color: booked(c) >= on(c).capacity ? brand.warning : brand.success,
            icon: Icons.people_alt_outlined,
          );
    return DataGrid<GymClass>(
      rows: classes,
      noun: 'classes',
      rowLabel: (c) => 'Open ${c.name}',
      onRowTap: (c) => _open(context, c),
      columns: [
        GridColumn(
          key: 'class',
          label: 'Class',
          flex: 4,
          sortBy: (c) => c.name.toLowerCase(),
          cell: (context, c) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
              _CellNote([
                if (!DataGrid.shows(context, 'time')) on(c).span,
                if (on(c).trainerName != null && !DataGrid.shows(context, 'trainer')) 'with ${on(c).trainerName}',
              ]),
              if (changeOf(c) case final change?)
                Text(change.isCancelled ? 'Not held this day' : 'Changed this day only',
                    style: TextStyle(color: change.isCancelled ? brand.danger : brand.highlight, fontSize: 12, fontWeight: FontWeight.w600)),
              if (!DataGrid.shows(context, 'booked')) Padding(padding: const EdgeInsets.only(top: 4), child: places(c)),
            ],
          ),
        ),
        GridColumn(
          key: 'time',
          label: 'Time',
          flex: 2,
          showFrom: 600,
          sortBy: (c) => on(c).hour * 60 + on(c).minute,
          cell: (context, c) => Text(on(c).span, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.body)),
        ),
        GridColumn(
          key: 'trainer',
          label: 'Trainer',
          flex: 3,
          showFrom: 860,
          sortBy: (c) => (on(c).trainerName ?? '').toLowerCase(),
          cell: (context, c) => Text(on(c).trainerName ?? '—',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: on(c).trainerName == null ? brand.muted : brand.body)),
        ),
        GridColumn(
          key: 'booked',
          label: 'Booked',
          width: 120,
          showFrom: 480,
          sortBy: booked,
          cell: (context, c) => places(c),
        ),
        GridColumn(
          key: 'members',
          label: 'Members',
          width: 100,
          showFrom: 720,
          sortBy: (c) => booked(c) - nonMembers(c),
          cell: (context, c) => Text('${booked(c) - nonMembers(c)}', style: TextStyle(color: brand.body)),
        ),
        GridColumn(
          key: 'non-members',
          label: 'Non-members',
          width: 140,
          showFrom: 820,
          sortBy: nonMembers,
          cell: (context, c) => Text('${nonMembers(c)}', style: TextStyle(color: nonMembers(c) == 0 ? brand.muted : brand.body)),
        ),
        GridColumn.actions(cell: (context, c) => GridOpenButton(onPressed: () => _open(context, c))),
      ],
    );
  }
}

/// How many have registered for the gym's classes to date: the totals at a
/// glance, each class's, and everyone who has booked (members or not), found
/// by name, phone, email or member code; a non-member can be registered from
/// there.
class _RegisteredToDate extends ConsumerStatefulWidget {
  final String venueId;
  final bool canRegister;

  const _RegisteredToDate({required this.venueId, this.canRegister = false});

  @override
  ConsumerState<_RegisteredToDate> createState() => _RegisteredToDateState();
}

class _RegisteredToDateState extends ConsumerState<_RegisteredToDate> {
  String _search = '';

  /// Everyone (null), members (true) or non-members (false).
  bool? _members;

  bool _matches(ClassRegistrant p) {
    if (_members != null && p.isMember != _members) return false;
    if (_search.isEmpty) return true;
    final digits = _search.replaceAll(RegExp(r'\D'), '');
    return p.name.toLowerCase().contains(_search) ||
        (p.memberCode?.toLowerCase().contains(_search) ?? false) ||
        (p.email?.toLowerCase().contains(_search) ?? false) ||
        (digits.length >= 3 && (p.phone ?? '').replaceAll(RegExp(r'\D'), '').contains(digits));
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final venueId = widget.venueId;
    return AsyncValueView<ClassRegistrations>(
      value: ref.watch(gymClassRegistrationsProvider(venueId)),
      onRetry: () => ref.invalidate(gymClassRegistrationsProvider(venueId)),
      data: (r) {
        if (r.bookings == 0) {
          return const EmptyState(
            icon: Icons.groups_outlined,
            title: 'No bookings yet',
            message: 'Everyone who books a class shows here: members of the gym, and anyone else on Health Pro.',
          );
        }
        final people = r.registrants.where(_matches).toList();
        Widget filter(String label, bool? value, int count) => ChoiceChip(
              label: Text('$label ($count)'),
              selected: _members == value,
              onSelected: (_) => setState(() => _members = value),
            );
        final search = TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded, size: 20),
            hintText: 'Search name, phone, email or code',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 10),
          ),
          onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
        );
        final filters = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            filter('Everyone', null, r.people),
            filter('Members', true, r.members),
            filter('Non-members', false, r.nonMembers),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ServiceStats(stats: [
              ServiceStat(label: 'Places booked', value: r.bookings, color: BrandColors.blue),
              ServiceStat(label: 'People', value: r.people, color: BrandColors.navy),
              ServiceStat(label: 'Members', value: r.members, color: BrandColors.green),
              ServiceStat(label: 'Non-members', value: r.nonMembers, color: brand.highlight),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 2),
              child: Text(
                [
                  'Since the first booking',
                  if (r.upcoming > 0) '${r.upcoming} still to come',
                  if (r.cancelled > 0) '${r.cancelled} cancelled, not counted',
                ].join(' · '),
                style: TextStyle(color: brand.muted, fontSize: 12.5),
              ),
            ),
            const SectionTitle('By class'),
            DataGrid<ClassTally>(
              rows: r.classes,
              noun: 'classes',
              columns: [
                GridColumn(
                  key: 'class',
                  label: 'Class',
                  flex: 4,
                  sortBy: (c) => c.name.toLowerCase(),
                  cell: (context, c) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                      _CellNote([c.when, if (!c.isActive) 'off the timetable']),
                      if (!DataGrid.shows(context, 'members'))
                        _CellNote(['${c.members} ${c.members == 1 ? 'member' : 'members'}',
                          '${c.nonMembers} ${c.nonMembers == 1 ? 'non-member' : 'non-members'}']),
                    ],
                  ),
                ),
                GridColumn(
                  key: 'booked',
                  label: 'Booked',
                  width: 90,
                  sortBy: (c) => c.bookings,
                  cell: (context, c) => Text('${c.bookings}', style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                ),
                GridColumn(
                  key: 'members',
                  label: 'Members',
                  width: 100,
                  showFrom: 640,
                  sortBy: (c) => c.members,
                  cell: (context, c) => Text('${c.members}', style: TextStyle(color: brand.body)),
                ),
                GridColumn(
                  key: 'non-members',
                  label: 'Non-members',
                  width: 140,
                  showFrom: 640,
                  sortBy: (c) => c.nonMembers,
                  cell: (context, c) => Text('${c.nonMembers}', style: TextStyle(color: c.nonMembers == 0 ? brand.muted : brand.body)),
                ),
                GridColumn(
                  key: 'upcoming',
                  label: 'To come',
                  width: 100,
                  showFrom: 820,
                  sortBy: (c) => c.upcoming,
                  cell: (context, c) => Text('${c.upcoming}', style: TextStyle(color: c.upcoming == 0 ? brand.muted : brand.body)),
                ),
                GridColumn(
                  key: 'last',
                  label: 'Last booked for',
                  width: 150,
                  showFrom: 980,
                  sortBy: (c) => c.lastDate?.millisecondsSinceEpoch ?? 0,
                  cell: (context, c) => Text(c.lastDate == null ? '—' : formatShortDate(c.lastDate!), style: TextStyle(color: brand.body)),
                ),
              ],
            ),
            SectionTitle('People (${r.people})'),
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth < 640
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [search, const SizedBox(height: 10), filters])
                  : Row(children: [SizedBox(width: 340, child: search), const SizedBox(width: 14), Expanded(child: filters)]),
            ),
            const SizedBox(height: 12),
            DataGrid<ClassRegistrant>(
              rows: people,
              noun: 'people',
              pageSizes: const [25, 50, 100],
              columns: [
                GridColumn(
                  key: 'name',
                  label: 'Name',
                  flex: 4,
                  sortBy: (p) => p.name.toLowerCase(),
                  cell: (context, p) {
                    final under = [
                      if (p.memberCode != null) p.memberCode!,
                      if (!DataGrid.shows(context, 'contact') && p.contact.isNotEmpty) p.contact,
                    ].join(' · ');
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                        if (under.isNotEmpty)
                          Text(under, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 13)),
                        if (!DataGrid.shows(context, 'member'))
                          Padding(padding: const EdgeInsets.only(top: 4), child: _memberChip(context, p.isMember)),
                      ],
                    );
                  },
                ),
                GridColumn(
                  key: 'member',
                  label: 'Status',
                  width: 170,
                  showFrom: 560,
                  sortBy: (p) => p.isMember ? 0 : 1,
                  cell: (context, p) => _memberChip(context, p.isMember),
                ),
                GridColumn(
                  key: 'contact',
                  label: 'Contact',
                  flex: 3,
                  showFrom: 900,
                  sortBy: (p) => p.contact.toLowerCase(),
                  cell: (context, p) => Text(p.contact.isEmpty ? '—' : p.contact,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.contact.isEmpty ? brand.muted : brand.body)),
                ),
                GridColumn(
                  key: 'times',
                  label: 'Bookings',
                  width: 100,
                  showFrom: 700,
                  sortBy: (p) => p.bookings,
                  cell: (context, p) => Text('${p.bookings}', style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                ),
                GridColumn(
                  key: 'latest',
                  label: 'Last class',
                  flex: 3,
                  showFrom: 1080,
                  sortBy: (p) => p.lastDate.millisecondsSinceEpoch,
                  cell: (context, p) => Text('${p.lastClass ?? 'Class'} · ${formatShortDate(p.lastDate)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.body)),
                ),
                if (widget.canRegister && r.nonMembers > 0)
                  GridColumn.actions(
                    width: 140,
                    cell: (context, p) => p.isMember
                        ? const SizedBox.shrink()
                        : GridOpenButton(
                            label: 'Register',
                            icon: Icons.person_add_alt_1_outlined,
                            onPressed: () => context.go(GymRoutes.registerEnquiryFor(venueId, name: p.name, phone: p.phone ?? '')),
                          ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  static Widget _memberChip(BuildContext context, bool member) => member
      ? StatusChip(label: 'Member', color: context.brand.success)
      : StatusChip(label: 'Non-member', color: context.brand.highlight, icon: Icons.public_rounded);
}

/// Every class in the week as a table, Monday first; Open changes one (for
/// those who may).
class _TimetableTable extends StatelessWidget {
  final List<GymClass> classes;
  final ValueChanged<GymClass>? onEdit;

  const _TimetableTable({required this.classes, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final rows = [...classes]..sort((a, b) => (a.weekday * 1440 + a.hour * 60 + a.minute).compareTo(b.weekday * 1440 + b.hour * 60 + b.minute));
    Widget status(GymClass c) => c.isActive
        ? StatusChip(label: 'On the timetable', color: brand.success)
        : StatusChip(label: 'Not on the timetable', color: brand.muted);
    Widget who(GymClass c) => c.openToAll
        ? StatusChip(label: 'Everyone', color: brand.highlight, icon: Icons.public_rounded)
        : StatusChip(label: 'Members only', color: brand.muted, icon: Icons.lock_outline_rounded);
    return DataGrid<GymClass>(
      rows: rows,
      noun: 'classes',
      pageSizes: const [25, 50, 100],
      rowLabel: (c) => 'Open ${c.name}',
      dimmed: (c) => !c.isActive,
      onRowTap: onEdit,
      columns: [
        GridColumn(
          key: 'class',
          label: 'Class',
          flex: 4,
          sortBy: (c) => c.name.toLowerCase(),
          cell: (context, c) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
              _CellNote([
                if (!DataGrid.shows(context, 'day')) '${weekdayNames[c.weekday - 1]} ${c.time}',
                if (c.trainerName != null && !DataGrid.shows(context, 'trainer')) 'with ${c.trainerName}',
                if (!DataGrid.shows(context, 'places')) '${c.durationMinutes} min · ${c.capacity} places',
                if (!DataGrid.shows(context, 'who')) c.openToAll ? 'everyone' : 'members only',
              ]),
              if (!DataGrid.shows(context, 'status') && !c.isActive)
                Padding(padding: const EdgeInsets.only(top: 4), child: status(c)),
            ],
          ),
        ),
        GridColumn(
          key: 'day',
          label: 'Day',
          flex: 2,
          showFrom: 560,
          sortBy: (c) => c.weekday * 1440 + c.hour * 60 + c.minute,
          cell: (context, c) => Text('${weekdayNames[c.weekday - 1]} ${c.time}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: brand.ink)),
        ),
        GridColumn(
          key: 'trainer',
          label: 'Trainer',
          flex: 3,
          showFrom: 900,
          sortBy: (c) => (c.trainerName ?? '').toLowerCase(),
          cell: (context, c) => Text(c.trainerName ?? '—',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.trainerName == null ? brand.muted : brand.body)),
        ),
        GridColumn(
          key: 'places',
          label: 'Length · places',
          flex: 2,
          showFrom: 1040,
          sortBy: (c) => c.capacity,
          cell: (context, c) => Text('${c.durationMinutes} min · ${c.capacity}', style: TextStyle(color: brand.body)),
        ),
        GridColumn(
          key: 'who',
          label: 'Who can book',
          width: 160,
          showFrom: 820,
          sortBy: (c) => c.openToAll ? 0 : 1,
          cell: (context, c) => who(c),
        ),
        GridColumn(
          key: 'status',
          label: 'Status',
          width: 190,
          showFrom: 720,
          sortBy: (c) => c.isActive ? 0 : 1,
          cell: (context, c) => status(c),
        ),
        if (onEdit != null) GridColumn.actions(cell: (context, c) => GridOpenButton(onPressed: () => onEdit!(c))),
      ],
    );
  }
}

/// One class on the chosen day, in the dialog Open shows: places taken,
/// who's booked, each a member of the gym or a non-member on Health Pro with
/// how to reach them (each can be taken out, a non-member registered as a
/// member),
/// and booking a member in.
class _SessionCard extends ConsumerWidget {
  final String venueId;

  /// The class as the timetable has it; [session]: as it runs that day.
  final GymClass weekly;
  final ClassSession session;
  final List<ClassBooking> bookings;
  final bool canRegister;
  final bool canBook;

  /// Who keeps the timetable: changes or cancels this date only.
  final bool canEdit;

  const _SessionCard({
    required this.venueId,
    required this.weekly,
    required this.session,
    required this.bookings,
    this.canRegister = false,
    this.canBook = false,
    this.canEdit = false,
  });

  void _refresh(WidgetRef ref) {
    ref.invalidate(gymClassBookingsProvider((venueId: venueId, date: session.date)));
    ref.invalidate(gymClassPlacesProvider(venueId));
    ref.invalidate(gymClassDaysProvider(venueId));
    ref.invalidate(gymClassRegistrationsProvider(venueId));
  }

  /// A new time, trainer or places on this date, or [cancel] it.
  Future<void> _changeDay(BuildContext context, WidgetRef ref, {bool cancel = false}) async {
    final saved = await showAppDialog<bool>(
      context: context,
      builder: (_) => _ClassDayDialog(session: session, weekly: weekly, cancel: cancel),
    );
    if (saved == true) _refresh(ref);
  }

  Future<void> _backToTimetable(BuildContext context, WidgetRef ref) async {
    final day = _onDay(session.date);
    final sure = await confirmAction(
      context,
      title: '${weekly.name} $day as the timetable has it?',
      message: session.cancelled
          ? 'It can be booked again. Places cancelled with the date stay cancelled.'
          : '${weekly.span}${weekly.trainerName == null ? '' : ' with ${weekly.trainerName}'}, ${weekly.capacity} places. '
              'Those booked are told.',
      confirmLabel: 'Back to the timetable',
      cancelLabel: 'Keep this date\'s',
    );
    if (!sure || !context.mounted) return;
    final ok = await runAction(context, () => ref.read(gymClassRepositoryProvider).clearDay(weekly.id, session.date),
        success: '${weekly.name} $day is back as the timetable has it');
    if (ok) _refresh(ref);
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, ClassBooking b) async {
    final sure = await confirmAction(
      context,
      title: 'Take ${b.memberName} out of ${session.gymClass.name}?',
      confirmLabel: 'Take out',
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (!sure || !context.mounted) return;
    final ok = await runAction(context, () => ref.read(gymClassRepositoryProvider).cancel(b.id));
    if (ok) _refresh(ref);
  }

  /// A non-member into the gym's register, filled in with their name and phone.
  void _register(BuildContext context, ClassBooking b) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(GymRoutes.registerEnquiryFor(venueId, name: b.memberName, phone: b.memberPhone ?? ''));
  }

  Future<void> _book(BuildContext context, WidgetRef ref) async {
    final member = await showAppDialog<ClassMemberChoice>(
      context: context,
      builder: (_) => _PickMemberDialog(venueId: venueId, booked: {for (final b in bookings) if (b.gymMemberId != null) b.gymMemberId!}),
    );
    if (member == null || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(gymClassRepositoryProvider).book(session.gymClass.id, session.date, gymMemberId: member.id),
      success: '${member.fullName} is booked in',
    );
    if (ok) _refresh(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final c = session.gymClass;
    final ended = !c.startOn(session.date).add(Duration(minutes: c.durationMinutes)).isAfter(BhutanTime.now());
    final started = session.startedBy(BhutanTime.now());
    final change = session.change;
    final nonMembers = bookings.where((b) => b.isNonMember).length;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                    Text(
                        [
                          c.span,
                          if (c.trainerName != null) 'with ${c.trainerName}',
                          if (bookings.isNotEmpty) '${bookings.length - nonMembers} ${bookings.length - nonMembers == 1 ? 'member' : 'members'}',
                          if (nonMembers > 0) '$nonMembers ${nonMembers == 1 ? 'non-member' : 'non-members'}',
                        ].join(' · '),
                        style: TextStyle(color: brand.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              session.cancelled
                  ? StatusChip(label: 'Cancelled', color: brand.danger, icon: Icons.event_busy_outlined)
                  : StatusChip(
                      label: '${session.booked} / ${c.capacity}',
                      color: session.isFull ? brand.warning : brand.success,
                      icon: Icons.people_alt_outlined,
                    ),
            ],
          ),
          // This date only: what's different, and how every other week runs.
          if (change != null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: (change.isCancelled ? brand.danger : brand.highlight).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(change.isCancelled ? Icons.event_busy_outlined : Icons.edit_calendar_outlined,
                      size: 18, color: change.isCancelled ? brand.danger : brand.highlight),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      [
                        change.isCancelled ? 'Not held this day.' : 'Changed this day only.',
                        if (change.note != null) change.note!,
                        'Every other ${weekdayNames[weekly.weekday - 1]}: ${weekly.span}'
                            '${weekly.trainerName == null ? '' : ' with ${weekly.trainerName}'}, ${weekly.capacity} places.',
                      ].join(' '),
                      style: TextStyle(color: brand.body, fontSize: 12.5, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          if (bookings.isEmpty)
            Text(
                session.cancelled
                    ? 'Nobody booked: places were cancelled with the date.'
                    : ended
                        ? 'Nobody booked.'
                        : 'Nobody booked yet.',
                style: TextStyle(color: brand.muted))
          else
            for (final b in bookings)
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${b.memberName}${b.memberCode == null ? '' : ' · ${b.memberCode}'}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: brand.ink)),
                          if (b.contact.isNotEmpty || b.bookedByDesk)
                            Text([if (b.contact.isNotEmpty) b.contact, if (b.bookedByDesk) 'booked by the desk'].join(' · '),
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  b.isMember
                      ? StatusChip(label: 'Member', color: brand.success)
                      : StatusChip(label: 'Non-member', color: brand.highlight, icon: Icons.public_rounded),
                  if (b.isNonMember && canRegister)
                    IconButton(
                      tooltip: 'Register ${b.memberName} as a member',
                      onPressed: () => _register(context, b),
                      icon: Icon(Icons.person_add_alt_1_outlined, size: 18, color: brand.muted),
                    ),
                  // Over: who came stays on record.
                  if (!ended)
                    IconButton(
                      tooltip: 'Take ${b.memberName} out',
                      onPressed: () => _remove(context, ref, b),
                      icon: Icon(Icons.close_rounded, size: 18, color: brand.muted),
                    ),
                ],
              ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 2,
            children: [
              if (canBook && !ended && !session.isFull && !session.cancelled)
                TextButton.icon(
                  onPressed: () => _book(context, ref),
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                  label: const Text('Book a member'),
                ),
              // This date only, before it starts; Edit on the timetable changes every week.
              if (canEdit && !started) ...[
                if (!session.cancelled) ...[
                  TextButton.icon(
                    onPressed: () => _changeDay(context, ref),
                    icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                    label: const Text('Change this date'),
                  ),
                  TextButton.icon(
                    onPressed: () => _changeDay(context, ref, cancel: true),
                    style: TextButton.styleFrom(foregroundColor: brand.danger),
                    icon: const Icon(Icons.event_busy_outlined, size: 18),
                    label: const Text('Cancel this date'),
                  ),
                ],
                if (change != null)
                  TextButton.icon(
                    onPressed: () => _backToTimetable(context, ref),
                    icon: const Icon(Icons.undo_rounded, size: 18),
                    label: const Text('Back to the timetable'),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Finds a member by name, phone or code, to book them in.
class _PickMemberDialog extends ConsumerStatefulWidget {
  final String venueId;
  final Set<String> booked;

  const _PickMemberDialog({required this.venueId, required this.booked});

  @override
  ConsumerState<_PickMemberDialog> createState() => _PickMemberDialogState();
}

class _PickMemberDialogState extends ConsumerState<_PickMemberDialog> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(gymClassMemberChoicesProvider(widget.venueId)).valueOrNull ?? const <ClassMemberChoice>[];
    final digits = _search.replaceAll(RegExp(r'\D'), '');
    final found = all
        .where((m) => !widget.booked.contains(m.id))
        .where((m) =>
            _search.isEmpty ||
            m.fullName.toLowerCase().contains(_search) ||
            m.code.toLowerCase().contains(_search) ||
            (digits.isNotEmpty && m.phone.replaceAll(RegExp(r'\D'), '').contains(digits)))
        .take(30)
        .toList();
    return AlertDialog(
      title: const Text('Book a member'),
      content: SizedBox(
        width: 440,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Name, phone or member code'),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: found.isEmpty
                  ? Center(child: Text('Nobody matches.', style: TextStyle(color: context.brand.muted)))
                  : ListView(
                      children: [
                        for (final m in found)
                          ListTile(
                            title: Text(m.fullName),
                            subtitle: Text('${m.code} · ${m.phone}'),
                            onTap: () => Navigator.pop(context, m),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

/// A new class ([gymClass] null) or changes to one: name, trainer, day,
/// time, length, places, and whether it's on the timetable.
class _ClassDialog extends ConsumerStatefulWidget {
  final String venueId;
  final GymClass? gymClass;

  const _ClassDialog({required this.venueId, this.gymClass});

  @override
  ConsumerState<_ClassDialog> createState() => _ClassDialogState();
}

class _ClassDialogState extends ConsumerState<_ClassDialog> {
  final _form = GlobalKey<FormState>();
  late final GymClass? _old = widget.gymClass;
  late final _name = TextEditingController(text: _old?.name ?? '');
  late final _trainer = TextEditingController(text: _old?.trainerName ?? '');
  late final _description = TextEditingController(text: _old?.description ?? '');
  late final _capacity = TextEditingController(text: '${_old?.capacity ?? 20}');
  late int _weekday = _old?.weekday ?? BhutanTime.today().weekday;
  late TimeOfDay _time = TimeOfDay(hour: _old?.hour ?? 7, minute: _old?.minute ?? 0);
  late int _minutes = _old?.durationMinutes ?? 60;
  late bool _active = _old?.isActive ?? true;
  late bool _open = _old?.openToAll ?? true;
  bool _saving = false;

  static const _lengths = [30, 45, 60, 75, 90, 120];

  @override
  void dispose() {
    for (final c in [_name, _trainer, _description, _capacity]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_old != null && _old.isActive && (!_active || _weekday != _old.weekday)) {
      final sure = await confirmAction(
        context,
        title: !_active ? 'Take ${_old.name} off the timetable?' : 'Move ${_old.name} to ${weekdayNames[_weekday - 1]}?',
        message: 'Bookings to come are cancelled, and members with the app are told.',
        confirmLabel: !_active ? 'Take it off' : 'Move it',
      );
      if (!sure || !mounted) return;
    }
    setState(() => _saving = true);
    final details = classDetails(
      name: _name.text,
      description: _description.text,
      trainerName: _trainer.text,
      weekday: _weekday,
      hour: _time.hour,
      minute: _time.minute,
      durationMinutes: _minutes,
      capacity: int.parse(_capacity.text.trim()),
      isActive: _active,
      openToAll: _open,
    );
    final ok = await runAction(context, () async {
      await ref.read(gymClassRepositoryProvider).saveClass(widget.venueId, details, classId: _old?.id);
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    showFeedback(context, _old == null ? 'Class added' : 'Saved');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: brand.ink)),
        );
    return AlertDialog(
      title: Text(_old == null ? 'New class' : _old.name),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Editing changes every week; one date has its own Change on Bookings.
                if (_old != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 17, color: brand.muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Changes every ${weekdayNames[_old.weekday - 1]}. To change one date only, open it on Bookings '
                            'and use Change this date.',
                            style: TextStyle(color: brand.body, fontSize: 12.5, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                TextFormField(
                  controller: _name,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name *', hintText: 'Yoga, Zumba, HIIT...'),
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Give it a name' : null,
                ),
                TextFormField(
                  controller: _trainer,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Trainer', hintText: 'Who takes it'),
                ),
                label('Day *'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var w = 1; w <= 7; w++)
                      ChoiceChip(
                        label: Text(weekdayNames[w - 1].substring(0, 3)),
                        selected: _weekday == w,
                        onSelected: (_) => setState(() => _weekday = w),
                      ),
                  ],
                ),
                label('Starts at, and how long'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: _time);
                        if (picked != null) setState(() => _time = picked);
                      },
                      icon: const Icon(Icons.schedule_rounded, size: 18),
                      label: Text(clockTime(_time.hour, _time.minute)),
                    ),
                    for (final m in _lengths)
                      ChoiceChip(label: Text('$m min'), selected: _minutes == m, onSelected: (_) => setState(() => _minutes = m)),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _capacity,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Places *', helperText: 'How many can book it'),
                  validator: (v) => Validators.wholeNumber(v, min: 1, max: 500, what: 'Places'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _description,
                  maxLength: 300,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'About it', hintText: 'For beginners; bring a mat...'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _open,
                  onChanged: (v) => setState(() => _open = v),
                  title: const Text('Open to everyone on Health Pro'),
                  subtitle: Text(_open
                      ? 'Anyone with a Health Pro account can book it, member of the gym or not'
                      : 'Only members with a package can book it. Places booked already stay'),
                ),
                if (_old != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                    title: const Text('On the timetable'),
                    subtitle: const Text('Turn off to stop it; its bookings to come are cancelled'),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_old == null ? 'Add' : 'Save')),
      ],
    );
  }
}

/// A class day in a sentence: 'tomorrow', 'Sat 28 Nov'.
String _dayWord(DateTime d) {
  final label = classDayLabel(d, BhutanTime.today());
  return const {'Yesterday', 'Today', 'Tomorrow'}.contains(label) ? label.toLowerCase() : label;
}

/// 'tomorrow', 'on Sat 28 Nov'.
String _onDay(DateTime d) {
  final word = _dayWord(d);
  return word == word.toLowerCase() ? word : 'on $word';
}

/// One date of a class only (gym_save_class_day): a new time, length,
/// trainer or places, or [cancel] it; with a note for those booked, who are
/// told. Every other week stays as the timetable has it ([weekly]).
class _ClassDayDialog extends ConsumerStatefulWidget {
  final ClassSession session;
  final GymClass weekly;
  final bool cancel;

  const _ClassDayDialog({required this.session, required this.weekly, this.cancel = false});

  @override
  ConsumerState<_ClassDayDialog> createState() => _ClassDayDialogState();
}

class _ClassDayDialogState extends ConsumerState<_ClassDayDialog> {
  final _form = GlobalKey<FormState>();
  late final GymClass _now = widget.session.gymClass;
  late final _trainer = TextEditingController(text: _now.trainerName ?? '');
  late final _capacity = TextEditingController(text: '${_now.capacity}');
  late final _note = TextEditingController(text: widget.session.change?.note ?? '');
  late TimeOfDay _time = TimeOfDay(hour: _now.hour, minute: _now.minute);
  late int _minutes = _now.durationMinutes;
  bool _saving = false;

  String get _day => _dayWord(widget.session.date);

  @override
  void dispose() {
    for (final c in [_trainer, _capacity, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final details = widget.cancel
        ? classDayDetails(cancel: true, note: _note.text)
        : classDayDetails(
            hour: _time.hour,
            minute: _time.minute,
            durationMinutes: _minutes,
            trainerName: _trainer.text,
            capacity: int.parse(_capacity.text.trim()),
            note: _note.text,
          );
    final ok = await runAction(
      context,
      () => ref.read(gymClassRepositoryProvider).saveDay(_now.id, widget.session.date, details),
      success: widget.cancel ? '${_now.name} ${_onDay(widget.session.date)} is cancelled' : '${_now.name} changed for $_day only',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final booked = widget.session.booked;
    final w = widget.weekly;
    final usual = '${w.span}${w.trainerName == null ? '' : ' with ${w.trainerName}'}, ${w.capacity} places';
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: brand.ink)),
        );
    final intro = widget.cancel
        ? '${booked == 0 ? 'Nobody is booked yet.' : '$booked booked ${booked == 1 ? 'loses their place' : 'lose their places'} and '
            '${booked == 1 ? 'is' : 'are'} told, with your note.'} Every other ${weekdayNames[w.weekday - 1]} runs as usual.'
        : 'Only $_day changes. Every other ${weekdayNames[w.weekday - 1]} stays $usual.'
            '${booked == 0 ? '' : ' The $booked booked keep their place and are told what changed.'}';
    return AlertDialog(
      title: Text(widget.cancel ? 'Cancel ${_now.name} ${_onDay(widget.session.date)}?' : '${_now.name}, $_day only'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(intro, style: TextStyle(color: brand.body, height: 1.45)),
                if (!widget.cancel) ...[
                  label('Starts at, and how long'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: _time);
                          if (picked != null) setState(() => _time = picked);
                        },
                        icon: const Icon(Icons.schedule_rounded, size: 18),
                        label: Text(clockTime(_time.hour, _time.minute)),
                      ),
                      for (final m in _ClassDialogState._lengths)
                        ChoiceChip(label: Text('$m min'), selected: _minutes == m, onSelected: (_) => setState(() => _minutes = m)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _trainer,
                    maxLength: 100,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Trainer', hintText: 'Who takes it that day'),
                  ),
                  TextFormField(
                    controller: _capacity,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                        labelText: 'Places *', helperText: booked == 0 ? 'How many can book it that day' : 'At least $booked: booked already'),
                    validator: (v) => Validators.wholeNumber(v, min: booked < 1 ? 1 : booked, max: 500, what: 'Places'),
                  ),
                  const SizedBox(height: 8),
                ] else
                  const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  maxLength: 200,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: widget.cancel ? 'Why' : 'Note',
                    hintText: widget.cancel ? 'Public holiday, trainer away...' : 'Tashi is away; Kinley takes it',
                    helperText: 'Those booked see it',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(widget.cancel ? 'Keep it' : 'Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: widget.cancel ? FilledButton.styleFrom(backgroundColor: brand.danger) : null,
          child: Text(widget.cancel ? 'Cancel this date' : 'Save for $_day'),
        ),
      ],
    );
  }
}

/// The quiet second line of a table's first cell: [parts] joined, nothing
/// when there are none (the other columns show them).
class _CellNote extends StatelessWidget {
  final List<String> parts;

  const _CellNote(this.parts);

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(parts.join(' · '),
        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.brand.muted, fontSize: 13));
  }
}
