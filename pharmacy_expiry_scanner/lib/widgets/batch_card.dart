// lib/widgets/batch_card.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/pharmacy_item.dart';
import '../utils/app_theme.dart';

class BatchCard extends StatelessWidget {
  final Batch batch;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onAdjust;

  const BatchCard({
    super.key,
    required this.batch,
    required this.onEdit,
    required this.onDelete,
    this.onAdjust,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = batch.isRemoved
        ? AppTheme.textSecondary
        : batch.isOutOfStock
            ? AppTheme.lowStock
            : _statusColor(batch.expiryStatus);
    final statusLabel = batch.isRemoved
        ? 'REMOVED'
        : batch.isOutOfStock
            ? 'OUT OF STOCK'
            : _statusLabel(batch.expiryStatus);
    final statusIcon = batch.isRemoved
        ? Icons.block
        : batch.isOutOfStock
            ? Icons.inventory_2_outlined
            : _statusIcon(batch.expiryStatus);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side:
            BorderSide(color: statusColor.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(statusIcon, size: 13, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: TextStyle(
                          fontSize: 11,
                          color: statusColor,
                          fontWeight: FontWeight.w700),
                    ),
                  ]),
                ),
                const Spacer(),
                IconButton(
                  icon:
                      const Icon(Icons.tune, size: 18, color: AppTheme.primary),
                  onPressed: onAdjust,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Adjust stock',
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit,
                      size: 18, color: AppTheme.textSecondary),
                  onPressed: onEdit,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: AppTheme.expired),
                  onPressed: onDelete,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                    child: _InfoCell(label: 'Batch No', value: batch.batchNo)),
                Expanded(
                  child: _InfoCell(
                    label: 'Expiry',
                    value: batch.isExpiryMissing
                        ? 'Expiry Missing'
                        : DateFormat('dd MMM yyyy').format(batch.expiryDate),
                    valueColor: statusColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _InfoCell(
                        label: 'Quantity', value: '${batch.quantity}')),
                Expanded(
                  child: _InfoCell(
                    label: batch.isExpiryMissing
                        ? 'Status'
                        : batch.isExpired
                            ? 'Expired'
                            : 'Days Left',
                    value: batch.isExpiryMissing
                        ? 'Review before sale'
                        : batch.isExpired
                            ? '${batch.daysUntilExpiry.abs()} days ago'
                            : '${batch.daysUntilExpiry} days',
                    valueColor: statusColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _InfoCell(
                        label: 'Purchase',
                        value: '\$${batch.purchasePrice.toStringAsFixed(2)}')),
                Expanded(
                    child: _InfoCell(
                        label: 'Sale Price',
                        value: '\$${batch.salePrice.toStringAsFixed(2)}')),
              ],
            ),
            if (batch.supplier.isNotEmpty) ...[
              const SizedBox(height: 8),
              _InfoCell(label: 'Supplier', value: batch.supplier),
            ],
            const SizedBox(height: 8),
            _InfoCell(
              label: 'Purchase Date',
              value: DateFormat('dd MMM yyyy').format(batch.purchaseDate),
            ),
            const SizedBox(height: 8),
            _InfoCell(
                label: 'Last Updated',
                value:
                    DateFormat('dd MMM yyyy, HH:mm').format(batch.updatedAt)),
          ],
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
      ExpiryStatus.expired => 'EXPIRED',
      ExpiryStatus.within7Days => 'WITHIN 7 DAYS',
      ExpiryStatus.within30Days => 'WITHIN 30 DAYS',
      ExpiryStatus.safe => 'SAFE',
      ExpiryStatus.missing => 'EXPIRY MISSING',
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

class _InfoCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoCell({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        Text(
          value,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppTheme.textPrimary),
        ),
      ],
    );
  }
}
