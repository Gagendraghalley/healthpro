import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/suppliers.dart';
import '../gym_permissions.dart';
import '../widgets/gym_widgets.dart';

/// Items from systems connected to Health Pro, with their stock there now,
/// for the gym's owner and managers. Shown only: each item opens in the
/// supplier's own system, where it's ordered and paid for.
class SuppliersScreen extends ConsumerStatefulWidget {
  final String venueId;

  /// The supplier shown first, by key (a link's `?open=`).
  final String? openId;

  const SuppliersScreen({super.key, required this.venueId, this.openId});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  late String? _supplier = widget.openId;

  @override
  void didUpdateWidget(covariant SuppliersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openId != null && widget.openId != oldWidget.openId) _supplier = widget.openId;
  }

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
