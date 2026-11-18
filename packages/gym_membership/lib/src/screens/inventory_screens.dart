import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/inventory.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import '../widgets/gym_widgets.dart';

// ─── Inventory ─────────────────────────────────────────────────────────────

/// The gym's stock, for its owner and managers: what it keeps (equipment,
/// supplements, towels...), how many, what's running low; stock in and out,
/// recounts, and each item's history. A way to the connected suppliers.
class GymInventoryScreen extends ConsumerStatefulWidget {
  final String venueId;

  const GymInventoryScreen({super.key, required this.venueId});

  @override
  ConsumerState<GymInventoryScreen> createState() => _GymInventoryScreenState();
}

/// The Low stock filter (the others are categories).
const _lowFilter = '\u0000low';

class _GymInventoryScreenState extends ConsumerState<GymInventoryScreen> {
  String _search = '';
  String? _filter;

  String get _id => widget.venueId;

  void _refresh() => ref.invalidate(gymInventoryProvider(_id));

  Future<void> _edit(InventoryItem? item) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ItemSheet(venueId: _id, item: item),
    );
    if (saved ?? false) _refresh();
  }

  Future<void> _move(InventoryItem item, StockReason reason) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MoveSheet(item: item, reason: reason),
    );
    if (saved ?? false) _refresh();
  }

  void _history(InventoryItem item) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _HistorySheet(item: item),
      );

  Future<void> _remove(InventoryItem item) async {
    final sure = await confirmAction(
      context,
      title: 'Remove ${item.name}?',
      message: 'It goes from the inventory with its history. This can\'t be undone.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!sure || !mounted) return;
    final ok = await runAction(context, () => ref.read(inventoryRepositoryProvider).deleteItem(item.id),
        success: '${item.name} removed');
    if (ok) _refresh();
  }

  List<InventoryItem> _shown(List<InventoryItem> items) => [
        for (final i in items)
          if ((_filter == null ||
                  (_filter == _lowFilter ? i.level != StockLevel.ok : i.category == _filter)) &&
              (_search.isEmpty ||
                  i.name.toLowerCase().contains(_search) ||
                  (i.category?.toLowerCase().contains(_search) ?? false)))
            i,
      ];

  @override
  Widget build(BuildContext context) {
    return GymStaffPage(
      venueId: _id,
      title: 'Inventory',
      permission: GymPermission.inventory,
      // The page's buttons sit under the bar, not in it.
      builder: (context, access) => AppPage(
        title: 'Inventory',
        body: AsyncValueView<List<InventoryItem>>(
          value: ref.watch(gymInventoryProvider(_id)),
          onRetry: _refresh,
          data: (items) {
            final shown = _shown(items);
            return RefreshIndicator(
              onRefresh: () => ref.refresh(gymInventoryProvider(_id).future),
              child: ListView(
                padding: pagePadding(context),
                children: [
                  PageActions(
                    text: 'What the gym keeps and how many.',
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => context.go(GymRoutes.suppliersFor(_id)),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                        icon: const Icon(Icons.storefront_outlined, size: 20),
                        label: const Text('Suppliers'),
                      ),
                      FilledButton.icon(
                        onPressed: () => _edit(null),
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text('Add item'),
                      ),
                    ],
                  ),
                  if (items.isEmpty)
                    EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'Nothing in the inventory yet',
                      message: 'Add what the gym keeps (equipment, supplements, drinks, towels...) with how many you '
                          'have now. Then record stock in and out, and see what\'s running low.',
                      actionLabel: 'Add item',
                      onAction: () => _edit(null),
                    )
                  else ...[
                    _summary(context, items),
                    const SizedBox(height: 16),
                    _toolbar(context, items),
                    const SizedBox(height: 12),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('No items match.',
                            textAlign: TextAlign.center, style: TextStyle(color: context.brand.muted)),
                      )
                    else
                      _ItemsTable(
                        items: shown,
                        onMove: _move,
                        onEdit: _edit,
                        onHistory: _history,
                        onRemove: _remove,
                      ),
                  ],
                  const SizedBox(height: 16),
                  _SuppliersBanner(venueId: _id),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _summary(BuildContext context, List<InventoryItem> items) {
    final brand = context.brand;
    final s = inventorySummary(items);
    return ResponsiveGrid(
      minItemWidth: 160,
      maxColumns: 4,
      children: [
        StatTile(label: 'Items', value: '${s.items}', icon: Icons.inventory_2_outlined, color: brand.highlight),
        StatTile(
          label: 'Low stock',
          value: '${s.low}',
          icon: Icons.trending_down_rounded,
          color: brand.warning,
          onTap: () => setState(() => _filter = _lowFilter),
        ),
        StatTile(
          label: 'Out of stock',
          value: '${s.out}',
          icon: Icons.remove_shopping_cart_outlined,
          color: brand.danger,
          onTap: () => setState(() => _filter = _lowFilter),
        ),
        StatTile(
          label: 'Stock value',
          value: s.value == null ? '—' : formatNu(s.value!),
          icon: Icons.account_balance_wallet_outlined,
          color: brand.accent,
        ),
      ],
    );
  }

  Widget _toolbar(BuildContext context, List<InventoryItem> items) {
    final categories = {for (final i in items) i.category}.whereType<String>().toList()..sort();
    final lowCount = items.where((i) => i.level != StockLevel.ok).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search items'),
          onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(label: const Text('All'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
            ChoiceChip(
              label: Text('Low or out ($lowCount)'),
              selected: _filter == _lowFilter,
              onSelected: (_) => setState(() => _filter = _filter == _lowFilter ? null : _lowFilter),
            ),
            for (final c in categories)
              ChoiceChip(
                label: Text(c),
                selected: _filter == c,
                onSelected: (_) => setState(() => _filter = _filter == c ? null : c),
              ),
          ],
        ),
      ],
    );
  }
}

enum _ItemAction { stockIn, takeOut, recount, history, remove }

/// The items as a table: how many there are and whether that's low. Open
/// changes one's details; the menu beside it moves stock and shows history.
class _ItemsTable extends StatelessWidget {
  final List<InventoryItem> items;
  final void Function(InventoryItem item, StockReason reason) onMove;
  final ValueChanged<InventoryItem> onEdit;
  final ValueChanged<InventoryItem> onHistory;
  final ValueChanged<InventoryItem> onRemove;

  const _ItemsTable({
    required this.items,
    required this.onMove,
    required this.onEdit,
    required this.onHistory,
    required this.onRemove,
  });

  Widget _menu(BuildContext context, InventoryItem i) {
    final brand = context.brand;
    PopupMenuItem<_ItemAction> item(_ItemAction value, IconData icon, String label, {bool enabled = true, Color? color}) =>
        PopupMenuItem(
          value: value,
          enabled: enabled,
          child: Row(
            children: [
              Icon(icon, size: 20, color: color ?? brand.body),
              const SizedBox(width: 12),
              Text(label, style: TextStyle(color: color)),
            ],
          ),
        );
    return PopupMenuButton<_ItemAction>(
      tooltip: 'More',
      icon: Icon(Icons.more_vert_rounded, color: brand.muted),
      onSelected: (a) => switch (a) {
        _ItemAction.stockIn => onMove(i, StockReason.stockIn),
        _ItemAction.takeOut => onMove(i, StockReason.used),
        _ItemAction.recount => onMove(i, StockReason.recount),
        _ItemAction.history => onHistory(i),
        _ItemAction.remove => onRemove(i),
      },
      itemBuilder: (_) => [
        item(_ItemAction.stockIn, Icons.add_rounded, 'Stock in'),
        item(_ItemAction.takeOut, Icons.remove_rounded, 'Take out', enabled: i.quantity > 0),
        item(_ItemAction.recount, Icons.fact_check_outlined, 'Recount'),
        item(_ItemAction.history, Icons.history_rounded, 'History'),
        item(_ItemAction.remove, Icons.delete_outline_rounded, 'Remove', color: brand.danger),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    Widget muted(String text) => Text(text, style: TextStyle(color: brand.muted));
    Widget quantity(InventoryItem i) => Text.rich(
          TextSpan(children: [
            TextSpan(text: '${i.quantity}', style: TextStyle(fontWeight: FontWeight.w800, color: brand.ink)),
            TextSpan(text: ' ${i.unit}', style: TextStyle(color: brand.muted, fontSize: 13)),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
    return DataGrid<InventoryItem>(
      rows: items,
      noun: 'items',
      pageSizes: const [25, 50, 100],
      rowLabel: (i) => 'Open ${i.name}',
      onRowTap: onEdit,
      columns: [
        GridColumn(
          key: 'item',
          label: 'Item',
          flex: 4,
          sortBy: (i) => i.name.toLowerCase(),
          cell: (context, i) {
            final carry = [
              if (i.category != null && !DataGrid.shows(context, 'category')) i.category!,
              if (i.notes != null) i.notes!,
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(i.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                if (carry.isNotEmpty)
                  Text(carry.join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 13)),
                if (!DataGrid.shows(context, 'quantity') || !DataGrid.shows(context, 'stock'))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (!DataGrid.shows(context, 'quantity')) quantity(i),
                        if (!DataGrid.shows(context, 'stock')) StockChip(level: i.level),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        GridColumn(
          key: 'category',
          label: 'Category',
          flex: 2,
          showFrom: 900,
          sortBy: (i) => (i.category ?? '').toLowerCase(),
          cell: (context, i) => i.category == null
              ? muted('—')
              : Text(i.category!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.body)),
        ),
        GridColumn(
          key: 'quantity',
          label: 'Quantity',
          flex: 2,
          showFrom: 560,
          sortBy: (i) => i.quantity,
          cell: (context, i) => quantity(i),
        ),
        GridColumn(
          key: 'reorder',
          label: 'Reorder at',
          flex: 2,
          showFrom: 1040,
          sortBy: (i) => i.reorderLevel,
          cell: (context, i) => i.reorderLevel > 0 ? Text('${i.reorderLevel}', style: TextStyle(color: brand.body)) : muted('—'),
        ),
        GridColumn(
          key: 'cost',
          label: 'Unit cost',
          flex: 2,
          showFrom: 1160,
          sortBy: (i) => i.unitCost ?? -1,
          cell: (context, i) => i.unitCost == null ? muted('—') : Text(formatNu(i.unitCost!), style: TextStyle(color: brand.body)),
        ),
        GridColumn(
          key: 'stock',
          label: 'Stock',
          width: 150,
          showFrom: 700,
          sortBy: (i) => i.level.index,
          cell: (context, i) => StockChip(level: i.level),
        ),
        GridColumn.actions(
          width: 172,
          cell: (context, i) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [GridOpenButton(onPressed: () => onEdit(i)), _menu(context, i)],
          ),
        ),
      ],
    );
  }
}

/// In stock, Low stock, Out of stock; with the count when [count] is given.
class StockChip extends StatelessWidget {
  final StockLevel level;
  final int? count;

  const StockChip({super.key, required this.level, this.count});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return switch (level) {
      StockLevel.ok => StatusChip(
          label: count == null ? 'In stock' : '$count in stock', color: brand.success, icon: Icons.check_circle_rounded),
      StockLevel.low => StatusChip(
          label: count == null ? 'Low stock' : 'Low stock · $count', color: brand.warning, icon: Icons.trending_down_rounded),
      StockLevel.out => StatusChip(label: 'Out of stock', color: brand.danger, icon: Icons.remove_shopping_cart_outlined),
    };
  }
}

class _SuppliersBanner extends StatelessWidget {
  final String venueId;

  const _SuppliersBanner({required this.venueId});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Need more stock?', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('See what connected suppliers have and how many, then buy in their own system.',
            style: TextStyle(color: brand.muted, fontSize: 13)),
      ],
    );
    final button = OutlinedButton.icon(
      onPressed: () => context.go(GymRoutes.suppliersFor(venueId)),
      icon: const Icon(Icons.storefront_outlined, size: 18),
      label: const Text('Browse suppliers'),
    );
    return SectionCard(
      child: LayoutBuilder(builder: (context, constraints) {
        final icon = Icon(Icons.storefront_rounded, color: brand.accent, size: 28);
        if (constraints.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [icon, const SizedBox(width: 12), Expanded(child: text)]),
              const SizedBox(height: 12),
              button,
            ],
          );
        }
        return Row(children: [icon, const SizedBox(width: 14), Expanded(child: text), const SizedBox(width: 12), button]);
      }),
    );
  }
}

