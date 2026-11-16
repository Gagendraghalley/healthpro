import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_repository.dart';
import '../data/trainers.dart';
import '../gym_routes.dart';
import '../widgets/trainer_widgets.dart';

// ─── The trainer's own ──────────────────────────────────────────────────────

/// A trainer's own page: their profile and certificates, each gym they
/// train at (or asked to: whether it verified them), their times there,
/// their attendance there gym by gym, their members there, and their
/// reviews. A verified trainer is public whether they applied themselves or
/// were added by a gym.
class TrainerHomeScreen extends ConsumerWidget {
  const TrainerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final training = ref.watch(myTrainingProvider);
    return AppPage(
      title: training.valueOrNull?.joinedPublicly == true ? 'Trainer profile' : 'My training',
      body: AsyncValueView<MyTraining>(
        value: training,
        onRetry: () => ref.invalidate(myTrainingProvider),
        data: (mine) {
          final profile = mine.profile;
          if (profile == null) {
            return EmptyState(
              icon: Icons.sports_rounded,
              title: 'No trainer profile yet',
              message: 'Open a gym\'s public page and apply as a trainer to set up your profile.',
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(myTrainingProvider.future),
            child: ListView(
              padding: pagePadding(context),
              children: [
                if (!mine.joinedPublicly)
                  SectionCard(
                    padding: const EdgeInsets.all(14),
                    child: const InfoRow(
                      icon: Icons.lock_outline_rounded,
                      text: 'Your trainer profile becomes public when a gym verifies you. It is not listed while you only have pending requests.',
                    ),
                  ),
                _ProfileHeader(profile: profile, publicProfile: mine.joinedPublicly),
                const SizedBox(height: 16),
                _TrainerSummary(
                  activeGyms: mine.gyms.where((g) => g.status == TrainerStatus.verified).length,
                  pendingGyms: mine.gyms.where((g) => g.status == TrainerStatus.pending).length,
                  attendanceDays: mine.gyms.fold<int>(
                    0,
                    (sum, g) => sum +
                        (g.status == TrainerStatus.verified
                            ? trainerAttendanceDaysLast30(g.attendance, BhutanTime.today())
                            : 0),
                  ),
                  members: mine.gyms
                      .where((g) => g.status == TrainerStatus.verified)
                      .fold<int>(0, (sum, g) => sum + g.members.length),
                ),
                _Certificates(certificates: mine.certificates, canEdit: mine.joinedPublicly),
                SectionTitle(
                  'Your gyms',
                  trailing: TextButton.icon(
                    onPressed: () => _askGym(context, ref, mine),
                    icon: const Icon(Icons.add_business_rounded, size: 18),
                    label: const Text('Train at a gym'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('Schedules, attendance and member assignments for each gym.',
                      style: TextStyle(color: context.brand.muted)),
                ),
                if (mine.gyms.isEmpty)
                  const FormHint('Ask the gyms you work at to verify you. Each gym checks your certificates itself.')
                else
                  ResponsiveGrid(
                    minItemWidth: 340,
                    maxColumns: 3,
                    equalHeight: false,
                    children: [for (final g in mine.gyms) _MyGymCard(gym: g)],
                  ),
                SectionTitle('Reviews (${mine.reviews.length})'),
                if (mine.reviews.isEmpty)
                  const FormHint('Reviews from members you have trained with will appear here.')
                else
                  _ReviewList(reviews: mine.reviews),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _askGym(BuildContext context, WidgetRef ref, MyTraining mine) async {
    const query = (type: gymVenueType, dzongkhag: null);
    final gyms = await ref.read(publicVenuesProvider(query).future);
    if (!context.mounted) return;
    final mineIds = {for (final g in mine.gyms) g.venueId};
    final choices = gyms.where((g) => !mineIds.contains(g.id)).toList();
    String? chosen;
    final message = TextEditingController();
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Train at a gym'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('The gym checks your profile and certificates, then verifies you; you\'re told either way.'),
                const SizedBox(height: 14),
                SearchableDropdown<String>(
                  value: chosen,
                  decoration: const InputDecoration(labelText: 'Gym *'),
                  options: [for (final g in choices) DropdownOption(g.id, '${g.name} · ${g.place}')],
                  onChanged: (v) => setState(() => chosen = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: message,
                  maxLines: 3,
                  minLines: 1,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'A note for them (optional)', hintText: 'e.g. I train there on Mondays'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: chosen == null ? null : () => Navigator.pop(context, true), child: const Text('Ask them')),
          ],
        ),
      ),
    );
    final note = message.text;
    message.dispose();
    if (ok != true || chosen == null || !context.mounted) return;
    final sent = await runAction(context, () => ref.read(gymRepositoryProvider).requestGym(chosen!, message: note),
        success: 'Asked. The gym will let you know.');
    if (sent) ref.invalidate(myTrainingProvider);
  }
}

class _ProfileHeader extends StatelessWidget {
  final TrainerProfile profile;
  final bool publicProfile;

  const _ProfileHeader({required this.profile, required this.publicProfile});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(
              label: publicProfile ? 'Public trainer profile' : 'Private trainer profile',
              color: publicProfile ? brand.success : brand.muted,
              icon: publicProfile ? Icons.public_rounded : Icons.lock_outline_rounded,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TrainerAvatar(name: profile.name, photoUrl: profile.photoUrl, size: 72),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.name, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    if (profile.headline != null) Text(profile.headline!, style: TextStyle(color: brand.body)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (profile.ratingCount > 0) ...[
                        RatingStars(rating: profile.ratingAverage!),
                        Text('${profile.ratingAverage!.toStringAsFixed(1)} (${profile.ratingCount})'),
                      ],
                      if (profile.experienceYears != null)
                        Text('${profile.experienceYears} years', style: TextStyle(color: brand.muted)),
                    ]),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (publicProfile)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => context.go(GymRoutes.trainerProfile),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit profile'),
                ),
                OutlinedButton(
                  onPressed: () => context.push(GymRoutes.trainerFor(profile.userId)),
                  child: const Text('See my public profile'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TrainerSummary extends StatelessWidget {
  final int activeGyms;
  final int pendingGyms;
  final int attendanceDays;
  final int members;

  const _TrainerSummary({
    required this.activeGyms,
    required this.pendingGyms,
    required this.attendanceDays,
    required this.members,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => ConsoleCells(
          columns: constraints.maxWidth >= 900 ? 4 : 2,
          children: staggered([
            ConsoleKpi(
              icon: Icons.fitness_center_rounded,
              color: BrandColors.orange,
              value: '$activeGyms',
              count: activeGyms,
              label: 'Active gyms',
              note: pendingGyms == 0 ? 'No requests waiting' : '$pendingGyms requests waiting',
            ),
            ConsoleKpi(
              icon: Icons.event_available_rounded,
              color: BrandColors.blue,
              value: '$attendanceDays',
              count: attendanceDays,
              label: 'Attendance days',
              note: 'Across active gyms · last 30 days',
            ),
            ConsoleKpi(
              icon: Icons.groups_rounded,
              color: BrandColors.green,
              value: '$members',
              count: members,
              label: 'Current members',
              note: 'Across active gyms',
            ),
            ConsoleKpi(
              icon: Icons.workspace_premium_rounded,
              color: BrandColors.amber,
              value: '$pendingGyms',
              count: pendingGyms,
              label: 'Pending requests',
              note: pendingGyms == 0 ? 'All caught up' : 'Waiting for gym review',
            ),
          ]),
        ),
      );
}

class _Certificates extends ConsumerWidget {
  final List<TrainerCertificate> certificates;
  final bool canEdit;

  const _Certificates({required this.certificates, required this.canEdit});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final issuer = TextEditingController();
    DateTime? issued;
    ({Uint8List bytes, String contentType})? file;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add a certificate'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Certificate *', hintText: 'e.g. CPR and first aid')),
                const SizedBox(height: 12),
                TextField(controller: issuer, decoration: const InputDecoration(labelText: 'Given by', hintText: 'e.g. Bhutan Red Cross')),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final now = BhutanTime.today();
                    final d = await showDatePicker(context: context, firstDate: DateTime(1950), lastDate: now, initialDate: issued ?? now);
                    if (d != null) setState(() => issued = d);
                  },
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(issued == null ? 'When it was given (optional)' : formatDate(issued!)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final photo = await pickPhoto(context);
                    if (photo != null) setState(() => file = (bytes: photo.bytes, contentType: photo.contentType));
                  },
                  icon: Icon(file == null ? Icons.upload_file_rounded : Icons.check_circle_rounded, size: 18),
                  label: Text(file == null ? 'A photo of it (for the gyms to check)' : 'Photo added'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    final name = title.text, by = issuer.text;
    title.dispose();
    issuer.dispose();
    if (ok != true || !context.mounted) return;
    final repo = ref.read(gymRepositoryProvider);
    final done = await runAction(context, () async {
      final url = file == null ? null : await repo.uploadTrainerFile(file!.bytes, file!.contentType);
      await repo.addCertificate(title: name, issuer: by, issuedOn: issued, fileUrl: url);
    }, success: 'Certificate added');
    if (done) ref.invalidate(myTrainingProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Certificates',
          trailing: canEdit ? TextButton.icon(
            onPressed: () => _add(context, ref),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add'),
          ) : null,
        ),
        if (certificates.isEmpty)
          FormHint(canEdit
              ? 'Add your certificates: gyms check them before they verify you, and members see them.'
              : 'Your gym has not added any certificates yet.')
        else
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final c in certificates)
                  ListTile(
                    leading: Icon(Icons.workspace_premium_rounded, color: brand.accent),
                    title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([if (c.issuer != null) c.issuer!, if (c.issuedOn != null) formatDate(c.issuedOn!)].join(' · ')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (c.fileUrl != null)
                          IconButton(
                            tooltip: 'See it',
                            icon: const Icon(Icons.open_in_new_rounded),
                            onPressed: () => openExternal(context, Uri.parse(c.fileUrl!)),
                          ),
                        if (canEdit)
                          IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              final ok = await runAction(context, () => ref.read(gymRepositoryProvider).removeCertificate(c.id));
                              if (ok) ref.invalidate(myTrainingProvider);
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One of the trainer's gyms: where they stand, their times there,
/// attendance there, members there.
class _MyGymCard extends ConsumerWidget {
  final MyTrainerGym gym;

  const _MyGymCard({required this.gym});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final recentAttendance = uniqueTrainerAttendanceEntries(gym.attendance);
    final color = switch (gym.status) {
      TrainerStatus.verified => brand.success,
      TrainerStatus.pending => brand.warning,
      TrainerStatus.inactive => brand.muted,
      _ => brand.danger,
    };
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(gym.venueName, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    if (gym.place.isNotEmpty) Text(gym.place, style: TextStyle(color: brand.muted)),
                  ],
                ),
              ),
              StatusChip(label: gym.status.label, color: color),
            ],
          ),
          if (gym.decisionNote != null) ...[
            const SizedBox(height: 8),
            Text('"${gym.decisionNote}"', style: TextStyle(color: brand.body, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 12),
          Text(gym.status == TrainerStatus.inactive ? 'Schedule at this gym' : 'Your times',
              style: TextStyle(color: brand.muted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (gym.status == TrainerStatus.inactive)
            Text('This gym made your trainer role inactive. Contact them if you would like to return.',
                style: TextStyle(color: brand.muted))
          else
            WeekSlotsView(slots: gym.slots),
          if (gym.status != TrainerStatus.rejected && gym.status != TrainerStatus.inactive)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => editTrainerSlots(context, ref, gym),
                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                label: const Text('Change times'),
              ),
            ),
          if (gym.status == TrainerStatus.verified) ...[
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                    child: _Stat(
                        value: '${trainerAttendanceDaysLast30(gym.attendance, BhutanTime.today())}',
                        label: 'attendance days · last 30')),
                Expanded(child: _Stat(value: '${gym.members.length}', label: gym.members.length == 1 ? 'member' : 'members')),
              ],
            ),
            if (recentAttendance.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Recent attendance', style: TextStyle(color: brand.muted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in recentAttendance.take(7))
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.event_available_rounded, size: 16),
                      label: Text('${formatShortDate(BhutanTime.toBhutan(a))} · ${formatTime(a)}'),
                    ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 10),
              Text('No attendance recorded yet.', style: TextStyle(color: brand.muted, fontSize: 12.5)),
            ],
            if (gym.members.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Your members here', style: TextStyle(color: brand.muted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final member in gym.members)
                    Chip(
                      avatar: const Icon(Icons.person_outline_rounded, size: 16),
                      visualDensity: VisualDensity.compact,
                      label: Text(member.name),
                    ),
                ],
              ),
            ],
          ],
          const SizedBox(height: 6),
          if (gym.status != TrainerStatus.inactive)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                final sure = await confirmAction(
                  context,
                  title: gym.status == TrainerStatus.pending ? 'Take your request back?' : 'Stop training at ${gym.venueName}?',
                  message: gym.status == TrainerStatus.pending
                      ? 'Your request will be withdrawn and the gym will be notified.'
                      : 'You will be made inactive at this gym. Your public listing, schedule, and member assignments here will be removed. The gym and your assigned members will be notified.',
                  confirmLabel: gym.status == TrainerStatus.pending ? 'Take it back' : 'Stop training there',
                  destructive: true,
                );
                if (!sure || !context.mounted) return;
                final ok = await runAction(context, () => ref.read(gymRepositoryProvider).leaveGym(gym.venueId));
                if (ok) ref.invalidate(myTrainingProvider);
                },
                child: Text(gym.status == TrainerStatus.pending ? 'Take my request back' : 'Stop training here',
                    style: TextStyle(color: brand.danger)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;

  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(color: context.brand.muted, fontSize: 12.5)),
        ],
      );
}

