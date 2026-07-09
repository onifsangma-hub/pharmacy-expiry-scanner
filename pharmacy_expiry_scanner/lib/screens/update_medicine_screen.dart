// lib/screens/update_medicine_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/pharmacy_item.dart';
import '../services/firestore_service.dart';
import '../utils/app_theme.dart';
import '../widgets/batch_card.dart';
import '../widgets/form_field_label.dart';

class UpdateMedicineScreen extends StatefulWidget {
  final String barcode;
  final bool openAddBatchOnLoad;
  final bool openSellOnLoad;
  final String initialBatchNo;
  final DateTime? initialExpiryDate;
  final DateTime? initialManufactureDate;
  const UpdateMedicineScreen({
    super.key,
    required this.barcode,
    this.openAddBatchOnLoad = false,
    this.openSellOnLoad = false,
    this.initialBatchNo = '',
    this.initialExpiryDate,
    this.initialManufactureDate,
  });

  @override
  State<UpdateMedicineScreen> createState() => _UpdateMedicineScreenState();
}

class _UpdateMedicineScreenState extends State<UpdateMedicineScreen> {
  final _firestoreService = FirestoreService();
  PharmacyItemWithBatches? _data;
  List<UpdateHistory> _history = [];
  bool _loading = true;
  bool _editing = false;
  bool _openedInitialBatchForm = false;
  bool _openedInitialSaleDialog = false;

