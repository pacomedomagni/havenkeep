import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/documents_provider.dart';
import '../../core/utils/error_handler.dart';

/// Maximum file size for document uploads (10 MB).
const _kMaxFileSizeBytes = 10 * 1024 * 1024;

/// Detect MIME type from file name extension.
String _detectMimeType(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.doc')) return 'application/msword';
  if (lower.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

/// Bottom sheet for uploading a document (photo) to an item.
class DocumentUploadSheet extends ConsumerStatefulWidget {
  final String itemId;

  const DocumentUploadSheet({super.key, required this.itemId});

  /// Show the upload sheet.
  static void show(BuildContext context, String itemId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: HavenColors.elevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(HavenRadius.card),
        ),
      ),
      builder: (_) => DocumentUploadSheet(itemId: itemId),
    );
  }

  @override
  ConsumerState<DocumentUploadSheet> createState() =>
      _DocumentUploadSheetState();
}

class _DocumentUploadSheetState extends ConsumerState<DocumentUploadSheet> {
  final _picker = ImagePicker();
  XFile? _selectedImage;
  DocumentType _selectedType = DocumentType.receipt;
  bool _isUploading = false;
  String? _errorMessage;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _selectedImage = image;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = ErrorHandler.getUserMessage(e);
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx'],
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedImage = XFile(result.files.single.path!);
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = ErrorHandler.getUserMessage(e);
      });
    }
  }

  Future<void> _upload() async {
    if (_selectedImage == null) return;

    // Validate file exists and check size
    final file = File(_selectedImage!.path);
    if (!file.existsSync()) {
      setState(() => _errorMessage = 'File no longer exists. Please select again.');
      return;
    }
    final fileSize = file.lengthSync();
    if (fileSize > _kMaxFileSizeBytes) {
      final sizeMb = (fileSize / (1024 * 1024)).toStringAsFixed(1);
      setState(() => _errorMessage = 'File too large ($sizeMb MB). Maximum is 10 MB.');
      return;
    }

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      await uploadDocument(
        ref,
        itemId: widget.itemId,
        filePath: _selectedImage!.path,
        fileName: _selectedImage!.name,
        type: _selectedType,
        mimeType: _detectMimeType(_selectedImage!.name),
      );

      if (mounted) {
        Navigator.of(context).pop();
        showHavenSnackBar(context, message: 'Document uploaded', isSuccess: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _errorMessage = ErrorHandler.getUserMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          HavenSpacing.lg,
          HavenSpacing.sm,
          HavenSpacing.lg,
          MediaQuery.of(context).viewInsets.bottom + HavenSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: HavenColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: HavenSpacing.md),

            // Title
            const Text(
              'Add Document',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: HavenColors.textPrimary,
              ),
            ),
            const SizedBox(height: HavenSpacing.lg),

            // Source options (if no image selected)
            if (_selectedImage == null) ...[
              _SourceOption(
                icon: Icons.camera_alt_outlined,
                label: 'Take Photo',
                onTap: () => _pickImage(ImageSource.camera),
              ),
              const SizedBox(height: HavenSpacing.sm),
              _SourceOption(
                icon: Icons.photo_library_outlined,
                label: 'Choose from Library',
                onTap: () => _pickImage(ImageSource.gallery),
              ),
              const SizedBox(height: HavenSpacing.sm),
              _SourceOption(
                icon: Icons.insert_drive_file_outlined,
                label: 'Choose File',
                subtitle: 'PDF, DOC, DOCX',
                onTap: () => _pickFile(),
              ),
            ] else ...[
              // Image selected — show type picker + upload
              // Preview
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: HavenColors.surface,
                  borderRadius: BorderRadius.circular(HavenRadius.card),
                  border: Border.all(color: HavenColors.border),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(HavenRadius.card),
                      ),
                      child: _selectedImage!.name.toLowerCase().endsWith('.pdf') ||
                              _selectedImage!.name.toLowerCase().endsWith('.doc') ||
                              _selectedImage!.name.toLowerCase().endsWith('.docx')
                          ? Container(
                              width: 120,
                              height: 120,
                              color: HavenColors.surface,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.description,
                                    size: 40,
                                    color: HavenColors.textTertiary,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _selectedImage!.name.split('.').last.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: HavenColors.textTertiary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Image.file(
                              File(_selectedImage!.path),
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 120,
                                height: 120,
                                color: HavenColors.surface,
                                child: const Icon(
                                  Icons.image,
                                  size: 40,
                                  color: HavenColors.textTertiary,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: HavenSpacing.md),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedImage!.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: HavenColors.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: HavenSpacing.xs),
                          GestureDetector(
                            onTap: () => setState(() => _selectedImage = null),
                            child: const Text(
                              'Change',
                              style: TextStyle(
                                fontSize: 13,
                                color: HavenColors.secondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: HavenSpacing.lg),

              // Document type picker
              const Text(
                'DOCUMENT TYPE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: HavenColors.textTertiary,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: HavenSpacing.sm),
              Wrap(
                spacing: HavenSpacing.sm,
                runSpacing: HavenSpacing.sm,
                children: DocumentType.values.map((type) {
                  final isSelected = type == _selectedType;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedType = type),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: HavenSpacing.md,
                        vertical: HavenSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? HavenColors.primary
                            : HavenColors.surface,
                        borderRadius: BorderRadius.circular(HavenRadius.chip),
                        border: Border.all(
                          color: isSelected
                              ? HavenColors.primary
                              : HavenColors.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            DocumentTypeIcon.get(type),
                            size: 16,
                            color: isSelected
                                ? Colors.white
                                : HavenColors.textSecondary,
                          ),
                          const SizedBox(width: HavenSpacing.xs),
                          Text(
                            type.displayLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : HavenColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: HavenSpacing.lg),

              // Error message with retry context
              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(HavenSpacing.sm),
                  decoration: BoxDecoration(
                    color: HavenColors.expired.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(HavenRadius.button),
                    border: Border.all(color: HavenColors.expired.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 18, color: HavenColors.expired),
                      const SizedBox(width: HavenSpacing.sm),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: HavenColors.expired,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: HavenSpacing.sm),
              ],

              // Upload / Retry button
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isUploading ? null : _upload,
                  icon: _isUploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _errorMessage != null ? Icons.refresh : Icons.upload,
                          size: 20,
                        ),
                  label: Text(_errorMessage != null ? 'Retry Upload' : 'Upload'),
                ),
              ),
            ],

            // Error for pick failure
            if (_selectedImage == null && _errorMessage != null) ...[
              const SizedBox(height: HavenSpacing.sm),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: HavenColors.expired,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A tappable source option row.
class _SourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;

  const _SourceOption({
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(HavenSpacing.md),
        decoration: BoxDecoration(
          color: HavenColors.surface,
          borderRadius: BorderRadius.circular(HavenRadius.button),
          border: Border.all(color: HavenColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: HavenColors.textSecondary, size: 24),
            const SizedBox(width: HavenSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: HavenColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: HavenColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: HavenColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
