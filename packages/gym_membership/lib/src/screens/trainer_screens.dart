import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_repository.dart';
import '../data/trainers.dart';
import '../gym_routes.dart';
import '../widgets/gym_public_widgets.dart';
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
          final brand = context.brand;
          final active = mine.gyms.where((g) => g.status == TrainerStatus.verified).toList();
          final pending = mine.gyms.where((g) => g.status == TrainerStatus.pending).length;
          final attendanceDays =
              active.fold<int>(0, (sum, g) => sum + trainerAttendanceDaysLast30(g.attendance, BhutanTime.today()));
          final members = active.fold<int>(0, (sum, g) => sum + g.members.length);
          // Who they are, on navy: public or not yet, and the way to change
          // it or see it as members do.
          final hero = TrainerProfileHero(
            trainer: profile,
            gyms: active.length,
            badge: mine.joinedPublicly
                ? (icon: Icons.public_rounded, text: 'PUBLIC PROFILE')
                : (icon: Icons.lock_outline_rounded, text: 'PRIVATE PROFILE'),
            actions: [
              if (mine.joinedPublicly) ...[
                HeroPillButton(
                  label: 'Edit profile',
                  icon: Icons.edit_outlined,
                  filled: true,
                  onPressed: () => context.go(GymRoutes.trainerProfile),
                ),
                HeroPillButton(
                  label: 'See my public profile',
                  icon: Icons.visibility_outlined,
                  onPressed: () => context.push(GymRoutes.trainerFor(profile.userId)),
                ),
              ],
            ],
          );
          final notice = mine.joinedPublicly
              ? null
              : Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: brand.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: brand.warning.withValues(alpha: 0.28)),
                  ),
                  child: Row(
                    children: [
                      PopIn(
                        delay: Motion.stagger * 4,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: brand.warning.withValues(alpha: 0.16)),
                          child: Icon(Icons.lock_outline_rounded, size: 20, color: brand.readable(brand.warning)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Your trainer profile becomes public when a gym verifies you. It is not listed while you only have pending requests.',
                          style: TextStyle(fontSize: 14, height: 1.5, color: brand.body),
                        ),
                      ),
                    ],
                  ),
                );
          final stats = GymStatTiles(
            stats: [
              (
                icon: Icons.fitness_center_rounded,
                color: BrandColors.orange,
                value: active.length,
                label: 'Active gyms',
                note: switch (pending) {
                  0 => 'No requests waiting',
                  1 => '1 request waiting',
                  _ => '$pending requests waiting',
                },
              ),
              (
                icon: Icons.event_available_rounded,
                color: BrandColors.blue,
                value: attendanceDays,
                label: 'Attendance days',
                note: 'Across active gyms · last 30 days',
              ),
              (icon: Icons.groups_rounded, color: BrandColors.green, value: members, label: 'Current members', note: 'Across active gyms'),
              (
                icon: Icons.workspace_premium_rounded,
                color: BrandColors.amber,
                value: pending,
                label: 'Pending requests',
                note: pending == 0 ? 'All caught up' : 'Waiting for gym review',
              ),
            ],
          );
          final gymsHead = Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 16,
            runSpacing: 12,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your gyms', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: brand.ink)),
                  const SizedBox(height: 6),
                  // An orange rule growing under the heading.
                  GymRevealItem(
                    order: 1,
                    grow: true,
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [brand.highlight, brand.highlight.withValues(alpha: 0.3)]),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Schedules, attendance and member assignments for each gym.',
                    style: TextStyle(fontSize: 14, color: brand.muted),
                  ),
                ],
              ),
              Pressable(
                child: FilledButton.tonalIcon(
                  onPressed: () => _askGym(context, ref, mine),
                  icon: const Icon(Icons.add_business_rounded, size: 18),
                  label: const Text('Train at a gym'),
                ),
              ),
            ],
          );
          final certificates = _Certificates(certificates: mine.certificates, canEdit: mine.joinedPublicly);
          final reviews = GymSection(
            icon: Icons.reviews_outlined,
            title: 'Reviews (${mine.reviews.length})',
            child: TrainerReviewsList(
              reviews: mine.reviews,
              average: profile.ratingAverage,
              count: profile.ratingCount,
              empty: 'Reviews from members you have trained with will appear here.',
            ),
          );
          return RefreshIndicator(
            onRefresh: () => ref.refresh(myTrainingProvider.future),
            child: ListView(
              padding: pagePadding(context),
              children: [
                FadeSlideIn(offset: 14, child: hero),
                if (notice != null) ...[const SizedBox(height: 16), FadeSlideIn(delay: Motion.stagger * 2, child: notice)],
                const SizedBox(height: 18),
                GymReveal(delay: Motion.stagger * 2, child: stats),
                const SizedBox(height: 30),
                GymReveal(child: gymsHead),
                const SizedBox(height: 16),
                if (mine.gyms.isEmpty)
                  GymReveal(
                    child: GymSection(
                      icon: Icons.add_business_rounded,
                      title: 'No gyms yet',
                      child: Text(
                        'Ask the gyms you work at to verify you. Each gym checks your certificates itself.',
                        style: TextStyle(fontSize: 14.5, height: 1.6, color: brand.body),
                      ),
                    ),
                  )
                else
                  // Rising into place as they scroll into view, a row's cards
                  // one after another.
                  ResponsiveGrid(
                    minItemWidth: 360,
                    maxColumns: 3,
                    spacing: 18,
                    runSpacing: 18,
                    equalHeight: false,
                    children: [
                      for (final (i, g) in mine.gyms.indexed)
                        GymReveal(key: ValueKey(g.venueId), delay: Motion.stagger * (i % 3), child: _MyGymCard(gym: g)),
                    ],
                  ),
                const SizedBox(height: 30),
                // Side by side on a computer.
                LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth >= 900
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: GymReveal(child: certificates)),
                            const SizedBox(width: 22),
                            Expanded(child: GymReveal(delay: Motion.stagger, child: reviews)),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [GymReveal(child: certificates), const SizedBox(height: 18), GymReveal(child: reviews)],
                        ),
                ),
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
    return GymSection(
      icon: Icons.workspace_premium_outlined,
      title: 'Certificates',
      trailing: canEdit
          ? TextButton.icon(
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
            )
          : null,
      child: TrainerCertificatesList(
        certificates: certificates,
        empty: canEdit
            ? 'Add your certificates: gyms check them before they verify you, and members see them.'
            : 'Your gym has not added any certificates yet.',
        onRemove: canEdit
            ? (c) async {
                final ok = await runAction(context, () => ref.read(gymRepositoryProvider).removeCertificate(c.id));
                if (ok) ref.invalidate(myTrainingProvider);
              }
            : null,
      ),
    );
  }
}

