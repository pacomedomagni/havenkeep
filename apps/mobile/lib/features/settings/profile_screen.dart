import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/items_provider.dart';
import '../../core/providers/profile_photo_provider.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated')),
        );
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

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final itemCountAsync = ref.watch(activeItemCountProvider);

    return Scaffold(
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
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: HavenColors.primary,
                        backgroundImage: user.avatarUrl != null
                            ? NetworkImage(user.avatarUrl!)
                            : null,
                        child: user.avatarUrl == null
                            ? Text(
                                (user.fullName ?? '?')[0].toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 32,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: HavenSpacing.sm),
                      TextButton(
                        onPressed: () async {
                          try {
                            await pickAndUploadProfilePhoto(ref);
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Photo upload failed: $e')),
                              );
                            }
                          }
                        },
                        child: const Text(
                          'Change Photo',
                          style: TextStyle(color: HavenColors.secondary),
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
                              ? HavenColors.active.withOpacity(0.2)
                              : HavenColors.expiring.withOpacity(0.2),
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
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save Changes'),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text(
            'Error loading profile',
            style: TextStyle(color: HavenColors.expired),
          ),
        ),
      ),
    );
  }
}