  final _nameCtrl = TextEditingController();
  final _genericCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _ndcCtrl = TextEditingController();
  final _manufacturerCtrl = TextEditingController();
  final _strengthCtrl = TextEditingController();
  final _minimumStockCtrl = TextEditingController(text: '0');
  final _reorderLevelCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  // Blank when uncategorized — never silently defaulted to a guessed category.
  String _category = '';
  String _dosageForm = AppDosageForms.list.first;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _genericCtrl.dispose();
    _brandCtrl.dispose();
    _ndcCtrl.dispose();
    _manufacturerCtrl.dispose();
    _strengthCtrl.dispose();
    _minimumStockCtrl.dispose();
    _reorderLevelCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _firestoreService.getItemWithBatches(widget.barcode);
    final history = await _firestoreService.getHistory(widget.barcode);
    if (!mounted) return;
    setState(() {
      _data = data;
      _history = history;
      _loading = false;
      if (data != null) _fillControllers(data.item);
    });
    if (widget.openAddBatchOnLoad && !_openedInitialBatchForm && data != null) {
      _openedInitialBatchForm = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addBatch();
      });
    }
    if (widget.openSellOnLoad && !_openedInitialSaleDialog && data != null) {
      _openedInitialSaleDialog = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sellMedicine();
      });
    }
  }

  void _fillControllers(PharmacyItem item) {
    _nameCtrl.text = item.medicineName;
    _genericCtrl.text = item.genericName;
    _brandCtrl.text = item.brand;
    _ndcCtrl.text = item.ndc;
    _manufacturerCtrl.text = item.manufacturer;
    _strengthCtrl.text = item.strength;
    _minimumStockCtrl.text = '${item.minimumStockLevel}';
    _reorderLevelCtrl.text =
        item.reorderLevel == 0 ? '' : '${item.reorderLevel}';
    _notesCtrl.text = item.notes;
    // Preserve a blank category — do not coerce to a default.
    _category = item.category;
    _dosageForm = item.dosageForm.isNotEmpty
        ? item.dosageForm
        : AppDosageForms.list.first;
  }

  Future<void> _saveItem() async {
    if (_data == null) return;
    final duplicateNdc = await _firestoreService.findItemByNdc(
      _ndcCtrl.text,
      excludingBarcode: _data!.item.barcode,
    );
    if (duplicateNdc != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('NDC already used by ${duplicateNdc.displayName}'),
          backgroundColor: AppTheme.expired,
        ),
      );
      return;
    }
    final minimumStockText = _minimumStockCtrl.text.trim();
    final minimumStockLevel = int.tryParse(minimumStockText);
    if (minimumStockText.isEmpty || minimumStockLevel == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Minimum stock level is required'),
          backgroundColor: AppTheme.expired,
        ),
      );
      return;
    }
    if (minimumStockLevel < 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Minimum stock level must be 0 or higher'),
          backgroundColor: AppTheme.expired,
        ),
      );
      return;
    }
    final reorderText = _reorderLevelCtrl.text.trim();
    final reorderLevel = reorderText.isEmpty ? 0 : int.tryParse(reorderText);
    if (reorderLevel == null || reorderLevel < 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reorder level must be 0 or higher'),
          backgroundColor: AppTheme.expired,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final updated = PharmacyItem(
      barcode: _data!.item.barcode,
      medicineName: _nameCtrl.text.trim(),
      genericName: _genericCtrl.text.trim(),
      brand: _brandCtrl.text.trim(),
      ndc: _ndcCtrl.text.trim(),
      manufacturer: _manufacturerCtrl.text.trim(),
      strength: _strengthCtrl.text.trim(),
      dosageForm: _dosageForm,
      category: _category,
      minimumStockLevel: minimumStockLevel,
      reorderLevel: reorderLevel,
      notes: _notesCtrl.text.trim(),
      createdAt: _data!.item.createdAt,
      updatedAt: now,
    );
    await _firestoreService.saveItem(updated);
    if (!mounted) return;
    setState(() => _editing = false);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Medicine updated'),
            backgroundColor: AppTheme.healthy),
      );
    }
  }

  void _addBatch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BatchForm(
        barcode: widget.barcode,
        initialBatchNo: widget.initialBatchNo,
        initialExpiryDate: widget.initialExpiryDate,
        initialManufactureDate: widget.initialManufactureDate,
        onSaved: _load,
        onEditExisting: _editBatch,
      ),
    );
  }

  void _editBatch(Batch batch) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BatchForm(
        barcode: widget.barcode,
        existingBatch: batch,
        onSaved: _load,
        onEditExisting: _editBatch,
      ),
    );
  }

  Future<void> _sellMedicine() async {
    final data = _data;
    if (data == null) return;
    final quantity = await showDialog<int>(
      context: context,
      builder: (_) => const _SaleDialog(),
    );
    if (quantity == null || !mounted) return;

    final paymentMethod = await showDialog<String>(
      context: context,
      builder: (_) => const _PaymentMethodDialog(),
    );
    if (paymentMethod == null) return;

    // FEFO logic
    final nonExpiredQty = data.batches
        .where((batch) => batch.hasStock && !batch.isExpired)
        .fold<int>(0, (sum, batch) => sum + batch.quantity);
    final expiredQty = data.batches
        .where((batch) => batch.hasStock && batch.isExpired)
        .fold<int>(0, (sum, batch) => sum + batch.quantity);
    var allowExpiredOverride = false;
    if (quantity > nonExpiredQty && expiredQty > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Expired Stock Override'),
          content: Text(
            nonExpiredQty == 0
                ? 'Only expired stock is available for this barcode. Continue with sale override?'
                : 'Only $nonExpiredQty non-expired unit(s) are available. Selling $quantity unit(s) will use expired stock. Continue with sale override?',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppTheme.expired),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Override'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      allowExpiredOverride = true;
    }

    if (_saleWouldUseMissingExpiry(data, quantity, allowExpiredOverride)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Expiry Missing'),
          content: const Text('Expiry date is missing. Confirm before sale.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm Sale'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      final sale = await _firestoreService.recordSale(
        barcode: widget.barcode,
        quantitySold: quantity,
        paymentMethod: paymentMethod,
        allowExpiredOverride: allowExpiredOverride,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sold $quantity unit(s) - Total \$${sale.totalSaleAmount.toStringAsFixed(2)}, profit \$${sale.profit.toStringAsFixed(2)}',
            ),
            backgroundColor: AppTheme.healthy,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: AppTheme.expired,
        ),
      );
    }
  }

  bool _saleWouldUseMissingExpiry(
    PharmacyItemWithBatches data,
    int quantity,
    bool allowExpiredOverride,
  ) {
    var remaining = quantity;
    final batches = data.batches
        .where((batch) =>
            batch.hasStock && (allowExpiredOverride || !batch.isExpired))
        .toList()
      ..sort((a, b) {
        if (a.isExpired != b.isExpired) return a.isExpired ? 1 : -1;
        if (a.isExpiryMissing != b.isExpiryMissing) {
          return a.isExpiryMissing ? 1 : -1;
        }
        return a.expiryDate.compareTo(b.expiryDate);
      });
    for (final batch in batches) {
      if (remaining <= 0) return false;
      final used = batch.quantity < remaining ? batch.quantity : remaining;
      if (used > 0 && batch.isExpiryMissing) return true;
      remaining -= used;
    }
    return false;
  }

  Future<void> _deleteBatch(Batch batch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Batch'),
        content: Text('Delete batch ${batch.batchNo}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.expired),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _firestoreService.deleteBatch(widget.barcode, batch);
      await _load();
    }
  }

  Future<void> _adjustBatch(Batch batch) async {
    final result = await showDialog<_StockAdjustmentResult>(
      context: context,
      builder: (_) => _StockAdjustmentDialog(batch: batch),
    );
    if (result == null) return;
    try {
      await _firestoreService.adjustBatchStock(
        barcode: widget.barcode,
        batchId: batch.batchId,
        quantityChange: result.quantityChange,
        reason: result.reason,
        note: result.note,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stock adjusted'),
          backgroundColor: AppTheme.healthy,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: AppTheme.expired,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Medicine')),
        body: const Center(child: Text('Item not found')),
      );
    }

    final item = _data!.item;
    final batches = _data!.batches;

    return Scaffold(
      appBar: AppBar(
        title: Text(item.displayName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(_editing ? Icons.close : Icons.edit),
            onPressed: () {
              if (_editing) _fillControllers(item);
              setState(() => _editing = !_editing);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _MedicineCard(
              item: item,
              data: _data!,
              editing: _editing,
              nameCtrl: _nameCtrl,
              genericCtrl: _genericCtrl,
              brandCtrl: _brandCtrl,
              ndcCtrl: _ndcCtrl,
              manufacturerCtrl: _manufacturerCtrl,
              strengthCtrl: _strengthCtrl,
              minimumStockCtrl: _minimumStockCtrl,
              reorderLevelCtrl: _reorderLevelCtrl,
              notesCtrl: _notesCtrl,
              category: _category,
              dosageForm: _dosageForm,
              onCategoryChanged: (value) => setState(() => _category = value),
              onDosageFormChanged: (value) =>
                  setState(() => _dosageForm = value),
              onSave: _saveItem,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Batches (${batches.length})',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary),
                  ),
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                        onPressed: _addBatch,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Batch')),
                    TextButton.icon(
                        onPressed: _sellMedicine,
                        icon: const Icon(Icons.point_of_sale, size: 18),
                        label: const Text('Sell')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (batches.isEmpty)
              const _EmptyBatches()
            else
              ...batches.map(
                (batch) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: BatchCard(
                      batch: batch,
                      onEdit: () => _editBatch(batch),
                      onDelete: () => _deleteBatch(batch),
                      onAdjust: () => _adjustBatch(batch)),
                ),
              ),
            const SizedBox(height: 20),
            const Text(
              'Update History',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            if (_history.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No history yet',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ),
              )
            else
              ..._history.map((history) => _HistoryTile(history: history)),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sellMedicine,
        backgroundColor: AppTheme.healthy,
        icon: const Icon(Icons.point_of_sale, color: Colors.white),
        label: const Text('Sell', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _SaleDialog extends StatefulWidget {
  const _SaleDialog();

  @override
  State<_SaleDialog> createState() => _SaleDialogState();
}

class _StockAdjustmentResult {
  final int quantityChange;
  final String reason;
  final String note;

  const _StockAdjustmentResult({
    required this.quantityChange,
    required this.reason,
    required this.note,
  });
}

class _StockAdjustmentDialog extends StatefulWidget {
  final Batch batch;

  const _StockAdjustmentDialog({required this.batch});

  @override
  State<_StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<_StockAdjustmentDialog> {
  static const _reasons = [
    'Damaged',
    'Expired',
    'Lost',
    'Manual Correction',
    'Supplier Return',
    'Opening Balance',
    'Other',
  ];

  final _quantityCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _reason = _reasons.first;
  bool _increase = false;

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final quantity = int.tryParse(_quantityCtrl.text.trim()) ?? 0;
    if (quantity <= 0) return;
    if (!_increase && quantity > widget.batch.quantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adjustment cannot make stock negative.'),
          backgroundColor: AppTheme.expired,
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      _StockAdjustmentResult(
        quantityChange: _increase ? quantity : -quantity,
        reason: _reason,
        note: _noteCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Stock Adjustment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Current Qty: ${widget.batch.quantity}',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Decrease')),
                ButtonSegment(value: true, label: Text('Increase')),
              ],
              selected: {_increase},
              onSelectionChanged: (value) =>
                  setState(() => _increase = value.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantityCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantity',
                prefixIcon: Icon(Icons.numbers),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                prefixIcon: Icon(Icons.assignment_late),
              ),
              items: _reasons
                  .map((reason) =>
                      DropdownMenuItem(value: reason, child: Text(reason)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _reason = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note',
                hintText: 'Optional',
                prefixIcon: Icon(Icons.notes),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.save),
          label: const Text('Save'),
        ),
      ],
    );
  }
}

class _PaymentMethodDialog extends StatefulWidget {
  const _PaymentMethodDialog();

  @override
  State<_PaymentMethodDialog> createState() => _PaymentMethodDialogState();
}

class _PaymentMethodDialogState extends State<_PaymentMethodDialog> {
  String _selectedMethod = 'Cash';
  final _methods = ['Cash', 'Credit Card', 'Debit Card', 'Other'];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Payment Method'),
      content: DropdownButtonFormField<String>(
        initialValue: _selectedMethod,
        items: _methods
            .map((method) => DropdownMenuItem(
                  value: method,
                  child: Text(method),
                ))
            .toList(),
        onChanged: (value) {
          if (value != null) {
            setState(() {
              _selectedMethod = value;
            });
          }
        },
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.payment),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
            onPressed: () => Navigator.pop(context, _selectedMethod),
            child: const Text('Continue')),
      ],
    );
  }
}