/// A week of times to choose: a day and a from–to time each. Returns them,
/// or null when cancelled.
Future<List<TrainerSlot>?> pickTrainerSlots(
  BuildContext context, {
  required String title,
  required List<TrainerSlot> initial,
  String note = "Add one row for each day and time. They can't overlap your times at other gyms.",
  String saveLabel = 'Save times',
}) {
  var slots = [...initial];
  return showAppDialog<List<TrainerSlot>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> pick(int i, {required bool end}) async {
          final s = slots[i];
          final current = end ? s.ends : s.starts;
          final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: current ~/ 60 % 24, minute: current % 60));
          if (t == null) return;
          final m = t.hour * 60 + t.minute;
          setState(() => slots[i] = end
              ? TrainerSlot(weekday: s.weekday, starts: s.starts, ends: m)
              : TrainerSlot(weekday: s.weekday, starts: m, ends: s.ends));
        }

        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(note),
                  const SizedBox(height: 12),
                  for (final (i, s) in slots.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          DropdownButton<int>(
                            value: s.weekday,
                            items: [for (var d = 1; d <= 7; d++) DropdownMenuItem(value: d, child: Text(OpeningHours.fullNames[d - 1]))],
                            onChanged: (d) => setState(() => slots[i] = TrainerSlot(weekday: d!, starts: s.starts, ends: s.ends)),
                          ),
                          ActionChip(label: Text(OpenPeriod.label(s.starts)), onPressed: () => pick(i, end: false)),
                          const Text('–'),
                          ActionChip(label: Text(OpenPeriod.label(s.ends)), onPressed: () => pick(i, end: true)),
                          IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() => slots.removeAt(i)),
                          ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => slots.add(
                          TrainerSlot(weekday: slots.isEmpty ? 1 : slots.last.weekday, starts: 660, ends: 720))),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add another day or time'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, slots), child: Text(saveLabel)),
          ],
        );
      },
    ),
  );
}

