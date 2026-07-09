// lib/screens/add_medicine_screen.dart

import 'package:flutter/material.dart';
import '../models/pharmacy_item.dart';
import '../services/firestore_service.dart';
import '../utils/app_theme.dart';
import '../widgets/form_field_label.dart';

class AddMedicineScreen extends StatefulWidget {
  final String barcode;
  final bool lockedBarcode;

  const AddMedicineScreen({
    super.key,
    required this.barcode,
    this.lockedBarcode = false,
  });

  @override
  State<AddMedicineScreen> createState() => _AddMedicineScreenState();
}

class _AddMedicineScreenState extends State<AddMedicineScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  bool _saving = false;

  late final TextEditingController _barcodeCtrl;
  final _nameCtrl = TextEditingController();
  final _genericCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _ndcCtrl = TextEditingController();
  final _manufacturerCtrl = TextEditingController();
  final _strengthCtrl = TextEditingController();
  final _packageSizeCtrl = TextEditingController();
  final _minimumStockCtrl = TextEditingController(text: '0');
  final _reorderLevelCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  List<PharmacyItem> _knownItems = [];
  List<String> _manufacturerSuggestions = [];
  List<String> _dosageFormSuggestions = AppDosageForms.list;
  String? _ndcError;
  // Category starts blank on purpose: it must NOT be guessed (e.g. defaulted to
  // "Antibiotics"). It stays blank until the user selects one, or an offline
  // name hint (e.g. Terconazole → Antifungal) suggests one they can override.
  String _category = '';
  bool _categoryTouched = false;
  String _dosageForm = AppDosageForms.list.first;
  bool _dosageFormTouched = false;
  bool _manufacturerTouched = false;

  @override
  void initState() {
    super.initState();
    _barcodeCtrl = TextEditingController(
        text: FirestoreService.normalizeBarcode(widget.barcode));
    _nameCtrl.addListener(_suggestFromName);
    _ndcCtrl.addListener(() {
      if (_ndcError != null) setState(() => _ndcError = null);
    });
    _loadOfflineSuggestions();
  }

  Future<void> _loadOfflineSuggestions() async {
    final items = await _firestoreService.getAllItems();
    final manufacturers = await _firestoreService.getManufacturerSuggestions();
    final dosageForms = await _firestoreService.getDosageFormSuggestions();
    if (!mounted) return;
    setState(() {
      _knownItems = items;
      _manufacturerSuggestions = manufacturers;
      _dosageFormSuggestions = {
        ...AppDosageForms.list,
        ...dosageForms,
      }.toList();
    });
    _suggestFromName();
  }

  /// Offline suggestions only. Uses local rules and already saved medicines;
  /// no external medicine database is queried.
  void _suggestFromName() {
    final text = _nameCtrl.text;
    final categorySuggestion = AppCategories.suggestForName(text);
    final dosageSuggestion = AppDosageForms.suggestForName(text);
    final manufacturerSuggestion = _suggestManufacturerForName(text);

    var changed = false;
    if (!_categoryTouched && categorySuggestion != _category) {
      _category = categorySuggestion;
      changed = true;
    }
    if (!_dosageFormTouched &&
        dosageSuggestion.isNotEmpty &&
        dosageSuggestion != _dosageForm) {
      _dosageForm = dosageSuggestion;
      changed = true;
    }
    if (!_manufacturerTouched &&
        manufacturerSuggestion.isNotEmpty &&
        manufacturerSuggestion != _manufacturerCtrl.text) {
      _manufacturerCtrl.text = manufacturerSuggestion;
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  String _suggestManufacturerForName(String name) {
    final query = name.trim().toLowerCase();
    if (query.length < 3) return '';
    for (final item in _knownItems) {
      final manufacturer = item.manufacturer.trim();
      if (manufacturer.isEmpty) continue;
      final candidates = [
        item.medicineName,
        item.genericName,
        item.brand,
        item.displayName,
      ].map((value) => value.toLowerCase());
      if (candidates.any((value) =>
          value.isNotEmpty &&
          (value.contains(query) || query.contains(value)))) {
        return manufacturer;
      }
    }
    return '';
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_suggestFromName);
    _barcodeCtrl.dispose();
    _nameCtrl.dispose();
    _genericCtrl.dispose();
    _brandCtrl.dispose();
    _ndcCtrl.dispose();
    _manufacturerCtrl.dispose();
    _strengthCtrl.dispose();
    _packageSizeCtrl.dispose();
    _minimumStockCtrl.dispose();
    _reorderLevelCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _ndcError = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final normalizedBarcode =
          FirestoreService.normalizeBarcode(_barcodeCtrl.text);
      final duplicateNdc = await _firestoreService.findItemByNdc(
        _ndcCtrl.text,
        excludingBarcode: normalizedBarcode,
      );
      if (duplicateNdc != null) {
        if (!mounted) return;
        setState(() {
          _ndcError = 'NDC already used by ${duplicateNdc.displayName}';
          _saving = false;
        });
        _formKey.currentState!.validate();
        return;
      }

      final now = DateTime.now();
      final minimumStock = int.tryParse(_minimumStockCtrl.text.trim()) ?? 0;
      final item = PharmacyItem(
        barcode: normalizedBarcode,
        medicineName: _nameCtrl.text.trim(),
        genericName: _genericCtrl.text.trim(),
        brand: _brandCtrl.text.trim(),
        ndc: _ndcCtrl.text.trim(),
        manufacturer: _manufacturerCtrl.text.trim(),
        strength: _strengthCtrl.text.trim(),
        dosageForm: _dosageForm,
        category: _category,
        packageSize: _packageSizeCtrl.text.trim(),
        minimumStockLevel: minimumStock,
        reorderLevel: int.tryParse(_reorderLevelCtrl.text.trim()) ?? 0,
        notes: _notesCtrl.text.trim(),
        createdAt: now,
        updatedAt: now,
      );

      await _firestoreService.saveItem(item);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Medicine details saved'),
            backgroundColor: AppTheme.healthy,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppTheme.expired),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Medicine')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _FirstScanBanner(),
            const _SectionHeader(title: 'Medicine', icon: Icons.medication),
            const SizedBox(height: 12),
            FormFieldLabel(label: 'Barcode'),
            TextFormField(
              controller: _barcodeCtrl,
              readOnly: widget.lockedBarcode,
              decoration:
                  const InputDecoration(prefixIcon: Icon(Icons.qr_code)),
              validator: (value) => value == null ||
                      FirestoreService.normalizeBarcode(value).isEmpty
                  ? 'Required'
                  : null,
            ),
            const SizedBox(height: 12),
            FormFieldLabel(label: 'Medicine Name'),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.local_pharmacy),
                hintText: 'e.g. Amoxicillin',
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            _TwoColumnFields(
              left: _TextFieldBlock(
                  label: 'Generic Name',
                  controller: _genericCtrl,
                  icon: Icons.science),
              right: _TextFieldBlock(
                  label: 'Brand',
                  controller: _brandCtrl,
                  icon: Icons.sell_outlined),
            ),
            const SizedBox(height: 12),
            _TwoColumnFields(
              left: _TextFieldBlock(
                  label: 'NDC',
                  controller: _ndcCtrl,
                  icon: Icons.numbers,
                  validator: (_) => _ndcError),
              right: _AutocompleteTextFieldBlock(
                  label: 'Manufacturer',
                  controller: _manufacturerCtrl,
                  icon: Icons.factory_outlined,
                  suggestions: _manufacturerSuggestions,
                  onChanged: (_) => _manufacturerTouched = true),
            ),
            const SizedBox(height: 12),
            _TwoColumnFields(
              left: _TextFieldBlock(
                  label: 'Strength',
                  controller: _strengthCtrl,
                  icon: Icons.bolt_outlined,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Required'
                      : null),
              right: _TextFieldBlock(
                  label: 'Package Size',
                  controller: _packageSizeCtrl,
                  icon: Icons.inventory_2_outlined,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Required'
                      : null),
            ),
            const SizedBox(height: 12),
            _DropdownBlock(
              label: 'Dosage Form',
              value: _dosageForm,
              values: _dosageFormSuggestions,
              icon: Icons.medication_liquid,
              onChanged: (value) => setState(() {
                _dosageForm = value;
                _dosageFormTouched = true;
              }),
            ),
            const SizedBox(height: 12),
            FormFieldLabel(label: 'Category'),
            DropdownButtonFormField<String>(
              // Keyed on the value so an offline name suggestion is reflected
              // in the field even after the first build.
              key: ValueKey('category-$_category'),
              initialValue: _category.isEmpty ? null : _category,
              decoration:
                  const InputDecoration(prefixIcon: Icon(Icons.category)),
              hint: const Text('Select category (optional)'),
              items: AppCategories.list
                  .map((category) =>
                      DropdownMenuItem(value: category, child: Text(category)))
                  .toList(),
              onChanged: (value) => setState(() {
                _category = value ?? '';
                _categoryTouched = true;
              }),
            ),
            const SizedBox(height: 12),
            FormFieldLabel(label: 'Minimum Stock Level'),
            TextFormField(
              controller: _minimumStockCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.warning_amber),
                hintText: '0 means no low stock alert',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Required';
                final parsed = int.tryParse(text);
                if (parsed == null || parsed < 0) {
                  return 'Enter 0 or a positive whole number';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            FormFieldLabel(label: 'Reorder Level'),
            TextFormField(
              controller: _reorderLevelCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.low_priority),
                hintText: 'Optional',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return null;
                final parsed = int.tryParse(text);
                if (parsed == null || parsed < 0) {
                  return 'Enter 0 or a positive whole number';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            FormFieldLabel(label: 'Notes'),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.notes),
                  hintText: 'Storage, warnings, shelf location'),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: Text(_saving ? 'Saving...' : 'Save Medicine'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _FirstScanBanner extends StatelessWidget {
  const _FirstScanBanner();

  @override
  Widget build(BuildContext context) {
    const color = AppTheme.primary;
    const icon = Icons.edit_note;
    const message =
        'First time scanning this barcode. Enter the medicine details once — '
        'every future scan loads them automatically.';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppTheme.primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary),
        ),
      ],
    );
  }
}

