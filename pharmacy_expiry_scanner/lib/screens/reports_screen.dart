// lib/screens/reports_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/pharmacy_item.dart';
import '../services/firestore_service.dart';
import '../utils/app_theme.dart';

Color _expiryColor(ExpiryStatus status) {
  return switch (status) {
    ExpiryStatus.expired => AppTheme.expired,
    ExpiryStatus.within7Days => AppTheme.expiring7Days,
    ExpiryStatus.within30Days => AppTheme.expiring30Days,
    ExpiryStatus.safe => AppTheme.healthy,
    ExpiryStatus.missing => AppTheme.expiryMissing,
  };
}

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

String _blankGroup(String value) =>
    value.trim().isEmpty ? 'Unspecified' : value;

String _batchMonthLabel(Batch batch) => batch.isExpiryMissing
    ? 'Expiry Missing'
    : DateFormat('MMMM yyyy').format(batch.expiryDate);

String _saleBatchExpiryLabel(SaleBatchUsage batch) =>
    batch.expiryDate.year >= 9999
        ? 'Expiry Missing'
        : DateFormat('dd MMM yyyy').format(batch.expiryDate);

StoreSettings _reportStoreSettings = StoreSettings.defaults;

List<pw.Widget> _pdfReportHeader(String title, DateTime generatedAt) {
  final settings = _reportStoreSettings;
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

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  final _firestoreService = FirestoreService();
  late TabController _tabController;
  StreamSubscription<void>? _stockSubscription;
  List<PharmacyItemWithBatches> _allItems = [];
  List<PharmacyItemWithBatches> _recentlyUpdated = [];
  List<UpdateHistory> _stockHistory = [];
  List<SaleRecord> _sales = [];
  List<InventoryBalanceRow> _inventoryBalance = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 16, vsync: this);
    _stockSubscription = _firestoreService.stockChanges.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _stockSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await _firestoreService.getAllItemsWithBatches();
    final recent = await _firestoreService.getRecentlyUpdatedItems(limit: 50);
    final history = await _firestoreService.getStockMovementHistory(limit: 100);
    final sales = await _firestoreService.getSalesReport(limit: 500);
    final balance = await _firestoreService.getInventoryBalanceReport();
    final storeSettings = await _firestoreService.getStoreSettings();
    if (!mounted) return;
    setState(() {
      _reportStoreSettings = storeSettings;
      _allItems = all;
      _recentlyUpdated = recent;
      _stockHistory = history;
      _sales = sales;
      _inventoryBalance = balance;
      _loading = false;
    });
  }

  List<_ReportBatchRow> get _allBatchRows {
    final rows = [
      for (final data in _allItems)
        for (final batch in data.batches)
          _ReportBatchRow(item: data.item, batch: batch),
    ];
    rows.sort((a, b) => a.batch.expiryDate.compareTo(b.batch.expiryDate));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Balance'),
            Tab(text: 'Sales'),
            Tab(text: 'Expired Stock'),
            Tab(text: 'Missing Expiry'),
            Tab(text: 'Movement'),
            Tab(text: 'Expired'),
            Tab(text: '7 Days'),
            Tab(text: '30 Days'),
            Tab(text: 'Low Stock'),
            Tab(text: 'Adjustments'),
            Tab(text: 'Manufacturer'),
            Tab(text: 'Supplier'),
            Tab(text: 'Category'),
            Tab(text: 'Batch'),
            Tab(text: 'Updated'),
            Tab(text: 'Inventory'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _InventoryBalanceReport(rows: _inventoryBalance),
                _SalesReport(rows: _sales),
                _BatchReport(
                  title: 'Expired Stock Report',
                  color: AppTheme.expired,
                  rows: _allBatchRows
                      .where((row) => row.batch.isExpired)
                      .toList(),
                ),
                _BatchReport(
                  title: 'Missing Expiry Date Report',
                  color: AppTheme.expiryMissing,
                  rows: _allBatchRows
                      .where((row) => row.batch.isExpiryMissing)
                      .toList(),
                ),
                _StockMovementReport(items: _stockHistory),
                _BatchReport(
                  title: 'Expired Medicines',
                  color: AppTheme.expired,
                  rows: _allBatchRows
                      .where((row) => row.batch.isExpired)
                      .toList(),
                ),
                _BatchReport(
                  title: 'Expiring Within 7 Days',
                  color: AppTheme.expiring7Days,
                  rows: _allBatchRows
                      .where((row) => row.batch.isWithin7Days)
                      .toList(),
                ),
                _BatchReport(
                  title: 'Expiring Within 30 Days',
                  color: AppTheme.expiring30Days,
                  rows: _allBatchRows
                      .where((row) => row.batch.isWithin30Days)
                      .toList(),
                ),
                _LowStockReport(
                    items: _allItems.where((data) => data.isLowStock).toList()),
                _StockMovementReport(
                  items: _stockHistory
                      .where(
                          (history) => history.actionType == 'Stock Adjustment')
                      .toList(),
                  title: 'Stock Adjustment Report',
                ),
                _GroupedBatchReport(
                  title: 'By Manufacturer',
                  color: AppTheme.primary,
                  rows: _allBatchRows,
                  groupBy: (row) => _blankGroup(row.item.manufacturer),
                ),
                _GroupedBatchReport(
                  title: 'By Supplier',
                  color: AppTheme.primary,
                  rows: _allBatchRows,
                  groupBy: (row) => _blankGroup(row.batch.supplier),
                ),
                _GroupedBatchReport(
                  title: 'By Category',
                  color: AppTheme.primary,
                  rows: _allBatchRows,
                  groupBy: (row) => _blankGroup(row.item.category),
                ),
                _GroupedBatchReport(
                  title: 'By Batch',
                  color: AppTheme.primary,
                  rows: _allBatchRows,
                  groupBy: (row) => _blankGroup(row.batch.batchNo),
                ),
                _RecentlyUpdatedReport(items: _recentlyUpdated),
                _BatchReport(
                    title: 'Full Inventory By Batch',
                    color: AppTheme.primary,
                    rows: _allBatchRows),
              ],
            ),
    );
  }
}

