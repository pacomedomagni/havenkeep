import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'auth_provider.dart';
import '../services/image_upload_service.dart';

/// The current user's profile photo URL.
///
/// Watches the current user and returns their avatar URL if set.
final profilePhotoUrlProvider = Provider<String?>((ref) {
  final user = ref.watch(currentUserProvider).value;
  return user?.avatarUrl;
});

/// Pick and upload a new profile photo.
///
/// Returns the uploaded URL on success, null on cancellation.
Future<String?> pickAndUploadProfilePhoto(Ref ref) async {
  final picker = ImagePicker();
  final image = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 512,
    maxHeight: 512,
    imageQuality: 80,
  );

  if (image == null) return null;

  final user = ref.read(currentUserProvider).value;
  if (user == null) return null;

  final imageFile = File(image.path);

  // Upload via the Express API
  final url = await ref.read(imageUploadServiceProvider).uploadProfilePhoto(
        userId: user.id,
        imageFile: imageFile,
      );

  // Update user profile with the new avatar URL
  await ref.read(currentUserProvider.notifier).updateProfile(avatarUrl: url);

  return url;
}
