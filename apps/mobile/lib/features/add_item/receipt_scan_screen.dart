import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/homes_provider.dart';
import '../../core/providers/items_provider.dart';
import '../../core/services/receipt_scanner_service.dart';
import '../../core/utils/error_handler.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/utils/price_parser.dart';
import '../../core/widgets/haven_loader.dart';

/// Receipt scan screen — capture a receipt photo, extract data via OCR,
/// review/edit extracted fields, then save as a new item.
class ReceiptScanScreen extends ConsumerStatefulWidget {
  const ReceiptScanScreen({super.key});

  @override
  ConsumerState<ReceiptScanScreen> createState() => _ReceiptScanScreenState();
}

class _ReceiptScanScreenState extends ConsumerState<ReceiptScanScreen> {
  final _picker = ImagePicker();
  File? _imageFile;
  // Ch05-F008: hash of the most recent image we've already OCR'd. We
  // refuse to re-OCR an identical capture (rapid double-tap on Try Again
  // or a re-pick that returned the same temp file) so we don't burn
  // quota for an answer we know won't change.
  String? _lastScannedHash;
  ReceiptScanResult? _scanResult;
  bool _isScanning = false;
  bool _isSaving = false;
  String? _error;

  // Editable fields from scan
  final _brandController = TextEditingController();
  final _priceController = TextEditingController();
  DateTime _purchaseDate = DateTime.now();
  ItemCategory _category = ItemCategory.other;

  @override
  void initState() {
    super.initState();
    // Auto-open camera
    _captureReceipt();
  }

