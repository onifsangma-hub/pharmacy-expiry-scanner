// lib/screens/inventory_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/pharmacy_item.dart';
import '../services/firestore_service.dart';
import '../utils/app_theme.dart';
import 'update_medicine_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _firestoreService = FirestoreService();
  StreamSubscription<void>? _stockSubscription;
  List<PharmacyItemWithBatches> _items = [];
  List<PharmacyItemWithBatches> _filtered = [];
  bool _loading = true;
  String _search = '';
  String _filterCategory = 'All';
  String _filterStatus = 'All';

  @override
  void initState() {
    super.initState();
    _stockSubscription = _firestoreService.stockChanges.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _stockSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _firestoreService.getAllItemsWithBatches();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
    _applyFilters();
  }

  void _applyFilters() {
    final query = _search.trim().toLowerCase();
    final filtered = _items.where((data) {
      final item = data.item;
      final batchText = data.batches
          .map((batch) => '${batch.batchNo} ${batch.supplier}')
          .join(' ')
          .toLowerCase();
      final matchSearch = query.isEmpty ||
          item.medicineName.toLowerCase().contains(query) ||
          item.genericName.toLowerCase().contains(query) ||
          item.brand.toLowerCase().contains(query) ||
          item.barcode.toLowerCase().contains(query) ||
          batchText.contains(query);
      final matchCategory =
          _filterCategory == 'All' || item.category == _filterCategory;
      final matchStatus = _filterStatus == 'All' ||
          (_filterStatus == 'Expired' && data.hasExpiredBatches) ||
          (_filterStatus == 'Expiry Missing' && data.hasMissingExpiryBatches) ||
          (_filterStatus == 'Low Stock' && data.isLowStock) ||
          (_filterStatus == 'Within 7 Days' && data.hasWithin7DaysBatches) ||
          (_filterStatus == 'Within 30 Days' && data.hasWithin30DaysBatches) ||
          (_filterStatus == 'Safe' && data.expiryStatus == ExpiryStatus.safe);
      return matchSearch && matchCategory && matchStatus;
    }).toList()
      ..sort((a, b) {
        final aBatch = a.nextExpiringBatch;
        final bBatch = b.nextExpiringBatch;
        if (aBatch == null && bBatch == null) return 0;
        if (aBatch == null) return 1;
        if (bBatch == null) return -1;
        return aBatch.expiryDate.compareTo(bBatch.expiryDate);
      });
    if (mounted) setState(() => _filtered = filtered);
  }

  @override
  Widget build(BuildContext context) {
    final categories = ['All', ...AppCategories.list];

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      body: Column(
        children: [
          Container(
            color: AppTheme.primary,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [
                TextField(
                  onChanged: (value) {
                    _search = value;
                    _applyFilters();
                  },
                  decoration: InputDecoration(
                    hintText: 'Search name, barcode, batch, supplier...',
                    prefixIcon: const Icon(Icons.search),
                    fillColor: Colors.white,
                    filled: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                          label: 'All',
                          selected: _filterStatus == 'All',
                          onTap: () => _setStatus('All')),
                      _FilterChip(
                          label: 'Expired',
                          selected: _filterStatus == 'Expired',
                          onTap: () => _setStatus('Expired')),
                      _FilterChip(
                          label: 'Expiry Missing',
                          selected: _filterStatus == 'Expiry Missing',
                          onTap: () => _setStatus('Expiry Missing')),
                      _FilterChip(
                          label: 'Low Stock',
                          selected: _filterStatus == 'Low Stock',
                          onTap: () => _setStatus('Low Stock')),
                      _FilterChip(
                          label: 'Within 7 Days',
                          selected: _filterStatus == 'Within 7 Days',
                          onTap: () => _setStatus('Within 7 Days')),
                      _FilterChip(
                          label: 'Within 30 Days',
                          selected: _filterStatus == 'Within 30 Days',
                          onTap: () => _setStatus('Within 30 Days')),
                      _FilterChip(
                          label: 'Safe',
                          selected: _filterStatus == 'Safe',
                          onTap: () => _setStatus('Safe')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text('${_filtered.length} medicines',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13)),
                  const Spacer(),
                  DropdownButton<String>(
                    value: _filterCategory,
                    underline: const SizedBox(),
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600),
                    items: categories
                        .map((category) => DropdownMenuItem(
                            value: category, child: Text(category)))
                        .toList(),
                    onChanged: (value) {
                      setState(() => _filterCategory = value!);
                      _applyFilters();
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(
                        child: Text('No medicines found',
                            style: TextStyle(color: AppTheme.textSecondary)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, index) => _ItemTile(
                            data: _filtered[index],
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => UpdateMedicineScreen(
                                        barcode:
                                            _filtered[index].item.barcode)),
                              );
                              _load();
                            },
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _setStatus(String value) {
    _filterStatus = value;
    _applyFilters();
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
              color:
                  selected ? Colors.white : Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20)),
          child: Text(
            label,
            style: TextStyle(
                fontSize: 13,
                color: selected ? AppTheme.primary : Colors.white,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final PharmacyItemWithBatches data;
  final VoidCallback onTap;
  const _ItemTile({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(data.expiryStatus);
    final statusLabel = _statusLabel(data.expiryStatus);
    final nextBatch = data.nextExpiringBatch;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(_statusIcon(data.expiryStatus),
                    color: statusColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.item.displayName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: AppTheme.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (data.item.description.isNotEmpty)
                        Text(data.item.description,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textSecondary),
                            overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text(
                        '${data.batches.length} batch${data.batches.length == 1 ? '' : 'es'}'
                        '${nextBatch == null ? '' : nextBatch.isExpiryMissing ? ' - Next: Expiry Missing' : ' - Next: ${DateFormat('dd MMM yyyy').format(nextBatch.expiryDate)}'}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (data.activeBatches.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: data.activeBatches
                              .map((batch) => _BatchStatusBadge(batch: batch))
                              .toList(),
                        ),
                      ],
                    ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Qty ${data.totalQuantity}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppTheme.textPrimary)),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(statusLabel,
                      style: TextStyle(
                          fontSize: 11,
                          color: statusColor,
                          fontWeight: FontWeight.w600)),
                ),
                if (data.isLowStock)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppTheme.lowStock.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Text('LOW STOCK',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.lowStock,
                            fontWeight: FontWeight.w600)),
                  ),
                if (data.isLowStock)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      'Current: ${data.totalActiveQuantity}\nMinimum: ${data.item.minimumStockLevel}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.lowStock,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ]),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(ExpiryStatus status) {
    return switch (status) {
      ExpiryStatus.expired => AppTheme.expired,
      ExpiryStatus.within7Days => AppTheme.expiring7Days,
      ExpiryStatus.within30Days => AppTheme.expiring30Days,
      ExpiryStatus.safe => AppTheme.healthy,
      ExpiryStatus.missing => AppTheme.expiryMissing,
    };
  }

  String _statusLabel(ExpiryStatus status) {
    return switch (status) {
      ExpiryStatus.expired => 'Expired',
      ExpiryStatus.within7Days => '7 days',
      ExpiryStatus.within30Days => '30 days',
      ExpiryStatus.safe => 'Safe',
      ExpiryStatus.missing => 'Expiry Missing',
    };
  }

  IconData _statusIcon(ExpiryStatus status) {
    return switch (status) {
      ExpiryStatus.expired => Icons.dangerous,
      ExpiryStatus.within7Days => Icons.priority_high,
      ExpiryStatus.within30Days => Icons.timer,
      ExpiryStatus.safe => Icons.check_circle,
      ExpiryStatus.missing => Icons.help_outline,
    };
  }
}

class _BatchStatusBadge extends StatelessWidget {
  final Batch batch;
  const _BatchStatusBadge({required this.batch});

  @override
  Widget build(BuildContext context) {
    final color = switch (batch.expiryStatus) {
      ExpiryStatus.expired => AppTheme.expired,
      ExpiryStatus.within7Days => AppTheme.expiring7Days,
      ExpiryStatus.within30Days => AppTheme.expiring30Days,
      ExpiryStatus.safe => AppTheme.healthy,
      ExpiryStatus.missing => AppTheme.expiryMissing,
    };
    final badgeColor = batch.isOutOfStock ? AppTheme.lowStock : color;
    final label = batch.isOutOfStock
        ? '${batch.batchNo}: out'
        : batch.isExpiryMissing
            ? '${batch.batchNo}: Expiry Missing'
            : batch.isExpired
                ? '${batch.batchNo}: expired'
                : '${batch.batchNo}: ${batch.daysUntilExpiry}d';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: badgeColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
