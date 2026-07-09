import 'package:flutter/foundation.dart';

enum CameraAccessStatus {
  granted,
  permissionDenied,
  noCameraFound,
  unsupportedBrowser,
  cameraFailed,
}

class CameraAccessResult {
  const CameraAccessResult(this.status, this.debugMessage, [this.details]);

  final CameraAccessStatus status;
  final String debugMessage;
  final String? details;

  bool get isGranted => status == CameraAccessStatus.granted;
}

Future<CameraAccessResult> requestCameraAccess() async {
  debugPrint('permission granted');
  return const CameraAccessResult(
    CameraAccessStatus.granted,
    'permission granted',
  );
}

Future<void> optimizeActiveCameraStream() async {}