class _SaleDialogState extends State<_SaleDialog> {
  final _quantityCtrl = TextEditingController(text: '1');

  @override
  void dispose() {
    _quantityCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record Sale'),
      content: TextField(
        controller: _quantityCtrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.numbers),
          labelText: 'Quantity sold',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            final quantity = int.tryParse(_quantityCtrl.text.trim());
            if (quantity == null || quantity <= 0) return;
            Navigator.pop(context, quantity);
          },
          icon: const Icon(Icons.point_of_sale),
          label: const Text('Sell FEFO'),
        ),
      ],
    );
  }
}

class _MedicineCard extends StatelessWidget {
  final PharmacyItem item;
  final PharmacyItemWithBatches data;
  final bool editing;
  final TextEditingController nameCtrl;
  final TextEditingController genericCtrl;
  final TextEditingController brandCtrl;
  final TextEditingController ndcCtrl;
  final TextEditingController manufacturerCtrl;
  final TextEditingController strengthCtrl;
  final TextEditingController minimumStockCtrl;
  final TextEditingController reorderLevelCtrl;
  final TextEditingController notesCtrl;
  final String category;
  final String dosageForm;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onDosageFormChanged;
  final VoidCallback onSave;

  const _MedicineCard({
    required this.item,
    required this.data,
    required this.editing,
    required this.nameCtrl,
    required this.genericCtrl,
    required this.brandCtrl,
    required this.ndcCtrl,
    required this.manufacturerCtrl,
    required this.strengthCtrl,
    required this.minimumStockCtrl,
    required this.reorderLevelCtrl,
    required this.notesCtrl,
    required this.category,
    required this.dosageForm,
    required this.onCategoryChanged,
    required this.onDosageFormChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(data.expiryStatus);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.medication, color: statusColor, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.displayName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                              color: AppTheme.textPrimary)),
                      if (item.description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(item.description,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        _Chip(
                            item.category.isEmpty
                                ? 'Uncategorized'
                                : item.category,
                            AppTheme.primary.withValues(alpha: 0.12),
                            AppTheme.primary),
                        _Chip(
                            'Qty: ${data.totalQuantity}',
                            AppTheme.healthy.withValues(alpha: 0.12),
                            AppTheme.healthy),
                        if (data.isLowStock)
                          _Chip(
                              'Low Stock',
                              AppTheme.lowStock.withValues(alpha: 0.12),
                              AppTheme.lowStock),
                      ]),
                    ]),
              ),
            ]),
            const SizedBox(height: 12),
            _InfoLine(icon: Icons.qr_code, text: item.barcode),
            if (item.ndc.isNotEmpty)
              _InfoLine(icon: Icons.numbers, text: 'NDC ${item.ndc}'),
            if (item.manufacturer.isNotEmpty)
              _InfoLine(icon: Icons.factory_outlined, text: item.manufacturer),
            _InfoLine(
                icon: Icons.event,
                text:
                    'Created ${DateFormat('dd MMM yyyy, HH:mm').format(item.createdAt)}'),
            _InfoLine(
                icon: Icons.update,
                text:
                    'Updated ${DateFormat('dd MMM yyyy, HH:mm').format(item.updatedAt)}'),
            if (item.minimumStockLevel > 0)
              _InfoLine(
                  icon: Icons.warning_amber,
                  text:
                      'Minimum stock ${item.minimumStockLevel} - Shortage ${data.shortageQty}'),
            if (item.reorderLevel > 0)
              _InfoLine(
                  icon: Icons.low_priority,
                  text: 'Reorder level ${item.reorderLevel}'),
            if (item.notes.isNotEmpty)
              _InfoLine(icon: Icons.notes, text: item.notes),
            if (editing) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              FormFieldLabel(label: 'Medicine Name'),
              TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.local_pharmacy))),
              const SizedBox(height: 12),
              _TwoColumnFields(
                left: _TextFieldBlock(
                    label: 'Generic Name',
                    controller: genericCtrl,
                    icon: Icons.science),
                right: _TextFieldBlock(
                    label: 'Brand',
                    controller: brandCtrl,
                    icon: Icons.sell_outlined),
              ),
              const SizedBox(height: 12),
              _TwoColumnFields(
                left: _TextFieldBlock(
                    label: 'NDC', controller: ndcCtrl, icon: Icons.numbers),
                right: _TextFieldBlock(
                    label: 'Manufacturer',
                    controller: manufacturerCtrl,
                    icon: Icons.factory_outlined),
              ),
              const SizedBox(height: 12),
              _TwoColumnFields(
                left: _TextFieldBlock(
                    label: 'Strength',
                    controller: strengthCtrl,
                    icon: Icons.bolt_outlined),
                right: _DropdownBlock(
                  label: 'Dosage Form',
                  value: dosageForm,
                  values: AppDosageForms.list,
                  icon: Icons.medication_liquid,
                  onChanged: onDosageFormChanged,
                ),
              ),
              const SizedBox(height: 12),
              FormFieldLabel(label: 'Category'),
              DropdownButtonFormField<String>(
                initialValue: category.isEmpty ? null : category,
                decoration:
                    const InputDecoration(prefixIcon: Icon(Icons.category)),
                hint: const Text('Select category (optional)'),
                items: AppCategories.list
                    .map((item) =>
                        DropdownMenuItem(value: item, child: Text(item)))
                    .toList(),
                onChanged: (value) => onCategoryChanged(value ?? ''),
              ),
              const SizedBox(height: 12),
              FormFieldLabel(label: 'Minimum Stock Level'),
              TextFormField(
                controller: minimumStockCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.warning_amber),
                  hintText: '0 means no low stock alert',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              FormFieldLabel(label: 'Reorder Level'),
              TextFormField(
                controller: reorderLevelCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.low_priority),
                  hintText: 'Optional',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              FormFieldLabel(label: 'Notes'),
              TextFormField(
                  controller: notesCtrl,
                  decoration:
                      const InputDecoration(prefixIcon: Icon(Icons.notes)),
                  minLines: 2,
                  maxLines: 4),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Changes')),
              ),
            ],
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

