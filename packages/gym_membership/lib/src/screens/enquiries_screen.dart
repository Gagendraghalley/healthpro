import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/follow_ups.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import '../widgets/gym_widgets.dart';

enum _View {
  open('To follow up'),
  due('Due today'),
  trials('Free trials'),
  joined('Joined'),
  lost('Not joining'),
  all('All');

  const _View(this.label);
  final String label;
}

bool _inView(_View view, GymEnquiry e, DateTime today) => switch (view) {
      _View.open => e.isOpen,
      _View.due => e.needsActionOn(today),
      _View.trials => e.status == EnquiryStatus.trial,
      _View.joined => e.status == EnquiryStatus.joined,
      _View.lost => e.status == EnquiryStatus.lost,
      _View.all => true,
    };

Color _statusColor(BuildContext context, EnquiryStatus s) => switch (s) {
      EnquiryStatus.open => themeTone(context, BrandColors.blue),
      EnquiryStatus.trial => context.brand.highlight,
      EnquiryStatus.joined => context.brand.success,
      EnquiryStatus.lost => context.brand.muted,
    };

/// Enquiries and free trials: people who walked in, phoned or messaged about
/// joining, for the desk to follow up and sign up. Those due today come
/// first (and count on the menu); registering one with the same phone number
/// marks them joined.
class EnquiriesScreen extends ConsumerStatefulWidget {
  final String venueId;

  /// The enquiry to open (a link's `?open=`).
  final String? openId;

  const EnquiriesScreen({super.key, required this.venueId, this.openId});

  @override
  ConsumerState<EnquiriesScreen> createState() => _EnquiriesScreenState();
}

class _EnquiriesScreenState extends ConsumerState<EnquiriesScreen> {
  _View _view = _View.open;
  String _search = '';

  Future<void> _edit([GymEnquiry? enquiry]) => showAppDialog<bool>(
        context: context,
        builder: (_) => _EnquiryDialog(venueId: widget.venueId, enquiry: enquiry),
      );

  bool _matches(GymEnquiry e) {
    if (_search.isEmpty) return true;
    final digits = _search.replaceAll(RegExp(r'\D'), '');
    return e.fullName.toLowerCase().contains(_search) ||
        (e.interest ?? '').toLowerCase().contains(_search) ||
        (digits.isNotEmpty && e.phone.replaceAll(RegExp(r'\D'), '').contains(digits));
  }