class _ReportBatchRow {
  final PharmacyItem item;
  final Batch batch;
  const _ReportBatchRow({required this.item, required this.batch});
}

Future<void> _printBatchRows({
  required String title,
  required List<_ReportBatchRow> rows,
  String Function(_ReportBatchRow row)? groupBy,
}) async {
  final pdf = pw.Document();
  final now = DateTime.now();
  final includeGroup = groupBy != null;

  pw.Widget cell(String text,
      {bool header = false, PdfColor? color, PdfColor? background}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      color: background,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: header ? 8 : 7,
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
        ),
      ),
    );
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        ..._pdfReportHeader(title, now),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: {
            if (includeGroup) 0: const pw.FlexColumnWidth(1.2),
            if (includeGroup) 1: const pw.FlexColumnWidth(1.5),
            if (includeGroup) 2: const pw.FlexColumnWidth(1.1),
            if (includeGroup) 3: const pw.FlexColumnWidth(0.9),
            if (includeGroup) 4: const pw.FlexColumnWidth(0.9),
            if (includeGroup) 5: const pw.FlexColumnWidth(0.7),
            if (includeGroup) 6: const pw.FlexColumnWidth(0.8),
            if (includeGroup) 7: const pw.FlexColumnWidth(0.8),
            if (includeGroup) 8: const pw.FlexColumnWidth(1.1),
            if (!includeGroup) 0: const pw.FlexColumnWidth(1.6),
            if (!includeGroup) 1: const pw.FlexColumnWidth(1.1),
            if (!includeGroup) 2: const pw.FlexColumnWidth(0.9),
            if (!includeGroup) 3: const pw.FlexColumnWidth(0.9),
            if (!includeGroup) 4: const pw.FlexColumnWidth(0.7),
            if (!includeGroup) 5: const pw.FlexColumnWidth(0.8),
            if (!includeGroup) 6: const pw.FlexColumnWidth(0.8),
            if (!includeGroup) 7: const pw.FlexColumnWidth(1.1),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                if (includeGroup) cell('Group', header: true),
                cell('Medicine', header: true),
                cell('Barcode', header: true),
                cell('Batch', header: true),
                cell('Expiry', header: true),
                cell('Days', header: true),
                cell('Qty', header: true),
                cell('Status', header: true),
                cell('Supplier', header: true),
              ],
            ),
            ...rows.map((row) {
              final status = row.batch.expiryStatus;
              final color = _pdfExpiryColor(status);
              final background = _pdfExpiryBackground(status);
              return pw.TableRow(
                decoration: pw.BoxDecoration(color: background),
                children: [
                  if (includeGroup) cell(groupBy(row), color: color),
                  cell(row.item.displayName, color: color),
                  cell(row.item.barcode, color: color),
                  cell(row.batch.batchNo, color: color),
                  cell(
                      row.batch.isExpiryMissing
                          ? 'Expiry Missing'
                          : DateFormat('dd MMM yyyy')
                              .format(row.batch.expiryDate),
                      color: color),
                  cell(
                      row.batch.isExpiryMissing
                          ? '-'
                          : '${row.batch.daysUntilExpiry}',
                      color: color),
                  cell('${row.batch.quantity}', color: color),
                  cell(_expiryLabel(status), color: color),
                  cell(row.batch.supplier, color: color),
                ],
              );
            }),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text('Total rows: ${rows.length}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );
  await Printing.layoutPdf(onLayout: (_) async => pdf.save());
}

