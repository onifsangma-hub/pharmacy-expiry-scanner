import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/pharmacy_item.dart';
import 'firestore_service.dart';
import 'receipt_share.dart';

class ReceiptService {
  final FirestoreService _firestoreService = FirestoreService();

  Future<StoreSettings> getStoreSettings() {
    return _firestoreService.getStoreSettings();
  }

  Future<Uint8List> buildReceiptPdf(SaleRecord sale) async {
    final settings = await getStoreSettings();
    final pdf = pw.Document();
    final receiptNo = receiptNumber(sale);
    final dateTime = DateFormat('MM/dd/yyyy hh:mm a').format(sale.soldAt);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Padding(
          padding: const pw.EdgeInsets.all(24),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'ASM DRUGS INC.',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'FARMACIA CENTRAL',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(settings.addressLine1),
                    pw.Text(settings.cityStateZip),
                  ],
                ),
              ),
              pw.SizedBox(height: 18),
              pw.Divider(),
              _line('Receipt number', receiptNo),
              _line('Date/time', dateTime),
              _line('Cashier', sale.userEmail.isEmpty ? '-' : sale.userEmail),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headers: const ['Medicine name', 'Qty', 'Unit price', 'Total'],
                data: sale.batchesUsed
                    .map(
                      (batch) => [
                        _medicineLine(sale),
                        '${batch.quantity}',
                        '\$${batch.salePrice.toStringAsFixed(2)}',
                        '\$${batch.totalSaleAmount.toStringAsFixed(2)}',
                      ],
                    )
                    .toList(),
                border: pw.TableBorder.all(color: PdfColors.grey300),
                cellAlignment: pw.Alignment.centerLeft,
                cellAlignments: {
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                },
              ),
              pw.SizedBox(height: 12),
              _line('Payment method', sale.paymentMethod),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  'Grand total: \$${sale.totalSaleAmount.toStringAsFixed(2)}',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Spacer(),
              pw.Center(
                child: pw.Text(
                  'COME SEE US AGAIN',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return pdf.save();
  }

  Future<void> savePdf(SaleRecord sale) async {
    final bytes = await buildReceiptPdf(sale);
    await saveReceiptPdf(bytes, 'receipt-${receiptNumber(sale)}.pdf');
  }

  Future<void> sharePdf(SaleRecord sale) async {
    final bytes = await buildReceiptPdf(sale);
    await shareReceiptPdf(
      bytes,
      'receipt-${receiptNumber(sale)}.pdf',
      'Receipt ${receiptNumber(sale)}',
    );
  }

  String receiptNumber(SaleRecord sale) {
    if (sale.saleId.length <= 8) return sale.saleId;
    return sale.saleId.substring(0, 8).toUpperCase();
  }

  String _medicineLine(SaleRecord sale) {
    final details = [sale.strength, sale.packageSize]
        .where((part) => part.trim().isNotEmpty)
        .join(' / ');
    return details.isEmpty
        ? sale.medicineName
        : '${sale.medicineName}\n$details';
  }

  pw.Widget _line(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 110,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }
}