class _BatchForm extends StatefulWidget {
  final String barcode;
  final Batch? existingBatch;
  final String initialBatchNo;
  final DateTime? initialExpiryDate;
  final DateTime? initialManufactureDate;
  final VoidCallback onSaved;
  final ValueChanged<Batch> onEditExisting;
  const _BatchForm(
      {required this.barcode,
      this.existingBatch,
      this.initialBatchNo = '',
      this.initialExpiryDate,
      this.initialManufactureDate,
      required this.onSaved,
      required this.onEditExisting});

  @override
  State<_BatchForm> createState() => _BatchFormState();
}

class _BatchFormState extends State<_BatchForm> {
  final _firestoreService = FirestoreService();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  late TextEditingController _batchNoCtrl;
  late TextEditingController _quantityCtrl;
  late TextEditingController _purchasePriceCtrl;
  late TextEditingController _salePriceCtrl;
  late TextEditingController _supplierCtrl;
  DateTime? _expiryDate;
  DateTime? _manufactureDate;

  @override
  void initState() {
    super.initState();
    final batch = widget.existingBatch;
    _batchNoCtrl =
        TextEditingController(text: batch?.batchNo ?? widget.initialBatchNo);
    _quantityCtrl =
        TextEditingController(text: batch?.quantity.toString() ?? '0');
    _purchasePriceCtrl = TextEditingController(
        text: batch?.purchasePrice.toStringAsFixed(2) ?? '0.00');
    _salePriceCtrl = TextEditingController(
        text: batch?.salePrice.toStringAsFixed(2) ?? '0.00');
    _supplierCtrl = TextEditingController(text: batch?.supplier ?? '');
    _expiryDate = batch == null || batch.isExpiryMissing
        ? widget.initialExpiryDate
        : batch.expiryDate;
    _manufactureDate = batch?.manufactureDate ?? widget.initialManufactureDate;
    _purchasePriceCtrl.addListener(_updateSalePriceFromPurchasePrice);
  }

