import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/classes.dart';
import '../data/gym_repository.dart';
import '../data/registered_member.dart';
import '../gym_permissions.dart';
import '../widgets/class_widgets.dart';
import '../widgets/gym_widgets.dart';

/// Group classes, for the desk: who's booked into each class on a day (the
/// next two weeks), booking members in and taking them out; and the weekly
/// timetable, kept by who sets the packages.
class ClassesScreen extends ConsumerStatefulWidget {
  final String venueId;

  const ClassesScreen({super.key, required this.venueId});

  @override
  ConsumerState<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends ConsumerState<ClassesScreen> {
  DateTime _day = BhutanTime.today();

  Future<void> _edit([GymClass? c]) async {
    final saved = await showAppDialog<bool>(context: context, builder: (_) => _ClassDialog(venueId: widget.venueId, gymClass: c));
    if (saved == true) {
      ref.invalidate(gymClassesProvider(widget.venueId));
      ref.invalidate(gymClassBookingsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.venueId;
    return GymStaffPage(
      venueId: id,
      title: 'Classes',
      permission: GymPermission.members,
      builder: (context, access) {
        final canEdit = access.can(GymPermission.plans);
        return AppPage(
          title: 'Classes',
          body: AsyncValueView<List<GymClass>>(
            value: ref.watch(gymClassesProvider(id)),
            onRetry: () => ref.invalidate(gymClassesProvider(id)),
            data: (classes) {
              final today = BhutanTime.today();
              final active = classes.where((c) => c.isActive).toList();
              final onDay = active.where((c) => c.weekday == _day.weekday).toList()
                ..sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
              final bookings =
                  ref.watch(gymClassBookingsProvider((venueId: id, date: _day))).valueOrNull ?? const <ClassBooking>[];
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(gymClassesProvider(id));
                  ref.invalidate(gymClassBookingsProvider);
                },
                child: ListView(
                  padding: pagePadding(context, bottom: 40),
                  children: [
                    PageActions(
                      text: active.isEmpty
                          ? 'Your weekly timetable: yoga, zumba and the rest. Members book their place in the app.'
                          : '${active.length} ${active.length == 1 ? 'class' : 'classes'} a week. Members book their place in the app.',
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
                            ? 'Add the gym\'s classes: the day, time, length and how many places. Members then book them on My gym.'
                            : 'The owner adds the gym\'s classes here.',
                        actionLabel: canEdit ? 'Add a class' : null,
                        onAction: canEdit ? _edit : null,
                      )
                    else ...[
                      const SectionTitle('Bookings'),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (var i = 0; i < 14; i++)
                              () {
                                final d = DateTime(today.year, today.month, today.day + i);
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(classDayLabel(d, today)),
                                    selected: _day == d,
                                    onSelected: (_) => setState(() => _day = d),
                                  ),
                                );
                              }(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (onDay.isEmpty)
                        SectionCard(
                          padding: const EdgeInsets.all(16),
                          child: Text('No classes on ${classDayLabel(_day, today).toLowerCase()}.',
                              style: TextStyle(color: context.brand.muted)),
                        )
                      else
                        ResponsiveGrid(
                          minItemWidth: 340,
                          maxColumns: 3,
                          children: [
                            for (final c in onDay)
                              _SessionCard(
                                venueId: id,
                                session: ClassSession(
                                  gymClass: c,
                                  date: _day,
                                  booked: bookings.where((b) => b.classId == c.id).length,
                                ),
                                bookings: bookings.where((b) => b.classId == c.id).toList(),
                              ),
                          ],
                        ),
                      const SectionTitle('Weekly timetable'),
                      SectionCard(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var w = 1; w <= 7; w++)
                              if (classes.any((c) => c.weekday == w)) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                                  child: Text(weekdayNames[w - 1],
                                      style: TextStyle(fontWeight: FontWeight.w800, color: context.brand.muted, fontSize: 12.5)),
                                ),
                                for (final c in classes.where((c) => c.weekday == w))
                                  ListTile(
                                    dense: true,
                                    onTap: canEdit ? () => _edit(c) : null,
                                    leading: SizedBox(
                                      width: 70,
                                      child: Text(c.time,
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700, color: c.isActive ? context.brand.ink : context.brand.muted)),
                                    ),
                                    title: Text(c.name, style: TextStyle(color: c.isActive ? null : context.brand.muted)),
                                    subtitle: Text([
                                      if (c.trainerName != null) 'with ${c.trainerName}',
                                      '${c.durationMinutes} min',
                                      '${c.capacity} places',
                                    ].join(' · ')),
                                    trailing: c.isActive
                                        ? (canEdit ? const Icon(Icons.edit_outlined, size: 18) : null)
                                        : StatusChip(label: 'Not on the timetable', color: context.brand.muted),
                                  ),
                              ],
                          ],
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
}

/// One class on the chosen day: places taken, who's booked (each can be
/// taken out), and booking a member in.
class _SessionCard extends ConsumerWidget {
  final String venueId;
  final ClassSession session;
  final List<ClassBooking> bookings;

  const _SessionCard({required this.venueId, required this.session, required this.bookings});

  void _refresh(WidgetRef ref) {
    ref.invalidate(gymClassBookingsProvider((venueId: venueId, date: session.date)));
    ref.invalidate(gymClassPlacesProvider(venueId));
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

  Future<void> _book(BuildContext context, WidgetRef ref) async {
    final member = await showAppDialog<GymMember>(
      context: context,
      builder: (_) => _PickMemberDialog(venueId: venueId, booked: {for (final b in bookings) b.gymMemberId}),
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
    return SectionCard(
      padding: const EdgeInsets.all(14),
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
                    Text([c.span, if (c.trainerName != null) 'with ${c.trainerName}'].join(' · '),
                        style: TextStyle(color: brand.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              StatusChip(
                label: '${session.booked} / ${c.capacity}',
                color: session.isFull ? brand.warning : brand.success,
                icon: Icons.people_alt_outlined,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (bookings.isEmpty)
            Text('Nobody booked yet.', style: TextStyle(color: brand.muted))
          else
            for (final b in bookings)
              Row(
                children: [
                  Expanded(
                    child: Text('${b.memberName}${b.memberCode == null ? '' : ' · ${b.memberCode}'}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                    tooltip: 'Take ${b.memberName} out',
                    onPressed: () => _remove(context, ref, b),
                    icon: Icon(Icons.close_rounded, size: 18, color: brand.muted),
                  ),
                ],
              ),
          if (!ended && !session.isFull) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _book(context, ref),
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('Book a member'),
              ),
            ),
          ],
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
    final all = ref.watch(gymMembersProvider(widget.venueId)).valueOrNull ?? const <GymMember>[];
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
                TextFormField(
                  controller: _name,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name *', hintText: 'Yoga, Zumba, HIIT...'),
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Give the class a name' : null,
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
