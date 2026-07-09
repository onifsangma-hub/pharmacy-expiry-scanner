// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

Future<void> openReceiptShareUrl(String url) async {
  html.window.open(url, '_blank');
}

Future<void> saveReceiptPdf(Uint8List bytes, String filename) async {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

Future<void> shareReceiptPdf(
  Uint8List bytes,
  String filename,
  String text,
) async {
  await saveReceiptPdf(bytes, filename);
}
