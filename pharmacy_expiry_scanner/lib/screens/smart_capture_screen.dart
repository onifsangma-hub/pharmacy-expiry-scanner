import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/smart_capture_result.dart';
import '../services/smart_capture_service.dart';
import '../utils/app_theme.dart';

class SmartCaptureScreen extends StatefulWidget {
  const SmartCaptureScreen({super.key});

  @override
  State<SmartCaptureScreen> createState() => _SmartCaptureScreenState();
}

class _SmartCaptureScreenState extends State<SmartCaptureScreen> {
  final _service = SmartCaptureService();
  final _photos = <SmartCapturePhoto>[];
  final _lotCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _ndcCtrl = TextEditingController();
  final _manufacturerCtrl = TextEditingController();
  Timer? _cleanupTimer;
  bool _reading = false;
  String _status = 'Optional smart capture';

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _clearTemporaryData();
    _lotCtrl.dispose();
    _expiryCtrl.dispose();
    _ndcCtrl.dispose();
    _manufacturerCtrl.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    setState(() {
      _reading = true;
      _status = 'Reading package photo';
    });
    final photo = await _service.capturePhoto('Package');
    if (photo != null) _photos.add(photo);
    final extraction = await _service.analyzePhotos(_photos);
    if (!mounted) return;
    setState(() {
      _lotCtrl.text = extraction.value('lot');
      _expiryCtrl.text = _formatDate(extraction.expiryDate);
      _ndcCtrl.text = extraction.value('ndc');
      _manufacturerCtrl.text = extraction.value('manufacturer');
      _status = extraction.warnings.isEmpty
          ? 'Review extracted fields'
          : extraction.warnings.first;
      _reading = false;
    });
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer(const Duration(seconds: 30), _clearTemporaryData);
  }

  void _save() {
    _clearTemporaryData();
    Navigator.pop(context);
  }

  void _cancel() {
    _clearTemporaryData();
    Navigator.pop(context);
  }

  Future<void> _clearTemporaryData() async {
    _cleanupTimer?.cancel();
    await _service.clearTemporaryData(_photos);
  }

  String _formatDate(DateTime? date) {
    return date == null ? '' : DateFormat('yyyy-MM-dd').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Capture'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _cancel,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _status,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _reading ? null : _capture,
            icon: _reading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.document_scanner),
            label: Text(_reading ? 'Reading...' : 'Capture Package Photo'),
          ),
          const SizedBox(height: 20),
          _ReadonlyField(
            label: 'LOT / Batch',
            controller: _lotCtrl,
            icon: Icons.tag,
          ),
          const SizedBox(height: 12),
          _ReadonlyField(
            label: 'Expiry',
            controller: _expiryCtrl,
            icon: Icons.calendar_month,
          ),
          const SizedBox(height: 12),
          _ReadonlyField(
            label: 'NDC',
            controller: _ndcCtrl,
            icon: Icons.numbers,
          ),
          const SizedBox(height: 12),
          _ReadonlyField(
            label: 'Manufacturer',
            controller: _manufacturerCtrl,
            icon: Icons.factory_outlined,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
          TextButton(
            onPressed: _cancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _ReadonlyField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;

  const _ReadonlyField({
    required this.label,
    required this.controller,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
    );
  }
}
