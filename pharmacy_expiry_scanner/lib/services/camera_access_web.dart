// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

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
  final mediaDevices = html.window.navigator.mediaDevices;
  final host = html.window.location.hostname;
  final isLocalhost =
      host == 'localhost' || host == '127.0.0.1' || host == '::1';

  if (html.window.isSecureContext != true && !isLocalhost) {
    return _result(
      CameraAccessStatus.unsupportedBrowser,
      'unsupported browser',
      'Camera access requires HTTPS.',
    );
  }

  if (mediaDevices == null) {
    return _result(
      CameraAccessStatus.unsupportedBrowser,
      'unsupported browser',
      'navigator.mediaDevices is not available.',
    );
  }

  try {
    final stream = await mediaDevices.getUserMedia({
      'audio': false,
      'video': {
        'facingMode': {'ideal': 'environment'},
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
        'frameRate': {'ideal': 30, 'max': 30},
        'advanced': [
          {'focusMode': 'continuous'},
          {'exposureMode': 'continuous'},
          {'whiteBalanceMode': 'continuous'},
        ],
      },
    });

    final videoTracks = stream.getVideoTracks();
    _stopStream(stream);

    if (videoTracks.isEmpty) {
      return _result(
        CameraAccessStatus.noCameraFound,
        'no camera found',
        'The browser granted media access but returned no video track.',
      );
    }

    debugPrint('permission granted');
    return const CameraAccessResult(
      CameraAccessStatus.granted,
      'permission granted',
    );
  } catch (error) {
    final firstError = error;
    final deniedResult = _permissionResultFor(error);
    if (deniedResult != null) {
      return deniedResult;
    }

    if (_isNoCameraError(error)) {
      return _result(
          CameraAccessStatus.noCameraFound, 'no camera found', '$error');
    }

    try {
      final fallbackStream = await mediaDevices.getUserMedia({
        'audio': false,
        'video': true,
      });
      final videoTracks = fallbackStream.getVideoTracks();
      _stopStream(fallbackStream);

      if (videoTracks.isEmpty) {
        return _result(
          CameraAccessStatus.noCameraFound,
          'no camera found',
          'Fallback stream returned no video track.',
        );
      }

      debugPrint('permission granted');
      return const CameraAccessResult(
        CameraAccessStatus.granted,
        'permission granted',
      );
    } catch (fallbackError) {
      final fallbackDenied = _permissionResultFor(fallbackError);
      if (fallbackDenied != null) {
        return fallbackDenied;
      }
      if (_isNoCameraError(fallbackError)) {
        return _result(
          CameraAccessStatus.noCameraFound,
          'no camera found',
          '$fallbackError',
        );
      }

      return _result(
        CameraAccessStatus.cameraFailed,
        'permission granted but camera failed',
        'Initial: $firstError; fallback: $fallbackError',
      );
    }
  }
}

Future<void> optimizeActiveCameraStream() async {
  final videos = html.document.querySelectorAll('video');
  for (final element in videos) {
    if (element is! html.VideoElement) continue;

    element
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..setAttribute('webkit-playsinline', 'true');

    final stream = element.srcObject;
    if (stream is! html.MediaStream) continue;

    for (final track in stream.getVideoTracks()) {
      try {
        await track.applyConstraints({
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 30, 'max': 30},
          'advanced': [
            {'focusMode': 'continuous'},
            {'exposureMode': 'continuous'},
            {'whiteBalanceMode': 'continuous'},
          ],
        });
        debugPrint('camera stream optimized');
      } catch (error) {
        debugPrint('camera focus constraints skipped: $error');
        try {
          await track.applyConstraints({
            'width': {'ideal': 1280},
            'height': {'ideal': 720},
            'frameRate': {'ideal': 30},
          });
        } catch (fallbackError) {
          debugPrint('camera resolution constraints skipped: $fallbackError');
        }
      }
    }
  }
}

CameraAccessResult? _permissionResultFor(Object error) {
  final text = error.toString();
  if (text.contains('NotAllowedError') ||
      text.contains('PermissionDeniedError') ||
      text.contains('SecurityError')) {
    return _result(
        CameraAccessStatus.permissionDenied, 'permission denied', text);
  }
  return null;
}

bool _isNoCameraError(Object error) {
  final text = error.toString();
  return text.contains('NotFoundError') ||
      text.contains('DevicesNotFoundError') ||
      text.contains('NotReadableError');
}

void _stopStream(html.MediaStream stream) {
  for (final track in stream.getTracks()) {
    track.stop();
  }
}

CameraAccessResult _result(
  CameraAccessStatus status,
  String debugMessage, [
  String? details,
]) {
  debugPrint(details == null ? debugMessage : '$debugMessage: $details');
  return CameraAccessResult(status, debugMessage, details);
}
