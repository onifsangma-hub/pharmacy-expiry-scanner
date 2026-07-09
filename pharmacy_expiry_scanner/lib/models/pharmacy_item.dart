// lib/models/pharmacy_item.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class StoreSettings {
  final String storeName;
  final String dbaName;
  final String addressLine1;
  final String city;
  final String state;
  final String zip;

  const StoreSettings({
    required this.storeName,
    required this.dbaName,
    required this.addressLine1,
    required this.city,
    required this.state,
    required this.zip,
  });

  static const defaults = StoreSettings(
    storeName: 'ASM DRUGS INC.',
    dbaName: 'FARMACIA CENTRAL',
    addressLine1: '55A East Gun Hill Road',
    city: 'Bronx',
    state: 'NY',
    zip: '10467',
  );

  factory StoreSettings.fromMap(Map<String, dynamic> data) {
    return StoreSettings(
      storeName: (data['storeName'] ?? defaults.storeName).toString(),
      dbaName: (data['dbaName'] ?? defaults.dbaName).toString(),
      addressLine1: _readAddressLine1(data['addressLine1']),
      city: (data['city'] ?? defaults.city).toString(),
      state: (data['state'] ?? defaults.state).toString(),
      zip: _readZip(data['zip']),
    );
  }

  static String _readAddressLine1(dynamic value) {
    final text = (value ?? defaults.addressLine1).toString();
    return text == '55A E Gun Hill Rd' ? defaults.addressLine1 : text;
  }

  static String _readZip(dynamic value) {
    final text = (value ?? defaults.zip).toString();
    return text == '10467-2103' ? defaults.zip : text;
  }

  Map<String, dynamic> toMap() {
    return {
      'storeName': storeName,
      'dbaName': dbaName,
      'addressLine1': addressLine1,
      'city': city,
      'state': state,
      'zip': zip,
    };
  }

  String get cityStateZip {
    final cityState = [city, state].where((part) => part.trim().isNotEmpty);
    final line = cityState.join(', ');
    if (line.isEmpty) return zip;
    return zip.trim().isEmpty ? line : '$line $zip';
  }
}

enum ExpiryStatus { expired, within7Days, within30Days, safe, missing }

enum BatchStatus { active, expired, removed, outOfStock, expiryMissing }

final DateTime missingExpiryDate = DateTime(9999, 12, 31);

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _isMissingExpiryDate(DateTime value) => value.year >= 9999;

DateTime _readDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.now();
}

int _readInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

double _readDouble(dynamic value) {
  if (value is int) return value.toDouble();
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? 0;
  return 0;
}

