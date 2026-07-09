// lib/screens/scanner_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/pharmacy_item.dart';
import '../services/camera_access.dart';
import '../services/firestore_service.dart';
import '../services/scanner_feedback.dart';
import '../utils/app_theme.dart';
import 'add_medicine_screen.dart';
import 'update_medicine_screen.dart';

class ScannerScreen extends StatefulWidget {
  final bool returnBarcode;

  const ScannerScreen({super.key, this.returnBarcode = false});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  static const _supportedFormats = [
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.dataMatrix,
    BarcodeFormat.qrCode,
    BarcodeFormat.pdf417,
  ];

  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 250,
    facing: CameraFacing.back,
    formats: _supportedFormats,
    autoZoom: true,
    torchEnabled: false,
  );
  final FirestoreService _firestoreService = FirestoreService();
  bool _isProcessing = false;
  bool _cameraFailed = false;
  bool _isStartingCamera = false;
  bool _pausedByLifecycle = false;
  String _statusMessage = 'Hold barcode inside box';
  String? _cameraHelpMessage;
  String? _lastScanned, _lastScannedFormat;
  DateTime? _lastScanTime;
  String _debugCameraStarted = 'camera started: no';
  String _debugBarcodeDetected = 'barcode detected: no'; // found/not found
  String _debugRawBarcode = 'raw barcode: -'; // raw value
  String _debugBarcodeFormat = 'barcode format: -'; // format
  String _debugNormalizedBarcode = 'normalized barcode: -'; // normalized value
  String _debugLookupResult = 'lookup found: -';
  String _debugScannerState = 'scanner paused/stopped: stopped';
  String _debugErrorMessage = 'error message: -';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _safeStopCamera(updateDebug: false);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_pausedByLifecycle && !_isProcessing) {
          _pausedByLifecycle = false;
          _startCamera();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _pausedByLifecycle = true;
        _safeStopCamera();
    }
  }

  Future<void> _handleBarcode(String barcode, {BarcodeFormat? format}) async {
    final scan = _ScannedBarcode.fromRaw(barcode);
    final normalizedBarcode = scan.lookupBarcode;
    final upcCandidate = _upcCandidateFor(normalizedBarcode);
    final detectedFormat = format?.name ?? 'manual';
    if (!_isValidBarcodeValue(normalizedBarcode)) {
      debugPrint('Ignored invalid barcode value: $barcode');
      if (mounted) {
        setState(() {
          _debugBarcodeDetected = 'barcode detected: yes (ignored)';
          _debugRawBarcode = 'raw barcode: $barcode';
          _debugBarcodeFormat = 'barcode format: $detectedFormat';
          _debugNormalizedBarcode = 'normalized barcode: invalid';
          _debugLookupResult = 'lookup found: -';
          _debugErrorMessage = 'error message: invalid barcode value';
        });
      }
      return;
    }
    final now = DateTime.now();
    if (_isProcessing ||
        (normalizedBarcode == _lastScanned &&
            _lastScanTime != null &&
            now.difference(_lastScanTime!) <
                const Duration(milliseconds: 800))) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _lastScanned = normalizedBarcode;
      _lastScanTime = now;
      _lastScannedFormat = detectedFormat;
      _statusMessage = 'Checking pharmacy database';
      _debugBarcodeDetected = 'barcode detected: yes';
      _debugRawBarcode = 'raw barcode: $barcode';
      _debugNormalizedBarcode = 'normalized barcode: $normalizedBarcode';
      _debugBarcodeFormat = 'barcode format: ${_lastScannedFormat ?? '-'}';
      _debugLookupResult = 'lookup found: -';
      _debugErrorMessage = 'error message: -';
    });

    await _safeStopCamera();
    try {
      await playScanFeedback();

      if (widget.returnBarcode) {
        if (mounted)
          Navigator.pop(context,
              upcCandidate.isNotEmpty ? upcCandidate : normalizedBarcode);
        return;
      }

      final lookup = await _lookupScannedBarcode(
        normalizedBarcode,
        upcCandidate,
      );
      final existingData = lookup.data;
      final exists = existingData != null;
      final firestorePath = FirestoreService.itemPathForBarcode(
        lookup.lookupBarcode,
      );
      debugPrint(
        'Barcode scan debug\n'
        'rawBarcode: $barcode\n'
        'detectedFormat: $detectedFormat\n'
        'normalizedBarcode: $normalizedBarcode\n'
        'upcCandidate: ${upcCandidate.isEmpty ? '-' : upcCandidate}\n'
        'lookupFound: $exists\n'
        'lookupStep: ${lookup.lookupStep}\n'
        'parsed gtin: ${scan.gs1?.gtin ?? ''}\n'
        'Firestore path checked: $firestorePath\n'
        'medicine found: $exists',
      );
      if (!mounted) return;

      setState(() {
        _debugLookupResult = exists ? 'lookup found: yes' : 'lookup found: no';
        _statusMessage =
            exists ? 'Medicine found' : 'Medicine not found in database';
      });

      if (existingData != null) {
        await _showProductCard(existingData, scan.gs1);
      } else {
        await _showNewProduct(normalizedBarcode, scan.gs1);
      }
    } catch (error) {
      debugPrint('Barcode handling failed: $error');
      if (mounted) {
        setState(() {
          _statusMessage = 'Scanner error';
          _debugLookupResult = 'lookup found: error';
          _debugErrorMessage = 'error message: $error';
        });
      }
    } finally {
      if (!mounted || widget.returnBarcode) return;
      setState(() {
        _isProcessing = false;
        _lastScanned = null;
        _statusMessage = 'Hold barcode inside box';
        _debugLookupResult = 'lookup found: -';
      });
      await _startCamera();
    }
  }

  Future<void> _showProductCard(
    PharmacyItemWithBatches data,
    _Gs1Data? gs1, {
    bool openAddBatch = false,
  }) async {
    await _firestoreService.recordLastScanned(data.item.barcode);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductCardSheet(
        initialData: data,
        initialGs1: gs1,
        openAddBatchOnLoad: openAddBatch,
      ),
    );
  }

  Future<void> _showNewProduct(String barcode, _Gs1Data? gs1) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddMedicineScreen(
          barcode: barcode,
          lockedBarcode: true,
        ),
      ),
    );
    if (saved != true || !mounted) return;

    final data = await _firestoreService.getItemWithBatches(barcode);
    if (data != null) {
      await _showProductCard(data, gs1, openAddBatch: true);
    }
  }

  String _normalizeBarcode(String value) {
    return FirestoreService.normalizeBarcode(value);
  }

  String _upcCandidateFor(String value) {
    final normalized = _normalizeBarcode(value);
    if (RegExp(r'^\d{13}$').hasMatch(normalized) &&
        normalized.startsWith('0')) {
      return normalized.substring(1);
    }
    return '';
  }

  Future<_LookupResult> _lookupScannedBarcode(
    String normalizedBarcode,
    String upcCandidate,
  ) async {
    // 1. Search for the normalized barcode directly.
    PharmacyItem? item = await _firestoreService.getItem(normalizedBarcode);
    String lookupStep = 'direct';
    String finalLookupBarcode = normalizedBarcode;

    // 2. If not found and a UPC-A candidate exists, search for that.
    if (item == null && upcCandidate.isNotEmpty) {
      item = await _firestoreService.getItem(upcCandidate);
      if (item != null) {
        lookupStep = 'upc-a candidate';
        finalLookupBarcode = upcCandidate;
      }
    }

    if (item != null) {
      final batches = await _firestoreService.getBatches(item.barcode);
      return _LookupResult(
        data: PharmacyItemWithBatches(item: item, batches: batches),
        lookupBarcode: finalLookupBarcode,
        lookupStep: lookupStep,
      );
    }

    return _LookupResult(
      data: null,
      lookupBarcode: upcCandidate.isNotEmpty ? upcCandidate : normalizedBarcode,
      lookupStep: 'not found',
    );
  }

  bool _isValidBarcodeValue(String value) {
    if (value.isEmpty || value.length > 128) return false;
    // Allow a wider range of characters for manual entry and less common barcodes
    if (!RegExp(r'^[\x00-\x7F]+$').hasMatch(value)) return false;

    final digitsOnly = RegExp(r'^\d+$').hasMatch(value);
    if (digitsOnly) {
      // For purely numeric barcodes, enforce a minimum length.
      // Standard formats like EAN-8, UPC-A, EAN-13 are common.
      return value.length >= 8;
    }

    // For alphanumeric, allow more flexibility but require a minimum length.
    return RegExp(r'^[A-Za-z0-9._\-\/()\s\x1D]+$').hasMatch(value) &&
        value.length >= 4;
  }

  Future<void> _safeStopCamera({bool updateDebug = true}) async {
    try {
      await _controller.stop();
      if (mounted && updateDebug) {
        setState(() {
          _debugCameraStarted = 'camera started: no';
          _debugScannerState = 'scanner paused/stopped: stopped';
        });
      }
    } catch (error) {
      debugPrint('Camera stop failed: $error');
      if (mounted && updateDebug) {
        setState(() {
          _debugScannerState = 'scanner paused/stopped: stop failed';
          _debugErrorMessage = 'error message: $error';
        });
      }
    }
  }

  Future<void> _startCamera() async {
    if (!mounted || _isStartingCamera || _isProcessing || _pausedByLifecycle) {
      return;
    }

    setState(() {
      _cameraFailed = false;
      _isStartingCamera = true;
      _statusMessage = 'Starting camera...';
      _cameraHelpMessage = null;
      _debugCameraStarted = 'camera started: starting';
      _debugScannerState = 'scanner paused/stopped: starting';
      _debugErrorMessage = 'error message: -';
    });

    await _safeStopCamera();

    try {
      await _controller.start(cameraDirection: CameraFacing.back);
      if (!mounted) return;
      await optimizeActiveCameraStream();
      if (!mounted) return;

      final hasCamera = (_controller.value.availableCameras ?? 1) > 0;
      if (!hasCamera) {
        _showCameraProblem(
          const CameraAccessResult(
            CameraAccessStatus.noCameraFound,
            'no camera found',
          ),
        );
        return;
      }

      debugPrint('camera started');
      setState(() {
        _cameraFailed = false;
        _isStartingCamera = false;
        _statusMessage = 'Hold barcode inside box';
        _cameraHelpMessage = null;
        _debugCameraStarted = 'camera started: yes';
        _debugScannerState = 'scanner paused/stopped: running';
        _debugErrorMessage = 'error message: -';
      });
    } on MobileScannerException catch (error) {
      if (!mounted) return;
      _showCameraProblem(_scannerErrorToAccessResult(error));
    } catch (error) {
      if (!mounted) return;
      _showCameraProblem(
        CameraAccessResult(
          CameraAccessStatus.cameraFailed,
          'permission granted but camera failed',
          '$error',
        ),
      );
    }
  }

  Future<void> _retryCamera() => _startCamera();

  Barcode? _firstValidBarcode(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      if (!_supportedFormats.contains(barcode.format)) continue;
      final raw = barcode.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;
      final scan = _ScannedBarcode.fromRaw(raw);
      if (_isValidBarcodeValue(scan.lookupBarcode)) return barcode;
    }
    return null;
  }

  void _showCameraProblem(CameraAccessResult result) {
    debugPrint(
      result.details == null
          ? result.debugMessage
          : '${result.debugMessage}: ${result.details}',
    );
    setState(() {
      _cameraFailed = true;
      _isStartingCamera = false;
      _statusMessage = _messageForCameraStatus(result.status);
      _cameraHelpMessage = _helpForCameraStatus(result.status);
      _debugCameraStarted = 'camera started: no';
      _debugScannerState = 'scanner paused/stopped: stopped';
      _debugErrorMessage = result.details == null
          ? 'error message: ${result.debugMessage}'
          : 'error message: ${result.debugMessage}: ${result.details}';
    });
  }

  CameraAccessResult _scannerErrorToAccessResult(MobileScannerException error) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return CameraAccessResult(
          CameraAccessStatus.permissionDenied,
          'permission denied',
          error.errorDetails?.message,
        );
      case MobileScannerErrorCode.unsupported:
        return CameraAccessResult(
          CameraAccessStatus.unsupportedBrowser,
          'unsupported browser',
          error.errorDetails?.message,
        );
      case MobileScannerErrorCode.controllerAlreadyInitialized:
      case MobileScannerErrorCode.controllerInitializing:
      case MobileScannerErrorCode.controllerUninitialized:
      case MobileScannerErrorCode.controllerDisposed:
      case MobileScannerErrorCode.controllerNotAttached:
      case MobileScannerErrorCode.genericError:
        final details = error.errorDetails?.message ?? error.toString();
        if (details.contains('NotFoundError') ||
            details.contains('NotSupportedError')) {
          return CameraAccessResult(
            CameraAccessStatus.noCameraFound,
            'no camera found',
            details,
          );
        }
        return CameraAccessResult(
          CameraAccessStatus.cameraFailed,
          'permission granted but camera failed',
          details,
        );
    }
  }

  String _messageForCameraStatus(CameraAccessStatus status) {
    switch (status) {
      case CameraAccessStatus.permissionDenied:
        return 'Camera permission denied';
      case CameraAccessStatus.noCameraFound:
        return 'No camera found';
      case CameraAccessStatus.unsupportedBrowser:
        return 'Unsupported browser';
      case CameraAccessStatus.cameraFailed:
        return 'Camera failed to start';
      case CameraAccessStatus.granted:
        return 'Hold barcode inside box';
    }
  }

  String _helpForCameraStatus(CameraAccessStatus status) {
    switch (status) {
      case CameraAccessStatus.permissionDenied:
        return 'Allow camera access in Safari settings, then retry.';
      case CameraAccessStatus.noCameraFound:
        return 'No available camera was reported by this device.';
      case CameraAccessStatus.unsupportedBrowser:
        return 'Use Safari on HTTPS, or enter the barcode manually.';
      case CameraAccessStatus.cameraFailed:
        return 'Camera permission was granted, but Safari could not start the camera.';
      case CameraAccessStatus.granted:
        return '';
    }
  }

  Future<void> _enterManually() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter Barcode'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.text,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Barcode / Product code'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Search'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      final barcode = _normalizeBarcode(result);
      if (!_isValidBarcodeValue(barcode)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid barcode value.')),
        );
        return;
      }
      await _handleBarcode(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Barcode'),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              final torchState = state.torchState;
              final enabled =
                  torchState == TorchState.on || torchState == TorchState.off;
              return IconButton(
                icon: Icon(
                  torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                ),
                onPressed: enabled ? _controller.toggleTorch : null,
                tooltip: 'Flashlight',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.keyboard),
            onPressed: _enterManually,
            tooltip: 'Enter manually',
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            placeholderBuilder: (_) => const ColoredBox(
              color: Colors.black,
              child: Center(
                child: Text('Scanning...',
                    style: TextStyle(color: Colors.white70)),
              ),
            ),
            errorBuilder: (_, __) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_cameraFailed) {
                  _showCameraProblem(_scannerErrorToAccessResult(__));
                }
              });
              return const ColoredBox(color: Colors.black);
            },
            onDetect: (capture) {
              if (_isProcessing) return;
              final supportedBarcode = _firstValidBarcode(capture);
              final raw = supportedBarcode?.rawValue;
              if (raw != null && raw.trim().isNotEmpty) {
                _handleBarcode(raw, format: supportedBarcode?.format);
              }
            },
          ),
          if (!_cameraFailed) _ScanOverlay(),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _ScannerDebugPanel(
              isVisible: true, // Set to true to always show debug info
              lines: [
                _debugCameraStarted,
                _debugBarcodeDetected,
                _debugRawBarcode,
                _debugBarcodeFormat,
                _debugNormalizedBarcode,
                _debugLookupResult,
                _debugScannerState,
                _debugErrorMessage,
              ],
            ),
          ),
          if (_cameraFailed)
            _CameraError(
              title: _statusMessage,
              message: _cameraHelpMessage ??
                  'Enter the barcode manually to continue.',
              onRetry: _retryCamera,
              onManualEntry: _enterManually,
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.transparent
                  ],
                ),
              ),
              child: Column(
                children: [
                  if (_isProcessing)
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Barcode found',
                            style:
                                TextStyle(color: Colors.white, fontSize: 16)),
                      ],
                    )
                  else if (!_cameraFailed)
                    Column(
                      children: [
                        Text(
                          _statusMessage,
                          style: TextStyle(
                            color: _cameraFailed
                                ? AppTheme.expiring7Days
                                : Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Scan a barcode to add a batch or create medicine',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  if (!_cameraFailed) const SizedBox(height: 12),
                  if (_cameraFailed) ...[
                    OutlinedButton.icon(
                      onPressed: _retryCamera,
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: const Text('Retry Camera',
                          style: TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white54)),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _enterManually,
                      icon: const Icon(Icons.keyboard),
                      label: const Text('Enter Barcode Manually'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerDebugPanel extends StatelessWidget {
  final List<String> lines;
  final bool isVisible;

  const _ScannerDebugPanel({required this.lines, this.isVisible = false});

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.68),
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              height: 1.25,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: lines
                  .map(
                    (line) => Text(
                      line,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCardSheet extends StatefulWidget {
  final PharmacyItemWithBatches initialData;
  final _Gs1Data? initialGs1;
  final bool openAddBatchOnLoad;

  const _ProductCardSheet({
    required this.initialData,
    required this.initialGs1,
    required this.openAddBatchOnLoad,
  });

  @override
  State<_ProductCardSheet> createState() => _ProductCardSheetState();
}

class _ProductCardSheetState extends State<_ProductCardSheet> {
  final _firestoreService = FirestoreService();
  late PharmacyItemWithBatches _data = widget.initialData;
  bool _loading = false;
  bool _openedInitialBatch = false;

  @override
  void initState() {
    super.initState();
    if (widget.openAddBatchOnLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_openedInitialBatch) {
          _openedInitialBatch = true;
          _addBatch();
        }
      });
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final data = await _firestoreService.getItemWithBatches(_data.item.barcode);
    if (!mounted) return;
    setState(() {
      if (data != null) _data = data;
      _loading = false;
    });
  }

  Future<void> _addBatch() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReceivingBatchSheet(
        item: _data.item,
        gs1: widget.initialGs1,
      ),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _sell() async {
    final sold = await showDialog<bool>(
      context: context,
      builder: (_) => _QuickSaleDialog(data: _data),
    );
    if (sold == true) await _refresh();
  }

  Future<void> _viewDetails() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UpdateMedicineScreen(barcode: _data.item.barcode),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final item = _data.item;
    final nearest = _data.nextExpiringBatch;
    final activeCount = _data.activeBatches.where((b) => b.hasStock).length;

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.medication, color: AppTheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.displayName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                if (_loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _ProductInfoRow(label: 'Medicine Name', value: item.medicineName),
            _ProductInfoRow(label: 'Generic Name', value: item.genericName),
            _ProductInfoRow(label: 'Strength', value: item.strength),
            _ProductInfoRow(label: 'Package Size', value: item.packageSize),
            _ProductInfoRow(label: 'Dosage Form', value: item.dosageForm),
            _ProductInfoRow(label: 'Manufacturer', value: item.manufacturer),
            _ProductInfoRow(
              label: 'Current Stock',
              value: '${_data.totalQuantity}',
            ),
            _ProductInfoRow(
              label: 'Active Batch Count',
              value: '$activeCount',
            ),
            _ProductInfoRow(
              label: 'Nearest Expiry',
              value: nearest == null
                  ? '-'
                  : nearest.isExpiryMissing
                      ? 'Expiry Missing'
                      : DateFormat('dd MMM yyyy').format(nearest.expiryDate),
            ),
            _ProductInfoRow(
              label: 'Low Stock Status',
              value: _data.isLowStock ? 'Low Stock' : 'OK',
              valueColor: _data.isLowStock ? AppTheme.expiring7Days : null,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _addBatch,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Batch'),
                ),
                ElevatedButton.icon(
                  onPressed: _sell,
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('Sell'),
                ),
                OutlinedButton.icon(
                  onPressed: _viewDetails,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('View Details'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ProductInfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '-' : value,
              style: TextStyle(
                color: valueColor ?? AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceivingBatchSheet extends StatefulWidget {
  final PharmacyItem item;
  final _Gs1Data? gs1;

  const _ReceivingBatchSheet({required this.item, required this.gs1});

  @override
  State<_ReceivingBatchSheet> createState() => _ReceivingBatchSheetState();
}

class _ReceivingBatchSheetState extends State<_ReceivingBatchSheet> {
  final _firestoreService = FirestoreService();
  final _formKey = GlobalKey<FormState>();
  final _batchNoCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController(text: '0');
  final _purchasePriceCtrl = TextEditingController(text: '0.00');
  final _salePriceCtrl = TextEditingController(text: '0.00');
  final _supplierCtrl = TextEditingController();
  final _invoiceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _expiryDate;
  DateTime? _manufactureDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final gs1 = widget.gs1;
    if (gs1 != null) {
      _batchNoCtrl.text = gs1.lot;
      _expiryDate = gs1.expiryDate;
      _manufactureDate = gs1.manufactureDate;
    }
  }

  @override
  void dispose() {
    _batchNoCtrl.dispose();
    _quantityCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _salePriceCtrl.dispose();
    _supplierCtrl.dispose();
    _invoiceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _expiryDate == null) {
      if (_expiryDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expiry Date is required')),
        );
      }
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final batch = Batch(
        batchId: '',
        barcode: widget.item.barcode,
        batchNo: _batchNoCtrl.text.trim(),
        expiryDate: _expiryDate!,
        quantity: int.tryParse(_quantityCtrl.text.trim()) ?? 0,
        purchasePrice: double.tryParse(_purchasePriceCtrl.text.trim()) ?? 0,
        salePrice: double.tryParse(_salePriceCtrl.text.trim()) ?? 0,
        supplier: _supplierCtrl.text.trim(),
        purchaseDate: now,
        status: BatchStatus.active,
        createdAt: now,
        updatedAt: now,
        receivedAt: now,
        manufactureDate: _manufactureDate,
        invoiceNumber: _invoiceCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
      );
      await _firestoreService.receiveBatch(widget.item.barcode, batch);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: AppTheme.expired,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            controller: scrollCtrl,
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            children: [
              Text(
                'Add Batch',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _ScannerTextField(
                label: 'LOT / Batch Number',
                controller: _batchNoCtrl,
                icon: Icons.tag,
                requiredField: true,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month),
                title: const Text('Expiry Date'),
                subtitle: Text(_expiryDate == null
                    ? 'Required'
                    : DateFormat('dd MMM yyyy').format(_expiryDate!)),
                trailing: const Icon(Icons.edit),
                onTap: _pickExpiry,
              ),
              const SizedBox(height: 12),
              _ScannerTextField(
                label: 'Quantity',
                controller: _quantityCtrl,
                icon: Icons.numbers,
                keyboardType: TextInputType.number,
                requiredField: true,
                validator: (value) =>
                    (int.tryParse(value?.trim() ?? '') ?? 0) <= 0
                        ? 'Required'
                        : null,
              ),
              const SizedBox(height: 12),
              _ScannerTextField(
                label: 'Purchase Price',
                controller: _purchasePriceCtrl,
                icon: Icons.attach_money,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                requiredField: true,
              ),
              const SizedBox(height: 12),
              _ScannerTextField(
                label: 'Sale Price',
                controller: _salePriceCtrl,
                icon: Icons.sell,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                requiredField: true,
              ),
              const SizedBox(height: 12),
              _ScannerTextField(
                label: 'Supplier',
                controller: _supplierCtrl,
                icon: Icons.business,
              ),
              const SizedBox(height: 12),
              _ScannerTextField(
                label: 'Invoice Number',
                controller: _invoiceCtrl,
                icon: Icons.receipt_long,
              ),
              const SizedBox(height: 12),
              _ScannerTextField(
                label: 'Notes',
                controller: _notesCtrl,
                icon: Icons.notes,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_saving ? 'Saving...' : 'Save Batch'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool requiredField;
  final String? Function(String?)? validator;

  const _ScannerTextField({
    required this.label,
    required this.controller,
    required this.icon,
    this.keyboardType,
    this.requiredField = false,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
      validator: validator ??
          (requiredField
              ? (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null
              : null),
    );
  }
}

class _QuickSaleDialog extends StatefulWidget {
  final PharmacyItemWithBatches data;

  const _QuickSaleDialog({required this.data});

  @override
  State<_QuickSaleDialog> createState() => _QuickSaleDialogState();
}

class _QuickSaleDialogState extends State<_QuickSaleDialog> {
  final _firestoreService = FirestoreService();
  final _quantityCtrl = TextEditingController(text: '1');
  bool _saving = false;

  @override
  void dispose() {
    _quantityCtrl.dispose();
    super.dispose();
  }

  Future<void> _sell() async {
    final quantity = int.tryParse(_quantityCtrl.text.trim()) ?? 0;
    if (quantity <= 0) return;
    setState(() => _saving = true);
    try {
      await _firestoreService.recordSale(
        barcode: widget.data.item.barcode,
        quantitySold: quantity,
        paymentMethod: 'Cash',
      );
      if (!mounted) return;
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: AppTheme.expired,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saleBatch =
        widget.data.activeBatches.where((b) => b.hasStock).firstOrNull;
    return AlertDialog(
      title: const Text('Quick Sale'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.data.item.displayName,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Current Stock: ${widget.data.totalQuantity}'),
          Text(
              'Sale Price: \$${(saleBatch?.salePrice ?? 0).toStringAsFixed(2)}'),
          const SizedBox(height: 12),
          TextField(
            controller: _quantityCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Quantity',
              prefixIcon: Icon(Icons.numbers),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _sell,
          icon: const Icon(Icons.point_of_sale),
          label: Text(_saving ? 'Selling...' : 'Sell'),
        ),
      ],
    );
  }
}

class _LookupResult {
  final PharmacyItemWithBatches? data;
  final String lookupBarcode;
  final String lookupStep;

  const _LookupResult({
    required this.data,
    required this.lookupBarcode,
    required this.lookupStep,
  });
}

class _ScannedBarcode {
  final String lookupBarcode;
  final _Gs1Data? gs1;

  const _ScannedBarcode({required this.lookupBarcode, required this.gs1});

  factory _ScannedBarcode.fromRaw(String raw) {
    final gs1 = _Gs1Data.parse(raw);
    final normalized = FirestoreService.normalizeBarcode(raw);
    final gtin = FirestoreService.normalizeBarcode(gs1?.gtin ?? '');
    return _ScannedBarcode(
      lookupBarcode: gtin.isNotEmpty ? gtin : normalized,
      gs1: gs1,
    );
  }
}

class _Gs1Data {
  final String gtin;
  final String lot;
  final DateTime? manufactureDate;
  final DateTime? expiryDate;

  const _Gs1Data({
    required this.gtin,
    required this.lot,
    required this.manufactureDate,
    required this.expiryDate,
  });

  static _Gs1Data? parse(String value) {
    final fields = <String, String>{};
    final text = value.replaceAll(String.fromCharCode(29), '|');
    final markedMatches =
        RegExp(r'\((01|10|11|17)\)').allMatches(text).toList();
    for (var i = 0; i < markedMatches.length; i++) {
      final match = markedMatches[i];
      final ai = match.group(1)!;
      final start = match.end;
      final end = i + 1 < markedMatches.length
          ? markedMatches[i + 1].start
          : text.length;
      fields[ai] = text.substring(start, end).replaceAll('|', '').trim();
    }

    if (fields.isEmpty) {
      final compact = text.replaceAll(RegExp(r'\s+'), '');
      final gtinIndex = compact.indexOf('01');
      if (gtinIndex >= 0 && compact.length >= gtinIndex + 16) {
        fields['01'] = compact.substring(gtinIndex + 2, gtinIndex + 16);
      }
      final mfgIndex = compact.indexOf('11');
      if (mfgIndex >= 0 && compact.length >= mfgIndex + 8) {
        fields['11'] = compact.substring(mfgIndex + 2, mfgIndex + 8);
      }
      final expIndex = compact.indexOf('17');
      if (expIndex >= 0 && compact.length >= expIndex + 8) {
        fields['17'] = compact.substring(expIndex + 2, expIndex + 8);
      }
      final lotIndex = compact.indexOf('10');
      if (lotIndex >= 0 && compact.length > lotIndex + 2) {
        var end = compact.length;
        for (final ai in ['11', '17']) {
          final aiIndex = compact.indexOf(ai, lotIndex + 2);
          if (aiIndex > lotIndex && aiIndex < end) end = aiIndex;
        }
        fields['10'] = compact.substring(lotIndex + 2, end);
      }
    }

    final gtin =
        RegExp(r'\d{14}').firstMatch(fields['01'] ?? '')?.group(0) ?? '';
    final lot = (fields['10'] ?? '').trim();
    final manufactureDate = _parseGs1Date(fields['11'] ?? '');
    final expiryDate = _parseGs1Date(fields['17'] ?? '');
    if (gtin.isEmpty &&
        lot.isEmpty &&
        manufactureDate == null &&
        expiryDate == null) {
      return null;
    }
    return _Gs1Data(
      gtin: gtin,
      lot: lot,
      manufactureDate: manufactureDate,
      expiryDate: expiryDate,
    );
  }

  static DateTime? _parseGs1Date(String value) {
    final digits = RegExp(r'\d{6}').firstMatch(value)?.group(0);
    if (digits == null) return null;
    final year = 2000 + int.parse(digits.substring(0, 2));
    final month = int.parse(digits.substring(2, 4));
    final dayText = digits.substring(4, 6);
    final day = dayText == '00' ? 1 : int.parse(dayText);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }
}

class _CameraError extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onManualEntry;
  const _CameraError({
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onManualEntry,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white70, size: 42),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text('Retry Camera',
                        style: TextStyle(color: Colors.white)),
                  ),
                  OutlinedButton.icon(
                    onPressed: onManualEntry,
                    icon: const Icon(Icons.keyboard, color: Colors.white),
                    label: const Text('Enter Manually',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      final frameWidth = (size.width * 0.86).clamp(280.0, 520.0);
      final frameHeight = (frameWidth * 0.72).clamp(210.0, 360.0);
      final top = ((size.height - frameHeight) * 0.32).clamp(88.0, 260.0);
      final left = (size.width - frameWidth) / 2;

      return Stack(
        children: [
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.28),
              BlendMode.srcOut,
            ),
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Positioned(
                  top: top,
                  left: left,
                  child: Container(
                    width: frameWidth,
                    height: frameHeight,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: top,
            left: left,
            child: _CornerFrame(frameWidth, frameHeight),
          ),
          Positioned(
            top: top + frameHeight + 10,
            left: 24,
            right: 24,
            child: const Text(
              'Move closer or farther until the barcode looks sharp',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      );
    });
  }
}

class _CornerFrame extends StatelessWidget {
  final double width;
  final double height;

  const _CornerFrame(this.width, this.height);

  @override
  Widget build(BuildContext context) {
    const color = AppTheme.primaryLight;
    const thickness = 3.0;
    const length = 24.0;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            child: Column(
              children: [
                Container(width: length, height: thickness, color: color),
                Container(width: thickness, height: length, color: color),
              ],
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(width: length, height: thickness, color: color),
                Container(width: thickness, height: length, color: color),
              ],
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: Column(
              children: [
                Container(width: thickness, height: length, color: color),
                Container(width: length, height: thickness, color: color),
              ],
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(width: thickness, height: length, color: color),
                Container(width: length, height: thickness, color: color),
              ],
            ),
          ),
          const _ScanLine(),
        ],
      ),
    );
  }
}

class _ScanLine extends StatefulWidget {
  const _ScanLine();

  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final travel = (constraints.maxHeight - 12).clamp(0.0, double.infinity);
        return AnimatedBuilder(
          animation: _animation,
          builder: (_, __) => Positioned(
            top: _animation.value * travel,
            left: 8,
            right: 8,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    AppTheme.primaryLight.withValues(alpha: 0.9),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
