const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

/**
 * Aggregates all inventory and sales data into a single summary document
 * for fast, real-time dashboard reads. This function is triggered manually
 * or on a schedule to ensure data consistency.
 */
exports.recalculateDashboard = functions.https.onCall(async (data, context) => {
  // Optional: Add auth check to ensure only admins can run this.
  // if (!context.auth) {
  //   throw new functions.https.HttpsError(
  //     "unauthenticated",
  //     "You must be authenticated to run this function.",
  //   );
  // }

  console.log("Starting full dashboard recalculation...");

  const summaryRef = db.collection("summaries").doc("dashboard");

  // 1. Count medicine master documents from pharmacy_items/{barcode}
  const medicinesSnapshot = await db.collection("pharmacy_items").get();
  const medicineBarcodes = medicinesSnapshot.docs.map((doc) => doc.id);

  console.log("DASHBOARD_COUNT_DEBUG medicine document count:",
    medicinesSnapshot.size);
  console.log("DASHBOARD_COUNT_DEBUG barcode list counted:",
    medicineBarcodes);

  // 2. Calculate all inventory stats from the 'batches' collection group
  const batchesSnapshot = await db.collectionGroup("batches").get();

  console.log("DASHBOARD_COUNT_DEBUG batch document count:",
    batchesSnapshot.size);

  let totalInventoryValue = 0;
  let expiredStockValue = 0;
  const activeBatches = [];

  batchesSnapshot.forEach((doc) => {
    const batch = doc.data();
    const quantity = batch.quantity || 0;
    const status = batch.status || "active";

    if (quantity > 0 && status === "active") {
      const purchasePrice = batch.purchasePrice || 0;
      const expiryDate = batch.expiryDate ? batch.expiryDate.toDate() : null;
      const isExpired = expiryDate ? expiryDate < new Date() : false;

      totalInventoryValue += purchasePrice * quantity;
      if (isExpired) {
        expiredStockValue += purchasePrice * quantity;
      }

      activeBatches.push(batch);
    }
  });

  const now = new Date();
  const todayStart = new Date(now.setHours(0, 0, 0, 0));

  // 2. Calculate today's sales and profit
  const salesSnapshot = await db
    .collection("sales")
    .where("soldAt", ">=", todayStart)
    .get();

  let todaySales = 0;
  let todayProfit = 0;

  salesSnapshot.forEach((doc) => {
    const sale = doc.data();
    todaySales += sale.totalSaleAmount || 0;
    todayProfit += sale.profit || 0;
  });

  // 3. Calculate expiry stats
  const daysUntil = (date) => {
    if (!date) return 9999;
    const diff = date.getTime() - now.getTime();
    return Math.floor(diff / (1000 * 60 * 60 * 24));
  };

  const summary = {
    totalItems: medicinesSnapshot.size,
    totalBatches: batchesSnapshot.size,
    totalInventoryValue,
    expiredStockValue,
    todaySales,
    todayProfit,
    expiredBatches: activeBatches.filter((b) => {
      const d = b.expiryDate?.toDate();
      return d && daysUntil(d) < 0;
    }).length,
    missingExpiryBatches: activeBatches.filter((b) => !b.expiryDate).length,
    expiring7Days: activeBatches.filter((b) => {
      const d = b.expiryDate?.toDate();
      const days = daysUntil(d);
      return d && days >= 0 && days <= 7;
    }).length,
    expiring30Days: activeBatches.filter((b) => {
      const d = b.expiryDate?.toDate();
      const days = daysUntil(d);
      return d && days > 7 && days <= 30;
    }).length,
    // Add other stats as needed
    receivedTodayQty: 0, // These are handled by incremental updates
    receivedTodayValue: 0,
    lastRecalculated: admin.firestore.FieldValue.serverTimestamp(),
  };

  await summaryRef.set(summary, {merge: true});

  console.log("Dashboard recalculation complete.", summary);
  return {status: "ok", summary};
});

/**
 * Increments dashboard summary totals when a new sale is recorded.
 */
exports.onSaleCreated = functions.firestore
  .document("sales/{saleId}")
  .onCreate(async (snap, context) => {
    const sale = snap.data();
    const summaryRef = db.collection("summaries").doc("dashboard");

    const saleAmount = sale.totalSaleAmount || 0;
    const profit = sale.profit || 0;
    const inventoryValueChange = -sale.totalCost || 0;

    // Use FieldValue.increment for atomic updates
    return summaryRef.set(
      {
        todaySales: admin.firestore.FieldValue.increment(saleAmount),
        todayProfit: admin.firestore.FieldValue.increment(profit),
        totalInventoryValue: admin.firestore.FieldValue.increment(
          inventoryValueChange,
        ),
      },
      {merge: true},
    );
  });

/**
 * Updates dashboard summary totals when a batch is created, updated, or deleted.
 * This is more complex and requires handling quantity and value changes.
 */
exports.onBatchWritten = functions.firestore
  .document("pharmacy_items/{itemId}/batches/{batchId}")
  .onWrite(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const summaryRef = db.collection("summaries").doc("dashboard");
    const now = new Date();

    // Calculate the change in inventory value
    const valueBefore = (before?.quantity || 0) * (before?.purchasePrice || 0);
    const valueAfter = (after?.quantity || 0) * (after?.purchasePrice || 0);
    const valueChange = valueAfter - valueBefore;

    // Determine if this is a new batch, a deleted batch, or an update
    const isNewBatch = !change.before.exists && change.after.exists;
    const isDeletedBatch = change.before.exists && !change.after.exists;
    const batchCountChange = isNewBatch ? 1 : isDeletedBatch ? -1 : 0;

    // *** IMPORTANT ***
    // If a sale just happened, the onSaleCreated trigger already handled the
    // inventory value change. We check if the quantity was DECREASED and if
    // the update happened within the last few seconds. If so, we assume it's
    // from a sale and we DO NOT adjust the inventory value here to avoid
    // double-counting.
    const isLikelyFromSale =
      !isNewBatch &&
      !isDeletedBatch &&
      (after.quantity < before.quantity) &&
      (now.getTime() - after.updatedAt.toDate().getTime() < 5000);

    const summaryUpdate = {
      totalBatches: admin.firestore.FieldValue.increment(batchCountChange),
    };

    if (!isLikelyFromSale) {
      summaryUpdate.totalInventoryValue =
        admin.firestore.FieldValue.increment(valueChange);
    }

    // Handle "Received Today" stats only for new batches created today
    if (isNewBatch) {
      const createdAt = after.createdAt.toDate();
      const todayStart = new Date(now.setHours(0, 0, 0, 0));
      if (createdAt >= todayStart) {
        summaryUpdate.receivedTodayQty = admin.firestore.FieldValue.increment(
          after.quantity || 0,
        );
        summaryUpdate.receivedTodayValue = admin.firestore.FieldValue.increment(
          (after.quantity || 0) * (after.purchasePrice || 0),
        );
      }
    }

    // A full recalculation is still needed periodically for expiry stats.
    return summaryRef.set(summaryUpdate, {merge: true});
  });