/// One of the trainer's gyms: where they stand, their times there,
/// attendance there, members there; changing their times and leaving.
class _MyGymCard extends ConsumerWidget {
  final MyTrainerGym gym;

  const _MyGymCard({required this.gym});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = gym.status == TrainerStatus.pending;
    return TrainerGymCard(
      gym: gym,
      onChangeTimes: gym.status != TrainerStatus.rejected && gym.status != TrainerStatus.inactive
          ? () => editTrainerSlots(context, ref, gym)
          : null,
      onLeave: gym.status == TrainerStatus.inactive
          ? null
          : () async {
              final sure = await confirmAction(
                context,
                title: pending ? 'Take your request back?' : 'Stop training at ${gym.venueName}?',
                message: pending
                    ? 'Your request will be withdrawn and the gym will be notified.'
                    : 'You will be made inactive at this gym. Your public listing, schedule, and member assignments here will be removed. The gym and your assigned members will be notified.',
                confirmLabel: pending ? 'Take it back' : 'Stop training there',
                destructive: true,
              );
              if (!sure || !context.mounted) return;
              final ok = await runAction(context, () => ref.read(gymRepositoryProvider).leaveGym(gym.venueId));
              if (ok) ref.invalidate(myTrainingProvider);
            },
    );
  }
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
    // Opened straight (after a refresh or from a link) there's nothing to go
    // back to: back leads to the gym it was seen from, or the list of gyms.
    // In the app's frame on a phone the bar keeps its menu button instead.
    final canGoBack = ModalRoute.of(context)?.canPop ?? false;
    final menu = AppShellScope.maybeOf(context)?.openMenu != null;
    return AppPage(
      title: profile.valueOrNull?.name ?? 'Trainer',
      leading: canGoBack || menu
          ? null
          : IconButton(
              tooltip: venueId == null ? 'All gyms' : 'Back to the gym',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.go(venueId == null ? GymRoutes.gyms : GymRoutes.gymFor(venueId!)),
            ),
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
          final about = p.bio == null
              ? null
              : GymSection(
                  icon: Icons.person_outline_rounded,
                  title: 'About',
                  child: Text(p.bio!, style: TextStyle(fontSize: 15, height: 1.7, color: brand.body)),
                );
          final certs = GymSection(
            icon: Icons.workspace_premium_outlined,
            title: 'Certificates',
            child: TrainerCertificatesList(certificates: certificates),
          );
          final verified = GymSection(
            icon: Icons.verified_outlined,
            title: 'Verified at',
            child: TrainerGymsList(gyms: gyms, onOpen: (id) => context.push(GymRoutes.gymFor(id))),
          );
          final times = GymSection(
            icon: Icons.schedule_rounded,
            title: 'Times',
            child: TrainerWeek(slots: timings, showGym: venueId == null),
          );
          final reviewsPart = GymSection(
            icon: Icons.reviews_outlined,
            title: 'Reviews',
            trailing: canReview
                ? TextButton.icon(
                    onPressed: () => _review(context, ref, p, reviews),
                    icon: const Icon(Icons.rate_review_outlined, size: 18),
                    label: const Text('Write a review'),
                  )
                : null,
            child: TrainerReviewsList(reviews: reviews, average: p.ratingAverage, count: p.ratingCount),
          );
          return ListView(
            padding: pagePadding(context),
            children: [
              FadeSlideIn(offset: 14, child: TrainerProfileHero(trainer: p, gyms: gyms.length)),
              const SizedBox(height: 18),
              // Side by side on a computer: who they are on the left, where
              // and when they train on the right. One column otherwise.
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 900) return _stack([about, certs, verified, times, reviewsPart]);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _stack([about, certs, reviewsPart])),
                      const SizedBox(width: 22),
                      Expanded(flex: 2, child: _stack([verified, times], after: Motion.stagger)),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// [parts] one under another (those there are), each rising into place as
  /// it scrolls into view: the first few in turn, [after] the page opens.
  static Widget _stack(List<Widget?> parts, {Duration after = Duration.zero}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, part) in parts.nonNulls.indexed) ...[
          if (i > 0) const SizedBox(height: 18),
          GymReveal(delay: after + Motion.stagger * (2 + (i < 3 ? i : 3)), child: part),
        ],
      ],
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
