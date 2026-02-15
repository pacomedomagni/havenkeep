import 'enums.dart';

/// A document attached to an item (receipt, warranty card, manual, etc.).
class Document {
  final String id;
  final String itemId;
  final String userId;
  final DocumentType type;
  final String fileUrl;
  final String fileName;
  final int fileSize;
  final String mimeType;
  final String? thumbnailUrl;
  final DateTime createdAt;

  const Document({
    required this.id,
    required this.itemId,
    required this.userId,
    this.type = DocumentType.other,
    required this.fileUrl,
    required this.fileName,
    this.fileSize = 0,
    this.mimeType = 'application/octet-stream',
    this.thumbnailUrl,
    required this.createdAt,
  });

  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      id: json['id'] as String,
      itemId: json['item_id'] as String,
      userId: json['user_id'] as String,
      type: json['type'] != null
          ? DocumentType.fromJson(json['type'] as String)
          : DocumentType.other,
      fileUrl: json['file_url'] as String,
      fileName: json['file_name'] as String,
      fileSize: json['file_size'] as int? ?? 0,
      mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
      thumbnailUrl: json['thumbnail_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'item_id': itemId,
      'user_id': userId,
      'type': type.toJson(),
      'file_url': fileUrl,
      'file_name': fileName,
      'file_size': fileSize,
      'mime_type': mimeType,
      'thumbnail_url': thumbnailUrl,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    final json = toJson();
    json.remove('id');
    return json;
  }

  /// Human-readable file size (e.g., "1.2 MB").
  String get fileSizeFormatted {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Whether this document is an image.
  bool get isImage => mimeType.startsWith('image/');

  /// Whether this document is a PDF.
  bool get isPdf => mimeType == 'application/pdf';

  Document copyWith({
    String? id,
    String? itemId,
    String? userId,
    DocumentType? type,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? thumbnailUrl,
    bool clearThumbnailUrl = false,
    DateTime? createdAt,
  }) {
    return Document(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      fileUrl: fileUrl ?? this.fileUrl,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      thumbnailUrl:
          clearThumbnailUrl ? null : (thumbnailUrl ?? this.thumbnailUrl),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'Document(id: $id, fileName: $fileName, type: ${type.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Document && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
