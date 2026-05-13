import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/homes_provider.dart';
import '../../../core/providers/items_provider.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/widgets/celebration_overlay.dart';
import 'add_item_draft.dart';
import 'wizard_step1_basics.dart';
import 'wizard_step2_warranty.dart';
import 'wizard_step3_details.dart';

/// Multi-step wizard for adding items (replaces long 17-field form).
///
/// Step 1: Basics (name, category, brand) - 30 seconds
/// Step 2: Warranty (purchase date, warranty length) - 20 seconds
/// Step 3: Details (optional: price, store, receipt) - 15 seconds
class AddItemWizardScreen extends ConsumerStatefulWidget {
  const AddItemWizardScreen({super.key});

  @override
  ConsumerState<AddItemWizardScreen> createState() => _AddItemWizardScreenState();
}

class _AddItemWizardScreenState extends ConsumerState<AddItemWizardScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isSaving = false;
  bool _draftLoaded = false;

  // Form data (collected across steps). Re-created in [initState] after we
  // attempt to restore a draft so steps see the same instance from first
  // build.
  WizardData _data = WizardData();

  @override
  void initState() {
    super.initState();
    // Attempt to restore an in-progress draft. We must replace `_data` before
    // any step builds, so we trigger a single rebuild via setState once the
    // load resolves (Ch05-F025: draft autosave + recover).
    AddItemDraft.load().then((restored) {
      if (!mounted) return;
      setState(() {
        if (restored != null) _data = restored;
        _draftLoaded = true;
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _persistDraft() {
    // Fire-and-forget; failures here are non-blocking. The next save will
    // overwrite, and `clear()` runs on a successful save.
    AddItemDraft.save(_data);
  }

  void _nextStep() {
    if (_currentStep < 2) {
      HavenHaptics.tap();
      _persistDraft();
      setState(() {
        _currentStep++;
      });
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      HavenHaptics.tap();
      setState(() {
        _currentStep--;
      });
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Confirm before discarding an in-progress wizard. Skips the prompt when
  /// the user has not entered anything yet (Ch05-F025).
  Future<bool> _confirmDiscard() async {
    if (!AddItemDraft.isDirty(_data)) return true;
    final confirmed = await showHavenConfirmDialog(
      context,
      title: 'Discard draft?',
      body: "You'll lose what you've entered so far.",
      confirmLabel: 'Discard',
      isDestructive: true,
    );
    if (confirmed) {
      await AddItemDraft.clear();
    }
    return confirmed;
  }

  Future<void> _handleClose() async {
    if (await _confirmDiscard() && mounted) {
      context.pop();
    }
  }

  Future<void> _save() async {
    // Ch05-F024: belt-and-braces null guard. If a back-button rewind or
    // automation slipped past step gating, route the user back to the
    // missing step rather than crashing on `!`.
    if (_data.name == null || _data.name!.trim().isEmpty || _data.category == null) {
      _jumpToStep(0);
      _showSnackBar('Add a product name and category to continue.');
      return;
    }
    if (_data.purchaseDate == null || _data.warrantyMonths == null) {
      _jumpToStep(1);
      _showSnackBar('Pick a purchase date and warranty length.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final home = ref.read(currentHomeProvider);
      final user = ref.read(currentUserProvider).value;

      if (home == null || user == null) {
        if (mounted) {
          _showSnackBar('Please sign in and pick a home before saving.');
        }
        return;
      }

      final item = Item(
        id: '',
        homeId: home.id,
        userId: user.id,
        name: _data.name!,
        brand: _data.brand,
        modelNumber: _data.modelNumber,
        serialNumber: _data.serialNumber,
        category: _data.category!,
        room: _data.room,
        purchaseDate: _data.purchaseDate!,
        // Server recomputes server-side; client keeps the formula synced
        // so optimistic UI matches the response (Ch08-Item-D010).
        warrantyEndDate: Item.computeWarrantyEndDate(
          _data.purchaseDate!,
          _data.warrantyMonths!,
        ),
        store: _data.store,
        price: _data.price,
        warrantyMonths: _data.warrantyMonths!,
        warrantyType: _data.warrantyType ?? WarrantyType.manufacturer,
        warrantyProvider: _data.warrantyProvider,
        notes: _data.notes,
        addedVia: ItemAddedVia.manual,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final (newItem, previousCount) = await ref.read(itemsProvider.notifier).addItem(item);

      // Save succeeded — wipe the persisted draft so it can't be re-restored.
      await AddItemDraft.clear();

      if (mounted) {
        // Only celebrate the FIRST item - that's truly special
        if (previousCount == 0) {
          CelebrationOverlay.show(
            context,
            type: CelebrationType.firstItem,
            title: 'Great start',
            subtitle: 'Your first item is protected. Keep adding to build your warranty vault.',
            onDismiss: () {
              context.go('/add-item/success/${newItem.id}', extra: newItem);
            },
          );
        } else {
          // Subtle success feedback for subsequent items.
          showHavenSnackBar(
            context,
            message: '${newItem.name} added',
            isSuccess: true,
            duration: const Duration(seconds: 2),
          );
          context.go('/add-item/success/${newItem.id}', extra: newItem);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(ErrorHandler.getUserMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _jumpToStep(int step) {
    if (step == _currentStep) return;
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_draftLoaded) {
      // Avoid flashing an empty form before a restored draft hydrates the
      // step children. The load resolves in initState within a frame or two.
      return const Scaffold(
        backgroundColor: HavenColors.background,
        body: SizedBox.shrink(),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_isSaving) return;
        final discarded = await _confirmDiscard();
        if (!discarded || !mounted) return;
        if (!context.mounted) return;
        context.pop();
      },
      child: Scaffold(
        backgroundColor: HavenColors.background,
        appBar: AppBar(
          title: const Text('Add Warranty'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _isSaving ? null : _handleClose,
          ),
          actions: [
            if (_currentStep > 0)
              TextButton(
                onPressed: _isSaving ? null : _previousStep,
                child: const Text('Back'),
              ),
          ],
        ),
        body: Column(
          children: [
            // Progress indicator
            _buildProgressIndicator(),

            // Page view
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // Disable swipe
                children: [
                  WizardStep1Basics(
                    data: _data,
                    onNext: _nextStep,
                  ),
                  WizardStep2Warranty(
                    data: _data,
                    onNext: _nextStep,
                  ),
                  WizardStep3Details(
                    data: _data,
                    onSave: _save,
                    isSaving: _isSaving,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Semantics(
      // Ch05-F023: announce step transitions for VoiceOver/TalkBack.
      label: 'Step ${_currentStep + 1} of 3',
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            ...List.generate(3, (index) {
              final isCompleted = index < _currentStep;
              final isCurrent = index == _currentStep;

              final Color color;
              if (isCompleted) {
                color = HavenColors.primary;
              } else if (isCurrent) {
                color = HavenColors.primary.withValues(alpha: 0.5);
              } else {
                color = HavenColors.border;
              }

              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    if (index < 2) const SizedBox(width: 8),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Shared data model for wizard steps.
class WizardData {
  // Step 1: Basics
  String? name;
  ItemCategory? category;
  String? brand;

  // Step 2: Warranty
  DateTime? purchaseDate;
  int? warrantyMonths = 12;
  WarrantyType? warrantyType = WarrantyType.manufacturer;
  String? warrantyProvider;

  // Step 3: Details (optional)
  double? price;
  String? store;
  ItemRoom? room;
  String? modelNumber;
  String? serialNumber;
  String? notes;
}
