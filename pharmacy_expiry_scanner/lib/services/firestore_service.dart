// lib/services/firestore_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/pharmacy_item.dart';

class FirestoreService {
  static PharmacyItemWithBatches? _lastScannedItem;
  static final StreamController<void> _stockChangedController =
      StreamController<void>.broadcast();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  CollectionReference get _items => _db.collection('pharmacy_items');
  CollectionReference get _sales => _db.collection('sales');
  DocumentReference get _storeSettingsDoc =>
      _db.collection('settings').doc('store');
  DocumentReference get _dashboardSummaryDoc =>
      _db.collection('summaries').doc('dashboard');

  Stream<DocumentSnapshot> getDashboardStream() =>
      _dashboardSummaryDoc.snapshots();

  Stream<void> get stockChanges => _stockChangedController.stream;

  Future<StoreSettings> getStoreSettings() async {
    try {
      final doc = await _storeSettingsDoc.get();
      if (!doc.exists) {
        await _storeSettingsDoc.set(StoreSettings.defaults.toMap());
        return StoreSettings.defaults;
      }
      final data = doc.data() as Map<String, dynamic>? ?? {};
      return StoreSettings.fromMap(data);
    } catch (_) {
      return StoreSettings.defaults;
    }
  }

  static String normalizeBarcode(String value) {
    return value
        .replaceAll(
          RegExp(r'[\u0000-\u001F\u007F\u200B-\u200D\uFEFF]'),
          '',
        )
        .trim();
  }

  static String itemPathForBarcode(String barcode) {
    return 'pharmacy_items/${normalizeBarcode(barcode)}';
  }

  /// The signed-in user stamped onto every history row, or empty when
  /// somehow unauthenticated (rules also enforce auth on writes).
  ({String id, String email}) get _actor {
    final user = FirebaseAuth.instance.currentUser;
    return (id: user?.uid ?? '', email: user?.email ?? '');
  }

  Future<bool> barcodeExists(String barcode) async {
    final doc = await _items.doc(normalizeBarcode(barcode)).get();
    return doc.exists;
  }

  Future<PharmacyItem?> getItem(String barcode) async {
    final normalizedBarcode = normalizeBarcode(barcode);
    final doc = await _items.doc(normalizedBarcode).get();
    if (!doc.exists) return null;
    return PharmacyItem.fromFirestore(doc);
  }

  Future<PharmacyItem?> findItemByBarcode(String barcode) async {
    final normalizedBarcode = normalizeBarcode(barcode);
    final direct = await getItem(normalizedBarcode);
    if (direct != null) return direct;

    final snap = await _items
        .where('barcode', isEqualTo: normalizedBarcode)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return PharmacyItem.fromFirestore(snap.docs.first);
  }

  Future<List<PharmacyItem>> getAllItems() async {
    final snap = await _items.orderBy('medicineName').get();
    return snap.docs.map((doc) => PharmacyItem.fromFirestore(doc)).toList();
  }

  Future<PharmacyItem?> findItemByNdc(String ndc,
      {String? excludingBarcode}) async {
    final normalized = _normalizeNdc(ndc);
    final normalizedExcludingBarcode =
        excludingBarcode == null ? null : normalizeBarcode(excludingBarcode);
    if (normalized.isEmpty) return null;

    final items = await getAllItems();
    for (final item in items) {
      if (normalizedExcludingBarcode != null &&
          item.barcode == normalizedExcludingBarcode) {
        continue;
      }
      if (_normalizeNdc(item.ndc) == normalized) return item;
    }
    return null;
  }

