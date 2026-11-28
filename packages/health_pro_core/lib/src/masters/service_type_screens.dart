import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../access/access.dart';
import '../access/permission_gate.dart';
import '../theme/brand.dart';
import '../venues/venue_repository.dart';
import '../venues/venue_type.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../widgets/feedback.dart';
import '../widgets/form_fields.dart';

/// Admin -> Service types: the kinds of health business on Health Pro (Gym,
/// Swimming Pool, Cycling, Wellness Centre...), kept here, not in code. Each
/// is offered on 'Register your organisation' and as a card on Services:
/// its name, what it is, icon, colour and cover photo, its place in the
/// list, and whether the card shows (Coming soon) before any of its kind is
/// verified. Its facilities are the ticks its organisations' form suggests.
/// A type in use is turned off rather than deleted, so its organisations
/// keep it.
class ServiceTypesScreen extends ConsumerStatefulWidget {
  const ServiceTypesScreen({super.key});

  @override
  ConsumerState<ServiceTypesScreen> createState() => _ServiceTypesScreenState();
}

class _ServiceTypesScreenState extends ConsumerState<ServiceTypesScreen> {
  bool _withInactive = true;

  Future<void> _edit(VenueType? type) async {
    final saved = await showAppDialog<bool>(context: context, builder: (_) => ServiceTypeDialog(type: type));
    if (saved == true) ref.invalidate(venueTypesProvider);
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      title: 'Service types',
      permission: PlatformPermission.masters,
      builder: (context, _) => AppPage(
        title: 'Service types',
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(null),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add a type'),
        ),
        body: RefreshIndicator(
          onRefresh: () => ref.refresh(venueTypesProvider.future),
          child: ListView(
            padding: pagePadding(context, bottom: 96),
            children: [
              Text(
                'The kinds of service on Health Pro. Each one is a card on the Services page, in this order, and a '
                'choice when an organisation registers. Packages, members, check-in and classes work the same for '
                'every type.',
                style: TextStyle(color: context.brand.muted),
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: const Text('Show turned-off ones'),
                value: _withInactive,
                onChanged: (v) => setState(() => _withInactive = v),
              ),
              AsyncValueView<List<VenueType>>(
                value: ref.watch(venueTypesProvider),
                onRetry: () => ref.invalidate(venueTypesProvider),
                data: (all) {
                  final types = [for (final t in all) if (_withInactive || t.isActive) t];
                  if (types.isEmpty) {
                    return const EmptyState(icon: Icons.category_outlined, title: 'No service types yet');
                  }
                  return _TypesTable(types: types, onTap: _edit);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The type's icon on its colour, as on its card.
class ServiceTypeIcon extends StatelessWidget {
  final VenueType type;
  final double size;

  const ServiceTypeIcon({super.key, required this.type, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final color = type.colorOr(context.colors.primary);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(type.iconData, size: size * 0.55, color: color),
    );
  }
}

/// The types as a table: name (with its icon on its colour), what it is,
/// whether it has a cover photo, its place on Services, in use or off. Tap a
/// row to change it.
class _TypesTable extends StatelessWidget {
  final List<VenueType> types;
  final ValueChanged<VenueType> onTap;

  const _TypesTable({required this.types, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return DataGrid<VenueType>(
      rows: types,
      noun: 'types',
      pageSizes: const [25, 50],
      rowLabel: (t) => 'Change ${t.name}',
      dimmed: (t) => !t.isActive,
      onRowTap: onTap,
      columns: [
        GridColumn(
          key: 'name',
          label: 'Name',
          flex: 3,
          sortBy: (t) => t.name.toLowerCase(),
          cell: (context, t) => Row(
            children: [
              ServiceTypeIcon(type: t, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                    if (!DataGrid.shows(context, 'about') && t.description != null)
                      Text(t.description!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: brand.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
        GridColumn(
          key: 'about',
          label: 'What it is',
          flex: 5,
          showFrom: 760,
          cell: (context, t) => Text(t.description ?? '—', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.body)),
        ),
        GridColumn(
          key: 'card',
          label: 'On Services',
          width: 150,
          showFrom: 900,
          sortBy: (t) => t.photo == null ? 1 : 0,
          cell: (context, t) => Text(
            [if (t.photo != null) 'Photo', t.showWhenEmpty ? 'Coming soon' : 'Hidden till one'].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: brand.body),
          ),
        ),
        GridColumn(
          key: 'order',
          label: 'Order',
          width: 80,
          showFrom: 600,
          sortBy: (t) => t.sortOrder,
          cell: (context, t) => Text('${t.sortOrder}', style: TextStyle(color: brand.muted)),
        ),
        GridColumn(
          key: 'status',
          label: 'Status',
          width: 108,
          showFrom: 480,
          sortBy: (t) => t.isActive ? 0 : 1,
          cell: (context, t) =>
              t.isActive ? StatusChip(label: 'In use', color: brand.success) : StatusChip(label: 'Off', color: brand.muted),
        ),
        GridColumn.actions(cell: (context, t) => GridOpenButton(onPressed: () => onTap(t))),
      ],
    );
  }
}

/// Adds a service type, or changes one ([type]). Pops true when saved or
/// deleted.
class ServiceTypeDialog extends ConsumerStatefulWidget {
  final VenueType? type;

  const ServiceTypeDialog({super.key, this.type});

  @override
  ConsumerState<ServiceTypeDialog> createState() => _ServiceTypeDialogState();
}

class _ServiceTypeDialogState extends ConsumerState<ServiceTypeDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.type?.name ?? '');
  late final _description = TextEditingController(text: widget.type?.description ?? '');
  late final _facilities = TextEditingController(text: (widget.type?.facilities ?? const []).join('\n'));
  late final _order = TextEditingController(text: '${widget.type?.sortOrder ?? 100}');
  late String _icon = widget.type?.icon ?? VenueTypeIcons.fallback;
  late String? _color = widget.type?.color ?? VenueTypeColors.all.keys.first;
  late String? _photo = widget.type?.photo;
  late bool _showWhenEmpty = widget.type?.showWhenEmpty ?? true;
  late bool _active = widget.type?.isActive ?? true;
  bool _saving = false;
  bool _uploading = false;

  @override
  void dispose() {
    for (final c in [_name, _description, _facilities, _order]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The card as it will look: the type with what's on the form now.
  VenueType get _preview => VenueType(
        key: widget.type?.key ?? 'new',
        moduleKey: widget.type?.moduleKey ?? '',
        name: _name.text.trim().isEmpty ? 'Name' : _name.text.trim(),
        icon: _icon,
        color: _color,
      );

  Future<void> _choosePhoto() async {
    final picked = await pickPhoto(context);
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    String? url;
    await runAction(context, () async {
      url = await ref.read(venueRepositoryProvider).uploadTypePhoto(widget.type?.key, picked.bytes, contentType: picked.contentType);
    });
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (url != null) _photo = url;
    });
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.type != null;
    final brand = context.brand;
    return AlertDialog(
      title: Text(editing ? 'Change ${widget.type!.name}' : 'Add a service type'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: !editing,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Name *', hintText: 'e.g. Swimming Pool'),
                  validator: (v) {
                    final text = (v ?? '').trim();
                    if (text.length < 2) return 'Enter the name';
                    if (text.length > 60) return 'Up to 60 letters';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _description,
                  maxLength: 300,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'What it is', hintText: 'Shown on its card on Services'),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('Icon', style: context.text.labelLarge),
                    const Spacer(),
                    ServiceTypeIcon(type: _preview, size: 40),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final MapEntry(:key, value: (icon, label)) in VenueTypeIcons.all.entries)
                      Tooltip(
                        message: label,
                        child: ChoiceChip(
                          showCheckmark: false,
                          label: Icon(icon, size: 20),
                          selected: _icon == key,
                          onSelected: (_) => setState(() => _icon = key),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Colour', style: context.text.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final MapEntry(:key, value: (color, label)) in VenueTypeColors.all.entries)
                      Tooltip(
                        message: label,
                        child: Semantics(
                          button: true,
                          selected: _color == key,
                          label: label,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => setState(() => _color = key),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(color: _color == key ? brand.ink : Colors.transparent, width: 2.5),
                              ),
                              child: _color == key ? const Icon(Icons.check_rounded, size: 18, color: Colors.white) : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Cover photo', style: context.text.labelLarge),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: 16 / 7,
                    child: _photo == null
                        ? ColoredBox(
                            color: _preview.colorOr(context.colors.primary).withValues(alpha: 0.1),
                            child: Center(child: Text('No photo: the card shows its icon', style: TextStyle(color: brand.muted))),
                          )
                        : Image.network(
                            _photo!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => ColoredBox(
                              color: brand.glassBorder,
                              child: Center(child: Text("The photo couldn't be shown", style: TextStyle(color: brand.muted))),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _uploading || _saving ? null : _choosePhoto,
                      icon: _uploading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_photo_alternate_outlined, size: 18),
                      label: Text(_photo == null ? 'Choose photo' : 'Change photo'),
                    ),
                    if (_photo != null)
                      TextButton(onPressed: _saving ? null : () => setState(() => _photo = null), child: const Text('Remove photo')),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _facilities,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Facilities to suggest',
                    hintText: 'One a line: Changing rooms, Lifeguard...',
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => _lines(v ?? '').length > 40 ? 'Up to 40' : null,
                ),
                const SizedBox(height: 4),
                const FormHint('Ticks on the form of an organisation of this type; it can add its own.'),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _order,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Order on Services', hintText: 'Smaller comes first'),
                  validator: (v) => (int.tryParse(v ?? '') ?? -1) > 10000 ? 'Up to 10000' : null,
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show before there are any'),
                  subtitle: Text(_showWhenEmpty
                      ? 'Its card shows "Coming soon" until the first one is verified'
                      : 'Its card stays hidden until the first one is verified'),
                  value: _showWhenEmpty,
                  onChanged: (v) => setState(() => _showWhenEmpty = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('In use'),
                  subtitle: Text(_active ? 'On Services, and offered to new organisations' : 'Hidden; organisations of this type keep it'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (editing)
          TextButton(
            onPressed: _saving ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: brand.danger),
            child: const Text('Delete'),
          ),
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving || _uploading ? null : _save, child: Text(editing ? 'Save' : 'Add')),
      ],
    );
  }

  static List<String> _lines(String text) => [for (final l in text.split('\n')) if (l.trim().isNotEmpty) l.trim()];

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final ok = await runAction(
      context,
      () => ref.read(venueRepositoryProvider).saveType(
            widget.type?.key,
            VenueTypeDraft(
              name: _name.text,
              description: _description.text,
              icon: _icon,
              facilities: _lines(_facilities.text),
              sortOrder: int.tryParse(_order.text) ?? 100,
              active: _active,
              color: _color,
              photo: _photo,
              showWhenEmpty: _showWhenEmpty,
            ),
          ),
      success: widget.type == null ? 'Added' : 'Saved',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final type = widget.type!;
    final sure = await confirmAction(
      context,
      title: 'Delete ${type.name}?',
      message: 'Only a type no organisation has can be deleted. One in use is turned off instead.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!sure || !mounted) return;
    setState(() => _saving = true);
    final ok = await runAction(context, () => ref.read(venueRepositoryProvider).deleteType(type.key), success: 'Deleted');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context, true);
  }
}
