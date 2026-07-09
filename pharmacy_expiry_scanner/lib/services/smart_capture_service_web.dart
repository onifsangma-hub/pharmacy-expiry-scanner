// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;

import '../models/smart_capture_result.dart';

class SmartCaptureService {
  Future<SmartCapturePhoto?> capturePhoto(String label) async {
    final input = html.FileUploadInputElement()
      ..accept = 'image/*'
      ..multiple = false;
    input.setAttribute('capture', 'environment');
    input.click();

    await input.onChange.first.timeout(
      const Duration(minutes: 2),
      onTimeout: () => html.Event('timeout'),
    );
    if (input.files == null || input.files!.isEmpty) return null;

    final reader = html.FileReader();
    reader.readAsDataUrl(input.files!.first);
    await reader.onLoad.first;
    final dataUrl = reader.result?.toString() ?? '';
    input.value = '';
    if (dataUrl.isEmpty) return null;

    return SmartCapturePhoto(
      dataUrl: dataUrl,
      label: label,
      capturedAt: DateTime.now(),
    );
  }

  Future<SmartCaptureExtraction> analyzePhotos(
      List<SmartCapturePhoto> photos) async {
    final warnings = <String>[];
    final textBlocks = <String>[];
    final supported = js.context['TextDetector'] != null;

    for (final photo in photos) {
      final image = await _loadImage(photo.dataUrl);
      final text = await _detectText(image);
      if (text.isNotEmpty) textBlocks.add(text);
    }

    if (!supported) {
      warnings.add('OCR not supported on this browser. Confirm manually.');
    } else if (textBlocks.isEmpty) {
      warnings.add('No text detected. Confirm manually.');
    }

    return SmartCaptureExtraction(
      fields: _parseFields(textBlocks.join('\n')),
      warnings: warnings,
    );
  }

  Future<void> clearTemporaryData(List<SmartCapturePhoto> photos) async {
    photos.clear();
    final inputs = html.document.querySelectorAll('input[type="file"]');
    for (final input in inputs) {
      if (input is html.FileUploadInputElement) input.value = '';
    }
  }

  Future<html.ImageElement> _loadImage(String dataUrl) {
    final completer = Completer<html.ImageElement>();
    final image = html.ImageElement()..src = dataUrl;
    image.onLoad.first.then((_) => completer.complete(image));
    image.onError.first.then((event) => completer.completeError(event));
    return completer.future;
  }

  Future<String> _detectText(html.ImageElement image) async {
    final constructor = js.context['TextDetector'];
    if (constructor == null) return '';
    try {
      final detector = js.JsObject(constructor, []);
      final result =
          await _promiseToList(detector.callMethod('detect', [image]));
      final values = <String>[];
      for (final block in result) {
        final object = js.JsObject.fromBrowserObject(block);
        final rawValue = object['rawValue'];
        final text = rawValue?.toString().trim();
        if (text != null && text.isNotEmpty) values.add(text);
      }
      return values.join('\n');
    } catch (_) {
      return '';
    }
  }

  Future<List<dynamic>> _promiseToList(dynamic promise) {
    final completer = Completer<List<dynamic>>();
    final jsPromise = js.JsObject.fromBrowserObject(promise);
    jsPromise.callMethod('then', [
      (dynamic result) {
        final list = <dynamic>[];
        final array = js.JsObject.fromBrowserObject(result);
        final length = array['length'] as int? ?? 0;
        for (var i = 0; i < length; i++) {
          list.add(array[i]);
        }
        completer.complete(list);
      },
      (dynamic error) => completer.completeError(error),
    ]);
    return completer.future;
  }

  Map<String, String> _parseFields(String rawText) {
    final text = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
    return {
      'lot': _firstMatch(
        text,
        RegExp(
            r'\b(?:LOT|Lot|Batch|BATCH|BN|B/N)\s*[:#]?\s*([A-Z0-9][A-Z0-9\-\/]{1,})\b'),
      ),
      'expiry': _parseExpiry(text),
      'ndc': _firstMatch(
        text,
        RegExp(
          r'\b(?:NDC|N\.D\.C\.?)\s*[:#]?\s*([0-9]{4,5}[- ]?[0-9]{3,4}[- ]?[0-9]{1,2})\b',
          caseSensitive: false,
        ),
      ),
      'manufacturer': _labeledValue(text, [
        'manufactured by',
        'manufacturer',
        'mfg by',
        'distributed by',
        'distributor',
      ]),
    };
  }

  String _firstMatch(String text, RegExp regex) {
    return regex.firstMatch(text)?.group(1)?.trim() ?? '';
  }

  String _labeledValue(String text, List<String> labels) {
    for (final label in labels) {
      final value = _firstMatch(
        text,
        RegExp(
          '${RegExp.escape(label)}\\s*[:#]?\\s*([^.;\\n]{3,60})',
          caseSensitive: false,
        ),
      );
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _parseExpiry(String text) {
    final raw = _firstMatch(
      text,
      RegExp(
        r'\b(?:EXP|Exp|Expiry|Expiration|Use by)\s*[:#]?\s*([0-9]{1,2}[\/\-.][0-9]{2,4}|[0-9]{1,2}[\/\-.][0-9]{1,2}[\/\-.][0-9]{2,4})\b',
        caseSensitive: false,
      ),
    );
    if (raw.isEmpty) return '';
    final parts = raw.split(RegExp(r'[\/\-.]'));
    if (parts.length == 2) {
      final month = int.tryParse(parts[0]) ?? 0;
      final year = _expandYear(parts[1]);
      if (month < 1 || month > 12 || year == 0) return '';
      return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-01';
    }
    if (parts.length == 3) {
      final first = int.tryParse(parts[0]) ?? 0;
      final second = int.tryParse(parts[1]) ?? 0;
      final year = _expandYear(parts[2]);
      if (first == 0 || second == 0 || year == 0) return '';
      return '${year.toString().padLeft(4, '0')}-${first.toString().padLeft(2, '0')}-${second.toString().padLeft(2, '0')}';
    }
    return '';
  }

  int _expandYear(String value) {
    final parsed = int.tryParse(value) ?? 0;
    if (parsed == 0) return 0;
    return parsed < 100 ? 2000 + parsed : parsed;
  }
}