/// Adds an item, or changes one's details (its count only through stock in,
/// out and recounts).
class _ItemSheet extends ConsumerStatefulWidget {
  final String venueId;
  final InventoryItem? item;

  const _ItemSheet({required this.venueId, this.item});

  @override
  ConsumerState<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends ConsumerState<_ItemSheet> {
  static const categories = ['Equipment', 'Supplements', 'Drinks', 'Merchandise', 'Towels & linen', 'Cleaning'];
  static const units = ['pcs', 'boxes', 'bottles', 'tubs', 'packs', 'kg'];

  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _category = TextEditingController(text: widget.item?.category ?? '');
  late final _unit = TextEditingController(text: widget.item?.unit ?? 'pcs');
  late final _quantity = TextEditingController(text: '0');
  late final _reorder = TextEditingController(text: '${widget.item?.reorderLevel ?? 0}');
  late final _cost = TextEditingController(text: widget.item?.unitCost == null ? '' : '${widget.item!.unitCost}');
  late final _notes = TextEditingController(text: widget.item?.notes ?? '');
  bool _busy = false;

  bool get _isNew => widget.item == null;

  @override
  void dispose() {
    for (final c in [_name, _category, _unit, _quantity, _reorder, _cost, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final details = InventoryDetails(
      name: _name.text,
      category: _category.text,
      unit: _unit.text,
      quantity: _isNew ? int.parse(_quantity.text.trim()) : 0,
      reorderLevel: int.parse(_reorder.text.trim()),
      unitCost: _cost.text.trim().isEmpty ? null : int.parse(_cost.text.trim()),
      notes: _notes.text,
    );
    final ok = await runAction(
      context,
      () => ref.read(inventoryRepositoryProvider).saveItem(widget.venueId, widget.item?.id, details),
      success: _isNew ? '${details.name.trim()} added' : 'Saved',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  Widget _number(TextEditingController controller, String label, {String? helper, String? prefix, bool optional = false}) =>
      TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, helperText: helper, prefixText: prefix),
        validator: (v) => optional && (v ?? '').trim().isEmpty ? null : Validators.wholeNumber(v, what: label.replaceAll(' *', '')),
      );

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_isNew ? 'Add item' : 'Edit ${widget.item!.name}', style: context.text.titleLarge),
              const SizedBox(height: 4),
              Text(
                  _isNew
                      ? 'Something the gym keeps, and how many it has now.'
                      : 'To change the count, use Stock in, Take out or Recount.',
                  style: TextStyle(color: brand.muted)),
              const SizedBox(height: 18),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Name *', hintText: 'Yoga mat, Whey protein 2 kg, Towel...'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a name' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _category,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Category (optional)', counterText: ''),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in categories)
                    ChoiceChip(
                      label: Text(c),
                      selected: _category.text.trim() == c,
                      onSelected: (_) => setState(() => _category.text = c),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isNew) ...[
                    Expanded(child: _number(_quantity, 'How many now *')),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: TextFormField(
                      controller: _unit,
                      maxLength: 20,
                      decoration: const InputDecoration(labelText: 'Counted in *', counterText: ''),
                      onChanged: (_) => setState(() {}),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'pcs, boxes...' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final u in units)
                    ChoiceChip(
                      label: Text(u),
                      selected: _unit.text.trim() == u,
                      onSelected: (_) => setState(() => _unit.text = u),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _number(_reorder, 'Low stock at *', helper: 'Warn at this many or fewer')),
                  const SizedBox(width: 12),
                  Expanded(child: _number(_cost, 'Cost each', prefix: 'Nu. ', helper: 'Optional', optional: true)),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Notes (optional)', hintText: 'Where it\'s kept, size, supplier...'),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: _busy ? null : _save, child: Text(_isNew ? 'Add item' : 'Save')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stock in, take out (used, sold, damaged) or a recount of one item.
class _MoveSheet extends ConsumerStatefulWidget {
  final InventoryItem item;
  final StockReason reason;

  const _MoveSheet({required this.item, required this.reason});

  @override
  ConsumerState<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends ConsumerState<_MoveSheet> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.reason == StockReason.recount ? '${widget.item.quantity}' : '');
  final _note = TextEditingController();
  late StockReason _reason = widget.reason;
  bool _busy = false;

  InventoryItem get _item => widget.item;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  int? _after() {
    final n = int.tryParse(_amount.text.trim());
    if (n == null) return null;
    return switch (_reason) {
      StockReason.stockIn => _item.quantity + n,
      StockReason.recount => n,
      _ => _item.quantity - n,
    };
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref.read(inventoryRepositoryProvider).moveStock(_item.id, _reason, int.parse(_amount.text.trim()), note: _note.text),
      success: 'Saved: ${_item.name} now ${_after()} ${_item.unit}',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final after = _after();
    final out = _reason.takesAway;
    final title = switch (_reason) {
      StockReason.stockIn => 'Stock in',
      StockReason.recount => 'Recount',
      _ => 'Take out',
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('$title: ${_item.name}', style: context.text.titleLarge),
              const SizedBox(height: 4),
              Text('${_item.countText} now', style: TextStyle(color: brand.muted)),
              const SizedBox(height: 16),
              if (out) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in StockReason.out)
                      ChoiceChip(label: Text(r.label), selected: _reason == r, onSelected: (_) => setState(() => _reason = r)),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: _reason == StockReason.recount ? 'How many you counted *' : 'How many *',
                  suffixText: _item.unit,
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final problem = Validators.wholeNumber(v, min: _reason == StockReason.recount ? 0 : 1, what: 'How many');
                  if (problem != null) return problem;
                  if (out && int.parse(v!.trim()) > _item.quantity) return 'Only ${_item.countText} in stock';
                  return null;
                },
              ),
              if (after != null && after >= 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: brand.highlight.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, color: brand.highlight, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('${_item.quantity} → $after ${_item.unit}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextFormField(
                controller: _note,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: switch (_reason) {
                    StockReason.stockIn => 'From which supplier, invoice no...',
                    StockReason.recount => 'Counted on...',
                    _ => 'For whom, why...',
                  },
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: _busy ? null : _save, child: Text(title)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The latest changes to an item's count, who made them and when.
class _HistorySheet extends ConsumerWidget {
  final InventoryItem item;

  const _HistorySheet({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('History: ${item.name}', style: context.text.titleLarge),
            const SizedBox(height: 4),
            Text('${item.countText} now · the latest 50 changes', style: TextStyle(color: brand.muted)),
            const SizedBox(height: 12),
            Flexible(
              child: AsyncValueView<List<StockMove>>(
                value: ref.watch(inventoryMovesProvider(item.id)),
                onRetry: () => ref.invalidate(inventoryMovesProvider(item.id)),
                data: (moves) => moves.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('No changes yet.', textAlign: TextAlign.center, style: TextStyle(color: brand.muted)),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: moves.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: brand.glassBorder),
                        itemBuilder: (context, i) {
                          final m = moves[i];
                          final who = [m.madeBy ?? 'Former staff', formatMoment(m.madeAt)].join(' · ');
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(m.reason.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(m.note == null ? who : '${m.note}\n$who'),
                            isThreeLine: m.note != null,
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(m.changeText,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800, color: m.change > 0 ? brand.success : brand.danger)),
                                Text('= ${m.quantityAfter}', style: TextStyle(color: brand.muted, fontSize: 12)),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Suppliers ─────────────────────────────────────────────────────────────

/// Items from systems connected to Health Pro, with their stock there now,
/// for the gym's owner and managers. Shown only: each item opens in the
/// supplier's own system, where it's ordered and paid for.
class SuppliersScreen extends ConsumerStatefulWidget {
  final String venueId;

  const SuppliersScreen({super.key, required this.venueId});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  String? _supplier;
  String _query = '';
  Timer? _typing;

  @override
  void dispose() {
    _typing?.cancel();
    super.dispose();
  }

  ({String venueId, String? supplier, String query}) get _request =>
      (venueId: widget.venueId, supplier: _supplier, query: _query);

  void _search(String value) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return GymStaffPage(
      venueId: widget.venueId,
      title: 'Suppliers',
      permission: GymPermission.inventory,
      builder: (context, access) => AppPage(
        title: 'Suppliers',
        body: AsyncValueView<List<Supplier>>(
          value: ref.watch(connectedSuppliersProvider),
          onRetry: () => ref.invalidate(connectedSuppliersProvider),
          data: (suppliers) {
            if (suppliers.isEmpty) {
              return ListView(
                padding: pagePadding(context),
                children: const [
                  EmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'No suppliers connected yet',
                    message: 'When a supplier\'s system is connected to Health Pro, their items and stock show here.',
                  ),
                ],
              );
            }
            final supplier = suppliers.where((s) => s.key == _supplier).firstOrNull ?? suppliers.first;
            return RefreshIndicator(
              onRefresh: () => ref.refresh(supplierCatalogProvider(_request).future),
              child: ListView(
                padding: pagePadding(context),
                children: [
                  _Notice(supplier: supplier),
                  const SizedBox(height: 14),
                  if (suppliers.length > 1) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in suppliers)
                          ChoiceChip(
                            label: Text(s.name),
                            selected: s.key == supplier.key,
                            onSelected: (_) => setState(() => _supplier = s.key),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText: 'Search ${supplier.name}',
                          ),
                          onChanged: _search,
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.outlined(
                        tooltip: 'Latest stock',
                        onPressed: () => ref.invalidate(supplierCatalogProvider(_request)),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _catalog(context, supplier),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _catalog(BuildContext context, Supplier supplier) {
    final brand = context.brand;
    final website = OutlinedButton.icon(
      onPressed: () => openExternal(context, supplier.website),
      icon: const Icon(Icons.open_in_new_rounded, size: 18),
      label: Text('Open ${supplier.name}'),
    );
    return ref.watch(supplierCatalogProvider((venueId: widget.venueId, supplier: supplier.key, query: _query))).when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _Problem(
            message: friendlyError(e),
            onRetry: () => ref.invalidate(supplierCatalogProvider(_request)),
            website: website,
          ),
          data: (c) {
            if (c.error != null) {
              return _Problem(message: c.error!, onRetry: () => ref.invalidate(supplierCatalogProvider(_request)), website: website);
            }
            if (c.items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Text(_query.isEmpty ? '${supplier.name} has no items to show.' : 'Nothing matches "$_query".',
                        textAlign: TextAlign.center, style: TextStyle(color: brand.muted)),
                    const SizedBox(height: 12),
                    website,
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ResponsiveGrid(
                  minItemWidth: 240,
                  maxColumns: 4,
                  equalHeight: false,
                  children: [for (final i in c.items) _SupplierItemCard(item: i, supplier: supplier)],
                ),
                if (c.total > c.items.length) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Showing ${c.items.length} of ${c.total}. Search to narrow it down, or open ${supplier.name} to see everything.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: brand.muted),
                  ),
                  const SizedBox(height: 8),
                  Center(child: website),
                ],
              ],
            );
          },
        );
  }
}

/// Which supplier, and that buying happens in their system.
class _Notice extends StatelessWidget {
  final Supplier supplier;

  const _Notice({required this.supplier});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(supplier.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(
          '${supplier.description == null ? '' : '${supplier.description} '}Prices and stock come live from their system. '
          'To buy, open an item there: ordering and payment happen in their system, not on Health Pro.',
          style: TextStyle(color: brand.muted, fontSize: 13),
        ),
      ],
    );
    final button = OutlinedButton.icon(
      onPressed: () => openExternal(context, supplier.website),
      icon: const Icon(Icons.open_in_new_rounded, size: 18),
      label: const Text('Visit their website'),
    );
    return SectionCard(
      child: LayoutBuilder(builder: (context, constraints) {
        final icon = Icon(Icons.storefront_rounded, color: brand.accent, size: 28);
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [icon, const SizedBox(width: 12), Expanded(child: text)]),
              const SizedBox(height: 12),
              button,
            ],
          );
        }
        return Row(children: [icon, const SizedBox(width: 14), Expanded(child: text), const SizedBox(width: 12), button]);
      }),
    );
  }
}

class _Problem extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final Widget website;

  const _Problem({required this.message, required this.onRetry, required this.website});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, color: brand.muted, size: 36),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: brand.body)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
              website,
            ],
          ),
        ],
      ),
    );
  }
}

class _SupplierItemCard extends StatelessWidget {
  final SupplierItem item;
  final Supplier supplier;

  const _SupplierItemCard({required this.item, required this.supplier});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final level = item.level;
    final meta = [if (item.brand != null) item.brand!, if (item.category != null) item.category!].join(' · ');
    final placeholder = ColoredBox(
      color: brand.subtle,
      child: Center(child: Icon(Icons.inventory_2_outlined, color: brand.muted, size: 32)),
    );
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: item.image == null
                  ? placeholder
                  : Image.network(item.image!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 12)),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (item.priceText != null)
                      Expanded(
                        child: Text(item.priceText!, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      )
                    else
                      const Spacer(),
                    if (level != null) StockChip(level: level, count: item.stock),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => openExternal(context, item.url),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text('View in ${supplier.name}', overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
