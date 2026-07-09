// lib/screens/auto_update_medicine_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/pharmacy_item.dart';
import '../services/firestore_service.dart';
import '../utils/app_theme.dart';
import '../widgets/batch_card.dart';
import 'update_medicine_screen.dart';

PdfColor _pdfExpiryColor(ExpiryStatus status) {
  return switch (status) {
    ExpiryStatus.expired => PdfColor.fromInt(0xFFD32F2F),
    ExpiryStatus.within7Days => PdfColor.fromInt(0xFFF57C00),
    ExpiryStatus.within30Days => PdfColor.fromInt(0xFFFBC02D),
    ExpiryStatus.safe => PdfColor.fromInt(0xFF2E7D32),
    ExpiryStatus.missing => PdfColor.fromInt(0xFF6A5F7D),
  };
}

PdfColor _pdfExpiryBackground(ExpiryStatus status) {
  return switch (status) {
    ExpiryStatus.expired => PdfColor.fromInt(0xFFFFEBEE),
    ExpiryStatus.within7Days => PdfColor.fromInt(0xFFFFF3E0),
    ExpiryStatus.within30Days => PdfColor.fromInt(0xFFFFFDE7),
    ExpiryStatus.safe => PdfColor.fromInt(0xFFE8F5E9),
    ExpiryStatus.missing => PdfColor.fromInt(0xFFF0EEF5),
  };
}

String _expiryLabel(ExpiryStatus status) {
  return switch (status) {
    ExpiryStatus.expired => 'Expired',
    ExpiryStatus.within7Days => '7 days',
    ExpiryStatus.within30Days => '30 days',
    ExpiryStatus.safe => 'Safe',
    ExpiryStatus.missing => 'Expiry Missing',
  };
}

class AutoUpdateMedicineScreen extends StatefulWidget {
  final String barcode;
  const AutoUpdateMedicineScreen({super.key, required this.barcode});

  @override
  State<AutoUpdateMedicineScreen> createState() =>
      _AutoUpdateMedicineScreenState();
}

class _AutoUpdateMedicineScreenState extends State<AutoUpdateMedicineScreen> {
  final _firestoreService = FirestoreService();
  PharmacyItemWithBatches? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _firestoreService.getItemWithBatches(widget.barcode);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  Future<void> _openFullEdit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => UpdateMedicineScreen(barcode: widget.barcode)),
    );
    await _load();
  }

  Future<void> _addNewBatch() async {
    await _openFullEdit();
  }

  Future<void> _printItem() async {
    final data = _data;
    if (data == null) return;
    final settings = await _firestoreService.getStoreSettings();
    final now = DateTime.now();
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          ..._itemPrintHeader(settings, data.item.displayName, now),
          pw.Text('Barcode: ${data.item.barcode}'),
          pw.Text('Generic: ${data.item.genericName}'),
          pw.Text('Brand: ${data.item.brand}'),
          pw.Text('Strength: ${data.item.strength}'),
          pw.Text('Dosage form: ${data.item.dosageForm}'),
          pw.Text(
              'Last updated: ${DateFormat('dd MMM yyyy HH:mm').format(data.item.updatedAt)}'),
          pw.SizedBox(height: 16),
          _batchPrintTable(data.activeBatches),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  List<pw.Widget> _itemPrintHeader(
    StoreSettings settings,
    String title,
    DateTime generatedAt,
  ) {
    return [
      pw.Text(
        settings.storeName,
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
      ),
      if (settings.dbaName.trim().isNotEmpty)
        pw.Text(
          settings.dbaName,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
      pw.Text(settings.addressLine1, style: const pw.TextStyle(fontSize: 10)),
      pw.Text(settings.cityStateZip, style: const pw.TextStyle(fontSize: 10)),
      pw.SizedBox(height: 10),
      pw.Text(
        title,
        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
      ),
      pw.Text(
        'Generated: ${DateFormat('dd MMM yyyy HH:mm').format(generatedAt)}',
        style: const pw.TextStyle(fontSize: 9),
      ),
      pw.Divider(),
      pw.SizedBox(height: 8),
    ];
  }

  pw.Widget _batchPrintTable(List<Batch> batches) {
    pw.Widget cell(String text,
        {bool header = false, PdfColor? color, PdfColor? background}) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        color: background,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: header ? 9 : 8,
            fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color,
          ),
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            cell('Batch', header: true),
            cell('Expiry', header: true),
            cell('Days', header: true),
            cell('Qty', header: true),
            cell('Supplier', header: true),
            cell('Status', header: true),
          ],
        ),
        ...batches.map((batch) {
          final color = _pdfExpiryColor(batch.expiryStatus);
          return pw.TableRow(
            decoration: pw.BoxDecoration(
                color: _pdfExpiryBackground(batch.expiryStatus)),
            children: [
              cell(batch.batchNo, color: color),
              cell(
                  batch.isExpiryMissing
                      ? 'Expiry Missing'
                      : DateFormat('dd MMM yyyy').format(batch.expiryDate),
                  color: color),
              cell(batch.isExpiryMissing ? '-' : '${batch.daysUntilExpiry}',
                  color: color),
              cell('${batch.quantity}', color: color),
              cell(batch.supplier, color: color),
              cell(_expiryLabel(batch.expiryStatus), color: color),
            ],
          );
        }),
      ],
    );
  }

  Future<void> _adjustStock(Batch batch, bool adding) async {
    final result = await showDialog<_StockUpdateResult>(
      context: context,
      builder: (_) => _StockUpdateDialog(adding: adding),
    );
    if (result == null) return;
    final change = adding ? result.quantity : -result.quantity;
    await _firestoreService.updateBatchQuantity(
      barcode: widget.barcode,
      batchId: batch.batchId,
      quantityChange: change,
      reason: result.reason,
    );
    await _load();
  }

  Future<void> _updateExpiry(Batch batch) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: batch.isExpiryMissing ? DateTime.now() : batch.expiryDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: AppTheme.primary)),
        child: child!,
      ),
    );
    if (picked == null) return;
    await _firestoreService.updateBatchExpiry(
      barcode: widget.barcode,
      batchId: batch.batchId,
      expiryDate: picked,
      reason: 'Correction',
    );
    await _load();
  }

  Future<void> _markRemoved(Batch batch) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(
          title: 'Remove Stock', defaultReason: 'Expired removed'),
    );
    if (result == null) return;
    await _firestoreService.updateBatchStatus(
      barcode: widget.barcode,
      batchId: batch.batchId,
      status: batch.isExpired ? BatchStatus.expired : BatchStatus.removed,
      reason: result,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final data = _data;
    if (data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Auto Update')),
        body: const Center(child: Text('Item not found')),
      );
    }
    final color = _statusColor(data.expiryStatus);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto Update Medicine'),
        actions: [
          IconButton(icon: const Icon(Icons.edit), onPressed: _openFullEdit),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.12),
                      child: Icon(Icons.medication, color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(data.item.displayName,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w800)),
                            if (data.item.description.isNotEmpty)
                              Text(data.item.description,
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary)),
                            const SizedBox(height: 4),
                            Text(
                                'Last updated ${DateFormat('dd MMM yyyy, HH:mm').format(data.item.updatedAt)}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary)),
                          ]),
                    ),
                    Text('Qty ${data.totalQuantity}',
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: ElevatedButton.icon(
                      onPressed: _addNewBatch,
                      icon: const Icon(Icons.add_box),
                      label: const Text('Add New Batch'))),
              const SizedBox(width: 10),
              Expanded(
                  child: ElevatedButton.icon(
                      onPressed: _printItem,
                      icon: const Icon(Icons.print),
                      label: const Text('Print'))),
            ]),
            const SizedBox(height: 18),
            const Text('Existing Batches',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            if (data.batches.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'No batches yet. Add a new batch to start tracking stock.',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ),
              )
            else
              ...data.batches.map((batch) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(children: [
                      BatchCard(
                          batch: batch,
                          onEdit: () => _openFullEdit(),
                          onDelete: () => _markRemoved(batch)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ActionButton(
                              label: 'Add Stock',
                              icon: Icons.add,
                              onTap: () => _adjustStock(batch, true)),
                          _ActionButton(
                              label: 'Reduce Stock',
                              icon: Icons.remove,
                              onTap: () => _adjustStock(batch, false)),
                          _ActionButton(
                              label: 'Update Expiry Date',
                              icon: Icons.event,
                              onTap: () => _updateExpiry(batch)),
                          _ActionButton(
                              label: 'Mark Expired / Remove',
                              icon: Icons.block,
                              onTap: () => _markRemoved(batch)),
                        ],
                      ),
                    ]),
                  )),
            const SizedBox(height: 80),
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
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ActionButton(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
        onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label));
  }
}

