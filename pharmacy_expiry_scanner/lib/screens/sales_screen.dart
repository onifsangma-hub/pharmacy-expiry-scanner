// lib/screens/sales_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/pharmacy_item.dart';
import '../services/camera_access.dart';
import '../services/firestore_service.dart';
import '../services/scanner_feedback.dart';
import '../utils/app_theme.dart';
import 'receipt_screen.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final _firestoreService = FirestoreService();
  final _quantityCtrl = TextEditingController(text: '1');
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    formats: const [
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.code128,
    ],
  );

  PharmacyItemWithBatches? _data;
  String _status = 'Scan medicine barcode';
  String? _lastScanned;
  bool _loading = false;
  bool _cameraActive = false;

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startCamera() async {
    final access = await requestCameraAccess();
    if (!mounted) return;
    if (!access.isGranted) {
      setState(() {
        _cameraActive = false;
        _status = access.debugMessage;
      });
      return;
    }
    try {
      await _controller.start(cameraDirection: CameraFacing.back);
      if (!mounted) return;
      setState(() {
        _cameraActive = true;
        _status = 'Scan medicine barcode';
        _lastScanned = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraActive = false;
        _status = 'Camera failed: $error';
      });
    }
  }

  Future<void> _stopCamera() async {
    try {
      await _controller.stop();
    } catch (_) {
      // Camera can already be stopped by browser lifecycle.
    }
    if (mounted) setState(() => _cameraActive = false);
  }

  Future<void> _handleBarcode(String rawBarcode) async {
    final barcode = FirestoreService.normalizeBarcode(rawBarcode);
    if (barcode.isEmpty || barcode == _lastScanned || _loading) return;

    setState(() {
      _lastScanned = barcode;
      _loading = true;
      _status = 'Checking $barcode';
    });
    await _stopCamera();
    await playScanFeedback();

    final data = await _firestoreService.getItemWithBatches(barcode);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
      _status = data == null ? 'Medicine not found' : 'Ready to sell';
    });
  }

  Future<void> _enterManually() async {
    final controller = TextEditingController();
    final barcode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter Barcode'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.qr_code),
            labelText: 'Barcode',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Find')),
        ],
      ),
    );
    if (barcode != null && barcode.trim().isNotEmpty) {
      await _handleBarcode(barcode);
    }
  }

  Future<void> _recordSale() async {
    final data = _data;
    if (data == null) return;
    final quantity = int.tryParse(_quantityCtrl.text.trim());
    if (quantity == null || quantity <= 0) {
      _showMessage('Enter a valid sale quantity.', AppTheme.expired);
      return;
    }

    final nonExpiredQty = _nonExpiredAvailableQty(data);
    final expiredQty = _expiredAvailableQty(data);
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

    setState(() => _loading = true);
    try {
      final sale = await _firestoreService.recordSale(
        barcode: data.item.barcode,
        quantitySold: quantity,
        paymentMethod: 'Cash',
        allowExpiredOverride: allowExpiredOverride,
      );
      final refreshed =
          await _firestoreService.getItemWithBatches(data.item.barcode);
      if (!mounted) return;
      setState(() {
        _data = refreshed;
        _loading = false;
        _status = 'Sale recorded';
      });
      _showMessage(
          'Sold $quantity unit(s) for \$${sale.totalSaleAmount.toStringAsFixed(2)}',
          AppTheme.healthy);
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReceiptScreen(sale: sale)),
      );
      if (!mounted) return;
      setState(() {
        _data = null;
        _quantityCtrl.text = '1';
        _status = 'Ready for next customer';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('$error', AppTheme.expired);
    }
  }

  void _showMessage(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  int _nonExpiredAvailableQty(PharmacyItemWithBatches data) {
    return data.batches
        .where((batch) => batch.hasStock && !batch.isExpired)
        .fold(0, (sum, batch) => sum + batch.quantity);
  }

  int _expiredAvailableQty(PharmacyItemWithBatches data) {
    return data.batches
        .where((batch) => batch.hasStock && batch.isExpired)
        .fold(0, (sum, batch) => sum + batch.quantity);
  }

  Batch? _nearestSaleBatch(PharmacyItemWithBatches data) {
    final nonExpired = data.batches
        .where((batch) => batch.hasStock && !batch.isExpired)
        .toList()
      ..sort((a, b) {
        if (a.isExpiryMissing != b.isExpiryMissing) {
          return a.isExpiryMissing ? 1 : -1;
        }
        return a.expiryDate.compareTo(b.expiryDate);
      });
    if (nonExpired.isNotEmpty) return nonExpired.first;
    final expired = data.batches
        .where((batch) => batch.hasStock && batch.isExpired)
        .toList()
      ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return expired.isEmpty ? null : expired.first;
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

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final nearestBatch = data == null ? null : _nearestSaleBatch(data);
    final availableQty = data == null ? 0 : data.totalQuantity;
    final nonExpiredQty = data == null ? 0 : _nonExpiredAvailableQty(data);
    final expiredQty = data == null ? 0 : _expiredAvailableQty(data);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales'),
        actions: [
          IconButton(
            onPressed: _enterManually,
            icon: const Icon(Icons.keyboard),
            tooltip: 'Enter barcode',
          ),
          IconButton(
            onPressed: _startCamera,
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final barcode = _data?.item.barcode;
          if (barcode == null) return;
          final data = await _firestoreService.getItemWithBatches(barcode);
          if (mounted) setState(() => _data = data);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ScannerPanel(
              controller: _controller,
              active: _cameraActive,
              status: _status,
              loading: _loading,
              onDetect: _handleBarcode,
              onStart: _startCamera,
              onManual: _enterManually,
            ),
            const SizedBox(height: 16),
            if (data == null)
              const _EmptySaleState()
            else
              _SaleMedicineCard(
                data: data,
                nearestBatch: nearestBatch,
                availableQty: availableQty,
                nonExpiredQty: nonExpiredQty,
                expiredQty: expiredQty,
                quantityCtrl: _quantityCtrl,
                loading: _loading,
                onSell: _recordSale,
              ),
          ],
        ),
      ),
    );
  }
}