  @override
  void dispose() {
    _purchasePriceCtrl.removeListener(_updateSalePriceFromPurchasePrice);
    _batchNoCtrl.dispose();
    _quantityCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _salePriceCtrl.dispose();
    _supplierCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: AppTheme.primary)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  Future<void> _pickManufactureDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _manufactureDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: AppTheme.primary)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _manufactureDate = picked);
  }

  void _updateSalePriceFromPurchasePrice() {
    final purchasePrice = double.tryParse(_purchasePriceCtrl.text);
    if (purchasePrice == null) return;

    final salePrice = _calculateSalePrice(purchasePrice).toStringAsFixed(2);
    if (_salePriceCtrl.text == salePrice) return;

    _salePriceCtrl.value = TextEditingValue(
      text: salePrice,
      selection: TextSelection.collapsed(offset: salePrice.length),
    );
  }

  double _calculateSalePrice(double purchasePrice) {
    final salePriceBase = purchasePrice * 1.35;
    final cents = salePriceBase < 50 ? 0.49 : 0.99;
    final dollars = salePriceBase.floorToDouble();
    final candidate = dollars + cents;

    return candidate >= salePriceBase ? candidate : candidate + 1;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final batch = _buildBatch();

      if (widget.existingBatch != null) {
        await _firestoreService.updateBatch(widget.barcode, batch);
      } else {
        final duplicate = await _firestoreService.findBatchByNumber(
          widget.barcode,
          batch.batchNo,
        );
        if (duplicate != null) {
          final action = await _showDuplicateBatchDialog(duplicate);
          if (action == null) {
            if (mounted) setState(() => _saving = false);
            return;
          }
          switch (action) {
            case _DuplicateBatchAction.addQuantity:
              await _firestoreService.updateBatchQuantity(
                barcode: widget.barcode,
                batchId: duplicate.batchId,
                quantityChange: batch.quantity,
                reason: 'Scanned duplicate batch',
              );
              break;
            case _DuplicateBatchAction.editBatch:
              if (mounted) {
                Navigator.pop(context);
                widget.onEditExisting(duplicate);
              }
              return;
            case _DuplicateBatchAction.createNewBatch:
              await _firestoreService.addBatch(widget.barcode, batch);
              break;
          }
        } else {
          await _firestoreService.addBatch(widget.barcode, batch);
        }
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppTheme.expired),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Batch _buildBatch() {
    final now = DateTime.now();
    return Batch(
      batchId: widget.existingBatch?.batchId ?? '',
      barcode: widget.barcode,
      batchNo: _batchNoCtrl.text.trim(),
      expiryDate: _expiryDate ?? DateTime(9999, 12, 31),
      quantity: int.tryParse(_quantityCtrl.text) ?? 0,
      purchasePrice: double.tryParse(_purchasePriceCtrl.text) ?? 0,
      salePrice: double.tryParse(_salePriceCtrl.text) ?? 0,
      supplier: _supplierCtrl.text.trim(),
      purchaseDate: widget.existingBatch?.purchaseDate ?? now,
      status: _expiryDate == null
          ? BatchStatus.expiryMissing
          : widget.existingBatch?.status == BatchStatus.outOfStock
              ? BatchStatus.outOfStock
              : BatchStatus.active,
      createdAt: widget.existingBatch?.createdAt ?? now,
      updatedAt: now,
      manufactureDate: _manufactureDate,
    );
  }

  Future<_DuplicateBatchAction?> _showDuplicateBatchDialog(Batch batch) {
    return showDialog<_DuplicateBatchAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batch already exists.'),
        content: Text('Batch ${batch.batchNo} already exists for this item.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, _DuplicateBatchAction.createNewBatch),
            child: const Text('Create new batch'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, _DuplicateBatchAction.editBatch),
            child: const Text('Edit batch'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(ctx, _DuplicateBatchAction.addQuantity),
            child: const Text('Add quantity'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingBatch != null;
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Form(
          key: _formKey,
          child: ListView(
            controller: scrollCtrl,
            padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(isEdit ? 'Edit Batch' : 'Add Batch',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 16),
              FormFieldLabel(label: 'Batch Number'),
              TextFormField(
                controller: _batchNoCtrl,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.tag)),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              FormFieldLabel(label: 'Expiry Date'),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                        color: _expiryDate != null &&
                                _expiryDate!.isBefore(DateTime.now())
                            ? AppTheme.expired
                            : AppTheme.divider),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_month,
                        color: _expiryDate != null &&
                                _expiryDate!.isBefore(DateTime.now())
                            ? AppTheme.expired
                            : AppTheme.textSecondary),
                    const SizedBox(width: 12),
                    Text(
                        _expiryDate == null
                            ? 'Expiry Missing'
                            : DateFormat('dd MMM yyyy').format(_expiryDate!),
                        style: const TextStyle(fontSize: 15)),
                    const Spacer(),
                    if (_expiryDate != null)
                      IconButton(
                        onPressed: () => setState(() => _expiryDate = null),
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: 'Clear expiry date',
                      ),
                    const Icon(Icons.edit,
                        size: 16, color: AppTheme.textSecondary),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              FormFieldLabel(label: 'Manufacture Date'),
              GestureDetector(
                onTap: _pickManufactureDate,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppTheme.divider),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.event_available,
                        color: AppTheme.textSecondary),
                    const SizedBox(width: 12),
                    Text(
                        _manufactureDate == null
                            ? 'Not set'
                            : DateFormat('dd MMM yyyy')
                                .format(_manufactureDate!),
                        style: const TextStyle(fontSize: 15)),
                    const Spacer(),
                    if (_manufactureDate != null)
                      IconButton(
                        onPressed: () =>
                            setState(() => _manufactureDate = null),
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: 'Clear manufacture date',
                      ),
                    const Icon(Icons.edit,
                        size: 16, color: AppTheme.textSecondary),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              _TwoColumnFields(
                left: _TextFieldBlock(
                  label: 'Quantity',
                  controller: _quantityCtrl,
                  icon: Icons.numbers,
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                      value == null || int.tryParse(value) == null
                          ? 'Invalid'
                          : null,
                ),
                right: _TextFieldBlock(
                  label: 'Purchase Price',
                  controller: _purchasePriceCtrl,
                  icon: Icons.payments,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(height: 12),
              _TwoColumnFields(
                left: _TextFieldBlock(
                  label: 'Sale Price',
                  controller: _salePriceCtrl,
                  icon: Icons.sell,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                right: _TextFieldBlock(
                  label: 'Supplier',
                  controller: _supplierCtrl,
                  icon: Icons.local_shipping_outlined,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(_saving ? 'Saving...' : 'Save Batch'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _DuplicateBatchAction { addQuantity, editBatch, createNewBatch }

class _EmptyBatches extends StatelessWidget {
  const _EmptyBatches();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No batches added yet.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final UpdateHistory history;

  const _HistoryTile({required this.history});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history, color: AppTheme.primary),
      title: Text(history.actionType.isEmpty
          ? history.fieldChanged
          : history.actionType),
      subtitle: Text(
        [
          if (history.batchNo.isNotEmpty) 'Batch ${history.batchNo}',
          if (history.reason.isNotEmpty) history.reason,
          DateFormat('dd MMM yyyy, HH:mm').format(history.updatedAt),
        ].join(' - '),
      ),
      trailing: history.quantityChange == null
          ? null
          : Text(
              history.quantityChange! > 0
                  ? '+${history.quantityChange}'
                  : '${history.quantityChange}',
              style: TextStyle(
                color: history.quantityChange! >= 0
                    ? AppTheme.healthy
                    : AppTheme.expired,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;

  const _Chip(this.label, this.backgroundColor, this.textColor);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _TwoColumnFields extends StatelessWidget {
  final Widget left;
  final Widget right;

  const _TwoColumnFields({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            children: [
              left,
              const SizedBox(height: 12),
              right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class _TextFieldBlock extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _TextFieldBlock({
    required this.label,
    required this.controller,
    required this.icon,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormFieldLabel(label: label),
        TextFormField(
          controller: controller,
          decoration: InputDecoration(prefixIcon: Icon(icon)),
          keyboardType: keyboardType,
          validator: validator,
        ),
      ],
    );
  }
}

class _DropdownBlock extends StatelessWidget {
  final String label;
  final String value;
  final List<String> values;
  final IconData icon;
  final ValueChanged<String> onChanged;

  const _DropdownBlock({
    required this.label,
    required this.value,
    required this.values,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormFieldLabel(label: label),
        DropdownButtonFormField<String>(
          initialValue: value.isEmpty ? null : value,
          decoration: InputDecoration(prefixIcon: Icon(icon)),
          hint: Text(label),
          items: values
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: (newValue) => onChanged(newValue ?? ''),
        ),
      ],
    );
  }
}
