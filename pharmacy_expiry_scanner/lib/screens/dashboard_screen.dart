// lib/screens/dashboard_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/pharmacy_item.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../utils/app_theme.dart';
import 'auto_update_medicine_screen.dart';
import 'scanner_screen.dart';
import 'smart_capture_screen.dart';
import 'update_medicine_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _firestoreService = FirestoreService();
  final _authService = AuthService();
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<void>? _stockSubscription;
  Map<String, num> _stats = {};
  List<Map<String, dynamic>> _expiryAlerts = [];
  List<PharmacyItemWithBatches> _recentlyUpdated = [];
  PharmacyItemWithBatches? _lastScanned;
  PharmacyItemWithBatches? _lastUpdated;
  bool _loading = true;
  bool _loadedInventoryStats = false;
  bool _shownDailyAlert = false;

  @override
  void initState() {
    super.initState();
    _listenToAuth();
    _listenToStockChanges();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _authService.currentUser == null) return;
      _loadSecondaryData(silent: false);
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _stockSubscription?.cancel();
    super.dispose();
  }

  void _listenToAuth() {
    _authSubscription = _authService.authState.listen((user) {
      if (user == null) {
        _logDashboardQueryDebug(reason: 'auth not ready');
        return;
      }
      _loadSecondaryData(silent: _loadedInventoryStats);
    }, onError: (error) {
      _logDashboardQueryDebug(reason: 'auth stream error', error: error);
      if (mounted) setState(() => _loading = false);
    });
  }

  void _listenToStockChanges() {
    _stockSubscription =
        _firestoreService.stockChanges.listen((_) => _loadSecondaryData(
              silent: true,
            ));
  }

  Future<void> _loadSecondaryData({bool silent = false}) async {
    final user = _authService.currentUser;
    if (user == null) {
      _logDashboardQueryDebug(reason: 'query skipped; auth not ready');
      if (mounted && !silent) setState(() => _loading = true);
      return;
    }

    if (!silent) setState(() => _loading = true);
    try {
      final allItems = await _firestoreService.getAllItemsWithBatches();
      final sales = await _firestoreService.getSalesReport(limit: 500);
      final dashboardStats = _calculateDashboardStats(allItems, sales);
      final alerts = _expiryAlertsFrom(allItems, limit: 5);
      final recent = await _firestoreService.getRecentlyUpdatedItems(limit: 5);
      if (!mounted) return;
      setState(() {
        _stats = dashboardStats;
        _expiryAlerts = alerts;
        _recentlyUpdated = recent;
        _lastScanned = _firestoreService.lastScannedItem;
        _lastUpdated = recent.isEmpty ? null : recent.first;
        _loadedInventoryStats = true;
        _loading = false;
      });
      _showDailyAlertOnce();
      if ((dashboardStats['totalItems'] ?? 0) == 0 ||
          (dashboardStats['totalBatches'] ?? 0) == 0) {
        _logDashboardQueryDebug(
          reason: 'live query returned zero count',
          medicineCount: dashboardStats['totalItems'],
          batchCount: dashboardStats['totalBatches'],
        );
      }
    } catch (error) {
      _logDashboardQueryDebug(reason: 'live query failed', error: error);
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, num> _calculateDashboardStats(
    List<PharmacyItemWithBatches> allItems,
    List<SaleRecord> sales,
  ) {
    final medicineCount = allItems.length;
    var batchCount = 0;
    var inventoryValue = 0.0;
    var expiredStockValue = 0.0;
    var missingExpiryBatches = 0;
    var expiredBatches = 0;
    var expiring7Days = 0;
    var expiring30Days = 0;
    var receivedTodayQty = 0;
    var receivedTodayValue = 0.0;
    var lowStockItems = 0;
    final valueRows = <String>[];
    final today = _dateOnly(DateTime.now());

    for (final data in allItems) {
      batchCount += data.batches.length;
      if (data.isLowStock) lowStockItems++;
      for (final batch in data.batches) {
        if (batch.hasStock) {
          switch (batch.expiryStatus) {
            case ExpiryStatus.missing:
              missingExpiryBatches++;
              break;
            case ExpiryStatus.expired:
              expiredBatches++;
              expiredStockValue += batch.quantity * batch.purchasePrice;
              break;
            case ExpiryStatus.within7Days:
              expiring7Days++;
              break;
            case ExpiryStatus.within30Days:
              expiring30Days++;
              break;
            case ExpiryStatus.safe:
              break;
          }
        }

        if (batch.isActive && batch.quantity > 0) {
          final lineValue = batch.quantity * batch.purchasePrice;
          inventoryValue += lineValue;
          valueRows.add(
            '${data.item.barcode}/${batch.batchNo}: '
            '${batch.quantity} x ${batch.purchasePrice.toStringAsFixed(2)} '
            '= ${lineValue.toStringAsFixed(2)}',
          );
        }

        final receivedAt = batch.receivedAt;
        if (receivedAt != null && _dateOnly(receivedAt) == today) {
          receivedTodayQty += batch.quantity;
          receivedTodayValue += batch.quantity * batch.purchasePrice;
        }
      }
    }

    final todaySales = sales.where((sale) => _dateOnly(sale.soldAt) == today);
    final todaySalesValue = todaySales.fold<double>(
      0,
      (sum, sale) => sum + sale.totalSaleAmount,
    );
    final todayProfit = todaySales.fold<double>(
      0,
      (sum, sale) => sum + sale.profit,
    );

    debugPrint('DASHBOARD_DEBUG medicine count: $medicineCount');
    debugPrint('DASHBOARD_DEBUG batch count: $batchCount');
    debugPrint(
      'DASHBOARD_DEBUG inventory value calculation: '
      '${valueRows.isEmpty ? 'no active batches' : valueRows.join(' | ')} '
      '=> ${inventoryValue.toStringAsFixed(2)}',
    );

    return {
      'totalItems': medicineCount,
      'totalBatches': batchCount,
      'totalInventoryValue': inventoryValue,
      'expiredStockValue': expiredStockValue,
      'missingExpiryBatches': missingExpiryBatches,
      'expiredBatches': expiredBatches,
      'expiring7Days': expiring7Days,
      'expiring30Days': expiring30Days,
      'lowStockItems': lowStockItems,
      'todaySales': todaySalesValue,
      'todayProfit': todayProfit,
      'receivedTodayQty': receivedTodayQty,
      'receivedTodayValue': receivedTodayValue,
    };
  }

  List<Map<String, dynamic>> _expiryAlertsFrom(
    List<PharmacyItemWithBatches> allItems, {
    required int limit,
  }) {
    final rows = <Map<String, dynamic>>[];
    for (final data in allItems) {
      for (final batch in data.batches) {
        if (!batch.hasStock) continue;
        if (batch.isExpiryMissing ||
            batch.isExpired ||
            batch.isWithin7Days ||
            batch.isWithin30Days) {
          rows.add({'item': data.item, 'batch': batch});
        }
      }
    }
    rows.sort((a, b) {
      final batchA = a['batch'] as Batch;
      final batchB = b['batch'] as Batch;
      if (batchA.isExpiryMissing != batchB.isExpiryMissing) {
        return batchA.isExpiryMissing ? 1 : -1;
      }
      return batchA.expiryDate.compareTo(batchB.expiryDate);
    });
    return rows.take(limit).toList();
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  void _logDashboardQueryDebug({
    required String reason,
    Object? error,
    num? medicineCount,
    num? batchCount,
  }) {
    final user = _authService.currentUser;
    debugPrint(
      'DASHBOARD_DEBUG $reason\n'
      'currentUser uid=${user?.uid ?? 'null'} '
      'email=${user?.email ?? 'null'}\n'
      'path queried: pharmacy_items and pharmacy_items/{barcode}/batches\n'
      'medicine count: ${medicineCount ?? 'unknown'}\n'
      'batch count: ${batchCount ?? 'unknown'}'
      '${error == null ? '' : '\nerror: $error'}',
    );
  }

  void _showDailyAlertOnce() {
    if (_shownDailyAlert || !mounted) return;
    _shownDailyAlert = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Expiry Summary'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AlertLine(
                  color: AppTheme.lowStock,
                  label: 'Low Stock:',
                  value: '${_stats['lowStockItems'] ?? 0} medicines'),
              _AlertLine(
                  color: AppTheme.expiryMissing,
                  label: 'Missing expiry date',
                  value: _stats['missingExpiryBatches'] ?? 0),
              _AlertLine(
                  color: AppTheme.expired,
                  label: 'Expired',
                  value: _stats['expiredBatches'] ?? 0),
              _AlertLine(
                  color: AppTheme.expiring7Days,
                  label: 'Expire within 7 days',
                  value: _stats['expiring7Days'] ?? 0),
              _AlertLine(
                  color: AppTheme.expiring30Days,
                  label: 'Expire within 30 days',
                  value: _stats['expiring30Days'] ?? 0),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomPadding =
        kBottomNavigationBarHeight + media.padding.bottom + 32;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_pharmacy, size: 20),
            SizedBox(width: 8),
            Text('Pharmacy Scanner'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: () => _loadSecondaryData(silent: false),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadSecondaryData(silent: false),
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
                children: [
                  Text(_greeting(),
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  Text(DateFormat('EEEE, dd MMMM yyyy').format(DateTime.now()),
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13)),
                  if ((_authService.currentUser?.email ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.account_circle_outlined,
                              size: 14, color: AppTheme.textSecondary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _authService.currentUser!.email!,
                              style: const TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  const _SectionHeader('Inventory'),
                  _StatGrid(children: [
                    _StatCard(
                        label: 'Total Medicines',
                        value: _stats['totalItems'] ?? 0,
                        icon: Icons.medication,
                        color: AppTheme.primary),
                    _StatCard(
                        label: 'Total Batches',
                        value: _stats['totalBatches'] ?? 0,
                        icon: Icons.inventory_2,
                        color: AppTheme.textPrimary),
                    _StatCard(
                        label: 'Inventory Value',
                        value: _stats['totalInventoryValue'] ?? 0,
                        icon: Icons.account_balance_wallet,
                        color: AppTheme.primary,
                        currency: true),
                    _StatCard(
                        label: 'Low Stock Items',
                        value: _stats['lowStockItems'] ?? 0,
                        icon: Icons.warning_amber,
                        color: AppTheme.lowStock),
                  ]),
                  const SizedBox(height: 20),
                  const _SectionHeader('Expiry'),
                  _StatGrid(children: [
                    _StatCard(
                        label: 'Expired Value',
                        value: _stats['expiredStockValue'] ?? 0,
                        icon: Icons.dangerous,
                        color: AppTheme.expired,
                        currency: true),
                    _StatCard(
                        label: 'Missing Expiry Date',
                        value: _stats['missingExpiryBatches'] ?? 0,
                        icon: Icons.help_outline,
                        color: AppTheme.expiryMissing),
                    _StatCard(
                        label: 'Within 7 Days',
                        value: _stats['expiring7Days'] ?? 0,
                        icon: Icons.priority_high,
                        color: AppTheme.expiring7Days),
                    _StatCard(
                        label: 'Within 30 Days',
                        value: _stats['expiring30Days'] ?? 0,
                        icon: Icons.timer,
                        color: AppTheme.expiring30Days),
                  ]),
                  const SizedBox(height: 20),
                  const _SectionHeader('Today Activity'),
                  _StatGrid(children: [
                    _StatCard(
                        label: 'Today Sales',
                        value: _stats['todaySales'] ?? 0,
                        icon: Icons.point_of_sale,
                        color: AppTheme.healthy,
                        currency: true),
                    _StatCard(
                        label: 'Today Profit',
                        value: _stats['todayProfit'] ?? 0,
                        icon: Icons.trending_up,
                        color: AppTheme.lowStock,
                        currency: true),
                    _StatCard(
                        label: 'Received Today Qty',
                        value: _stats['receivedTodayQty'] ?? 0,
                        icon: Icons.add_box,
                        color: AppTheme.healthy),
                    _StatCard(
                        label: 'Received Today Value',
                        value: _stats['receivedTodayValue'] ?? 0,
                        icon: Icons.today,
                        color: AppTheme.primaryLight,
                        currency: true),
                  ]),
                  const SizedBox(height: 20),
                  InkWell(
                    onTap: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ScannerScreen()));
                      await _loadSecondaryData();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [AppTheme.primary, AppTheme.primaryLight],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4))
                        ],
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.qr_code_scanner,
                              color: Colors.white, size: 36),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Scan Barcode',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700)),
                                  Text('Add or update medicine by scanning',
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 13)),
                                ]),
                          ),
                          Icon(Icons.chevron_right, color: Colors.white70),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SmartCaptureScreen()));
                      await _loadSecondaryData();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.add_a_photo,
                              color: AppTheme.primary, size: 30),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Smart Capture',
                                      style: TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800)),
                                  Text(
                                      'Package photos, OCR suggestions, human verification',
                                      style: TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 12)),
                                ]),
                          ),
                          Icon(Icons.chevron_right,
                              color: AppTheme.textSecondary),
                        ],
                      ),
                    ),
                  ),
                  if (_lastScanned != null) ...[
                    const SizedBox(height: 20),
                    const Text('Last Scanned Item',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 10),
                    _LastScannedRow(data: _lastScanned!),
                  ],
                  if (_lastUpdated != null) ...[
                    const SizedBox(height: 20),
                    const Text('Last Updated Medicine',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 10),
                    _LastUpdatedRow(data: _lastUpdated!),
                  ],
                  if (_expiryAlerts.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text('Expiry Alerts',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary)),
                    ..._expiryAlerts.map((entry) => _ExpiryAlertRow(
                        item: entry['item'] as PharmacyItem,
                        batch: entry['batch'] as Batch)),
                  ],
                  if (_recentlyUpdated.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text('Recently Updated',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 10),
                    ..._recentlyUpdated.map((data) => _RecentRow(data: data)),
                  ],
                ],
              ),
            ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _confirmLogout() async {
    final email = _authService.currentUser?.email ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: Text(
            email.isEmpty ? 'Sign out of this device?' : 'Sign out of $email?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.expired),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // AuthGate reacts to authStateChanges and returns to the login screen.
      try {
        await _authService.signOut();
      } on AuthFailure catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 390;
    return Padding(
      padding: EdgeInsets.only(bottom: isCompact ? 8 : 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: isCompact ? 15 : 18,
          fontWeight: FontWeight.w800,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  final List<Widget> children;
  const _StatGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 390;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: isCompact ? 8 : 12,
      mainAxisSpacing: isCompact ? 8 : 12,
      childAspectRatio: isCompact ? 1.72 : 1.5,
      children: children,
    );
  }
}

class _AlertLine extends StatelessWidget {
  final Color color;
  final String label;
  final Object value;
  const _AlertLine(
      {required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        Text('$value',
            style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final num value;
  final IconData icon;
  final Color color;
  final bool currency;
  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color,
      this.currency = false});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 390;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(isCompact ? 10 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: EdgeInsets.all(isCompact ? 6 : 8),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: isCompact ? 17 : 20),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(currency ? '\$${value.toStringAsFixed(2)}' : '$value',
                  style: TextStyle(
                      fontSize: isCompact ? 20 : 23,
                      fontWeight: FontWeight.w800,
                      color: color,
                      height: 1)),
              Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: isCompact ? 10.5 : 11.5,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _ExpiryAlertRow extends StatelessWidget {
  final PharmacyItem item;
  final Batch batch;
  const _ExpiryAlertRow({required this.item, required this.batch});

  @override
  Widget build(BuildContext context) {
    final color = switch (batch.expiryStatus) {
      ExpiryStatus.expired => AppTheme.expired,
      ExpiryStatus.within7Days => AppTheme.expiring7Days,
      ExpiryStatus.within30Days => AppTheme.expiring30Days,
      ExpiryStatus.safe => AppTheme.healthy,
      ExpiryStatus.missing => AppTheme.expiryMissing,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    AutoUpdateMedicineScreen(barcode: item.barcode))),
        leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: batch.isExpiryMissing
                ? Icon(Icons.help_outline, color: color)
                : Text('${batch.daysUntilExpiry}',
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.w800))),
        title: Text(item.displayName, overflow: TextOverflow.ellipsis),
        subtitle: Text(batch.isExpiryMissing
            ? 'Batch ${batch.batchNo} - Expiry Missing'
            : 'Batch ${batch.batchNo} - Exp ${DateFormat('dd MMM yyyy').format(batch.expiryDate)}'),
        trailing: Text('Qty ${batch.quantity}',
            style: const TextStyle(color: AppTheme.textSecondary)),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  final PharmacyItemWithBatches data;
  const _RecentRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    UpdateMedicineScreen(barcode: data.item.barcode))),
        leading: const Icon(Icons.update, color: AppTheme.primary),
        title: Text(data.item.displayName, overflow: TextOverflow.ellipsis),
        subtitle:
            Text(DateFormat('dd MMM yyyy, HH:mm').format(data.item.updatedAt)),
        trailing: Text('Qty ${data.totalQuantity}',
            style: const TextStyle(color: AppTheme.textSecondary)),
      ),
    );
  }
}

class _LastScannedRow extends StatelessWidget {
  final PharmacyItemWithBatches data;
  const _LastScannedRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    AutoUpdateMedicineScreen(barcode: data.item.barcode))),
        leading: const Icon(Icons.qr_code_scanner, color: AppTheme.primary),
        title: Text(data.item.displayName, overflow: TextOverflow.ellipsis),
        subtitle: Text('Barcode: ${data.item.barcode}'),
        trailing: Text('Qty ${data.totalQuantity}',
            style: const TextStyle(color: AppTheme.textSecondary)),
      ),
    );
  }
}

class _LastUpdatedRow extends StatelessWidget {
  final PharmacyItemWithBatches data;
  const _LastUpdatedRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    UpdateMedicineScreen(barcode: data.item.barcode))),
        leading: const Icon(Icons.update, color: AppTheme.primary),
        title: Text(data.item.displayName, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          DateFormat('dd MMM yyyy, HH:mm').format(data.item.updatedAt),
        ),
        trailing: Text('Qty ${data.totalQuantity}',
            style: const TextStyle(color: AppTheme.textSecondary)),
      ),
    );
  }
}