class _ScannerPanel extends StatelessWidget {
  final MobileScannerController controller;
  final bool active;
  final String status;
  final bool loading;
  final ValueChanged<String> onDetect;
  final VoidCallback onStart;
  final VoidCallback onManual;

  const _ScannerPanel({
    required this.controller,
    required this.active,
    required this.status,
    required this.loading,
    required this.onDetect,
    required this.onStart,
    required this.onManual,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 220,
            child: active
                ? MobileScanner(
                    controller: controller,
                    onDetect: (capture) {
                      final raw = capture.barcodes
                          .where((barcode) => barcode.rawValue != null)
                          .firstOrNull
                          ?.rawValue;
                      if (raw != null && raw.trim().isNotEmpty) onDetect(raw);
                    },
                  )
                : Container(
                    color: AppTheme.textPrimary,
                    alignment: Alignment.center,
                    child: Icon(Icons.qr_code_scanner,
                        color: Colors.white.withValues(alpha: 0.8), size: 48),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (loading)
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Icon(active ? Icons.camera_alt : Icons.info_outline,
                      color: AppTheme.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(status)),
                TextButton.icon(
                  onPressed: onManual,
                  icon: const Icon(Icons.keyboard, size: 16),
                  label: const Text('Manual'),
                ),
                IconButton(
                  onPressed: onStart,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Restart scanner',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleMedicineCard extends StatelessWidget {
  final PharmacyItemWithBatches data;
  final Batch? nearestBatch;
  final int availableQty;
  final int nonExpiredQty;
  final int expiredQty;
  final TextEditingController quantityCtrl;
  final bool loading;
  final VoidCallback onSell;

  const _SaleMedicineCard({
    required this.data,
    required this.nearestBatch,
    required this.availableQty,
    required this.nonExpiredQty,
    required this.expiredQty,
    required this.quantityCtrl,
    required this.loading,
    required this.onSell,
  });

  @override
  Widget build(BuildContext context) {
    final batch = nearestBatch;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(data.item.displayName,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          if (data.item.description.isNotEmpty)
            Text(data.item.description,
                style: const TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                  label: 'Sale Price',
                  value: batch == null
                      ? '-'
                      : '\$${batch.salePrice.toStringAsFixed(2)}'),
              _InfoChip(label: 'Available', value: '$availableQty'),
              _InfoChip(label: 'Non-expired', value: '$nonExpiredQty'),
              _InfoChip(label: 'Expired Stock', value: '$expiredQty'),
              _InfoChip(
                  label: 'Nearest Batch',
                  value: batch == null ? '-' : batch.batchNo),
              _InfoChip(
                  label: 'Nearest Expiry',
                  value: batch == null
                      ? '-'
                      : batch.isExpiryMissing
                          ? 'Expiry Missing'
                          : DateFormat('dd MMM yyyy').format(batch.expiryDate)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: quantityCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.numbers),
              labelText: 'Quantity sold',
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: loading || batch == null ? null : onSell,
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.point_of_sale),
              label: const Text('Record FEFO Sale'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style:
                const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
      ]),
    );
  }
}

class _EmptySaleState extends StatelessWidget {
  const _EmptySaleState();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Text(
          'Scan a barcode to load the medicine for sale.',
          style: TextStyle(color: AppTheme.textSecondary),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