/// Changes the trainer's week at [gym].
Future<void> editTrainerSlots(BuildContext context, WidgetRef ref, MyTrainerGym gym) async {
  final saved = await pickTrainerSlots(context, title: 'Your times at ${gym.venueName}', initial: gym.slots);
  if (saved == null || !context.mounted) return;
  final ok = await runAction(context, () => ref.read(gymRepositoryProvider).saveSlots(gym.venueId, saved), success: 'Times saved');
  if (ok) ref.invalidate(myTrainingProvider);
}

/// Making or changing a trainer profile: name, what they do, about them,
/// specialties, experience, photo. From a gym's page ([thenAskGymId]),
/// saving it also asks that gym to let them train there.
class TrainerProfileScreen extends ConsumerWidget {
  final String? thenAskGymId;

  const TrainerProfileScreen({super.key, this.thenAskGymId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).valueOrNull;
    return AsyncValueView<MyTraining>(
      value: ref.watch(myTrainingProvider),
      onRetry: () => ref.invalidate(myTrainingProvider),
      data: (mine) {
        if (thenAskGymId == null && !mine.joinedPublicly) {
          return const EmptyState(
            icon: Icons.sports_rounded,
            title: 'Apply from a gym’s public page',
            message: 'Trainer profiles are for people who apply to a gym as a trainer.',
          );
        }
        return _ProfileForm(
          profile: mine.profile ?? TrainerProfile(userId: '', name: profile?.fullName ?? ''),
          isNew: mine.profile == null,
          askGym: thenAskGymId == null || mine.gyms.any((g) => g.venueId == thenAskGymId && g.status != TrainerStatus.rejected)
              ? null
              : ref.watch(venueProvider(thenAskGymId!)).valueOrNull,
        );
      },
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  final TrainerProfile profile;
  final bool isNew;

  /// The gym they're applying to train at, asked when they save.
  final Venue? askGym;

  const _ProfileForm({required this.profile, required this.isNew, this.askGym});

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.name);
  late final _headline = TextEditingController(text: widget.profile.headline ?? '');
  late final _bio = TextEditingController(text: widget.profile.bio ?? '');
  late final _years = TextEditingController(text: widget.profile.experienceYears?.toString() ?? '');
  final _specialty = TextEditingController();
  final _note = TextEditingController();
  late List<String> _specialties = [...widget.profile.specialties];
  late String? _photo = widget.profile.photoUrl;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _headline, _bio, _years, _specialty, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addSpecialty() {
    final s = _specialty.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (s.isEmpty || s.length > 40 || _specialties.length >= 15 || _specialties.any((x) => x.toLowerCase() == s.toLowerCase())) return;
    setState(() => _specialties = [..._specialties, s]);
    _specialty.clear();
  }

  Future<void> _uploadPhoto() async {
    final photo = await pickPhoto(context);
    if (photo == null || !mounted) return;
    setState(() => _busy = true);
    await runAction(context, () async {
      final url = await ref.read(gymRepositoryProvider).uploadTrainerFile(photo.bytes, photo.contentType);
      if (mounted) setState(() => _photo = url);
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final gym = widget.askGym;
    final repo = ref.read(gymRepositoryProvider);
    final ok = await runAction(
      context,
      () async {
        await repo.saveTrainerProfile(TrainerProfile(
          userId: widget.profile.userId,
          name: _name.text,
          headline: _headline.text,
          bio: _bio.text,
          specialties: _specialties,
          experienceYears: int.tryParse(_years.text.trim()),
          photoUrl: _photo,
        ));
        if (gym != null) await repo.requestGym(gym.id, message: _note.text);
      },
      success: gym != null
          ? 'Sent to ${gym.name}. Add your certificates and times: they check them before they verify you.'
          : widget.isNew
              ? 'You\'re a trainer on Health Pro. Now ask your gyms to verify you.'
              : 'Saved',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    ref.invalidate(myTrainingProvider);
    context.go(GymRoutes.trainerHome);
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: widget.askGym != null
          ? 'Apply to train at ${widget.askGym!.name}'
          : widget.isNew
              ? 'Become a trainer'
              : 'Your trainer profile',
      body: Form(
        key: _form,
        child: ListView(
          padding: pagePadding(context),
          children: [
            if (widget.askGym != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: InfoRow(
                  icon: Icons.sports_rounded,
                  text: 'This is your trainer profile on Health Pro: one for every gym you train at. '
                      '${widget.askGym!.name} checks it and your certificates, then verifies you; members can then choose you.',
                ),
              ),
            ResponsiveColumns(
              spacing: 32,
              first: [
                Row(
                  children: [
                    TrainerAvatar(name: _name.text, photoUrl: _photo, size: 80),
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _uploadPhoto,
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: Text(_photo == null ? 'Add a photo' : 'Change photo'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Your name, as members see it *'),
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your name' : null,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _headline,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'What you do', hintText: 'e.g. Strength and conditioning coach'),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _years,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Years of experience'),
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) return null;
                    final n = int.tryParse(v!.trim());
                    return n == null || n < 0 || n > 60 ? 'Enter 0 to 60' : null;
                  },
                ),
              ],
              second: [
                const SizedBox(height: 14),
                TextFormField(
                  controller: _bio,
                  maxLines: 5,
                  minLines: 3,
                  maxLength: 2000,
                  decoration: const InputDecoration(labelText: 'About you', hintText: 'How you train people, what you\'re good at'),
                ),
                const SizedBox(height: 6),
                Text('Specialties', style: context.text.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in _specialties)
                      InputChip(label: Text(s), onDeleted: () => setState(() => _specialties = _specialties.where((x) => x != s).toList())),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _specialty,
                        decoration: const InputDecoration(labelText: 'Add a specialty', hintText: 'e.g. Weight loss, Yoga'),
                        onSubmitted: (_) => _addSpecialty(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: _addSpecialty, child: const Text('Add')),
                  ],
                ),
                if (widget.askGym != null) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _note,
                    maxLines: 3,
                    minLines: 1,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: 'A note for ${widget.askGym!.name} (optional)',
                      hintText: 'e.g. I can train mornings and weekends',
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(widget.askGym != null
                      ? 'Send my application'
                      : widget.isNew
                          ? 'Make my trainer profile'
                          : 'Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewList extends StatelessWidget {
  final List<TrainerReview> reviews;

  const _ReviewList({required this.reviews});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return SectionCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final r in reviews)
            ListTile(
              title: Row(children: [
                RatingStars(rating: r.rating.toDouble()),
                const SizedBox(width: 8),
                Flexible(child: Text(r.reviewerName, overflow: TextOverflow.ellipsis)),
              ]),
              subtitle: r.comment == null ? null : Text(r.comment!, style: TextStyle(color: brand.body)),
              trailing: Text(timeAgo(r.createdAt), style: TextStyle(color: brand.muted, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

// ─── Everyone: a trainer's public profile ──────────────────────────────────

/// A trainer's public profile: who they are, their certificates, the gyms
/// that verified them, their times (seen from a gym, [venueId], the others
/// are only Not available), and members' reviews; those who trained with
/// them write one.
class TrainerPublicScreen extends ConsumerWidget {
  final String trainerId;
  final String? venueId;

  const TrainerPublicScreen({super.key, required this.trainerId, this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(trainerProfileProvider(trainerId));
    return AppPage(
      title: profile.valueOrNull?.name ?? 'Trainer',
      body: AsyncValueView<TrainerProfile?>(
        value: profile,
        onRetry: () => ref.invalidate(trainerProfileProvider(trainerId)),
        data: (p) {
          if (p == null) return const EmptyState(icon: Icons.person_search_rounded, title: 'This trainer isn\'t on Health Pro');
          final brand = context.brand;
          final certificates = ref.watch(trainerCertificatesProvider(trainerId)).valueOrNull ?? const <TrainerCertificate>[];
          final gyms = ref.watch(trainerGymsProvider(trainerId)).valueOrNull ?? const [];
          final timings = ref.watch(trainerTimingsProvider((trainerId: trainerId, venueId: venueId))).valueOrNull ?? const <TrainerSlot>[];
          final reviews = ref.watch(trainerReviewsProvider(trainerId)).valueOrNull ?? const <TrainerReview>[];
          final canReview = ref.watch(canReviewTrainerProvider(trainerId)).valueOrNull ?? false;
          return ListView(
            padding: pagePadding(context),
            children: [
              ResponsiveColumns(
                flex: (3, 2),
                first: [
                  Row(
                    children: [
                      TrainerAvatar(name: p.name, photoUrl: p.photoUrl, size: 88),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                            if (p.headline != null) Text(p.headline!, style: TextStyle(color: brand.body)),
                            const SizedBox(height: 4),
                            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              if (p.ratingCount > 0) ...[
                                RatingStars(rating: p.ratingAverage!),
                                Text('${p.ratingAverage!.toStringAsFixed(1)} · ${p.ratingCount} reviews'),
                              ],
                              if (p.experienceYears != null)
                                Text('${p.experienceYears} years\' experience', style: TextStyle(color: brand.muted)),
                            ]),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (p.specialties.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(spacing: 8, runSpacing: 8, children: [for (final s in p.specialties) Chip(label: Text(s))]),
                  ],
                  if (p.bio != null) ...[const SectionTitle('About'), Text(p.bio!)],
                  const SectionTitle('Certificates'),
                  if (certificates.isEmpty)
                    const FormHint('None added yet.')
                  else
                    SectionCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          for (final c in certificates)
                            ListTile(
                              leading: Icon(Icons.workspace_premium_rounded, color: brand.accent),
                              title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                  [if (c.issuer != null) c.issuer!, if (c.issuedOn != null) '${c.issuedOn!.year}'].join(' · ')),
                              trailing: c.fileUrl == null ? null : const Icon(Icons.open_in_new_rounded),
                              onTap: c.fileUrl == null ? null : () => openExternal(context, Uri.parse(c.fileUrl!)),
                            ),
                        ],
                      ),
                    ),
                  SectionTitle(
                    'Reviews',
                    trailing: canReview
                        ? TextButton.icon(
                            onPressed: () => _review(context, ref, p, reviews),
                            icon: const Icon(Icons.rate_review_outlined, size: 18),
                            label: const Text('Write a review'),
                          )
                        : null,
                  ),
                  if (reviews.isEmpty)
                    const FormHint('No reviews yet. Members who train with them can write one.')
                  else
                    _ReviewList(reviews: reviews),
                ],
                second: [
                  const SectionTitle('Verified at'),
                  if (gyms.isEmpty)
                    const FormHint('No gyms yet.')
                  else
                    SectionCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          for (final g in gyms)
                            ListTile(
                              leading: Icon(Icons.verified_rounded, color: brand.success),
                              title: Text(g.name),
                              subtitle: Text(g.place),
                              onTap: () => context.push(GymRoutes.gymFor(g.id)),
                            ),
                        ],
                      ),
                    ),
                  const SectionTitle('Times'),
                  SectionCard(padding: const EdgeInsets.all(14), child: WeekSlotsView(slots: timings, showGym: venueId == null)),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _review(BuildContext context, WidgetRef ref, TrainerProfile p, List<TrainerReview> reviews) async {
    final uid = ref.read(currentUserIdProvider);
    final mine = reviews.where((r) => r.userId == uid).firstOrNull;
    var rating = mine?.rating ?? 5;
    final comment = TextEditingController(text: mine?.comment ?? '');
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Review ${p.name}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RatingPicker(value: rating, onChanged: (v) => setState(() => rating = v)),
                const SizedBox(height: 12),
                TextField(
                  controller: comment,
                  maxLines: 4,
                  minLines: 2,
                  maxLength: 1000,
                  decoration: const InputDecoration(labelText: 'What was training with them like?'),
                ),
              ],
            ),
          ),
          actions: [
            if (mine != null)
              TextButton(
                onPressed: () async {
                  await ref.read(gymRepositoryProvider).deleteTrainerReview(p.userId);
                  if (context.mounted) Navigator.pop(context, false);
                  ref.invalidate(trainerReviewsProvider(p.userId));
                  ref.invalidate(trainerProfileProvider(p.userId));
                },
                child: const Text('Remove my review'),
              ),
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Post')),
          ],
        ),
      ),
    );
    final text = comment.text;
    comment.dispose();
    if (ok != true || !context.mounted) return;
    final done = await runAction(context, () => ref.read(gymRepositoryProvider).saveTrainerReview(p.userId, rating, text),
        success: 'Thanks for your review');
    if (done) {
      ref.invalidate(trainerReviewsProvider(p.userId));
      ref.invalidate(trainerProfileProvider(p.userId));
    }
  }
}
