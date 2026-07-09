import '../models/smart_capture_result.dart';

class SmartCaptureService {
  Future<SmartCapturePhoto?> capturePhoto(String label) async => null;

  Future<SmartCaptureExtraction> analyzePhotos(
      List<SmartCapturePhoto> photos) async {
    return const SmartCaptureExtraction(
      fields: {},
      warnings: ['Smart Capture is available in the web app.'],
    );
  }

  Future<void> clearTemporaryData(List<SmartCapturePhoto> photos) async {
    photos.clear();
  }
}