class PharmacyItem {
  final String barcode;
  final String medicineName;
  final String genericName;
  final String brand;
  final String ndc;
  final String manufacturer;
  final String strength;
  final String dosageForm;
  final String category;
  final String packageSize;
  final int minimumStockLevel;
  final int reorderLevel;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PharmacyItem({
    required this.barcode,
    required this.medicineName,
    required this.genericName,
    required this.brand,
    this.ndc = '',
    this.manufacturer = '',
    required this.strength,
    required this.dosageForm,
    required this.category,
    this.packageSize = '',
    this.minimumStockLevel = 0,
    this.reorderLevel = 0,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PharmacyItem.empty(String barcode) {
    final now = DateTime.now();
    return PharmacyItem(
      barcode: barcode,
      medicineName: '',
      genericName: '',
      brand: '',
      ndc: '',
      manufacturer: '',
      strength: '',
      dosageForm: '',
      category: '',
      packageSize: '',
      minimumStockLevel: 0,
      reorderLevel: 0,
      notes: '',
      createdAt: now,
      updatedAt: now,
    );
  }

  factory PharmacyItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return PharmacyItem(
      barcode: doc.id,
      medicineName: data['medicineName'] ?? '',
      genericName: data['genericName'] ?? '',
      brand: data['brand'] ?? '',
      ndc: data['ndc'] ?? '',
      manufacturer: data['manufacturer'] ?? '',
      strength: data['strength'] ?? '',
      dosageForm: data['dosageForm'] ?? '',
      category: data['category'] ?? '',
      packageSize: data['packageSize'] ?? '',
      minimumStockLevel: _readInt(data['minimumStockLevel']),
      reorderLevel: _readInt(data['reorderLevel']),
      notes: data['notes'] ?? '',
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'barcode': barcode,
      'medicineName': medicineName,
      'genericName': genericName,
      'brand': brand,
      'ndc': ndc,
      'manufacturer': manufacturer,
      'strength': strength,
      'dosageForm': dosageForm,
      'category': category,
      'packageSize': packageSize,
      'minimumStockLevel': minimumStockLevel,
      'reorderLevel': reorderLevel,
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  String get displayName => medicineName.isNotEmpty ? medicineName : barcode;

  String get description {
    final parts = [genericName, brand, strength, dosageForm]
        .where((part) => part.trim().isNotEmpty)
        .toList();
    return parts.join(' - ');
  }
}

class Batch {
  final String batchId;
  final String barcode;
  final String batchNo;
  final DateTime expiryDate;
  final int quantity;
  final double purchasePrice;
  final double salePrice;
  final String supplier;
  final DateTime purchaseDate;
  final BatchStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? receivedAt;
  final DateTime? manufactureDate;
  final String invoiceNumber;
  final String notes;

  const Batch({
    required this.batchId,
    required this.barcode,
    required this.batchNo,
    required this.expiryDate,
    required this.quantity,
    required this.purchasePrice,
    required this.salePrice,
    required this.supplier,
    required this.purchaseDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.receivedAt,
    this.manufactureDate,
    this.invoiceNumber = '',
    this.notes = '',
  });

  int get daysUntilExpiry {
    return _dateOnly(expiryDate).difference(_dateOnly(DateTime.now())).inDays;
  }

  bool get isActive => status == BatchStatus.active;
  bool get isRemoved => status == BatchStatus.removed;
  bool get isOutOfStock => status == BatchStatus.outOfStock || quantity == 0;
  bool get isExpiryMissing => status == BatchStatus.expiryMissing;
  bool get hasStock => !isRemoved && !isOutOfStock && quantity > 0;
  bool get isExpired =>
      !isRemoved &&
      !isExpiryMissing &&
      (status == BatchStatus.expired || daysUntilExpiry < 0);
  bool get isWithin7Days =>
      isActive && !isExpiryMissing && !isExpired && daysUntilExpiry <= 7;
  bool get isWithin30Days =>
      isActive &&
      !isExpiryMissing &&
      !isExpired &&
      daysUntilExpiry > 7 &&
      daysUntilExpiry <= 30;
  bool get isSafe =>
      isActive && !isExpiryMissing && !isExpired && daysUntilExpiry > 30;
  bool get isExpiringSoon => isWithin7Days || isWithin30Days;

  ExpiryStatus get expiryStatus {
    if (isExpiryMissing) return ExpiryStatus.missing;
    if (isExpired) return ExpiryStatus.expired;
    if (isWithin7Days) return ExpiryStatus.within7Days;
    if (isWithin30Days) return ExpiryStatus.within30Days;
    return ExpiryStatus.safe;
  }

  factory Batch.fromFirestore(DocumentSnapshot doc, String barcode) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final status = _readStatus(data['status']);
    final rawExpiryDate = data['expiryDate'];
    final expiryDate =
        status == BatchStatus.expiryMissing || rawExpiryDate == null
            ? missingExpiryDate
            : _readDate(rawExpiryDate);
    return Batch(
      batchId: doc.id,
      barcode: barcode,
      batchNo: data['batchNo'] ?? '',
      expiryDate: expiryDate,
      quantity: _readInt(data['quantity'] ?? data['currentQty']),
      purchasePrice: _readDouble(data['purchasePrice']),
      salePrice: _readDouble(data['salePrice']),
      supplier: data['supplier'] ?? '',
      purchaseDate: _readDate(data['purchaseDate'] ?? data['createdAt']),
      status: status,
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['lastUpdatedAt'] ?? data['updatedAt']),
      receivedAt:
          data['receivedAt'] == null ? null : _readDate(data['receivedAt']),
      manufactureDate: data['manufactureDate'] == null
          ? null
          : _readDate(data['manufactureDate']),
      invoiceNumber: data['invoiceNumber'] ?? '',
      notes: data['notes'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'barcode': barcode,
      'batchNo': batchNo,
      'expiryDate': isExpiryMissing || _isMissingExpiryDate(expiryDate)
          ? null
          : Timestamp.fromDate(expiryDate),
      'quantity': quantity,
      'purchasePrice': purchasePrice,
      'salePrice': salePrice,
      'supplier': supplier,
      'lastUpdatedAt': Timestamp.fromDate(updatedAt),
      'status': _writeStatus(status),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      if (receivedAt != null) 'receivedAt': Timestamp.fromDate(receivedAt!),
      if (manufactureDate != null)
        'manufactureDate': Timestamp.fromDate(manufactureDate!),
      'invoiceNumber': invoiceNumber,
      'notes': notes,
    };
  }
}

class UpdateHistory {
  final String historyId;
  final String barcode;
  final String medicineName;
  final String batchNo;
  final String actionType;
  final int? oldQuantity;
  final int? newQuantity;
  final int? quantityChange;
  final DateTime? oldExpiryDate;
  final DateTime? newExpiryDate;
  final String reason;
  final String note;
  final String fieldChanged;
  final String oldValue;
  final String newValue;
  final DateTime updatedAt;
  final String userId;
  final String userEmail;

  const UpdateHistory({
    required this.historyId,
    required this.barcode,
    required this.medicineName,
    required this.batchNo,
    required this.actionType,
    required this.oldQuantity,
    required this.newQuantity,
    required this.quantityChange,
    required this.oldExpiryDate,
    required this.newExpiryDate,
    required this.reason,
    this.note = '',
    required this.fieldChanged,
    required this.oldValue,
    required this.newValue,
    required this.updatedAt,
    this.userId = '',
    this.userEmail = '',
  });

  factory UpdateHistory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UpdateHistory(
      historyId: doc.id,
      barcode: data['barcode'] ?? '',
      medicineName: data['medicineName'] ?? '',
      batchNo: data['batchNo'] ?? '',
      actionType: data['actionType'] ?? data['fieldChanged'] ?? '',
      oldQuantity: data['oldQuantity'],
      newQuantity: data['newQuantity'],
      quantityChange: data['quantityChange'],
      oldExpiryDate: data['oldExpiryDate'] == null
          ? null
          : _readDate(data['oldExpiryDate']),
      newExpiryDate: data['newExpiryDate'] == null
          ? null
          : _readDate(data['newExpiryDate']),
      reason: data['reason'] ?? '',
      note: data['note'] ?? '',
      fieldChanged: data['fieldChanged'] ?? '',
      oldValue: data['oldValue'] ?? '',
      newValue: data['newValue'] ?? '',
      updatedAt: _readDate(data['updatedAt']),
      userId: data['userId'] ?? '',
      userEmail: data['userEmail'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'barcode': barcode,
      'medicineName': medicineName,
      'batchNo': batchNo,
      'actionType': actionType,
      'oldQuantity': oldQuantity,
      'newQuantity': newQuantity,
      'quantityChange': quantityChange,
      'oldExpiryDate':
          oldExpiryDate == null || _isMissingExpiryDate(oldExpiryDate!)
              ? null
              : Timestamp.fromDate(oldExpiryDate!),
      'newExpiryDate':
          newExpiryDate == null || _isMissingExpiryDate(newExpiryDate!)
              ? null
              : Timestamp.fromDate(newExpiryDate!),
      'reason': reason,
      'note': note,
      'fieldChanged': fieldChanged,
      'oldValue': oldValue,
      'newValue': newValue,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'userId': userId,
      'userEmail': userEmail,
    };
  }
}

class SaleBatchUsage {
  final String batchId;
  final String batchNo;
  final DateTime expiryDate;
  final int quantity;
  final double salePrice;
  final double purchasePrice;
  final double totalSaleAmount;
  final double totalCost;
  final double profit;

  const SaleBatchUsage({
    required this.batchId,
    required this.batchNo,
    required this.expiryDate,
    required this.quantity,
    required this.salePrice,
    required this.purchasePrice,
    required this.totalSaleAmount,
    required this.totalCost,
    required this.profit,
  });

  bool get isExpiryMissing => _isMissingExpiryDate(expiryDate);

  factory SaleBatchUsage.fromMap(Map<String, dynamic> data) {
    final quantity = _readInt(data['quantity'] ?? data['quantitySold']);
    final salePrice = _readDouble(data['salePrice']);
    final purchasePrice = _readDouble(data['purchasePrice']);
    final rawExpiryDate = data['expiryDate'];
    return SaleBatchUsage(
      batchId: data['batchId'] ?? '',
      batchNo: data['batchNo'] ?? '',
      expiryDate:
          rawExpiryDate == null ? missingExpiryDate : _readDate(rawExpiryDate),
      quantity: quantity,
      salePrice: salePrice,
      purchasePrice: purchasePrice,
      totalSaleAmount:
          _readDouble(data['totalSaleAmount'] ?? (salePrice * quantity)),
      totalCost: _readDouble(data['totalCost'] ?? (purchasePrice * quantity)),
      profit: _readDouble(
          data['profit'] ?? ((salePrice - purchasePrice) * quantity)),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'batchId': batchId,
      'batchNo': batchNo,
      'expiryDate': isExpiryMissing ? null : Timestamp.fromDate(expiryDate),
      'quantity': quantity,
      'salePrice': salePrice,
      'purchasePrice': purchasePrice,
      'totalSaleAmount': totalSaleAmount,
      'totalCost': totalCost,
      'profit': profit,
    };
  }
}

class SaleRecord {
  final String saleId;
  final String barcode;
  final String medicineName;
  final String strength;
  final String packageSize;
  final List<SaleBatchUsage> batchesUsed;
  final int quantitySold;
  final double salePrice;
  final double purchasePrice;
  final double totalSaleAmount;
  final double totalCost;
  final double profit;
  final DateTime soldAt;
  final String userEmail;
  final String paymentMethod;

  const SaleRecord({
    required this.saleId,
    required this.barcode,
    required this.medicineName,
    this.strength = '',
    this.packageSize = '',
    required this.batchesUsed,
    required this.quantitySold,
    required this.salePrice,
    required this.purchasePrice,
    required this.totalSaleAmount,
    required this.totalCost,
    required this.profit,
    required this.soldAt,
    required this.userEmail,
    this.paymentMethod = 'Cash',
  });

  factory SaleRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final rawBatches = data['batchesUsed'];
    final batchesUsed = rawBatches is List
        ? rawBatches
            .whereType<Map>()
            .map((entry) =>
                SaleBatchUsage.fromMap(Map<String, dynamic>.from(entry)))
            .toList()
        : <SaleBatchUsage>[];
    final quantitySold = _readInt(data['quantitySold']);
    final salePrice = _readDouble(data['salePrice']);
    final purchasePrice = _readDouble(data['purchasePrice']);
    final legacyRawExpiryDate = data['expiryDate'];
    final legacyBatch = batchesUsed.isNotEmpty
        ? null
        : SaleBatchUsage(
            batchId: data['batchId'] ?? '',
            batchNo: data['batchNo'] ?? '',
            expiryDate: legacyRawExpiryDate == null
                ? missingExpiryDate
                : _readDate(legacyRawExpiryDate),
            quantity: quantitySold,
            salePrice: salePrice,
            purchasePrice: purchasePrice,
            totalSaleAmount: _readDouble(
                data['totalSaleAmount'] ?? salePrice * quantitySold),
            totalCost:
                _readDouble(data['totalCost'] ?? purchasePrice * quantitySold),
            profit: _readDouble(
                data['profit'] ?? ((salePrice - purchasePrice) * quantitySold)),
          );
    final normalizedBatches =
        batchesUsed.isNotEmpty ? batchesUsed : [legacyBatch!];
    return SaleRecord(
      saleId: doc.id,
      barcode: data['barcode'] ?? '',
      medicineName: data['medicineName'] ?? '',
      strength: data['strength'] ?? '',
      packageSize: data['packageSize'] ?? '',
      batchesUsed: normalizedBatches,
      quantitySold: quantitySold,
      salePrice: salePrice,
      purchasePrice: purchasePrice,
      totalSaleAmount: _readDouble(data['totalSaleAmount'] ??
          normalizedBatches.fold<double>(
              0, (sum, batch) => sum + batch.totalSaleAmount)),
      totalCost: _readDouble(data['totalCost'] ??
          normalizedBatches.fold<double>(
              0, (sum, batch) => sum + batch.totalCost)),
      profit: _readDouble(data['profit'] ??
          normalizedBatches.fold<double>(
              0, (sum, batch) => sum + batch.profit)),
      soldAt: _readDate(data['soldAt']),
      userEmail: data['userEmail'] ?? '',
      paymentMethod: data['paymentMethod'] ?? 'Cash',
    );
  }

  String get batchNo => batchesUsed
      .map((batch) => batch.batchNo)
      .where((v) => v.isNotEmpty)
      .join(', ');

  DateTime get expiryDate => batchesUsed.isEmpty
      ? soldAt
      : batchesUsed
          .map((batch) => batch.expiryDate)
          .reduce((a, b) => a.isBefore(b) ? a : b);

  Map<String, dynamic> toMap() {
    return {
      'barcode': barcode,
      'medicineName': medicineName,
      'strength': strength,
      'packageSize': packageSize,
      'batchesUsed': batchesUsed.map((batch) => batch.toMap()).toList(),
      'quantitySold': quantitySold,
      'salePrice': salePrice,
      'purchasePrice': purchasePrice,
      'totalSaleAmount': totalSaleAmount,
      'totalCost': totalCost,
      'profit': profit,
      'soldAt': Timestamp.fromDate(soldAt),
      'userEmail': userEmail,
      'paymentMethod': paymentMethod,
    };
  }
}

class InventoryBalanceRow {
  final PharmacyItem item;
  final Batch batch;
  final int openingQty;
  final int receivedQty;
  final int soldQty;
  final int expiredRemovedQty;
  final int damagedQty;
  final int adjustmentQty;