class _BatchReport extends StatefulWidget {
  final String title;
  final Color color;
  final List<_ReportBatchRow> rows;

  const _BatchReport(
      {required this.title, required this.color, required this.rows});

  @override
  State<_BatchReport> createState() => _BatchReportState();
}

class _BatchReportState extends State<_BatchReport> {
  String _query = '';
  String _month = 'All months';

  List<String> get _months {
    final values = widget.rows
        .map((row) => _batchMonthLabel(row.batch))
        .toSet()
        .toList()
      ..sort();
    return ['All months', ...values];
  }

  List<_ReportBatchRow> get _filteredRows {
    final query = _query.trim().toLowerCase();
    return widget.rows.where((row) {
      final item = row.item;
      final batch = row.batch;
      final haystack = [
        item.medicineName,
        item.genericName,
        item.brand,
        item.barcode,
        batch.batchNo,
        batch.supplier,
      ].join(' ').toLowerCase();
      final matchQuery = query.isEmpty || haystack.contains(query);
      final matchMonth =
          _month == 'All months' || _batchMonthLabel(batch) == _month;
      return matchQuery && matchMonth;
    }).toList();
  }

  Future<void> _print() async {
    await _printBatchRows(title: widget.title, rows: _filteredRows);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows;
    return Column(
      children: [
        _ReportToolbar(
          title: widget.title,
          subtitle: '${rows.length} batch(es)',
          color: widget.color,
          queryChanged: (value) => setState(() => _query = value),
          month: _month,
          months: _months,
          monthChanged: (value) => setState(() => _month = value),
          onPrint: _print,
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Text('No report rows',
                      style: TextStyle(color: AppTheme.textSecondary)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) => _BatchReportTile(row: rows[index]),
                ),
        ),
      ],
    );
  }
}

class _GroupedBatchReport extends StatefulWidget {
  final String title;
  final Color color;
  final List<_ReportBatchRow> rows;
  final String Function(_ReportBatchRow row) groupBy;

  const _GroupedBatchReport({
    required this.title,
    required this.color,
    required this.rows,
    required this.groupBy,
  });

  @override
  State<_GroupedBatchReport> createState() => _GroupedBatchReportState();
}

class _GroupedBatchReportState extends State<_GroupedBatchReport> {
  String _query = '';
  String _month = 'All months';

  List<String> get _months {
    final values = widget.rows
        .map((row) => _batchMonthLabel(row.batch))
        .toSet()
        .toList()
      ..sort();
    return ['All months', ...values];
  }

