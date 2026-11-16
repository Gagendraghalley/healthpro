import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_repository.dart';
import '../data/trainers.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import '../widgets/gym_widgets.dart';
import '../widgets/trainer_widgets.dart';
import 'trainer_screens.dart' show pickTrainerSlots;

/// The gym adds a trainer itself, as it registers a member: who they are and
/// how to reach them, their photo, what they do, their certificates and
/// their week here. Their Health Pro account is made from their email (or
/// found by it), and they're verified here straight away: no request to
/// check. For the gym's staff who check trainers.
class AddTrainerScreen extends ConsumerStatefulWidget {
  final String venueId;

  const AddTrainerScreen({super.key, required this.venueId});

  @override
  ConsumerState<AddTrainerScreen> createState() => _AddTrainerScreenState();
}

class _AddTrainerScreenState extends ConsumerState<AddTrainerScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _headline = TextEditingController();
  final _bio = TextEditingController();
  final _years = TextEditingController();
  final _specialty = TextEditingController();
  List<String> _specialties = const [];
  List<NewCertificate> _certificates = const [];
  List<TrainerSlot> _slots = const [];
  ({Uint8List bytes, String contentType})? _photo;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _headline, _bio, _years, _specialty]) {
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

  Future<void> _pickPhoto() async {
    final photo = await pickPhoto(context);
    if (photo != null && mounted) setState(() => _photo = photo);
  }

  Future<void> _addCertificate() async {
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
                TextField(
                  controller: title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Certificate *', hintText: 'e.g. CPR and first aid'),
                  onChanged: (_) => setState(() {}),
                ),
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
                    if (photo != null) setState(() => file = photo);
                  },
                  icon: Icon(file == null ? Icons.upload_file_rounded : Icons.check_circle_rounded, size: 18),
                  label: Text(file == null ? 'A photo of it (optional)' : 'Photo added'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: title.text.trim().length < 2 ? null : () => Navigator.pop(context, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    final name = title.text, by = issuer.text;
    title.dispose();
    issuer.dispose();
    if (ok != true || !mounted) return;
    setState(() => _certificates = [..._certificates, NewCertificate(title: name, issuer: by, issuedOn: issued, file: file)]);
  }

  Future<void> _pickTimes(String gymName) async {
    final picked = await pickTrainerSlots(
      context,
      title: 'Their times at $gymName',
      initial: _slots,
      note: 'Add one row for each day and time. Times that overlap another gym are unavailable. They can change their schedule later.',
      saveLabel: 'Use these times',
    );
    if (picked != null && mounted) setState(() => _slots = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    ({String name, bool alreadyTrainer})? added;
    final ok = await runAction(
      context,
      () async => added = await ref.read(gymRepositoryProvider).addTrainer(
            widget.venueId,
            NewTrainer(
              name: _name.text,
              email: _email.text,
              phone: _phone.text.trim().isEmpty ? null : Validators.normalizePhone(_phone.text),
              headline: _headline.text,
              bio: _bio.text,
              specialties: _specialties,
              experienceYears: int.tryParse(_years.text.trim()),
              photo: _photo,
              certificates: _certificates,
              slots: _slots,
            ),
          ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    refreshGym(ref, widget.venueId);
    showFeedback(
      context,
      added!.alreadyTrainer
          ? '${added!.name} is a trainer here now. They were on Health Pro already: their own profile is kept.'
          : '${added!.name} is a trainer here now. They sign in with ${_email.text.trim().toLowerCase()}.',
    );
    context.go(GymRoutes.gymTrainersFor(widget.venueId));
  }

  @override
  Widget build(BuildContext context) {
    return GymStaffPage(
      venueId: widget.venueId,
      title: 'Add a trainer',
      permission: GymPermission.trainers,
      builder: (context, access) {
        final brand = context.brand;
        final gym = access.venue;
        final cancel = TextButton(
          onPressed: _saving ? null : () => context.go(GymRoutes.gymTrainersFor(widget.venueId)),
          child: const Text('Cancel'),
        );
        final submit = FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.verified_rounded),
          label: const Text('Add trainer'),
        );

        final person = [
          const SectionTitle('Who they are'),
          Row(
            children: [
              ClipOval(
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: _photo == null
                      ? TrainerAvatar(name: _name.text, size: 80)
                      : Image.memory(_photo!.bytes, fit: BoxFit.cover, semanticLabel: 'Their photo'),
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickPhoto,
                icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                label: Text(_photo == null ? 'Add a photo' : 'Change photo'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name *', prefixIcon: Icon(Icons.person_outline_rounded)),
            validator: (v) => (v ?? '').trim().length < 2 ? 'Enter their name' : null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email *',
              helperText: 'Their Health Pro account: they sign in with it to see their members, times and QR code.',
              helperMaxLines: 2,
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
            validator: Validators.email,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone', hintText: '17123456', prefixIcon: Icon(Icons.phone_outlined)),
            validator: Validators.phone,
          ),
          const SectionTitle('What they do'),
          TextFormField(
            controller: _headline,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'What they do', hintText: 'e.g. Strength and conditioning coach'),
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
          const SizedBox(height: 14),
          TextFormField(
            controller: _bio,
            maxLines: 5,
            minLines: 3,
            maxLength: 2000,
            decoration: const InputDecoration(labelText: 'About them', hintText: 'How they train people, what they\'re good at'),
          ),
        ];

        final work = [
          const SectionTitle('Specialties'),
          if (_specialties.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _specialties)
                    InputChip(label: Text(s), onDeleted: () => setState(() => _specialties = _specialties.where((x) => x != s).toList())),
                ],
              ),
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
          SectionTitle(
            'Certificates',
            trailing: TextButton.icon(
              onPressed: _certificates.length >= 20 ? null : _addCertificate,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
            ),
          ),
          if (_certificates.isEmpty)
            const FormHint('The certificates you\'ve checked. Members see them on the trainer\'s profile.')
          else
            SectionCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (final (i, c) in _certificates.indexed)
                    ListTile(
                      leading: Icon(Icons.workspace_premium_rounded, color: brand.accent),
                      title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([
                        if ((c.issuer ?? '').trim().isNotEmpty) c.issuer!.trim(),
                        if (c.issuedOn != null) formatDate(c.issuedOn!),
                        if (c.file != null) 'photo added',
                      ].join(' · ')),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => setState(() => _certificates = [..._certificates]..removeAt(i)),
                      ),
                    ),
                ],
              ),
            ),
          SectionTitle(
            'Their week at ${gym.name}',
            trailing: TextButton.icon(
              onPressed: () => _pickTimes(gym.name),
              icon: const Icon(Icons.edit_calendar_outlined, size: 18),
              label: Text(_slots.isEmpty ? 'Set times' : 'Change'),
            ),
          ),
          SectionCard(padding: const EdgeInsets.all(14), child: WeekSlotsView(slots: _slots)),
          const SizedBox(height: 16),
          const InfoRow(
            icon: Icons.verified_outlined,
            text: 'They\'re verified here as soon as you add them: members can choose them, and the desk takes their '
                'attendance (their QR code, or Mark arrived). They\'re told in the app.',
          ),
          const InfoRow(
            icon: Icons.key_outlined,
            text: 'New to Health Pro: they sign in with this email and the starting code 123456, then choose their own. '
                'On Health Pro already as a trainer: their own profile is kept, and only the times here are used.',
          ),
        ];

        return AppPage(
          title: 'Add a trainer',
          bottomBar: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [cancel, const SizedBox(width: 4), submit],
            ),
          ),
          body: Form(
            key: _form,
            child: ListView(
              padding: pagePadding(context),
              children: [
                ResponsiveColumns(spacing: 32, first: person, second: work),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}