class _StockUpdateResult {
  final int quantity;
  final String reason;
  const _StockUpdateResult({required this.quantity, required this.reason});
}

class _StockUpdateDialog extends StatefulWidget {
  final bool adding;
  const _StockUpdateDialog({required this.adding});

  @override
  State<_StockUpdateDialog> createState() => _StockUpdateDialogState();
}

class _StockUpdateDialogState extends State<_StockUpdateDialog> {
  final _quantityCtrl = TextEditingController();
  String _reason = 'New stock received';

  @override
  void initState() {
    super.initState();
    _reason = widget.adding ? 'New stock received' : 'Sold';
  }

  @override
  void dispose() {
    _quantityCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const reasons = [
      'New stock received',
      'Sold',
      'Damaged',
      'Expired removed',
      'Correction'
    ];
    return AlertDialog(
      title: Text(widget.adding ? 'Add Stock' : 'Reduce Stock'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _quantityCtrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Quantity'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _reason,
            decoration: const InputDecoration(labelText: 'Reason'),
            items: reasons
                .map((reason) =>
                    DropdownMenuItem(value: reason, child: Text(reason)))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _reason = value);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final quantity = int.tryParse(_quantityCtrl.text.trim()) ?? 0;
            if (quantity <= 0) return;
            Navigator.pop(context,
                _StockUpdateResult(quantity: quantity, reason: _reason));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  final String title;
  final String defaultReason;
  const _ReasonDialog({required this.title, required this.defaultReason});

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  late String _reason;

  @override
  void initState() {
    super.initState();
    _reason = widget.defaultReason;
  }

  @override
  Widget build(BuildContext context) {
    const reasons = ['Expired removed', 'Damaged', 'Correction', 'Sold'];
    return AlertDialog(
      title: Text(widget.title),
      content: DropdownButtonFormField<String>(
        initialValue: _reason,
        decoration: const InputDecoration(labelText: 'Reason'),
        items: reasons
            .map((reason) =>
                DropdownMenuItem(value: reason, child: Text(reason)))
            .toList(),
        onChanged: (value) {
          if (value != null) setState(() => _reason = value);
        },
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
            onPressed: () => Navigator.pop(context, _reason),
            child: const Text('Save')),
      ],
    );
  }
}