  List<_ReportBatchRow> get _filteredRows {
    final query = _query.trim().toLowerCase();
    final rows = widget.rows.where((row) {
      final item = row.item;
      final batch = row.batch;
      final group = widget.groupBy(row);
      final haystack = [
        group,
        item.medicineName,
        item.genericName,
        item.brand,
        item.barcode,
        item.manufacturer,
        item.category,
        batch.batchNo,
        batch.supplier,
      ].join(' ').toLowerCase();
      final matchQuery = query.isEmpty || haystack.contains(query);
      final matchMonth =
          _month == 'All months' || _batchMonthLabel(batch) == _month;
      return matchQuery && matchMonth;
    }).toList();
    rows.sort((a, b) {
      final groupCompare = widget
          .groupBy(a)
          .toLowerCase()
          .compareTo(widget.groupBy(b).toLowerCase());
      if (groupCompare != 0) return groupCompare;
      return a.batch.expiryDate.compareTo(b.batch.expiryDate);
    });
    return rows;
  }

  Map<String, List<_ReportBatchRow>> get _groups {
    final grouped = <String, List<_ReportBatchRow>>{};
    for (final row in _filteredRows) {
      grouped.putIfAbsent(widget.groupBy(row), () => []).add(row);
    }
    return grouped;
  }

