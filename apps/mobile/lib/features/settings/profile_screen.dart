import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/items_provider.dart';
import '../../core/providers/profile_photo_provider.dart';
import '../../core/services/image_upload_service.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/error_state_widget.dart';

/// Profile editing screen.
///
/// Allows editing user name, shows email (read-only), plan info.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  bool _isDirty = false;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _initFromUser(AppUser user) {
    if (_isInitialized) return;
    _isInitialized = true;
    _nameController.text = user.fullName ?? '';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      await ref.read(currentUserProvider.notifier).updateProfile(
            fullName: _nameController.text.trim(),
          );

      if (mounted) {
        setState(() {
          _isSaving = false;
          _isDirty = false;
        });
        showHavenSnackBar(context, message: 'Profile updated', isSuccess: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        showHavenSnackBar(context, message: ErrorHandler.getUserMessage(e), isError: true);
      }
    }
  }

  Future<void> _changePhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (image == null || !mounted) return;

    final imageFile = File(image.path);

    // Show preview and confirm
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HavenColors.elevated,
        title: const Text('Update profile photo?'),
        content: ClipRRect(
          borderRadius: BorderRadius.circular(HavenRadius.card),
          child: Image.file(imageFile, width: 200, height: 200, fit: BoxFit.cover),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Use Photo'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isUploadingPhoto = true);

    try {
      final user = ref.read(currentUserProvider).value;
      if (user == null) return;

      final url = await ref.read(imageUploadServiceProvider).uploadProfilePhoto(
            userId: user.id,
            imageFile: imageFile,
          );
      await ref.read(currentUserProvider.notifier).updateProfile(avatarUrl: url);

      if (mounted) {
        showHavenSnackBar(context, message: 'Photo updated', isSuccess: true);
      }
    } catch (e) {
      if (mounted) {
        showHavenSnackBar(context, message: ErrorHandler.getUserMessage(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final itemCountAsync = ref.watch(activeItemCountProvider);

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: HavenColors.background,
        appBar: AppBar(
          title: const Text('Profile'),
        ),
        body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const Center(
              child: Text(
                'Not signed in',
                style: TextStyle(color: HavenColors.textSecondary),
              ),
            );
          }

          _initFromUser(user);

          final isPremium = user.plan == UserPlan.premium;
          final itemCount = itemCountAsync.value ?? 0;

          return Form(
            key: _formKey,
            onChanged: () {
              if (!_isDirty) setState(() => _isDirty = true);
            },
            child: ListView(
              padding: const EdgeInsets.all(HavenSpacing.md),
              children: [
                // Avatar
                Center(
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: HavenColors.primary,
                            backgroundImage: user.avatarUrl != null
                                ? NetworkImage(user.avatarUrl!)
                                : null,
                            child: user.avatarUrl == null
                                ? Text(
                                    (user.fullName != null && user.fullName!.isNotEmpty ? user.fullName![0] : '?').toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 32,
                                      color: HavenColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                          if (_isUploadingPhoto)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: HavenSpacing.sm),
                      TextButton(
                        onPressed: _isUploadingPhoto ? null : () => _changePhoto(),
                        child: Text(
                          _isUploadingPhoto ? 'Uploading...' : 'Change Photo',
                          style: TextStyle(
                            color: _isUploadingPhoto
                                ? HavenColors.textTertiary
                                : HavenColors.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: HavenSpacing.lg),

                // Full name
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: HavenColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Name is required' : null,
                ),
                const SizedBox(height: HavenSpacing.md),

                // Email (read-only)
                TextFormField(
                  initialValue: user.email,
                  readOnly: true,
                  style: const TextStyle(color: HavenColors.textTertiary),
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    helperText: 'Email changes require re-authentication',
                  ),
                ),
                const SizedBox(height: HavenSpacing.lg),

                // Plan info
                Container(
                  padding: const EdgeInsets.all(HavenSpacing.md),
                  decoration: BoxDecoration(
                    color: HavenColors.surface,
                    borderRadius: BorderRadius.circular(HavenRadius.card),
                    border: Border.all(color: HavenColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: HavenSpacing.sm,
                          vertical: HavenSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: isPremium
                              ? HavenColors.active.withValues(alpha: 0.2)
                              : HavenColors.expiring.withValues(alpha: 0.2),
                          borderRadius:
                              BorderRadius.circular(HavenRadius.chip),
                        ),
                        child: Text(
                          isPremium ? 'Premium' : 'Free Plan',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isPremium
                                ? HavenColors.active
                                : HavenColors.expiring,
                          ),
                        ),
                      ),
                      const SizedBox(width: HavenSpacing.md),
                      Text(
                        isPremium
                            ? 'Unlimited items'
                            : '$itemCount/$kFreePlanItemLimit items',
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
                              color: HavenColors.textPrimary,
                            ),
                          )
                        : const Text('Save Changes'),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => Padding(
          padding: const EdgeInsets.all(HavenSpacing.md),
          child: Column(
            children: const [
              SizedBox(height: HavenSpacing.lg),
              SkeletonBox(width: 80, height: 80),
              SizedBox(height: HavenSpacing.lg),
              SkeletonLine(height: 48),
              SizedBox(height: HavenSpacing.md),
              SkeletonLine(height: 48),
              SizedBox(height: HavenSpacing.lg),
              SkeletonLine(height: 60),
            ],
          ),
        ),
        error: (_, __) => ErrorStateWidget(
          message: 'Could not load profile',
          onRetry: () => ref.invalidate(currentUserProvider),
        ),
      ),
    ),
    );
  }

  Future<void> _confirmDiscard() async {
    final confirmed = await showHavenConfirmDialog(
      context,
      title: 'Discard changes?',
      body: 'You have unsaved changes that will be lost.',
      confirmLabel: 'Discard',
      isDestructive: true,
    );
    if (confirmed && mounted) {
      Navigator.of(context).pop();
    }
  }
}
