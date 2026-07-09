import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

Future<String?> showScanner(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
  );
}

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen>
    with WidgetsBindingObserver {
  static const _formats = <BarcodeFormat>[
    BarcodeFormat.qrCode,
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
  ];

  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 300,
    facing: CameraFacing.back,
    formats: _formats,
    torchEnabled: false,
  );

  bool _isStarting = false;
  bool _isProcessingScan = false;
  bool _permissionDenied = false;
  bool _permissionPermanentlyDenied = false;
  bool _noCamera = false;
  String? _errorMessage;
  String? _lastValue;
  DateTime? _lastScanAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestAndStart());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;

    switch (state) {
      case AppLifecycleState.resumed:
        if (!_isProcessingScan) _startCamera();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _controller.stop();
    }
  }

  Future<void> _requestAndStart() async {
    setState(() {
      _permissionDenied = false;
      _permissionPermanentlyDenied = false;
      _noCamera = false;
      _errorMessage = null;
    });

    final status = await Permission.camera.request();
    if (!mounted) return;

    if (status.isGranted || status.isLimited) {
      await _startCamera();
      return;
    }

    setState(() {
      _permissionDenied = status.isDenied || status.isRestricted;
      _permissionPermanentlyDenied = status.isPermanentlyDenied;
      _errorMessage = status.isPermanentlyDenied
          ? 'Camera permission is permanently denied.'
          : 'Camera permission is required to scan barcodes.';
    });
  }

  Future<void> _startCamera() async {
    if (!mounted || _isStarting || _isProcessingScan) return;

    setState(() {
      _isStarting = true;
      _noCamera = false;
      _errorMessage = null;
    });

    try {
      await _controller.start(cameraDirection: CameraFacing.back);
      if (!mounted) return;

      final availableCameras = _controller.value.availableCameras;
      if (availableCameras != null && availableCameras == 0) {
        await _controller.stop();
        if (!mounted) return;
        setState(() {
          _noCamera = true;
          _errorMessage = 'No camera was found on this device.';
        });
      }
    } on MobileScannerException catch (error) {
      if (!mounted) return;
      _handleScannerException(error);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Camera failed to start.';
      });
    } finally {
      if (mounted) {
        setState(() => _isStarting = false);
      }
    }
  }

  void _handleScannerException(MobileScannerException error) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        _permissionDenied = true;
        _errorMessage = 'Camera permission was denied.';
      case MobileScannerErrorCode.unsupported:
        _noCamera = true;
        _errorMessage = 'Barcode scanning is not supported on this device.';
      case MobileScannerErrorCode.controllerAlreadyInitialized:
      case MobileScannerErrorCode.controllerInitializing:
        _errorMessage = null;
      case MobileScannerErrorCode.controllerUninitialized:
      case MobileScannerErrorCode.controllerDisposed:
      case MobileScannerErrorCode.controllerNotAttached:
      case MobileScannerErrorCode.genericError:
        _errorMessage = 'Camera failed to initialize.';
    }
    setState(() {});
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_isProcessingScan) return;

    final barcode = _firstSupportedBarcode(capture);
    final rawValue = barcode?.rawValue?.trim();
    if (rawValue == null || rawValue.isEmpty) return;

    final now = DateTime.now();
    if (_lastValue == rawValue &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!) < const Duration(milliseconds: 900)) {
      return;
    }

    _lastValue = rawValue;
    _lastScanAt = now;
    _isProcessingScan = true;

    await _controller.stop();
    if (!mounted) return;

    Navigator.of(context).pop(rawValue);
  }

  Barcode? _firstSupportedBarcode(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      if (!_formats.contains(barcode.format)) continue;
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;
      return barcode;
    }

    if (capture.barcodes.isNotEmpty && mounted) {
      setState(() => _errorMessage = 'Unsupported barcode format.');
    }
    return null;
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  Future<void> _switchCamera() async {
    try {
      await _controller.switchCamera();
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Unable to switch camera.');
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Torch is not available.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan barcode'),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              final torchAvailable = state.torchState == TorchState.on ||
                  state.torchState == TorchState.off;
              return IconButton(
                tooltip: 'Toggle torch',
                onPressed: torchAvailable ? _toggleTorch : null,
                icon: Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                ),
              );
            },
          ),
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              final canSwitch = (state.availableCameras ?? 0) > 1;
              return IconButton(
                tooltip: 'Switch camera',
                onPressed: canSwitch ? _switchCamera : null,
                icon: const Icon(Icons.cameraswitch),
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleDetect,
            errorBuilder: (context, error) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _handleScannerException(error);
              });
              return const ColoredBox(color: Colors.black);
            },
          ),
          const _ScannerOverlay(),
          if (_isStarting)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          if (_permissionDenied ||
              _permissionPermanentlyDenied ||
              _noCamera ||
              _errorMessage != null)
            _ScannerStatusPanel(
              title: _statusTitle,
              message: _errorMessage ?? 'Camera is not available.',
              primaryLabel:
                  _permissionPermanentlyDenied ? 'Open settings' : 'Try again',
              primaryIcon:
                  _permissionPermanentlyDenied ? Icons.settings : Icons.refresh,
              onPrimary: _permissionPermanentlyDenied
                  ? _openSettings
                  : _requestAndStart,
              secondaryLabel: 'Close',
              onSecondary: () => Navigator.of(context).maybePop(),
            ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32 + MediaQuery.of(context).padding.bottom,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Align the barcode inside the box',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _statusTitle {
    if (_permissionPermanentlyDenied) return 'Permission blocked';
    if (_permissionDenied) return 'Camera permission needed';
    if (_noCamera) return 'No camera found';
    return 'Scanner unavailable';
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final boxWidth = (size.width * 0.78).clamp(260.0, 420.0);
        final boxHeight = boxWidth * 0.62;
        final rect = Rect.fromCenter(
          center: Offset(size.width / 2, size.height * 0.44),
          width: boxWidth,
          height: boxHeight,
        );

        return IgnorePointer(
          child: CustomPaint(
            painter: _ScannerOverlayPainter(rect),
            size: size,
          ),
        );
      },
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final Rect scanRect;

  const _ScannerOverlayPainter(this.scanRect);

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.48)
      ..style = PaintingStyle.fill;

    final clearPaint = Paint()..blendMode = BlendMode.clear;
    final layerBounds = Offset.zero & size;
    canvas.saveLayer(layerBounds, Paint());
    canvas.drawRect(layerBounds, overlayPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(scanRect, const Radius.circular(18)),
      clearPaint,
    );
    canvas.restore();

    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 34.0;
    final r = scanRect;

    canvas.drawLine(
        r.topLeft, r.topLeft + const Offset(cornerLength, 0), borderPaint);
    canvas.drawLine(
        r.topLeft, r.topLeft + const Offset(0, cornerLength), borderPaint);

    canvas.drawLine(
        r.topRight, r.topRight - const Offset(cornerLength, 0), borderPaint);
    canvas.drawLine(
        r.topRight, r.topRight + const Offset(0, cornerLength), borderPaint);

    canvas.drawLine(r.bottomLeft, r.bottomLeft + const Offset(cornerLength, 0),
        borderPaint);
    canvas.drawLine(r.bottomLeft, r.bottomLeft - const Offset(0, cornerLength),
        borderPaint);

    canvas.drawLine(r.bottomRight,
        r.bottomRight - const Offset(cornerLength, 0), borderPaint);
    canvas.drawLine(r.bottomRight,
        r.bottomRight - const Offset(0, cornerLength), borderPaint);
  }

  @override
  bool shouldRepaint(_ScannerOverlayPainter oldDelegate) {
    return oldDelegate.scanRect != scanRect;
  }
}

class _ScannerStatusPanel extends StatelessWidget {
  final String title;
  final String message;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  const _ScannerStatusPanel({
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(primaryIcon, size: 40),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: onPrimary,
                      icon: Icon(primaryIcon),
                      label: Text(primaryLabel),
                    ),
                    TextButton(
                      onPressed: onSecondary,
                      child: Text(secondaryLabel),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