  Future<void> _print() async {
    await _printBatchRows(
      title: widget.title,
      rows: _filteredRows,
      groupBy: widget.groupBy,
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    final rows = _filteredRows;
    return Column(
      children: [
        _ReportToolbar(
          title: widget.title,
          subtitle: '${groups.length} group(s), ${rows.length} batch(es)',
          color: widget.color,
          queryChanged: (value) => setState(() => _query = value),
          month: _month,
          months: _months,
          monthChanged: (value) => setState(() => _month = value),
          onPrint: _print,
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Text('No report rows',
                      style: TextStyle(color: AppTheme.textSecondary)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final entry in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, top: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.key,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${entry.value.length}',
                              style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      ...entry.value.map(
                        (row) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _BatchReportTile(row: row),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _InventoryBalanceReport extends StatefulWidget {
  final List<InventoryBalanceRow> rows;
  const _InventoryBalanceReport({required this.rows});

  @override
  State<_InventoryBalanceReport> createState() =>
      _InventoryBalanceReportState();
}

class _InventoryBalanceReportState extends State<_InventoryBalanceReport> {
  String _query = '';

  List<InventoryBalanceRow> get _filtered {
    final query = _query.trim().toLowerCase();
    return widget.rows.where((row) {
      final haystack = [
        row.item.displayName,
        row.item.barcode,
        row.batch.batchNo,
        row.batch.supplier,
      ].join(' ').toLowerCase();
      return query.isEmpty || haystack.contains(query);
    }).toList();
  }

  Future<void> _print() async {
    final rows = _filtered;
    final pdf = pw.Document();
    final now = DateTime.now();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          ..._pdfReportHeader('Inventory Balance Report', now),
          pw.TableHelper.fromTextArray(
            headers: [
              'Medicine',
              'Batch',
              'Opening',
              'Received',
              'Sold',
              'Expired/Removed',
              'Damaged',
              'Adjustment',
              'Current'
            ],
            data: rows
                .map((row) => [
                      row.item.displayName,
                      row.batch.batchNo,
                      '${row.openingQty}',
                      '${row.receivedQty}',
                      '${row.soldQty}',
                      '${row.expiredRemovedQty}',
                      '${row.damagedQty}',
                      '${row.adjustmentQty}',
                      '${row.currentQty}',
                    ])
                .toList(),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Column(
      children: [
        _SimpleReportHeader(
          title: 'Inventory Balance Report',
          subtitle: '${rows.length} batch(es)',
          color: AppTheme.primary,
          queryChanged: (value) => setState(() => _query = value),
          onPrint: _print,
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No balance rows'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) =>
                      _InventoryBalanceTile(row: rows[index]),
                ),
        ),
      ],
    );
  }
}

class _SalesReport extends StatefulWidget {
  final List<SaleRecord> rows;
  const _SalesReport({required this.rows});

  @override
  State<_SalesReport> createState() => _SalesReportState();
}

class _SalesReportState extends State<_SalesReport> {
  String _query = '';

  List<SaleRecord> get _filtered {
    final query = _query.trim().toLowerCase();
    return widget.rows.where((sale) {
      final batchText = sale.batchesUsed
          .map((batch) => '${batch.batchNo} ${batch.quantity}')
          .join(' ');
      final haystack = [
        sale.medicineName,
        sale.barcode,
        batchText,
        sale.userEmail,
      ].join(' ').toLowerCase();
      return query.isEmpty || haystack.contains(query);
    }).toList();
  }

  Future<void> _print() async {
    final rows = _filtered;
    final pdf = pw.Document();
    final now = DateTime.now();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          ..._pdfReportHeader('Sales Report', now),
          pw.TableHelper.fromTextArray(
            headers: [
              'Sold At',
              'Medicine',
              'Barcode',
              'Batches Used',
              'Qty',
              'Sale Amount',
              'Cost',
              'Profit',
              'User'
            ],
            data: rows
                .map((sale) => [
                      DateFormat('dd MMM yyyy HH:mm').format(sale.soldAt),
                      sale.medicineName,
                      sale.barcode,
                      sale.batchesUsed
                          .map((batch) =>
                              '${batch.batchNo} (${batch.quantity}, exp ${_saleBatchExpiryLabel(batch)})')
                          .join('; '),
                      '${sale.quantitySold}',
                      sale.totalSaleAmount.toStringAsFixed(2),
                      sale.totalCost.toStringAsFixed(2),
                      sale.profit.toStringAsFixed(2),
                      sale.userEmail,
                    ])
                .toList(),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final totalSales =
        rows.fold<double>(0, (sum, sale) => sum + sale.totalSaleAmount);
    final totalProfit = rows.fold<double>(0, (sum, sale) => sum + sale.profit);
    return Column(
      children: [
        _SimpleReportHeader(
          title: 'Sales Report',
          subtitle:
              '${rows.length} sale row(s) - \$${totalSales.toStringAsFixed(2)} sales - \$${totalProfit.toStringAsFixed(2)} profit',
          color: AppTheme.healthy,
          queryChanged: (value) => setState(() => _query = value),
          onPrint: _print,
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No sales yet'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) => _SaleTile(sale: rows[index]),
                ),
        ),
      ],
    );
  }
}

class _SimpleReportHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final ValueChanged<String> queryChanged;
  final VoidCallback onPrint;

  const _SimpleReportHeader({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.queryChanged,
    required this.onPrint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      color: color.withValues(alpha: 0.08),
      child: Column(
        children: [
          Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: color)),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                  ]),
            ),
            ElevatedButton.icon(
              onPressed: onPrint,
              icon: const Icon(Icons.print, size: 16),
              label: const Text('Print'),
              style: ElevatedButton.styleFrom(backgroundColor: color),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            onChanged: queryChanged,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search medicine, barcode, batch, supplier',
              fillColor: Colors.white,
              filled: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryBalanceTile extends StatelessWidget {
  final InventoryBalanceRow row;
  const _InventoryBalanceTile({required this.row});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(row.item.displayName,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          Text('Batch ${row.batch.batchNo} - Current ${row.currentQty}',
              style:
                  const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _QtyChip(label: 'Opening', value: row.openingQty),
              _QtyChip(label: 'Received', value: row.receivedQty),
              _QtyChip(label: 'Sold', value: row.soldQty),
              _QtyChip(label: 'Expired/Removed', value: row.expiredRemovedQty),
              _QtyChip(label: 'Damaged', value: row.damagedQty),
              _QtyChip(label: 'Adjustment', value: row.adjustmentQty),
            ],
          ),
        ]),
      ),
    );
  }
}

class _SaleTile extends StatelessWidget {
  final SaleRecord sale;
  const _SaleTile({required this.sale});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.point_of_sale, color: AppTheme.healthy),
        title: Text(sale.medicineName, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          'Batch ${sale.batchNo.isEmpty ? '-' : sale.batchNo} - Qty ${sale.quantitySold} - ${DateFormat('dd MMM yyyy HH:mm').format(sale.soldAt)}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('\$${sale.totalSaleAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            Text('+\$${sale.profit.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.healthy,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _QtyChip extends StatelessWidget {
  final String label;
  final int value;
  const _QtyChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$label $value',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _RecentlyUpdatedReport extends StatefulWidget {
  final List<PharmacyItemWithBatches> items;
  const _RecentlyUpdatedReport({required this.items});

  @override
  State<_RecentlyUpdatedReport> createState() => _RecentlyUpdatedReportState();
}

class _RecentlyUpdatedReportState extends State<_RecentlyUpdatedReport> {
  String _query = '';
  String _month = 'All months';

  List<String> get _months {
    final values = widget.items
        .map((data) => DateFormat('MMMM yyyy').format(data.item.updatedAt))
        .toSet()
        .toList()
      ..sort();
    return ['All months', ...values];
  }

  List<PharmacyItemWithBatches> get _filtered {
    final query = _query.trim().toLowerCase();
    return widget.items.where((data) {
      final batchText = data.batches
          .map((batch) => '${batch.batchNo} ${batch.supplier}')
          .join(' ');
      final haystack = [
        data.item.medicineName,
        data.item.genericName,
        data.item.brand,
        data.item.barcode,
        batchText,
      ].join(' ').toLowerCase();
      final matchQuery = query.isEmpty || haystack.contains(query);
      final matchMonth = _month == 'All months' ||
          DateFormat('MMMM yyyy').format(data.item.updatedAt) == _month;
      return matchQuery && matchMonth;
    }).toList();
  }

  Future<void> _print() async {
    final rows = _filtered;
    final pdf = pw.Document();
    final now = DateTime.now();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          ..._pdfReportHeader('Recently Updated Medicines', now),
          pw.TableHelper.fromTextArray(
            headers: [
              'Medicine',
              'Barcode',
              'Brand',
              'Strength',
              'Batches',
              'Qty',
              'Last Updated'
            ],
            data: rows
                .map(
                  (data) => [
                    data.item.medicineName,
                    data.item.barcode,
                    data.item.brand,
                    data.item.strength,
                    '${data.batches.length}',
                    '${data.totalQuantity}',
                    DateFormat('dd MMM yyyy HH:mm').format(data.item.updatedAt),
                  ],
                )
                .toList(),
          ),
          pw.SizedBox(height: 12),
          pw.Text('Total medicines: ${rows.length}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Column(
      children: [
        _ReportToolbar(
          title: 'Recently Updated',
          subtitle: '${rows.length} medicine(s)',
          color: AppTheme.primary,
          queryChanged: (value) => setState(() => _query = value),
          month: _month,
          months: _months,
          monthChanged: (value) => setState(() => _month = value),
          onPrint: _print,
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Text('No recently updated medicines',
                      style: TextStyle(color: AppTheme.textSecondary)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) => _UpdatedTile(data: rows[index]),
                ),
        ),
      ],
    );
  }
}

class _LowStockReport extends StatefulWidget {
  final List<PharmacyItemWithBatches> items;
  const _LowStockReport({required this.items});

  @override
  State<_LowStockReport> createState() => _LowStockReportState();
}

class _LowStockReportState extends State<_LowStockReport> {
  String _query = '';

  List<PharmacyItemWithBatches> get _filtered {
    final query = _query.trim().toLowerCase();
    final rows = widget.items.where((data) {
      final haystack = [
        data.item.barcode,
        data.item.medicineName,
        data.item.genericName,
        data.item.brand,
        data.item.manufacturer,
      ].join(' ').toLowerCase();
      return query.isEmpty || haystack.contains(query);
    }).toList();
    rows.sort((a, b) => b.shortageQty.compareTo(a.shortageQty));
    return rows;
  }

  Future<void> _print() async {
    final rows = _filtered;
    final pdf = pw.Document();
    final now = DateTime.now();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          ..._pdfReportHeader('Low Stock Report', now),
          pw.TableHelper.fromTextArray(
            headers: [
              'Barcode',
              'Medicine',
              'Total Qty',
              'Minimum Stock',
              'Shortage Qty',
            ],
            data: rows
                .map((data) => [
                      data.item.barcode,
                      data.item.displayName,
                      '${data.totalActiveQuantity}',
                      '${data.item.minimumStockLevel}',
                      '${data.shortageQty}',
                    ])
                .toList(),
          ),
          pw.SizedBox(height: 12),
          pw.Text('Low stock items: ${rows.length}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          color: AppTheme.lowStock.withValues(alpha: 0.08),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Low Stock Report',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: AppTheme.lowStock)),
                          Text('${rows.length} item(s)',
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.textSecondary)),
                        ]),
                  ),
                  ElevatedButton.icon(
                    onPressed: _print,
                    icon: const Icon(Icons.print, size: 16),
                    label: const Text('Print'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.lowStock,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search medicine, barcode, manufacturer',
                  fillColor: Colors.white,
                  filled: true,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Text('No low stock items',
                      style: TextStyle(color: AppTheme.textSecondary)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) => _LowStockTile(data: rows[index]),
                ),
        ),
      ],
    );
  }
}