  /// The ones to act on soonest first: their follow-up day (none last), then newest.
  static int _bySoonest(GymEnquiry a, GymEnquiry b) {
    final x = a.followUpOn ?? a.trialEndsOn;
    final y = b.followUpOn ?? b.trialEndsOn;
    if (x != null && y != null && x != y) return x.compareTo(y);
    if (x != null && y == null) return -1;
    if (x == null && y != null) return 1;
    return b.createdAt.compareTo(a.createdAt);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.venueId;
    return GymStaffPage(
      venueId: id,
      title: 'Enquiries & trials',
      permission: GymPermission.register,
      builder: (context, access) {
        return OpenFromLink<GymEnquiry>(
          id: widget.openId,
          items: ref.watch(gymEnquiriesProvider(id)).valueOrNull,
          idOf: (e) => e.id,
          open: _edit,
          child: AppPage(
          title: 'Enquiries & trials',
          body: AsyncValueView<List<GymEnquiry>>(
            value: ref.watch(gymEnquiriesProvider(id)),
            onRetry: () => ref.invalidate(gymEnquiriesProvider(id)),
            data: (all) {
              final today = BhutanTime.today();
              final counts = {for (final v in _View.values) v: all.where((e) => _inView(v, e, today)).length};
              final rows = all.where((e) => _inView(_view, e, today) && _matches(e)).toList();
              if (_view != _View.all && _view != _View.joined && _view != _View.lost) rows.sort(_bySoonest);
              final month = enquiriesIn(all, today);
              final due = counts[_View.due]!;
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(gymEnquiriesProvider(id)),
                child: ListView(
                  padding: pagePadding(context, bottom: 40),
                  children: [
                    PageActions(
                      text: all.isEmpty
                          ? 'People who asked about the gym, to follow up and sign up.'
                          : '${due == 0 ? 'Nobody to follow up today' : '$due to follow up today'}  ·  '
                              '${formatMonth(today)}: ${month.added} ${month.added == 1 ? 'enquiry' : 'enquiries'}, '
                              '${month.joined} joined',
                      children: [
                        FilledButton.icon(
                          onPressed: _edit,
                          style: FilledButton.styleFrom(minimumSize: PageActions.buttonSize),
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text('Add enquiry'),
                        ),
                      ],
                    ),
                    if (all.isEmpty)
                      EmptyState(
                        icon: Icons.contact_phone_outlined,
                        title: 'No enquiries yet',
                        message: 'When someone walks in, phones or messages about joining, add them here: what they\'re '
                            'after, a free trial and when to follow up. Registering them marks it joined.',
                        actionLabel: 'Add an enquiry',
                        onAction: _edit,
                      )
                    else ...[
                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded),
                          hintText: 'Search by name, phone or what they\'re after',
                        ),
                        onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final v in _View.values)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text('${v.label}  ${counts[v]}'),
                                  selected: _view == v,
                                  onSelected: (_) => setState(() => _view = v),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text(_search.isEmpty ? 'Nobody here.' : 'Nobody matches "$_search".',
                                style: TextStyle(color: context.brand.muted)),
                          ),
                        )
                      else
                        _EnquiriesTable(
                          rows: rows,
                          today: today,
                          venueId: id,
                          gymName: access.venue.name,
                          onEdit: _edit,
                        ),
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
}

/// The enquiries as a table: who, how they heard, what they're after, their
/// trial and follow-up, where it stands. Open changes one; the menu beside
/// it calls, WhatsApps, and registers them while it's open.
class _EnquiriesTable extends StatelessWidget {
  final List<GymEnquiry> rows;
  final DateTime today;
  final String venueId;
  final String gymName;
  final ValueChanged<GymEnquiry> onEdit;

  const _EnquiriesTable({required this.rows, required this.today, required this.venueId, required this.gymName, required this.onEdit});

  /// The follow-up and trial, as chips; none when there's nothing to do.
  List<Widget> _chips(BuildContext context, GymEnquiry e) {
    final brand = context.brand;
    return [
      if (e.isOpen && e.followUpOn != null)
        if (e.followUpOn!.isBefore(today))
          StatusChip(label: 'Follow-up missed, ${formatShortDate(e.followUpOn!)}', color: brand.danger, icon: Icons.alarm_rounded)
        else if (e.followUpOn == today)
          StatusChip(label: 'Follow up today', color: brand.warning, icon: Icons.alarm_rounded)
        else
          StatusChip(label: 'Follow up ${formatShortDate(e.followUpOn!)}', color: brand.muted, icon: Icons.event_outlined),
      if (e.status == EnquiryStatus.trial && e.trialEndsOn != null)
        if (e.trialOverOn(today))
          StatusChip(label: 'Trial ended ${formatShortDate(e.trialEndsOn!)}', color: brand.warning, icon: Icons.flag_outlined)
        else if (e.trialStartsOn!.isAfter(today))
          StatusChip(label: 'Trial from ${formatShortDate(e.trialStartsOn!)}', color: brand.highlight, icon: Icons.flag_outlined)
        else
          StatusChip(label: 'Trial until ${formatShortDate(e.trialEndsOn!)}', color: brand.highlight, icon: Icons.flag_outlined),
    ];
  }

  Widget _menu(BuildContext context, GymEnquiry e) {
    final brand = context.brand;
    PopupMenuItem<VoidCallback> item(IconData icon, String label, VoidCallback onTap) => PopupMenuItem(
          value: onTap,
          child: Row(children: [Icon(icon, size: 20, color: brand.body), const SizedBox(width: 12), Text(label)]),
        );
    return PopupMenuButton<VoidCallback>(
      tooltip: 'More',
      icon: Icon(Icons.more_vert_rounded, color: brand.muted),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        item(Icons.call_outlined, 'Call', () => callPhone(context, e.phone)),
        item(Icons.chat_outlined, 'WhatsApp', () => openWhatsApp(context, e.phone,
            message: 'Hello ${firstName(e.fullName, fallback: e.fullName)}, this is $gymName. ')),
        if (e.isOpen)
          item(Icons.person_add_alt_1_rounded, 'Register',
              () => context.go(GymRoutes.registerEnquiryFor(venueId, name: e.fullName, phone: e.phone)))
        else if (e.gymMemberId != null)
          item(Icons.person_outline_rounded, 'Open member', () => context.go(GymRoutes.memberFor(venueId, e.gymMemberId!))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    Widget status(GymEnquiry e) => StatusChip(label: e.status.label, color: _statusColor(context, e.status));
    return DataGrid<GymEnquiry>(
      rows: rows,
      noun: 'enquiries',
      pageSizes: const [25, 50, 100],
      rowLabel: (e) => 'Open ${e.fullName}',
      onRowTap: onEdit,
      columns: [
        GridColumn(
          key: 'name',
          label: 'Name',
          flex: 4,
          sortBy: (e) => e.fullName.toLowerCase(),
          cell: (context, e) {
            final chips = DataGrid.shows(context, 'follow') ? const <Widget>[] : _chips(context, e);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.fullName,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                Text('${e.phone} · ${e.source.label}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 13)),
                if (!DataGrid.shows(context, 'interest') && e.interest != null)
                  Text(e.interest!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.body, fontSize: 13)),
                if (!DataGrid.shows(context, 'status') || chips.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 6, runSpacing: 4, children: [if (!DataGrid.shows(context, 'status')) status(e), ...chips]),
                  ),
              ],
            );
          },
        ),
        GridColumn(
          key: 'interest',
          label: 'What they\'re after',
          flex: 3,
          showFrom: 860,
          sortBy: (e) => (e.interest ?? '').toLowerCase(),
          cell: (context, e) {
            final text = [if (e.interest != null) e.interest!, if (e.notes != null) e.notes!];
            return text.isEmpty
                ? Text('—', style: TextStyle(color: brand.muted))
                : Text(text.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.body));
          },
        ),
        GridColumn(
          key: 'follow',
          label: 'Follow-up',
          flex: 3,
          showFrom: 680,
          sortBy: (e) => e.followUpOn ?? e.trialEndsOn ?? DateTime(9999),
          cell: (context, e) {
            final chips = _chips(context, e);
            return chips.isEmpty
                ? Text('—', style: TextStyle(color: brand.muted))
                : Wrap(spacing: 6, runSpacing: 4, children: chips);
          },
        ),
        GridColumn(
          key: 'status',
          label: 'Status',
          width: 130,
          showFrom: 520,
          sortBy: (e) => e.status.index,
          cell: (context, e) => status(e),
        ),
        GridColumn.actions(
          width: 172,
          cell: (context, e) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [GridOpenButton(onPressed: () => onEdit(e)), _menu(context, e)],
          ),
        ),
      ],
    );
  }
}

/// A new enquiry ([enquiry] null) or changes to one: who, how they heard,
/// what they're after, where it stands (a free trial's days), the day to
/// follow up and notes. Deleting is here too. True once saved.
class _EnquiryDialog extends ConsumerStatefulWidget {
  final String venueId;
  final GymEnquiry? enquiry;

  const _EnquiryDialog({required this.venueId, this.enquiry});

  @override
  ConsumerState<_EnquiryDialog> createState() => _EnquiryDialogState();
}

class _EnquiryDialogState extends ConsumerState<_EnquiryDialog> {
  final _form = GlobalKey<FormState>();
  late final EnquiryDetails? _old = widget.enquiry?.details;
  late final _name = TextEditingController(text: _old?.fullName ?? '');
  late final _phone = TextEditingController(text: _old?.phone ?? '');
  late final _interest = TextEditingController(text: _old?.interest ?? '');
  late final _notes = TextEditingController(text: _old?.notes ?? '');
  late EnquirySource _source = _old?.source ?? EnquirySource.walkIn;
  late EnquiryStatus _status = _old?.status ?? EnquiryStatus.open;
  late DateTime _trialFrom = _old?.trialStartsOn ?? BhutanTime.today();
  late int _trialDays = widget.enquiry?.trialDays ?? 3;
  late DateTime? _followUp = _old?.followUpOn;
  bool _saving = false;

  static const _quickTrial = [1, 3, 7, 14];

  bool get _editing => widget.enquiry != null;

  DateTime get _trialTo => DateTime(_trialFrom.year, _trialFrom.month, _trialFrom.day + _trialDays - 1);

  @override
  void dispose() {
    for (final c in [_name, _phone, _interest, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickTrialStart() async {
    final today = BhutanTime.today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _trialFrom,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 1, 12, 31),
    );
    if (picked != null && mounted) setState(() => _trialFrom = picked);
  }

  Future<void> _pickFollowUp() async {
    final today = BhutanTime.today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _followUp ?? today,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 2, 12, 31),
    );
    if (picked != null && mounted) setState(() => _followUp = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final trial = _status == EnquiryStatus.trial || (_old?.trialStartsOn != null);
    final details = EnquiryDetails(
      fullName: _name.text,
      phone: _phone.text,
      source: _source,
      interest: _interest.text,
      status: _status,
      trialStartsOn: trial ? _trialFrom : null,
      trialEndsOn: trial ? _trialTo : null,
      // On a trial: ask how it went on its last day, unless they chose a day.
      followUpOn: _followUp ?? (_status == EnquiryStatus.trial ? _trialTo : null),
      notes: _notes.text,
    );
    setState(() => _saving = true);
    final ok = await runAction(context, () async {
      await ref.read(gymFollowUpRepositoryProvider).saveEnquiry(widget.venueId, details, enquiryId: widget.enquiry?.id);
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    ref.invalidate(gymEnquiriesProvider(widget.venueId));
    showFeedback(context, _editing ? 'Saved' : 'Added to enquiries');
    Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final sure = await confirmAction(
      context,
      title: 'Delete ${widget.enquiry!.fullName}\'s enquiry?',
      message: 'For a mistake or a duplicate. To keep a record that they won\'t join, mark it "Not joining" instead.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!sure || !mounted) return;
    final ok = await runAction(context, () => ref.read(gymFollowUpRepositoryProvider).deleteEnquiry(widget.enquiry!.id));
    if (!ok || !mounted) return;
    ref.invalidate(gymEnquiriesProvider(widget.venueId));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final today = BhutanTime.today();
    final brand = context.brand;
    final statuses = _editing ? EnquiryStatus.values : const [EnquiryStatus.open, EnquiryStatus.trial];
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: brand.ink)),
        );
    return AlertDialog(
      title: Text(_editing ? widget.enquiry!.fullName : 'New enquiry'),
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
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name *', prefixIcon: Icon(Icons.person_outline_rounded)),
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Enter their name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone *', hintText: '17123456', prefixIcon: Icon(Icons.call_outlined)),
                  validator: (v) => Validators.phone(v, required: true),
                ),
                label('How they heard of the gym'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in EnquirySource.values)
                      ChoiceChip(label: Text(s.label), selected: _source == s, onSelected: (_) => setState(() => _source = s)),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _interest,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'What they\'re after', hintText: 'Weight loss, a trainer, evenings...'),
                ),
                label('Where it stands'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in statuses)
                      ChoiceChip(label: Text(s.label), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
                  ],
                ),
                if (_status == EnquiryStatus.trial) ...[
                  label('Free trial'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickTrialStart,
                        icon: const Icon(Icons.event_rounded, size: 18),
                        label: Text(_trialFrom == today ? 'From today' : 'From ${formatDate(_trialFrom)}'),
                      ),
                      for (final n in _quickTrial)
                        ChoiceChip(
                          label: Text(n == 1 ? '1 day' : '$n days'),
                          selected: _trialDays == n,
                          onSelected: (_) => setState(() => _trialDays = n),
                        ),
                    ],
                  ),
                  InfoRow(icon: Icons.flag_outlined, text: 'Free until ${formatDate(_trialTo)} (let them in at the desk).'),
                ],
                label('Follow up'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickFollowUp,
                      icon: const Icon(Icons.alarm_rounded, size: 18),
                      label: Text(_followUp == null ? 'Choose a day' : 'On ${formatDate(_followUp!)}'),
                    ),
                    for (final (text, days) in const [('Tomorrow', 1), ('In 3 days', 3), ('In a week', 7)])
                      ChoiceChip(
                        label: Text(text),
                        selected: _followUp == DateTime(today.year, today.month, today.day + days),
                        onSelected: (_) => setState(() => _followUp = DateTime(today.year, today.month, today.day + days)),
                      ),
                    if (_followUp != null)
                      IconButton(
                        tooltip: 'No follow-up',
                        onPressed: () => setState(() => _followUp = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notes,
                  maxLength: 1000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Notes', hintText: 'What they asked, prices quoted...'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (_editing)
          TextButton(
            onPressed: _saving ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: brand.danger),
            child: const Text('Delete'),
          ),
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_editing ? 'Save' : 'Add')),
      ],
    );
  }
}