  @override
  void dispose() {
    _brandController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _captureReceipt() async {
    try {
      // Ch05-F007: 90 is the OCR sweet spot — receipts have small fonts
      // and at 80 the JPEG ringing eats characters along the totals line.
      // 1600px max keeps memory low; we trust the OCR to compensate for
      // perspective and skew on its own.
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );

      if (image == null) {
        if (mounted) context.pop();
        return;
      }

      if (!mounted) return;
      setState(() {
        _imageFile = File(image.path);
        _isScanning = true;
        _error = null;
      });

      await _processReceipt();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorHandler.getUserMessage(e);
        _isScanning = false;
      });
    }
  }

  Future<void> _processReceipt() async {
    if (_imageFile == null) return;

    // Ch05-F008: skip OCR if the bytes haven't changed since the last
    // scan. We compare SHA-256 of the file contents — `picker.pickImage`
    // sometimes hands back the same temp file on a quick re-pick, and
    // we don't want to charge the user (or our API budget) twice for
    // the same image.
    try {
      final bytes = await _imageFile!.readAsBytes();
      final hash = sha256.convert(bytes).toString();
      if (hash == _lastScannedHash && _scanResult != null) {
        if (mounted) {
          setState(() => _isScanning = false);
        }
        return;
      }
      _lastScannedHash = hash;
    } catch (_) {
      // If hashing fails (rare; permissions/file gone), let the OCR call
      // surface the real failure instead of swallowing it here.
    }

    try {
      final result = await ref
          .read(receiptScannerServiceProvider)
          .scanReceipt(_imageFile!);

      if (mounted) {
        setState(() {
          _scanResult = result;
          _isScanning = false;

          // Pre-fill fields
          _brandController.text = result.merchant ?? '';
          _priceController.text =
              result.total != null ? result.total!.toStringAsFixed(2) : '';
          if (result.date != null) {
            try {
              _purchaseDate = DateTime.parse(result.date!);
            } catch (_) {
              _purchaseDate = DateTime.now();
            }
          }

          if (result.categoryGuess != null) {
            try {
              _category = ItemCategory.fromJson(result.categoryGuess!);
            } catch (_) {
              _category = ItemCategory.other;
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _error = 'Could not read this receipt. You can enter details manually below, or retake the photo with better lighting.';
          // Still allow manual entry
          _scanResult = const ReceiptScanResult();
        });
      }
    }
  }

  Future<void> _saveItem() async {
    setState(() => _isSaving = true);

    try {
      final user = ref.read(currentUserProvider).value;
      final home = ref.read(currentHomeProvider);
      if (user == null || home == null) return;

      // Ch05-F009: use the locale-aware parser everywhere.
      final price = parsePriceInput(_priceController.text);

      // Ch05-F011: prefer "<Brand> <Category>" so the items list doesn't end
      // up with three duplicates literally named "Refrigerator".
      final brand = _brandController.text.trim();
      final itemName = brand.isNotEmpty
          ? '$brand ${_category.displayLabel}'
          : _category.displayLabel;

      // Ch05-F005: anchor purchase date at local midnight.
      final purchaseDateOnly = DateTime(
        _purchaseDate.year,
        _purchaseDate.month,
        _purchaseDate.day,
      );

      const warrantyMonths = 12;
      final item = Item(
        id: '', // DB generates
        homeId: home.id,
        userId: user.id,
        name: itemName,
        brand: brand.isNotEmpty ? brand : null,
        category: _category,
        purchaseDate: purchaseDateOnly,
        price: price,
        warrantyMonths: warrantyMonths,
        // Server overwrites on insert (Ch08-Item-D010); keep the optimistic
        // value in sync with the API formula.
        warrantyEndDate:
            Item.computeWarrantyEndDate(purchaseDateOnly, warrantyMonths),
        addedVia: ItemAddedVia.receipt_scan,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final (newItem, _) =
          await ref.read(itemsProvider.notifier).addItem(item);

      if (mounted) {
        context.go('/add-item/success/${newItem.id}', extra: newItem);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ErrorHandler.getUserMessage(e);
        });
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickPurchaseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(1970),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: HavenColors.primary,
              surface: HavenColors.elevated,
              onSurface: HavenColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        // Ch05-F005: normalise to local midnight so timezone flips
        // don't bump the displayed date.
        _purchaseDate =
            DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text(
          'Scan Receipt',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Scanning state
    if (_isScanning) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HavenLoader(color: HavenColors.primary),
            SizedBox(height: HavenSpacing.md),
            Text(
              'Extracting details...',
              style: TextStyle(
                color: HavenColors.textSecondary,
                fontSize: 16,
              ),
            ),
            SizedBox(height: HavenSpacing.xs),
            Text(
              'This may take a few seconds',
              style: TextStyle(
                color: HavenColors.textTertiary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    // No image yet (camera was cancelled)
    if (_imageFile == null && _scanResult == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.camera_alt_outlined,
              size: 64,
              color: HavenColors.textTertiary,
            ),
            const SizedBox(height: HavenSpacing.md),
            ElevatedButton.icon(
              onPressed: _captureReceipt,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take Photo'),
            ),
          ],
        ),
      );
    }

    // Review extracted data
    return SingleChildScrollView(
      padding: const EdgeInsets.all(HavenSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Success/error banner
          if (_scanResult?.hasData == true)
            Container(
              padding: const EdgeInsets.all(HavenSpacing.md),
              decoration: BoxDecoration(
                color: HavenColors.active.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(HavenRadius.card),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: HavenColors.active, size: 20),
                  SizedBox(width: HavenSpacing.sm),
                  Expanded(
                    child: Text(
                      'Receipt scanned! Review and edit the details below.',
                      style: TextStyle(
                        color: HavenColors.active,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(HavenSpacing.md),
              decoration: BoxDecoration(
                color: HavenColors.expiring.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(HavenRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber, color: HavenColors.expiring, size: 20),
                      const SizedBox(width: HavenSpacing.sm),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: HavenColors.expiring,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: HavenSpacing.sm),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _imageFile = null;
                            _scanResult = null;
                            _error = null;
                            _lastScannedHash = null;
                          });
                          _captureReceipt();
                        },
                        icon: const Icon(Icons.camera_alt, size: 16),
                        label: const Text('Retake'),
                        style: TextButton.styleFrom(
                          foregroundColor: HavenColors.expiring,
                        ),
                      ),
                      const SizedBox(width: HavenSpacing.sm),
                      // Ch05-F008: re-OCR the same image without making the
                      // user re-take the photo.
                      if (_imageFile != null) ...[
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _error = null;
                              _isScanning = true;
                            });
                            _processReceipt();
                          },
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Try Again'),
                          style: TextButton.styleFrom(
                            foregroundColor: HavenColors.primary,
                          ),
                        ),
                        const SizedBox(width: HavenSpacing.sm),
                      ],
                      TextButton.icon(
                        onPressed: () {
                          setState(() => _error = null);
                        },
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Enter Manually'),
                        style: TextButton.styleFrom(
                          foregroundColor: HavenColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: HavenSpacing.lg),

          // Category picker
          const SectionHeader(title: 'Category'),
          const SizedBox(height: HavenSpacing.sm),
          DropdownButtonFormField<ItemCategory>(
            initialValue: _category,
            decoration: const InputDecoration(
              filled: true,
              fillColor: HavenColors.surface,
            ),
            dropdownColor: HavenColors.elevated,
            items: ItemCategory.values
                .map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(c.displayLabel),
                    ))
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => _category = val);
            },
          ),

          const SizedBox(height: HavenSpacing.md),

          // Brand / Store
          const SectionHeader(title: 'Store / Brand'),
          const SizedBox(height: HavenSpacing.sm),
          TextFormField(
            controller: _brandController,
            decoration: const InputDecoration(
              hintText: 'e.g. Home Depot, Samsung',
              filled: true,
              fillColor: HavenColors.surface,
            ),
          ),

          const SizedBox(height: HavenSpacing.md),

          // Price
          const SectionHeader(title: 'Total Price'),
          const SizedBox(height: HavenSpacing.sm),
          TextFormField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              prefixText: '\$ ',
              hintText: '0.00',
              filled: true,
              fillColor: HavenColors.surface,
            ),
          ),

          const SizedBox(height: HavenSpacing.md),

          // Date
          const SectionHeader(title: 'Purchase Date'),
          const SizedBox(height: HavenSpacing.sm),
          InkWell(
            onTap: _pickPurchaseDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                filled: true,
                fillColor: HavenColors.surface,
                suffixIcon: Icon(Icons.calendar_today, size: 18, color: HavenColors.textSecondary),
              ),
              child: Text(
                DateFormat.yMMMd().format(_purchaseDate),
                style: const TextStyle(
                  color: HavenColors.textPrimary,
                  fontSize: 16,
                ),
              ),
            ),
          ),

          const SizedBox(height: HavenSpacing.md),

          // Line items from scan
          if (_scanResult?.items.isNotEmpty == true) ...[
            const SectionHeader(title: 'Line Items'),
            const SizedBox(height: HavenSpacing.sm),
            ...(_scanResult!.items.map((item) => Container(
                  margin: const EdgeInsets.only(bottom: HavenSpacing.xs),
                  padding: const EdgeInsets.all(HavenSpacing.sm),
                  decoration: BoxDecoration(
                    color: HavenColors.surface,
                    borderRadius: BorderRadius.circular(HavenRadius.button),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.description,
                          style: const TextStyle(
                            fontSize: 13,
                            color: HavenColors.textSecondary,
                          ),
                        ),
                      ),
                      if (item.amount != null)
                        Text(
                          Money.format(item.amount),
                          style: const TextStyle(
                            fontSize: 13,
                            color: HavenColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ))),
            const SizedBox(height: HavenSpacing.md),
          ],

          // Action buttons
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveItem,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: HavenLoader(color: HavenColors.textPrimary),
                    )
                  : const Text('Save Item'),
            ),
          ),
          const SizedBox(height: HavenSpacing.sm),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _imageFile = null;
                  _scanResult = null;
                  _error = null;
                  _lastScannedHash = null;
                });
                _captureReceipt();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retake Photo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: HavenColors.secondary,
                side: const BorderSide(color: HavenColors.border),
              ),
            ),
          ),
          const SizedBox(height: HavenSpacing.lg),
        ],
      ),
    );
  }
}