class _LowStockTile extends StatelessWidget {
  final PharmacyItemWithBatches data;
  const _LowStockTile({required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.lowStock.withValues(alpha: 0.12),
              child: const Icon(Icons.warning_amber,
                  color: AppTheme.lowStock, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.item.displayName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                        overflow: TextOverflow.ellipsis),
                    Text('Barcode: ${data.item.barcode}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                        overflow: TextOverflow.ellipsis),
                    Text(
                        'Total ${data.totalActiveQuantity} - Minimum ${data.item.minimumStockLevel}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                        overflow: TextOverflow.ellipsis),
                  ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('Shortage',
                  style:
                      TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              Text('${data.shortageQty}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: AppTheme.lowStock)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _StockMovementReport extends StatefulWidget {
  final List<UpdateHistory> items;
  final String title;
  const _StockMovementReport({
    required this.items,
    this.title = 'Batch Movement Report',
  });

  @override
  State<_StockMovementReport> createState() => _StockMovementReportState();
}

class _StockMovementReportState extends State<_StockMovementReport> {
  String _query = '';
  String _month = 'All months';

  List<String> get _months {
    final values = widget.items
        .map((history) => DateFormat('MMMM yyyy').format(history.updatedAt))
        .toSet()
        .toList()
      ..sort();
    return ['All months', ...values];
  }

  List<UpdateHistory> get _filtered {
    final query = _query.trim().toLowerCase();
    return widget.items.where((history) {
      final haystack = [
        history.medicineName,
        history.barcode,
        history.batchNo,
        history.actionType,
        history.reason,
      ].join(' ').toLowerCase();
      final matchQuery = query.isEmpty || haystack.contains(query);
      final matchMonth = _month == 'All months' ||
          DateFormat('MMMM yyyy').format(history.updatedAt) == _month;
      return matchQuery && matchMonth;
    }).toList();
  }

  Future<void> _print() async {
    final rows = _filtered;
    final pdf = pw.Document();
    final now = DateTime.now();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          ..._pdfReportHeader(widget.title, now),
          pw.TableHelper.fromTextArray(
            headers: [
              'Date',
              'Medicine',
              'Barcode',
              'Batch',
              'Action',
              'Old',
              'New',
              'Change',
              'Reason',
              'Note',
              'By'
            ],
            data: rows
                .map(
                  (history) => [
                    DateFormat('dd MMM yyyy HH:mm').format(history.updatedAt),
                    history.medicineName,
                    history.barcode,
                    history.batchNo,
                    history.actionType,
                    '${history.oldQuantity ?? ''}',
                    '${history.newQuantity ?? ''}',
                    '${history.quantityChange ?? ''}',
                    history.reason,
                    history.note,
                    history.userEmail,
                  ],
                )
                .toList(),
          ),
          pw.SizedBox(height: 12),
          pw.Text('Total movements: ${rows.length}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Column(
      children: [
        _ReportToolbar(
          title: widget.title,
          subtitle: '${rows.length} movement(s)',
          color: AppTheme.primary,
          queryChanged: (value) => setState(() => _query = value),
          month: _month,
          months: _months,
          monthChanged: (value) => setState(() => _month = value),
          onPrint: _print,
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Text('No batch movement history',
                      style: TextStyle(color: AppTheme.textSecondary)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) =>
                      _StockHistoryTile(history: rows[index]),
                ),
        ),
      ],
    );
  }
}

class _ReportToolbar extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final ValueChanged<String> queryChanged;
  final String month;
  final List<String> months;
  final ValueChanged<String> monthChanged;
  final VoidCallback onPrint;

  const _ReportToolbar({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.queryChanged,
    required this.month,
    required this.months,
    required this.monthChanged,
    required this.onPrint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      color: color.withValues(alpha: 0.08),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: color)),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary)),
                    ]),
              ),
              ElevatedButton.icon(
                onPressed: onPrint,
                icon: const Icon(Icons.print, size: 16),
                label: const Text('Print'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            onChanged: queryChanged,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search name, barcode, batch, supplier',
              fillColor: Colors.white,
              filled: true,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: month,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.calendar_month),
                fillColor: Colors.white,
                filled: true),
            items: months
                .map((value) =>
                    DropdownMenuItem(value: value, child: Text(value)))
                .toList(),
            onChanged: (value) {
              if (value != null) monthChanged(value);
            },
          ),
        ],
      ),
    );
  }
}

