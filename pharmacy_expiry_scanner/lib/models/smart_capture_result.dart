class SmartCapturePhoto {
  final String dataUrl;
  final String label;
  final DateTime capturedAt;

  const SmartCapturePhoto({
    required this.dataUrl,
    required this.label,
    required this.capturedAt,
  });
}

class SmartCaptureExtraction {
  final Map<String, String> fields;
  final List<String> warnings;

  const SmartCaptureExtraction({
    required this.fields,
    this.warnings = const [],
  });

  String value(String key) => fields[key] ?? '';

  DateTime? get expiryDate {
    final value = fields['expiry'] ?? '';
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }
}
