const {setGlobalOptions} = require("firebase-functions");
const {onCall} = require("firebase-functions/v2/https");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const {initializeApp} = require("firebase-admin/app");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");

initializeApp();
setGlobalOptions({maxInstances: 10});

const db = getFirestore();

/**
 * Counts medicine master documents and batch documents for dashboard totals.
 *
 * @return {Promise<object>} Dashboard document counts and counted barcodes.
 */
async function countDashboardDocuments() {
  const medicinesSnapshot = await db.collection("pharmacy_items").get();
  const batchesSnapshot = await db.collectionGroup("batches").get();
  const medicineBarcodes = medicinesSnapshot.docs.map((doc) => doc.id);

  logger.info("DASHBOARD_COUNT_DEBUG medicine document count", {
    count: medicinesSnapshot.size,
  });
  logger.info("DASHBOARD_COUNT_DEBUG batch document count", {
    count: batchesSnapshot.size,
  });
  logger.info("DASHBOARD_COUNT_DEBUG barcode list counted", {
    barcodes: medicineBarcodes,
  });

  return {
    medicineCount: medicinesSnapshot.size,
    batchCount: batchesSnapshot.size,
    medicineBarcodes,
  };
}

exports.recalculateDashboard = onCall(async () => {
  logger.info("Starting full dashboard recalculation...");

  const summaryRef = db.collection("summaries").doc("dashboard");

  const counts = await countDashboardDocuments();
  const batchesSnapshot = await db.collectionGroup("batches").get();

  let totalInventoryValue = 0;
  let expiredStockValue = 0;
  const activeBatches = [];

  const now = new Date();
  const todayStart = new Date(now);
  todayStart.setHours(0, 0, 0, 0);

  batchesSnapshot.forEach((doc) => {
    const batch = doc.data();
    const quantity = batch.quantity || 0;
    const status = batch.status || "active";

    if (quantity > 0 && status === "active") {
      const purchasePrice = batch.purchasePrice || 0;
      const expiryDate = batch.expiryDate ? batch.expiryDate.toDate() : null;
      const isExpired = expiryDate ? expiryDate < now : false;

      totalInventoryValue += purchasePrice * quantity;
      if (isExpired) {
        expiredStockValue += purchasePrice * quantity;
      }

      activeBatches.push(batch);
    }
  });

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

  const daysUntil = (date) => {
    if (!date) return 9999;
    const diff = date.getTime() - now.getTime();
    return Math.floor(diff / (1000 * 60 * 60 * 24));
  };

  const summary = {
    totalItems: counts.medicineCount,
    totalBatches: counts.batchCount,
    totalInventoryValue,
    expiredStockValue,
    todaySales,
    todayProfit,
    expiredBatches: activeBatches.filter((batch) => {
      const expiryDate = batch.expiryDate ? batch.expiryDate.toDate() : null;
      return expiryDate && daysUntil(expiryDate) < 0;
    }).length,
    missingExpiryBatches:
      activeBatches.filter((batch) => !batch.expiryDate).length,
    expiring7Days: activeBatches.filter((batch) => {
      const expiryDate = batch.expiryDate ? batch.expiryDate.toDate() : null;
      const days = daysUntil(expiryDate);
      return expiryDate && days >= 0 && days <= 7;
    }).length,
    expiring30Days: activeBatches.filter((batch) => {
      const expiryDate = batch.expiryDate ? batch.expiryDate.toDate() : null;
      const days = daysUntil(expiryDate);
      return expiryDate && days > 7 && days <= 30;
    }).length,
    lastRecalculated: FieldValue.serverTimestamp(),
  };

  await summaryRef.set(summary, {merge: true});

  logger.info("Dashboard recalculation complete.", summary);
  return {status: "ok", summary};
});

/**
 * Refreshes total medicine and batch document counts in the dashboard summary.
 *
 * @return {Promise<void>} Resolves after the summary document is updated.
 */
async function refreshDashboardDocumentCounts() {
  const counts = await countDashboardDocuments();
  await db.collection("summaries").doc("dashboard").set(
      {
        totalItems: counts.medicineCount,
        totalBatches: counts.batchCount,
        countRefreshedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
  );
}

exports.onMedicineMasterWritten = onDocumentWritten(
    "pharmacy_items/{barcode}",
    async () => refreshDashboardDocumentCounts(),
);

exports.onBatchDocumentWritten = onDocumentWritten(
    "pharmacy_items/{barcode}/batches/{batchId}",
    async () => refreshDashboardDocumentCounts(),
);
