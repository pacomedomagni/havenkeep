import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/homes_provider.dart';
import '../../core/providers/items_provider.dart';
import '../../core/router/router.dart';
import '../../core/services/barcode_lookup_service.dart';
import '../../core/utils/error_handler.dart';
import '../../core/utils/haven_haptics.dart';
import '../../core/widgets/haven_image.dart';
import '../../core/widgets/haven_loader.dart';

/// Barcode scan screen — uses the camera to detect barcodes,
/// looks up product info, and creates a new item.
class BarcodeScanScreen extends ConsumerStatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  ConsumerState<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends ConsumerState<BarcodeScanScreen>
    with WidgetsBindingObserver {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _isLookingUp = false;
  bool _isSaving = false;
  bool _isProcessing = false;
  BarcodeLookupResult? _lookupResult;
  String? _error;
  bool _hasDetected = false;
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ch05 barcode lifecycle: pause the camera while backgrounded so we
    // don't keep the sensor warm (battery + privacy LED) and can resume
    // cleanly on return.
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _scannerController.stop();
      case AppLifecycleState.resumed:
        if (_lookupResult == null) {
          _scannerController.start();
        }
      case AppLifecycleState.detached:
        // No-op; dispose() will clean up.
        break;
    }
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    // Immediately prevent re-entry before any async work
    if (_hasDetected || _isProcessing || _isLookingUp) return;
    _hasDetected = true;
    _isProcessing = true;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) {
      _hasDetected = false;
      _isProcessing = false;
      return;
    }

    final barcode = barcodes.first.rawValue;
    if (barcode == null || barcode.isEmpty) {
      _hasDetected = false;
      _isProcessing = false;
      return;
    }

    setState(() {
      _isLookingUp = true;
    });

    _lookupProduct(barcode);
  }

  Future<void> _lookupProduct(String barcode) async {
    try {
      final result = await ref
          .read(barcodeLookupServiceProvider)
          .lookupBarcode(barcode);

      if (mounted) {
        setState(() {
          _lookupResult = result;
          _isLookingUp = false;
        });
      }
    } catch (e) {
      if (mounted) {
        // 403 means the user needs a premium plan to use barcode scanning.
        // Ch05-F003: when the user returns from the paywall (still
        // un-premium), reset the scanner so they can try again immediately
        // instead of having to pop and re-enter.
        if (e is ApiForbiddenException) {
          await context.push(AppRoutes.premium);
          if (mounted) {
            setState(() {
              _hasDetected = false;
              _isProcessing = false;
              _isLookingUp = false;
              _lookupResult = null;
              _error = null;
            });
          }
          return;
        }
        // Ch05-F002: barcode lookup failure is the user's "miss" moment;
        // the strongest haptic we have draws their eye to the inline
        // error/manual-entry prompt before they keep waving the camera
        // around. `warn` maps to `vibrate` on Android and a sharp pulse
        // on iOS — heavier than the celebratory `confirm` tap.
        HavenHaptics.warn();
        setState(() {
          _isLookingUp = false;
          _error = ErrorHandler.getUserMessage(e);
          _lookupResult = BarcodeLookupResult(barcode: barcode);
        });
      }
    }
  }

  Future<void> _saveItem() async {
    if (_lookupResult == null) return;
    setState(() => _isSaving = true);

    try {
      final user = ref.read(currentUserProvider).value;
      final home = ref.read(currentHomeProvider);
      // Ch05-F004: surface why the save bailed instead of returning to a
      // disabled-button limbo with no feedback.
      if (user == null || home == null) {
        if (mounted) {
          showHavenSnackBar(
            context,
            message:
                'Sign in and pick a home before adding items.',
            isError: true,
          );
        }
        return;
      }

      ItemCategory category = ItemCategory.other;
      if (_lookupResult!.category != null) {
        try {
          category = ItemCategory.fromJson(_lookupResult!.category!);
        } catch (_) {}
      }

      // Local-midnight anchor (Ch05-F005).
      final now = DateTime.now();
      final purchaseDate = DateTime(now.year, now.month, now.day);
      const warrantyMonths = 12;
      final item = Item(
        id: '',
        homeId: home.id,
        userId: user.id,
        name: _lookupResult!.productName ?? category.displayLabel,
        brand: _lookupResult!.brand,
        barcode: _lookupResult!.barcode,
        category: category,
        purchaseDate: purchaseDate,
        warrantyMonths: warrantyMonths,
        // The server overwrites this from `purchase_date + warranty_months`,
        // but the constructor now requires a non-null value (Ch08-Item-D010).
        warrantyEndDate:
            Item.computeWarrantyEndDate(purchaseDate, warrantyMonths),
        addedVia: ItemAddedVia.barcode_scan,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final (newItem, _) = await ref.read(itemsProvider.notifier).addItem(item);

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

  void _resetScan() {
    setState(() {
      _hasDetected = false;
      _isProcessing = false;
      _lookupResult = null;
      _isLookingUp = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text(
          'Scan Barcode',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          // Ch05-F003: torch toggle for low-light cabinets/stockrooms.
          if (_lookupResult == null)
            IconButton(
              tooltip: _torchOn ? 'Turn off flash' : 'Turn on flash',
              icon: Icon(
                _torchOn ? Icons.flash_on : Icons.flash_off,
                semanticLabel: _torchOn ? 'Flash on' : 'Flash off',
              ),
              onPressed: () async {
                await _scannerController.toggleTorch();
                if (mounted) {
                  setState(() => _torchOn = !_torchOn);
                }
              },
            ),
        ],
      ),
      body: _lookupResult != null ? _buildResultView() : _buildScannerView(),
    );
  }

  Widget _buildScannerView() {
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: _onBarcodeDetected,
        ),

        // Overlay with scan guide
        Center(
          child: Container(
            width: 280,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: HavenColors.primary, width: 2),
              borderRadius: BorderRadius.circular(HavenRadius.button),
            ),
          ),
        ),

        // Instruction text
        Positioned(
          bottom: 100,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: HavenSpacing.md,
                vertical: HavenSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: HavenColors.background.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(HavenRadius.chip),
              ),
              child: Text(
                _isLookingUp
                    ? 'Looking up product...'
                    : 'Position barcode within the frame',
                style: const TextStyle(
                  color: HavenColors.textPrimary,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),

        if (_isLookingUp)
          const Center(
            child: HavenLoader(color: HavenColors.primary),
          ),
      ],
    );
  }

  Widget _buildResultView() {
    final result = _lookupResult!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(HavenSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product image
          if (result.imageUrl != null)
            Center(
              child: Container(
                width: 120,
                height: 120,
                margin: const EdgeInsets.only(bottom: HavenSpacing.md),
                decoration: BoxDecoration(
                  color: HavenColors.surface,
                  borderRadius: BorderRadius.circular(HavenRadius.card),
                ),
                child: HavenImage(
                  url: result.imageUrl,
                  fit: BoxFit.contain,
                  borderRadius: HavenRadius.card,
                  errorFallback: const Center(
                    child: Icon(
                      Icons.image_not_supported,
                      color: HavenColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),

          // Product info card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(HavenSpacing.md),
            decoration: BoxDecoration(
              color: HavenColors.elevated,
              borderRadius: BorderRadius.circular(HavenRadius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.hasData) ...[
                  Text(
                    result.productName ?? 'Unknown Product',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: HavenColors.textPrimary,
                    ),
                  ),
                  if (result.brand != null) ...[
                    const SizedBox(height: HavenSpacing.xs),
                    Text(
                      result.brand!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: HavenColors.textSecondary,
                      ),
                    ),
                  ],
                  if (result.description != null) ...[
                    const SizedBox(height: HavenSpacing.sm),
                    Text(
                      result.description!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: HavenColors.textTertiary,
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ] else ...[
                  const Text(
                    'Product Not Found',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: HavenColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: HavenSpacing.xs),
                  const Text(
                    'We couldn\'t find this product in our database. You can still add it manually.',
                    style: TextStyle(
                      fontSize: 13,
                      color: HavenColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],

                const SizedBox(height: HavenSpacing.sm),

                // Barcode info
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HavenSpacing.sm,
                    vertical: HavenSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: HavenColors.surface,
                    borderRadius: BorderRadius.circular(HavenRadius.chip),
                  ),
                  child: Text(
                    'Barcode: ${result.barcode}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: HavenColors.textTertiary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: HavenSpacing.sm),
            Text(
              _error!,
              style: const TextStyle(
                color: HavenColors.expired,
                fontSize: 13,
              ),
            ),
          ],

          const SizedBox(height: HavenSpacing.lg),

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
                  : Text(result.hasData ? 'Add This Item' : 'Add Manually'),
            ),
          ),
          const SizedBox(height: HavenSpacing.sm),

          if (result.hasData)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: () => context.push(AppRoutes.manualEntry),
                style: OutlinedButton.styleFrom(
                  foregroundColor: HavenColors.secondary,
                  side: const BorderSide(color: HavenColors.border),
                ),
                child: const Text('Not what I expected — enter manually'),
              ),
            ),

          const SizedBox(height: HavenSpacing.sm),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: TextButton.icon(
              onPressed: _resetScan,
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: const Text('Scan Another'),
              style: TextButton.styleFrom(
                foregroundColor: HavenColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