class _TwoColumnFields extends StatelessWidget {
  final Widget left;
  final Widget right;
  const _TwoColumnFields({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }
}

class _TextFieldBlock extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String? Function(String?)? validator;

  const _TextFieldBlock({
    required this.label,
    required this.controller,
    required this.icon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormFieldLabel(label: label),
        TextFormField(
          controller: controller,
          decoration: InputDecoration(prefixIcon: Icon(icon)),
          validator: validator,
        ),
      ],
    );
  }
}

class _AutocompleteTextFieldBlock extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final List<String> suggestions;
  final ValueChanged<String>? onChanged;

  const _AutocompleteTextFieldBlock({
    required this.label,
    required this.controller,
    required this.icon,
    required this.suggestions,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormFieldLabel(label: label),
        Autocomplete<String>(
          initialValue: TextEditingValue(text: controller.text),
          optionsBuilder: (value) {
            final query = value.text.trim().toLowerCase();
            if (query.isEmpty) return suggestions.take(8);
            return suggestions.where(
              (item) => item.toLowerCase().contains(query),
            );
          },
          onSelected: (value) {
            controller.text = value;
            onChanged?.call(value);
          },
          fieldViewBuilder: (context, textController, focusNode, onSubmitted) {
            if (textController.text != controller.text) {
              textController.text = controller.text;
            }
            return TextFormField(
              controller: textController,
              focusNode: focusNode,
              decoration: InputDecoration(prefixIcon: Icon(icon)),
              onChanged: (value) {
                controller.text = value;
                onChanged?.call(value);
              },
            );
          },
        ),
      ],
    );
  }
}

class _DropdownBlock extends StatelessWidget {
  final String label;
  final String value;
  final List<String> values;
  final IconData icon;
  final ValueChanged<String> onChanged;

  const _DropdownBlock({
    required this.label,
    required this.value,
    required this.values,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormFieldLabel(label: label),
        DropdownButtonFormField<String>(
          initialValue: value,
          decoration: InputDecoration(prefixIcon: Icon(icon)),
          items: values
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: (selected) {
            if (selected != null) onChanged(selected);
          },
        ),
      ],
    );
  }
}