  const InventoryBalanceRow({
    required this.item,
    required this.batch,
    required this.openingQty,
    required this.receivedQty,
    required this.soldQty,
    required this.expiredRemovedQty,
    required this.damagedQty,
    required this.adjustmentQty,
  });

  int get expectedCurrentQty =>
      openingQty +
      receivedQty -
      soldQty -
      expiredRemovedQty -
      damagedQty +
      adjustmentQty;

  int get currentQty => batch.quantity;
}

class PharmacyItemWithBatches {
  final PharmacyItem item;
  final List<Batch> batches;

  const PharmacyItemWithBatches({required this.item, required this.batches});

  int get totalQuantity => batches
      .where((batch) => batch.hasStock)
      .fold(0, (sum, batch) => sum + batch.quantity);
  int get totalActiveQuantity => batches
      .where((batch) => batch.isActive && batch.quantity > 0)
      .fold(0, (sum, batch) => sum + batch.quantity);
  int get shortageQty {
    final shortage = item.minimumStockLevel - totalActiveQuantity;
    return shortage > 0 ? shortage : 0;
  }

  List<Batch> get activeBatches =>
      batches.where((batch) => !batch.isRemoved).toList()
        ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
  bool get hasExpiredBatches => batches.any((batch) => batch.isExpired);
  bool get hasWithin7DaysBatches => batches.any((batch) => batch.isWithin7Days);
  bool get hasWithin30DaysBatches =>
      batches.any((batch) => batch.isWithin30Days);
  bool get hasSafeBatches => batches.any((batch) => batch.isSafe);
  bool get hasMissingExpiryBatches =>
      batches.any((batch) => batch.isExpiryMissing);
  bool get hasExpiringSoonBatches =>
      hasWithin7DaysBatches || hasWithin30DaysBatches;
  bool get isLowStock => totalActiveQuantity <= item.minimumStockLevel;

