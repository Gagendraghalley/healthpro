import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../data/money.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import '../widgets/gym_widgets.dart';

/// Offers & discounts, for those who set prices: the gym's offers (so much
/// off, as a percentage or an amount) the desk picks when selling a package;
/// and the month's discounts: who paid less, by how much, and why, flagging
/// those with no reason.
class OffersScreen extends ConsumerStatefulWidget {
  final String venueId;

  const OffersScreen({super.key, required this.venueId});

  @override
  ConsumerState<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends ConsumerState<OffersScreen> {
  late DateTime _month = () {
    final t = BhutanTime.today();
    return DateTime(t.year, t.month);
  }();

  Future<void> _edit([GymOffer? offer]) async {
    final saved = await showAppDialog<bool>(context: context, builder: (_) => _OfferDialog(venueId: widget.venueId, offer: offer));
    if (saved == true) ref.invalidate(gymOffersProvider(widget.venueId));
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.venueId;
    return GymStaffPage(
      venueId: id,
      title: 'Offers & discounts',
      permission: GymPermission.plans,
      builder: (context, access) {
        return AppPage(
          title: 'Offers & discounts',
          body: AsyncValueView<List<GymOffer>>(
            value: ref.watch(gymOffersProvider(id)),
            onRetry: () => ref.invalidate(gymOffersProvider(id)),
            data: (offers) {
              final subs = ref.watch(gymSubscriptionsProvider(id)).valueOrNull ?? const <GymSubscription>[];
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(gymOffersProvider(id));
                  refreshGym(ref, id);
                },
                child: ListView(
                  padding: pagePadding(context, bottom: 40),
                  children: [
                    PageActions(
                      text: 'Offers the front desk picks when selling a package, and every discount given, with why.',
                      children: [
                        FilledButton.icon(
                          onPressed: _edit,
                          style: FilledButton.styleFrom(minimumSize: PageActions.buttonSize),
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text('New offer'),
                        ),
                      ],
                    ),
                    const SectionTitle('Offers'),
                    if (offers.isEmpty)
                      EmptyState(
                        icon: Icons.local_offer_outlined,
                        title: 'No offers yet',
                        message: 'Add the gym\'s usual deals (Student 10% off, Couple Nu. 500 off) so the desk picks one '
                            'instead of typing a lower amount.',
                        actionLabel: 'Add an offer',
                        onAction: _edit,
                      )
                    else
                      _offersTable(context, offers),
                    _discounts(context, subs, id),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// The offers as a table; Open changes one.
  Widget _offersTable(BuildContext context, List<GymOffer> offers) {
    final brand = context.brand;
    Widget status(GymOffer o) => o.isActive
        ? StatusChip(label: 'Offered', color: brand.success)
        : StatusChip(label: 'Not offered', color: brand.muted, icon: Icons.visibility_off_outlined);
    return DataGrid<GymOffer>(
      rows: offers,
      noun: 'offers',
      rowLabel: (o) => 'Open ${o.name}',
      dimmed: (o) => !o.isActive,
      onRowTap: _edit,
      columns: [
        GridColumn(
          key: 'offer',
          label: 'Offer',
          flex: 4,
          sortBy: (o) => o.name.toLowerCase(),
          cell: (context, o) => Row(
            children: [
              Icon(Icons.local_offer_outlined, color: o.isActive ? brand.highlight : brand.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(o.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                    if (!DataGrid.shows(context, 'discount')) Text(o.label, style: TextStyle(color: brand.muted, fontSize: 13)),
                    if (!DataGrid.shows(context, 'status')) Padding(padding: const EdgeInsets.only(top: 4), child: status(o)),
                  ],
                ),
              ),
            ],
          ),
        ),
        GridColumn(
          key: 'discount',
          label: 'Discount',
          flex: 2,
          showFrom: 600,
          sortBy: (o) => '${o.kind.index}-${o.value.toString().padLeft(9, '0')}',
          cell: (context, o) => Text(o.label, style: TextStyle(fontWeight: FontWeight.w700, color: brand.body)),
        ),
        GridColumn(
          key: 'status',
          label: 'Status',
          width: 150,
          showFrom: 480,
          sortBy: (o) => o.isActive ? 0 : 1,
          cell: (context, o) => status(o),
        ),
        GridColumn.actions(cell: (context, o) => GridOpenButton(onPressed: () => _edit(o))),
      ],
    );
  }

  /// The month's discounts: totals, then each one.
  Widget _discounts(BuildContext context, List<GymSubscription> subs, String venueId) {
    final brand = context.brand;
    final today = BhutanTime.today();
    final thisMonth = DateTime(today.year, today.month);
    final given = discountedIn(subs, _month);
    final totals = discountTotals(given);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Discounts given',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Month before',
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text(formatMonth(_month), style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(
                tooltip: 'Month after',
                onPressed: _month.isBefore(thisMonth) ? () => setState(() => _month = DateTime(_month.year, _month.month + 1)) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
        if (given.isEmpty)
          SectionCard(
            padding: const EdgeInsets.all(16),
            child: Text('No discounts in ${formatMonth(_month)}.', style: TextStyle(color: brand.muted)),
          )
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusChip(
                label: '${totals.count} ${totals.count == 1 ? 'discount' : 'discounts'}, ${formatNu(totals.total)} off',
                color: brand.highlight,
                icon: Icons.local_offer_outlined,
              ),
              if (totals.unexplained > 0)
                StatusChip(
                  label: '${totals.unexplained} without a reason',
                  color: brand.warning,
                  icon: Icons.help_outline_rounded,
                ),
            ],
          ),
          const SizedBox(height: 10),
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < given.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _DiscountRow(
                    sub: given[i],
                    onTap: given[i].gymMemberId == null
                        ? null
                        : () => context.push(GymRoutes.memberFor(venueId, given[i].gymMemberId!)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('Who gave each one is in the activity log.', style: TextStyle(color: brand.muted, fontSize: 12.5)),
        ],
      ],
    );
  }
}

class _DiscountRow extends StatelessWidget {
  final GymSubscription sub;
  final VoidCallback? onTap;

  const _DiscountRow({required this.sub, this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final s = sub;
    final why = discountWhy(s);
    final unexplained = why == 'No reason given';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.memberDisplayName, style: TextStyle(fontWeight: FontWeight.w600, color: brand.ink)),
                  Text(
                    '${s.planName} · ${formatShortDate(BhutanTime.toBhutan(s.activatedAt!))} · paid ${formatNu(s.price)} of '
                    '${formatNu(s.listPrice!)}',
                    style: TextStyle(color: brand.muted, fontSize: 12.5),
                  ),
                  Text(why, style: TextStyle(color: unexplained ? brand.readable(brand.warning) : brand.body, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('- ${formatNu(s.discount)}', style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
          ],
        ),
      ),
    );
  }
}

/// A new offer ([offer] null) or changes to one: its name, a percentage or
/// an amount off, and whether it's still offered.
class _OfferDialog extends ConsumerStatefulWidget {
  final String venueId;
  final GymOffer? offer;

  const _OfferDialog({required this.venueId, this.offer});

  @override
  ConsumerState<_OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends ConsumerState<_OfferDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.offer?.name ?? '');
  late final _value = TextEditingController(text: widget.offer == null ? '' : '${widget.offer!.value}');
  late OfferKind _kind = widget.offer?.kind ?? OfferKind.percent;
  late bool _active = widget.offer?.isActive ?? true;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final ok = await runAction(context, () async {
      await ref.read(gymMoneyRepositoryProvider).saveOffer(
            widget.venueId,
            offerId: widget.offer?.id,
            name: _name.text,
            kind: _kind,
            value: int.parse(_value.text.trim()),
            isActive: _active,
          );
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    showFeedback(context, widget.offer == null ? 'Offer added' : 'Saved');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final percent = _kind == OfferKind.percent;
    return AlertDialog(
      title: Text(widget.offer == null ? 'New offer' : widget.offer!.name),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                maxLength: 60,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name *', hintText: 'Student, Couple, New Year...'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Give the offer a name' : null,
              ),
              const SizedBox(height: 8),
              SegmentedButton<OfferKind>(
                segments: const [
                  ButtonSegment(value: OfferKind.percent, label: Text('Percentage off')),
                  ButtonSegment(value: OfferKind.amount, label: Text('Amount off')),
                ],
                selected: {_kind},
                onSelectionChanged: (v) => setState(() => _kind = v.first),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _value,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: percent ? 'Percentage off *' : 'Amount off *',
                  prefixText: percent ? null : 'Nu. ',
                  suffixText: percent ? '%' : null,
                  helperText: percent ? 'Off the package price, whatever the package' : 'Off each package sold with it',
                ),
                validator: (v) => percent
                    ? Validators.wholeNumber(v, min: 1, max: 100, what: 'Percentage')
                    : Validators.wholeNumber(v, min: 1, max: 1000000),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('Offered at the desk'),
                subtitle: const Text('Turn off to stop offering it; discounts already given keep its name'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(widget.offer == null ? 'Add' : 'Save')),
      ],
    );
  }
}