  Future<List<String>> getManufacturerSuggestions() async {
    final items = await getAllItems();
    final suggestions = <String>{};
    for (final item in items) {
      final manufacturer = item.manufacturer.trim();
      if (manufacturer.isNotEmpty) suggestions.add(manufacturer);
    }
    final sorted = suggestions.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  Future<List<String>> getDosageFormSuggestions() async {
    final items = await getAllItems();
    final suggestions = <String>{};
    for (final item in items) {
      final dosageForm = item.dosageForm.trim();
      if (dosageForm.isNotEmpty) suggestions.add(dosageForm);
    }
    final sorted = suggestions.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  Future<PharmacyItemWithBatches?> getItemWithBatches(String barcode) async {
    final item = await findItemByBarcode(barcode);
    if (item == null) return null;
    final batches = await getBatches(item.barcode);
    return PharmacyItemWithBatches(item: item, batches: batches);
  }

  PharmacyItemWithBatches? get lastScannedItem => _lastScannedItem;

  Future<void> recordLastScanned(String barcode) async {
    _lastScannedItem = await getItemWithBatches(normalizeBarcode(barcode));
  }

  Future<List<PharmacyItemWithBatches>> getAllItemsWithBatches() async {
    final items = await getAllItems();
    final results = <PharmacyItemWithBatches>[];
    for (final item in items) {
      final batches = await getBatches(item.barcode);
      results.add(PharmacyItemWithBatches(item: item, batches: batches));
    }
    return results;
  }

  Future<void> saveItem(PharmacyItem item) async {
    final normalizedBarcode = normalizeBarcode(item.barcode);
    final itemToSave = PharmacyItem(
      barcode: normalizedBarcode,
      medicineName: item.medicineName,
      genericName: item.genericName,
      brand: item.brand,
      ndc: item.ndc,
      manufacturer: item.manufacturer,
      strength: item.strength,
      dosageForm: item.dosageForm,
      category: item.category,
      packageSize: item.packageSize,
      minimumStockLevel: item.minimumStockLevel,
      reorderLevel: item.reorderLevel,
      notes: item.notes,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
    );
    final existing = await getItem(normalizedBarcode);
    await _items
        .doc(normalizedBarcode)
        .set(itemToSave.toMap(), SetOptions(merge: true));

    if (existing == null) {
      await _addHistory(
        normalizedBarcode,
        fieldChanged: 'Created',
        oldValue: '',
        newValue: itemToSave.medicineName,
        updatedAt: itemToSave.updatedAt,
      );
      return;
    }

    await _writeItemHistory(existing, itemToSave);
  }

  Future<List<Batch>> getBatches(String barcode) async {
    final normalizedBarcode = normalizeBarcode(barcode);
    final snap = await _items
        .doc(normalizedBarcode)
        .collection('batches')
        .orderBy('expiryDate')
        .get();
    final batches = snap.docs
        .map((doc) => Batch.fromFirestore(doc, normalizedBarcode))
        .toList();
    batches.sort(_compareBatchExpiry);
    return batches;
  }

  Future<String> addBatch(String barcode, Batch batch) async {
    final normalizedBarcode = normalizeBarcode(barcode);
    final batchId = _uuid.v4();
    final batchToSave = Batch(
      batchId: batchId,
      barcode: normalizedBarcode,
      batchNo: batch.batchNo,
      expiryDate: batch.expiryDate,
      quantity: batch.quantity,
      purchasePrice: batch.purchasePrice,
      salePrice: batch.salePrice,
      supplier: batch.supplier,
      purchaseDate: batch.purchaseDate,
      status: batch.status,
      createdAt: batch.createdAt,
      updatedAt: batch.updatedAt,
      receivedAt: batch.receivedAt ?? batch.createdAt,
      manufactureDate: batch.manufactureDate,
      invoiceNumber: batch.invoiceNumber,
      notes: batch.notes,
    );
    await _items
        .doc(normalizedBarcode)
        .collection('batches')
        .doc(batchId)
        .set(batchToSave.toMap());
    await _touchItem(normalizedBarcode, batch.updatedAt);
    await _updateDashboardSummary();
    _notifyStockChanged();
    final item = await getItem(normalizedBarcode);
    await _addAutoHistory(
      barcode: normalizedBarcode,
      medicineName: item?.medicineName ?? '',
      batchNo: batch.batchNo,
      actionType: 'Batch added',
      oldQuantity: 0,
      newQuantity: batch.quantity,
      quantityChange: batch.quantity,
      oldExpiryDate: batch.expiryDate,
      newExpiryDate: batch.expiryDate,
      reason: 'New batch',
      updatedAt: batch.updatedAt,
    );
    return batchId;
  }

  Future<String> receiveBatch(String barcode, Batch batch) async {
    final normalizedBarcode = normalizeBarcode(barcode);
    final batches = await getBatches(normalizedBarcode);
    for (final existing in batches) {
      if (_isSameReceivingBatch(existing, batch)) {
        await updateBatchQuantity(
          barcode: normalizedBarcode,
          batchId: existing.batchId,
          quantityChange: batch.quantity,
          reason: 'Received matching batch',
        );
        return existing.batchId;
      }
    }
    return addBatch(normalizedBarcode, batch);
  }

  Future<Batch?> findBatchByNumber(String barcode, String batchNo) async {
    final normalized = batchNo.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final batches = await getBatches(barcode);
    for (final batch in batches) {
      if (batch.batchNo.trim().toLowerCase() == normalized) {
        return batch;
      }
    }
    return null;
  }

  Future<void> updateBatch(String barcode, Batch batch) async {
    final normalizedBarcode = normalizeBarcode(barcode);
    final batchToSave = Batch(
      batchId: batch.batchId,
      barcode: normalizedBarcode,
      batchNo: batch.batchNo,
      expiryDate: batch.expiryDate,
      quantity: batch.quantity,
      purchasePrice: batch.purchasePrice,
      salePrice: batch.salePrice,
      supplier: batch.supplier,
      purchaseDate: batch.purchaseDate,
      status: batch.status,
      createdAt: batch.createdAt,
      updatedAt: batch.updatedAt,
      receivedAt: batch.receivedAt,
      manufactureDate: batch.manufactureDate,
      invoiceNumber: batch.invoiceNumber,
      notes: batch.notes,
    );
    final batchRef =
        _items.doc(normalizedBarcode).collection('batches').doc(batch.batchId);
    final existingDoc = await batchRef.get();
    final existing = existingDoc.exists
        ? Batch.fromFirestore(existingDoc, normalizedBarcode)
        : null;

    await batchRef.update(batchToSave.toMap());
    await _touchItem(normalizedBarcode, batch.updatedAt);

    if (existing != null) {
      await _writeBatchHistory(normalizedBarcode, existing, batchToSave);
    }
    await _updateDashboardSummary();
    _notifyStockChanged();
  }

  Future<void> updateBatchQuantity({
    required String barcode,
    required String batchId,
    required int quantityChange,
    required String reason,
  }) async {
    final normalizedBarcode = normalizeBarcode(barcode);
    final item = await getItem(normalizedBarcode);
    final batchRef =
        _items.doc(normalizedBarcode).collection('batches').doc(batchId);
    final existingDoc = await batchRef.get();
    if (!existingDoc.exists) return;
    final batch = Batch.fromFirestore(existingDoc, normalizedBarcode);
    final now = DateTime.now();
    if (batch.quantity + quantityChange < 0) {
      throw Exception('Adjustment cannot make stock negative.');
    }
    final newQuantity = (batch.quantity + quantityChange).clamp(0, 999999);
    final restoredStatus =
        batch.isExpiryMissing ? BatchStatus.expiryMissing : BatchStatus.active;
    final newStatus = newQuantity == 0
        ? _writeBatchStatus(BatchStatus.outOfStock)
        : quantityChange > 0
            ? _writeBatchStatus(restoredStatus)
            : _writeBatchStatus(batch.status);
    await batchRef.update({
      'quantity': newQuantity,
      'status': newStatus,
      'lastUpdatedAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
    await _touchItem(normalizedBarcode, now);
    await _updateDashboardSummary();
    _notifyStockChanged();
    await _addAutoHistory(
      barcode: normalizedBarcode,
      medicineName: item?.medicineName ?? '',
      batchNo: batch.batchNo,
      actionType: quantityChange >= 0 ? 'Add Stock' : 'Reduce Stock',
      oldQuantity: batch.quantity,
      newQuantity: newQuantity,
      quantityChange: quantityChange,
      oldExpiryDate: batch.expiryDate,
      newExpiryDate: batch.expiryDate,
      reason: reason,
      note: '',
      updatedAt: now,
    );
  }

  Future<void> adjustBatchStock({
    required String barcode,
    required String batchId,
    required int quantityChange,
    required String reason,
    String note = '',
  }) async {
    final normalizedBarcode = normalizeBarcode(barcode);
    if (quantityChange == 0) {
      throw Exception('Adjustment quantity must be greater than zero.');
    }
    final item = await getItem(normalizedBarcode);
    if (item == null) throw Exception('Medicine not found.');

    final batchRef =
        _items.doc(normalizedBarcode).collection('batches').doc(batchId);
    final existingDoc = await batchRef.get();
    if (!existingDoc.exists) throw Exception('Batch not found.');

    final batch = Batch.fromFirestore(existingDoc, normalizedBarcode);
    final newQuantity = batch.quantity + quantityChange;
    if (newQuantity < 0) {
      throw Exception('Adjustment cannot make stock negative.');
    }

    final now = DateTime.now();
    final restoredStatus =
        batch.isExpiryMissing ? BatchStatus.expiryMissing : BatchStatus.active;
    final status = newQuantity == 0
        ? BatchStatus.outOfStock
        : quantityChange > 0
            ? restoredStatus
            : batch.status;

    await batchRef.update({
      'quantity': newQuantity,
      'status': _writeBatchStatus(status),
      'lastUpdatedAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
    await _touchItem(normalizedBarcode, now);
    await _updateDashboardSummary();
    _notifyStockChanged();
    await _addAutoHistory(
      barcode: normalizedBarcode,
      medicineName: item.medicineName,
      batchNo: batch.batchNo,
      actionType: 'Stock Adjustment',
      oldQuantity: batch.quantity,
      newQuantity: newQuantity,
      quantityChange: quantityChange,
      oldExpiryDate: batch.expiryDate,
      newExpiryDate: batch.expiryDate,
      reason: reason,
      note: note,
      updatedAt: now,
    );
  }

  Future<SaleRecord> recordSale({
    required String barcode,
    required int quantitySold,
    required String paymentMethod,
    bool allowExpiredOverride = false,
  }) async {
    final normalizedBarcode = normalizeBarcode(barcode);
    if (quantitySold <= 0) {
      throw Exception('Sale quantity must be greater than zero.');
    }

    final item = await getItem(normalizedBarcode);
    if (item == null) throw Exception('Medicine not found.');

    final batches = await getBatches(normalizedBarcode);
    final candidateBatches = batches
        .where((batch) =>
            batch.quantity > 0 &&
            !batch.isRemoved &&
            !batch.isOutOfStock &&
            (allowExpiredOverride || !batch.isExpired))
        .toList()
      ..sort(_compareSaleBatches);
    final available =
        candidateBatches.fold<int>(0, (sum, batch) => sum + batch.quantity);
    if (available < quantitySold) {
      final expiredAvailable = batches
          .where((batch) =>
              batch.hasStock && batch.isExpired && batch.quantity > 0)
          .fold<int>(0, (sum, batch) => sum + batch.quantity);
      if (!allowExpiredOverride &&
          available == 0 &&
          expiredAvailable >= quantitySold) {
        throw Exception('Only expired stock is available.');
      }
      throw Exception('Only $available unit(s) available for sale.');
    }

    final now = DateTime.now();
    final actor = _actor;
    final saleId = _uuid.v4();
    var remaining = quantitySold;
    final batchesUsed = <SaleBatchUsage>[];
    final debugRows = <Map<String, Object?>>[];
    final writeBatch = _db.batch();

    for (final batch in candidateBatches) {
      if (remaining == 0) break;

      final soldFromBatch =
          batch.quantity < remaining ? batch.quantity : remaining;
      final newQuantity = batch.quantity - soldFromBatch;
      remaining -= soldFromBatch;

      final totalSaleAmount = batch.salePrice * soldFromBatch;
      final totalCost = batch.purchasePrice * soldFromBatch;
      batchesUsed.add(SaleBatchUsage(
        batchId: batch.batchId,
        batchNo: batch.batchNo,
        expiryDate: batch.expiryDate,
        quantity: soldFromBatch,
        salePrice: batch.salePrice,
        purchasePrice: batch.purchasePrice,
        totalSaleAmount: totalSaleAmount,
        totalCost: totalCost,
        profit: totalSaleAmount - totalCost,
      ));

      final batchRef = _items
          .doc(normalizedBarcode)
          .collection('batches')
          .doc(batch.batchId);
      writeBatch.update(batchRef, {
        'quantity': newQuantity,
        'status': newQuantity == 0
            ? _writeBatchStatus(BatchStatus.outOfStock)
            : _writeBatchStatus(batch.status),
        'lastUpdatedAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });

      // Add history record to the same batch write
      _addAutoHistory(
        barcode: normalizedBarcode,
        medicineName: item.medicineName,
        batchNo: batch.batchNo,
        actionType: 'Sale',
        oldQuantity: batch.quantity,
        newQuantity: newQuantity,
        quantityChange: -soldFromBatch,
        reason: 'FEFO sale',
        updatedAt: now,
        writeBatch: writeBatch,
      );

      debugRows.add({
        'barcode': normalizedBarcode,
        'batchId': batch.batchId,
        'batchNo': batch.batchNo,
        'oldQty': batch.quantity,
        'soldQty': soldFromBatch,
        'newQty': newQuantity,
        'saleId': saleId,
      });
    }

    if (remaining > 0) {
      final sold = quantitySold - remaining;
      throw Exception('Only $sold unit(s) available for sale.');
    }

    final sale = SaleRecord(
      saleId: saleId,
      barcode: normalizedBarcode,
      medicineName: item.medicineName,
      strength: item.strength,
      packageSize: item.packageSize,
      batchesUsed: batchesUsed,
      quantitySold: quantitySold,
      salePrice: batchesUsed.isEmpty ? 0 : batchesUsed.first.salePrice,
      purchasePrice: batchesUsed.isEmpty ? 0 : batchesUsed.first.purchasePrice,
      totalSaleAmount: batchesUsed.fold<double>(
          0, (sum, batch) => sum + batch.totalSaleAmount),
      totalCost:
          batchesUsed.fold<double>(0, (sum, batch) => sum + batch.totalCost),
      profit: batchesUsed.fold<double>(0, (sum, batch) => sum + batch.profit),
      soldAt: now,
      userEmail: actor.email,
      paymentMethod: paymentMethod,
    );

    writeBatch.set(_sales.doc(saleId), sale.toMap());
    writeBatch.set(
      _items.doc(normalizedBarcode),
      {'updatedAt': Timestamp.fromDate(now)},
      SetOptions(merge: true),
    );
    await writeBatch.commit();
    await _updateDashboardSummary();
    _notifyStockChanged();

    return sale;
  }

  Future<void> updateBatchExpiry({
    required String barcode,
    required String batchId,
    required DateTime expiryDate,
    required String reason,
  }) async {
    final normalizedBarcode = normalizeBarcode(barcode);
    final item = await getItem(normalizedBarcode);
    final batchRef =
        _items.doc(normalizedBarcode).collection('batches').doc(batchId);
    final existingDoc = await batchRef.get();
    if (!existingDoc.exists) return;
    final batch = Batch.fromFirestore(existingDoc, normalizedBarcode);
    final now = DateTime.now();
    final updateData = <String, dynamic>{
      'expiryDate': Timestamp.fromDate(expiryDate),
      'lastUpdatedAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    };
    if (batch.isExpiryMissing) {
      updateData['status'] = 'active';
    }
    await batchRef.update(updateData);
    await _touchItem(normalizedBarcode, now);
    await _addAutoHistory(
      barcode: normalizedBarcode,
      medicineName: item?.medicineName ?? '',
      batchNo: batch.batchNo,
      actionType: 'Update Expiry Date',
      oldQuantity: batch.quantity,
      newQuantity: batch.quantity,
      quantityChange: 0,
      oldExpiryDate: batch.expiryDate,
      newExpiryDate: expiryDate,
      reason: reason,
      note: '',
      updatedAt: now,
    );
    _notifyStockChanged();
  }

  Future<void> updateBatchStatus({
    required String barcode,
    required String batchId,
    required BatchStatus status,
    required String reason,
  }) async {
    final normalizedBarcode = normalizeBarcode(barcode);
    final item = await getItem(normalizedBarcode);
    final batchRef =
        _items.doc(normalizedBarcode).collection('batches').doc(batchId);
    final existingDoc = await batchRef.get();
    if (!existingDoc.exists) return;
    final batch = Batch.fromFirestore(existingDoc, normalizedBarcode);
    final now = DateTime.now();
    final newQuantity =
        (status == BatchStatus.active || status == BatchStatus.expiryMissing)
            ? batch.quantity
            : 0;
    await batchRef.update({
      'status': _writeBatchStatus(status),
      'quantity': newQuantity,
      'lastUpdatedAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
    await _touchItem(normalizedBarcode, now);
    await _addAutoHistory(
      barcode: normalizedBarcode,
      medicineName: item?.medicineName ?? '',
      batchNo: batch.batchNo,
      actionType: status == BatchStatus.expiryMissing
          ? 'Mark Expiry Missing'
          : status == BatchStatus.expired
              ? 'Mark Expired'
              : 'Remove from Active Stock',
      oldQuantity: batch.quantity,
      newQuantity: newQuantity,
      quantityChange: newQuantity - batch.quantity,
      oldExpiryDate: batch.expiryDate,
      newExpiryDate: batch.expiryDate,
      reason: reason,
      note: '',
      updatedAt: now,
    );
    _notifyStockChanged();
  }

  Future<void> deleteBatch(String barcode, Batch batch) async {
    final normalizedBarcode = normalizeBarcode(barcode);
    final now = DateTime.now();
    await _items
        .doc(normalizedBarcode)
        .collection('batches')
        .doc(batch.batchId)
        .delete();
    await _touchItem(normalizedBarcode, now);
    await _updateDashboardSummary();
    await _addHistory(
      normalizedBarcode,
      fieldChanged: 'Batch deleted',
      oldValue: batch.batchNo,
      newValue: '',
      updatedAt: now,
    );
    _notifyStockChanged();
  }

  /// Recalculates and saves the dashboard summary document.
  /// NOTE: This is inefficient and should be replaced by a Cloud Function.
  Future<void> _updateDashboardSummary() async {
    final allItems = await getAllItemsWithBatches();
    int totalMedicines = allItems.length;
    int totalBatches = 0;
    double inventoryValue = 0;

    for (final itemWithBatches in allItems) {
      totalBatches += itemWithBatches.batches.length;
      for (final batch in itemWithBatches.batches) {
        inventoryValue += batch.quantity * batch.purchasePrice;
      }
    }

    await _dashboardSummaryDoc.set({
      'totalMedicines': totalMedicines,
      'totalBatches': totalBatches,
      'inventoryValue': inventoryValue,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<UpdateHistory>> getHistory(String barcode) async {
    final normalizedBarcode = normalizeBarcode(barcode);
    final snap = await _items
        .doc(normalizedBarcode)
        .collection('history')
        .orderBy('updatedAt', descending: true)
        .limit(50)
        .get();
    return snap.docs.map(UpdateHistory.fromFirestore).toList();
  }

  Future<List<PharmacyItemWithBatches>> getRecentlyUpdatedItems(
      {int limit = 10}) async {
    final allData = await getAllItemsWithBatches();
    allData.sort((a, b) => b.item.updatedAt.compareTo(a.item.updatedAt));
    return allData.take(limit).toList();
  }

  Future<List<Map<String, dynamic>>> getExpiryAlerts({int limit = 5}) async {
    final missing = await getMissingExpiryBatches();
    final expired = await getExpiredBatches();
    final expiring7 = await getExpiringWithin7DaysBatches();
    final expiring30 = await getExpiringWithin30DaysBatches();
    return [...missing, ...expired, ...expiring7, ...expiring30]
        .take(limit)
        .toList();
  }

  Future<List<Map<String, dynamic>>> getExpiredBatches() async {
    return _getBatchesWhere((batch) => batch.isExpired);
  }

  Future<List<Map<String, dynamic>>> getExpiringWithin7DaysBatches() async {
    return _getBatchesWhere((batch) => batch.isWithin7Days);
  }

  Future<List<Map<String, dynamic>>> getExpiringWithin30DaysBatches() async {
    return _getBatchesWhere((batch) => batch.isWithin30Days);
  }

  Future<List<Map<String, dynamic>>> getMissingExpiryBatches() async {
    return _getBatchesWhere((batch) => batch.isExpiryMissing);
  }

  Future<List<Map<String, dynamic>>> getExpiringSoonBatches() {
    return _getBatchesWhere((batch) => batch.isExpiringSoon);
  }

  Future<void> _touchItem(String barcode, DateTime updatedAt) async {
    final normalizedBarcode = normalizeBarcode(barcode);
    // Use set+merge instead of update so a missing master document never
    // throws (e.g. a batch touched before the item doc was created).
    await _items.doc(normalizedBarcode).set(
      {'updatedAt': Timestamp.fromDate(updatedAt)},
      SetOptions(merge: true),
    );
  }

  Future<void> _addHistory(
    String barcode, {
    required String fieldChanged,
    required String oldValue,
    required String newValue,
    required DateTime updatedAt,
  }) async {
    final normalizedBarcode = normalizeBarcode(barcode);
    final historyId = _uuid.v4();
    final actor = _actor;
    final history = UpdateHistory(
      historyId: historyId,
      barcode: normalizedBarcode,
      medicineName: '',
      batchNo: '',
      actionType: fieldChanged,
      oldQuantity: null,
      newQuantity: null,
      quantityChange: null,
      oldExpiryDate: null,
      newExpiryDate: null,
      reason: '',
      note: '',
      fieldChanged: fieldChanged,
      oldValue: oldValue,
      newValue: newValue,
      updatedAt: updatedAt,
      userId: actor.id,
      userEmail: actor.email,
    );
    await _items
        .doc(normalizedBarcode)
        .collection('history')
        .doc(historyId)
        .set(history.toMap());
  }

  Future<void> _addAutoHistory({
    required String barcode,
    required String medicineName,
    String batchNo = '',
    required String actionType,
    int? oldQuantity,
    int? newQuantity,
    int? quantityChange,
    DateTime? oldExpiryDate,
    DateTime? newExpiryDate,
    required String reason,
    String note = '',
    required DateTime updatedAt,
    WriteBatch? writeBatch,
  }) async {
    final normalizedBarcode = normalizeBarcode(barcode);
    final historyId = _uuid.v4();
    final actor = _actor;
    final dateFormat = DateFormat('dd MMM yyyy');
    final oldExpiryText = _historyExpiryText(oldExpiryDate, dateFormat);
    final newExpiryText = _historyExpiryText(newExpiryDate, dateFormat);
    final history = UpdateHistory(
      historyId: historyId,
      barcode: normalizedBarcode,
      medicineName: medicineName,
      batchNo: batchNo,
      actionType: actionType,
      oldQuantity: oldQuantity,
      newQuantity: newQuantity,
      quantityChange: quantityChange,
      oldExpiryDate: oldExpiryDate,
      newExpiryDate: newExpiryDate,
      reason: reason,
      note: note,
      fieldChanged: actionType,
      oldValue: '$oldQuantity / $oldExpiryText',
      newValue: '$newQuantity / $newExpiryText',
      updatedAt: updatedAt,
      userId: actor.id,
      userEmail: actor.email,
    );
    final historyRef =
        _items.doc(normalizedBarcode).collection('history').doc(historyId);
    final historyData = history.toMap()
      ..['expiryDate'] = _historyExpiryValue(newExpiryDate)
      ..['expiryStatus'] = _historyExpiryStatus(newExpiryDate)
      ..['oldExpiryStatus'] = _historyExpiryStatus(oldExpiryDate)
      ..['newExpiryStatus'] = _historyExpiryStatus(newExpiryDate);
    if (writeBatch != null) {
      writeBatch.set(historyRef, historyData);
    } else {
      await historyRef.set(historyData);
    }
  }

  String _historyExpiryText(DateTime? expiryDate, DateFormat dateFormat) {
    if (expiryDate == null || expiryDate.year >= 9999) {
      return 'Expiry Missing';
    }
    return dateFormat.format(expiryDate);
  }

  Object? _historyExpiryValue(DateTime? expiryDate) {
    if (expiryDate == null || expiryDate.year >= 9999) {
      return null;
    }
    return Timestamp.fromDate(expiryDate);
  }

  String _historyExpiryStatus(DateTime? expiryDate) {
    if (expiryDate == null || expiryDate.year >= 9999) {
      return 'missing';
    }
    return 'known';
  }

  Future<List<UpdateHistory>> getStockMovementHistory({int limit = 100}) async {
    final allData = await getAllItemsWithBatches();
    final histories = <UpdateHistory>[];
    for (final data in allData) {
      final snap = await _items
          .doc(data.item.barcode)
          .collection('history')
          .orderBy('updatedAt', descending: true)
          .limit(limit)
          .get();
      histories.addAll(snap.docs.map(UpdateHistory.fromFirestore));
    }
    histories.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return histories.take(limit).toList();
  }

  Future<List<Map<String, dynamic>>> _getBatchesWhere(
      bool Function(Batch batch) test) async {
    // This is still inefficient for large datasets but is only used for
    // non-critical UI elements like expiry alerts.
    final allData = await getAllItemsWithBatches();
    final rows = <({PharmacyItem item, Batch batch})>[];
    for (final data in allData) {
      for (final batch in data.batches) {
        if (batch.hasStock) {
          rows.add((item: data.item, batch: batch));
        }
      }
    }

    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (test(row.batch)) {
        result.add({'item': row.item, 'batch': row.batch});
      }
    }
    result.sort((a, b) =>
        _compareBatchExpiry(a['batch'] as Batch, b['batch'] as Batch));
    return result;
  }

  Future<List<SaleRecord>> getSalesReport({int limit = 500}) async {
    final topLevelSnap =
        await _sales.orderBy('soldAt', descending: true).limit(limit).get();
    final salesById = <String, SaleRecord>{};
    for (final sale in topLevelSnap.docs.map(SaleRecord.fromFirestore)) {
      salesById[sale.saleId] = sale;
    }
    try {
      final legacySnap = await _db
          .collectionGroup('sales')
          .orderBy('soldAt', descending: true)
          .limit(limit)
          .get();
      for (final sale in legacySnap.docs.map(SaleRecord.fromFirestore)) {
        salesById.putIfAbsent(sale.saleId, () => sale);
      }
    } catch (error) {
      print('SALES_DEBUG legacy collectionGroup sales read skipped: $error');
    }
    final sales = salesById.values.toList();
    sales.sort((a, b) => b.soldAt.compareTo(a.soldAt));
    return sales.take(limit).toList();
  }

  Future<List<InventoryBalanceRow>> getInventoryBalanceReport() async {
    final allData = await getAllItemsWithBatches();
    final sales = await getSalesReport(limit: 5000);
    final history = await getStockMovementHistory(limit: 5000);
    final rows = <InventoryBalanceRow>[];

    for (final data in allData) {
      for (final batch in data.batches) {
        final batchSales = sales.expand((sale) {
          if (sale.barcode != data.item.barcode) return <SaleBatchUsage>[];
          return sale.batchesUsed
              .where((used) => used.batchNo == batch.batchNo)
              .toList();
        });
        final batchHistory = history.where((entry) =>
            entry.barcode == data.item.barcode &&
            entry.batchNo == batch.batchNo);

        final receivedQty = batchHistory
            .where((entry) =>
                entry.actionType == 'Batch added' ||
                entry.actionType == 'Add Stock')
            .fold<int>(
                0, (sum, entry) => sum + (entry.quantityChange ?? 0).abs());
        final soldQty =
            batchSales.fold<int>(0, (sum, used) => sum + used.quantity);
        final expiredRemovedQty = batchHistory
            .where((entry) =>
                entry.actionType == 'Mark Expired' ||
                entry.actionType == 'Remove from Active Stock')
            .fold<int>(
                0, (sum, entry) => sum + (entry.quantityChange ?? 0).abs());
        final damagedQty = batchHistory
            .where((entry) => entry.reason.toLowerCase().contains('damage'))
            .fold<int>(
                0, (sum, entry) => sum + (entry.quantityChange ?? 0).abs());
        final adjustmentQty = batchHistory
            .where((entry) =>
                entry.actionType == 'Reduce Stock' &&
                !entry.reason.toLowerCase().contains('damage'))
            .fold<int>(0, (sum, entry) => sum + (entry.quantityChange ?? 0));
        final openingQty = batch.quantity -
            receivedQty +
            soldQty +
            expiredRemovedQty +
            damagedQty -
            adjustmentQty;

        rows.add(InventoryBalanceRow(
          item: data.item,
          batch: batch,
          openingQty: openingQty,
          receivedQty: receivedQty,
          soldQty: soldQty,
          expiredRemovedQty: expiredRemovedQty,
          damagedQty: damagedQty,
          adjustmentQty: adjustmentQty,
        ));
      }
    }

    rows.sort((a, b) => _compareBatchExpiry(a.batch, b.batch));
    return rows;
  }

  Future<void> _writeItemHistory(
      PharmacyItem oldItem, PharmacyItem newItem) async {
    final changes = <String, List<String>>{
      'Medicine name': [oldItem.medicineName, newItem.medicineName],
      'Generic name': [oldItem.genericName, newItem.genericName],
      'Brand': [oldItem.brand, newItem.brand],
      'NDC': [oldItem.ndc, newItem.ndc],
      'Manufacturer': [oldItem.manufacturer, newItem.manufacturer],
      'Strength': [oldItem.strength, newItem.strength],
      'Dosage form': [oldItem.dosageForm, newItem.dosageForm],
      'Category': [oldItem.category, newItem.category],
      'Package size': [oldItem.packageSize, newItem.packageSize],
      'Minimum stock level': [
        '${oldItem.minimumStockLevel}',
        '${newItem.minimumStockLevel}'
      ],
      'Reorder level': ['${oldItem.reorderLevel}', '${newItem.reorderLevel}'],
      'Notes': [oldItem.notes, newItem.notes],
    };
    for (final entry in changes.entries) {
      if (entry.value[0] != entry.value[1]) {
        await _addHistory(
          newItem.barcode,
          fieldChanged: entry.key,
          oldValue: entry.value[0],
          newValue: entry.value[1],
          updatedAt: newItem.updatedAt,
        );
      }
    }
  }

  Future<void> _writeBatchHistory(
      String barcode, Batch oldBatch, Batch newBatch) async {
    final dateFormat = DateFormat('dd MMM yyyy');
    final oldExpiryText = oldBatch.isExpiryMissing
        ? 'Expiry Missing'
        : dateFormat.format(oldBatch.expiryDate);
    final newExpiryText = newBatch.isExpiryMissing
        ? 'Expiry Missing'
        : dateFormat.format(newBatch.expiryDate);
    final changes = <String, List<String>>{
      'Batch number': [oldBatch.batchNo, newBatch.batchNo],
      'Expiry date': [oldExpiryText, newExpiryText],
      'Quantity': ['${oldBatch.quantity}', '${newBatch.quantity}'],
      'Supplier': [oldBatch.supplier, newBatch.supplier],
      'Purchase price': [
        oldBatch.purchasePrice.toStringAsFixed(2),
        newBatch.purchasePrice.toStringAsFixed(2)
      ],
      'Sale price': [
        oldBatch.salePrice.toStringAsFixed(2),
        newBatch.salePrice.toStringAsFixed(2)
      ],
      'Invoice number': [oldBatch.invoiceNumber, newBatch.invoiceNumber],
      'Batch notes': [oldBatch.notes, newBatch.notes],
    };
    for (final entry in changes.entries) {
      if (entry.value[0] != entry.value[1]) {
        await _addHistory(
          barcode,
          fieldChanged: '${entry.key} (${newBatch.batchNo})',
          oldValue: entry.value[0],
          newValue: entry.value[1],
          updatedAt: newBatch.updatedAt,
        );
      }
    }
  }

  String _normalizeNdc(String value) {
    return value.trim().replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toLowerCase();
  }

  int _compareSaleBatches(Batch a, Batch b) {
    if (a.isExpired != b.isExpired) return a.isExpired ? 1 : -1;
    if (a.isExpiryMissing != b.isExpiryMissing) {
      return a.isExpiryMissing ? 1 : -1;
    }
    return a.expiryDate.compareTo(b.expiryDate);
  }

  int _compareBatchExpiry(Batch a, Batch b) {
    if (a.isExpiryMissing != b.isExpiryMissing) {
      return a.isExpiryMissing ? 1 : -1;
    }
    return a.expiryDate.compareTo(b.expiryDate);
  }

  bool _isSameReceivingBatch(Batch a, Batch b) {
    return a.batchNo.trim().toLowerCase() == b.batchNo.trim().toLowerCase() &&
        _sameDate(a.expiryDate, b.expiryDate) &&
        a.purchasePrice == b.purchasePrice;
  }

  bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _writeBatchStatus(BatchStatus status) {
    return switch (status) {
      BatchStatus.active => 'active',
      BatchStatus.expired => 'expired',
      BatchStatus.removed => 'removed',
      BatchStatus.outOfStock => 'out_of_stock',
      BatchStatus.expiryMissing => 'expiry_missing',
    };
  }

  void _notifyStockChanged() {
    if (!_stockChangedController.isClosed) {
      _stockChangedController.add(null);
    }
  }
}
