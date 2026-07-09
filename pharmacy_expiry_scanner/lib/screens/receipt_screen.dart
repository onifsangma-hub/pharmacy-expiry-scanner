import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/pharmacy_item.dart';
import '../services/receipt_service.dart';
import '../utils/app_theme.dart';

class ReceiptScreen extends StatelessWidget {
  final SaleRecord sale;

  ReceiptScreen({super.key, required this.sale});

  final ReceiptService _receiptService = ReceiptService();

  @override
  Widget build(BuildContext context) {
    final receiptNo = _receiptService.receiptNumber(sale);

    return Scaffold(
      appBar: AppBar(
        title: Text('Receipt #$receiptNo'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Finish', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 420),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppTheme.divider),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'ASM DRUGS INC.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        const Text(
                          'FARMACIA CENTRAL',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '55A East Gun Hill Road',
                          textAlign: TextAlign.center,
                        ),
                        const Text('Bronx, NY 10467',
                            textAlign: TextAlign.center),
                        const Divider(height: 28),
                        _InfoRow(label: 'Receipt number', value: receiptNo),
                        _InfoRow(
                          label: 'Date/time',
                          value: DateFormat('MM/dd/yyyy hh:mm a')
                              .format(sale.soldAt),
                        ),
                        _InfoRow(
                          label: 'Cashier',
                          value: sale.userEmail.isEmpty ? '-' : sale.userEmail,
                        ),
                        const Divider(height: 28),
                        ...sale.batchesUsed.map(
                          (batch) => _ReceiptItem(
                            medicineName: sale.medicineName,
                            details: _medicineDetails(sale),
                            quantity: batch.quantity,
                            unitPrice: batch.salePrice,
                            total: batch.totalSaleAmount,
                          ),
                        ),
                        const Divider(height: 28),
                        _InfoRow(
                          label: 'Payment method',
                          value: sale.paymentMethod,
                        ),
                        _InfoRow(
                          label: 'Total',
                          value: '\$${sale.totalSaleAmount.toStringAsFixed(2)}',
                          bold: true,
                        ),
                        const SizedBox(height: 22),
                        const Text(
                          'COME SEE US AGAIN',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _ReceiptActions(
              onFinish: () => Navigator.pop(context),
              onSavePdf: () => _receiptService.savePdf(sale),
              onSharePdf: () => _receiptService.sharePdf(sale),
            ),
          ],
        ),
      ),
    );
  }

  String _medicineDetails(SaleRecord sale) {
    return [sale.strength, sale.packageSize]
        .where((part) => part.trim().isNotEmpty)
        .join(' / ');
  }
}

class _ReceiptItem extends StatelessWidget {
  final String medicineName;
  final String details;
  final int quantity;
  final double unitPrice;
  final double total;

  const _ReceiptItem({
    required this.medicineName,
    required this.details,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            medicineName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              details,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Text('Qty $quantity'),
              const Spacer(),
              Text('@ \$${unitPrice.toStringAsFixed(2)}'),
              const SizedBox(width: 12),
              Text(
                '\$${total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _InfoRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptActions extends StatelessWidget {
  final VoidCallback onFinish;
  final Future<void> Function() onSavePdf;
  final Future<void> Function() onSharePdf;

  const _ReceiptActions({
    required this.onFinish,
    required this.onSavePdf,
    required this.onSharePdf,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: onFinish,
              icon: const Icon(Icons.check),
              label: const Text('Finish'),
            ),
            OutlinedButton.icon(
              onPressed: onSavePdf,
              icon: const Icon(Icons.save_alt),
              label: const Text('Save PDF'),
            ),
            OutlinedButton.icon(
              onPressed: onSharePdf,
              icon: const Icon(Icons.share),
              label: const Text('Share PDF'),
            ),
          ],
        ),
      ),
    );
  }
}
