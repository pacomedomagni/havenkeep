import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/homes_provider.dart';
import '../../core/providers/items_provider.dart';
import '../../core/router/router.dart';

/// Home detail / edit screen.
///
/// Allows editing home name, type, address, move-in date.
class HomeDetailScreen extends ConsumerStatefulWidget {
  final String homeId;

  const HomeDetailScreen({super.key, required this.homeId});

  @override
  ConsumerState<HomeDetailScreen> createState() => _HomeDetailScreenState();
}

class _HomeDetailScreenState extends ConsumerState<HomeDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _cityController;
  late TextEditingController _stateController;
  late TextEditingController _zipController;
  HomeType _homeType = HomeType.house;
  DateTime? _moveInDate;
  bool _isDirty = false;
  bool _isSaving = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _addressController = TextEditingController();
    _cityController = TextEditingController();
    _stateController = TextEditingController();
    _zipController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    super.dispose();
  }

  void _initFromHome(Home home) {
    if (_isInitialized) return;
    _isInitialized = true;
    _nameController.text = home.name;
    _addressController.text = home.address ?? '';
    _cityController.text = home.city ?? '';
    _stateController.text = home.state ?? '';
    _zipController.text = home.zip ?? '';
    _homeType = home.homeType;
    _moveInDate = home.moveInDate;
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  Future<void> _pickMoveInDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _moveInDate ?? DateTime.now(),
      firstDate: DateTime(1950),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: HavenColors.primary,
              surface: HavenColors.elevated,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _moveInDate = picked);
      _markDirty();
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final homes = ref.read(homesProvider).value ?? [];
      final home = homes.firstWhere((h) => h.id == widget.homeId);

      final updated = home.copyWith(
        name: _nameController.text.trim(),
        address: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        clearAddress: _addressController.text.trim().isEmpty,
        city: _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        clearCity: _cityController.text.trim().isEmpty,
        state: _stateController.text.trim().isEmpty
            ? null
            : _stateController.text.trim(),
        clearState: _stateController.text.trim().isEmpty,
        zip: _zipController.text.trim().isEmpty
            ? null
            : _zipController.text.trim(),
        clearZip: _zipController.text.trim().isEmpty,
        homeType: _homeType,
        moveInDate: _moveInDate,
        clearMoveInDate: _moveInDate == null,
        updatedAt: DateTime.now(),
      );

      await ref.read(homesProvider.notifier).updateHome(updated);

      if (mounted) {
        setState(() {
          _isSaving = false;
          _isDirty = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Home updated')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _delete() async {
    final homes = ref.read(homesProvider).value ?? [];
    if (homes.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete your only home')),
      );
      return;
    }

    final confirmed = await showHavenConfirmDialog(
      context,
      title: 'Delete home?',
      body:
          'All items in this home will be permanently deleted. This cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );

    if (confirmed && mounted) {
      await ref.read(homesProvider.notifier).deleteHome(widget.homeId);
      if (mounted) {
        context.go(AppRoutes.dashboard);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final homesAsync = ref.watch(homesProvider);
    final itemsAsync = ref.watch(itemsProvider);
    final homes = homesAsync.value ?? [];
    final home = homes.where((h) => h.id == widget.homeId).firstOrNull;

    if (home != null) _initFromHome(home);

    final itemCount = itemsAsync.value?.length ?? 0;

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Edit Home'),
        actions: [
          if (homes.length > 1)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: HavenColors.expired),
              onPressed: _delete,
            ),
        ],
      ),
      body: home == null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              onChanged: _markDirty,
              child: ListView(
                padding: const EdgeInsets.all(HavenSpacing.md),
                children: [
                  // Home name
                  TextFormField(
                    controller: _nameController,
                    style: const TextStyle(color: HavenColors.textPrimary),
                    decoration: const InputDecoration(labelText: 'Home Name *'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: HavenSpacing.md),

                  // Home type
                  DropdownButtonFormField<HomeType>(
                    value: _homeType,
                    dropdownColor: HavenColors.elevated,
                    style: const TextStyle(color: HavenColors.textPrimary),
                    decoration: const InputDecoration(labelText: 'Home Type'),
                    items: HomeType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type.displayLabel),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _homeType = v);
                        _markDirty();
                      }
                    },
                  ),
                  const SizedBox(height: HavenSpacing.md),

                  // Address
                  TextFormField(
                    controller: _addressController,
                    style: const TextStyle(color: HavenColors.textPrimary),
                    decoration: const InputDecoration(labelText: 'Address'),
                  ),
                  const SizedBox(height: HavenSpacing.md),

                  // City
                  TextFormField(
                    controller: _cityController,
                    style: const TextStyle(color: HavenColors.textPrimary),
                    decoration: const InputDecoration(labelText: 'City'),
                  ),
                  const SizedBox(height: HavenSpacing.md),

                  // State + ZIP row
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _stateController,
                          style:
                              const TextStyle(color: HavenColors.textPrimary),
                          decoration:
                              const InputDecoration(labelText: 'State'),
                        ),
                      ),
                      const SizedBox(width: HavenSpacing.md),
                      Expanded(
                        child: TextFormField(
                          controller: _zipController,
                          style:
                              const TextStyle(color: HavenColors.textPrimary),
                          decoration: const InputDecoration(labelText: 'ZIP'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: HavenSpacing.md),

                  // Move-in date
                  GestureDetector(
                    onTap: _pickMoveInDate,
                    child: InputDecorator(
                      decoration:
                          const InputDecoration(labelText: 'Move-in Date'),
                      child: Text(
                        _moveInDate != null
                            ? DateFormat.yMMMd().format(_moveInDate!)
                            : 'Not set',
                        style: TextStyle(
                          color: _moveInDate != null
                              ? HavenColors.textPrimary
                              : HavenColors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: HavenSpacing.lg),

                  // Item count info
                  Container(
                    padding: const EdgeInsets.all(HavenSpacing.md),
                    decoration: BoxDecoration(
                      color: HavenColors.surface,
                      borderRadius: BorderRadius.circular(HavenRadius.card),
                      border: Border.all(color: HavenColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.inventory_2_outlined,
                          color: HavenColors.textSecondary,
                        ),
                        const SizedBox(width: HavenSpacing.md),
                        Text(
                          '$itemCount items tracked in this home',
                          style: const TextStyle(
                            fontSize: 14,
                            color: HavenColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: HavenSpacing.xl),

                  // Save button
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isDirty && !_isSaving ? _save : null,
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Save Changes'),
                    ),
                  ),
                  const SizedBox(height: HavenSpacing.lg),
                ],
              ),
            ),
    );
  }
}