  Batch? get nextExpiringBatch {
    final sorted = activeBatches;
    return sorted.isEmpty ? null : sorted.first;
  }

  ExpiryStatus get expiryStatus {
    if (hasExpiredBatches) return ExpiryStatus.expired;
    if (hasWithin7DaysBatches) return ExpiryStatus.within7Days;
    if (hasWithin30DaysBatches) return ExpiryStatus.within30Days;
    if (hasMissingExpiryBatches) return ExpiryStatus.missing;
    return ExpiryStatus.safe;
  }
}

BatchStatus _readStatus(dynamic value) {
  return switch (value) {
    'expired' => BatchStatus.expired,
    'removed' => BatchStatus.removed,
    'out_of_stock' => BatchStatus.outOfStock,
    'outOfStock' => BatchStatus.outOfStock,
    'expiry_missing' => BatchStatus.expiryMissing,
    'expiryMissing' => BatchStatus.expiryMissing,
    _ => BatchStatus.active,
  };
}

String _writeStatus(BatchStatus status) {
  return switch (status) {
    BatchStatus.active => 'active',
    BatchStatus.expired => 'expired',
    BatchStatus.removed => 'removed',
    BatchStatus.outOfStock => 'out_of_stock',
    BatchStatus.expiryMissing => 'expiry_missing',
  };
}