class _BatchReportTile extends StatelessWidget {
  final _ReportBatchRow row;
  const _BatchReportTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final color = _expiryColor(row.batch.expiryStatus);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(Icons.medication, color: color, size: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.item.displayName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                        overflow: TextOverflow.ellipsis),
                    Text('Barcode: ${row.item.barcode}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                        overflow: TextOverflow.ellipsis),
                    Text(
                        'Batch: ${row.batch.batchNo} - Supplier: ${row.batch.supplier}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                        overflow: TextOverflow.ellipsis),
                  ]),
            ),
            const SizedBox(width: 8),
            Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      row.batch.isExpiryMissing
                          ? 'Expiry Missing'
                          : DateFormat('dd MMM yyyy')
                              .format(row.batch.expiryDate),
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  Text(
                      row.batch.isExpiryMissing
                          ? 'Review'
                          : '${row.batch.daysUntilExpiry} days',
                      style: const TextStyle(fontSize: 12)),
                  Text('Qty ${row.batch.quantity}',
                      style: const TextStyle(fontSize: 12)),
                ]),
          ],
        ),
      ),
    );
  }
}

class _UpdatedTile extends StatelessWidget {
  final PharmacyItemWithBatches data;
  const _UpdatedTile({required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Icon(Icons.update, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(data.item.displayName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                  overflow: TextOverflow.ellipsis),
              Text('${data.item.brand} ${data.item.strength}'.trim(),
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
              Text('Barcode: ${data.item.barcode}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(DateFormat('dd MMM yyyy').format(data.item.updatedAt),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text(DateFormat('HH:mm').format(data.item.updatedAt),
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
            Text('Qty ${data.totalQuantity}',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          ]),
        ]),
      ),
    );
  }
}

class _StockHistoryTile extends StatelessWidget {
  final UpdateHistory history;
  const _StockHistoryTile({required this.history});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.swap_vert, color: AppTheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        history.medicineName.isEmpty
                            ? history.actionType
                            : history.medicineName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                        overflow: TextOverflow.ellipsis),
                    Text(
                        '${history.actionType} - Batch ${history.batchNo.isEmpty ? '-' : history.batchNo}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                        overflow: TextOverflow.ellipsis),
                    Text(
                        'Reason: ${history.reason.isEmpty ? '-' : history.reason}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                        overflow: TextOverflow.ellipsis),
                    if (history.note.isNotEmpty)
                      Text('Note: ${history.note}',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary),
                          overflow: TextOverflow.ellipsis),
                    if (history.userEmail.isNotEmpty)
                      Text('By: ${history.userEmail}',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textSecondary),
                          overflow: TextOverflow.ellipsis),
                  ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${history.quantityChange ?? ''}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14)),
              Text(
                  '${history.oldQuantity ?? '-'} -> ${history.newQuantity ?? '-'}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
              Text(DateFormat('dd MMM HH:mm').format(history.updatedAt),
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary)),
            ]),
          ],
        ),
      ),
    );
  }
}
