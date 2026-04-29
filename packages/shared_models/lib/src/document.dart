import 'enums.dart';

/// A document attached to an item (receipt, warranty card, manual, etc.).
class Document {
  final String id;
  final String? itemId;
  final String userId;
  final DocumentType type;
  final String fileUrl;
  final String fileName;

  /// Bytes. Backed by a `BIGINT` on the server (Ch08-Document-D019) so the
  /// client can carry the full PostgreSQL range without overflow.
  final int fileSize;

  final String mimeType;
  final String? thumbnailUrl;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

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
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      id: json['id'] as String? ?? '',
      itemId: json['item_id'] as String?,
      userId: json['user_id'] as String? ?? '',
      type: json['type'] != null
          ? DocumentType.fromJson(json['type'] as String)
          : DocumentType.other,
      fileUrl: json['file_url'] as String? ?? '',
      fileName: json['file_name'] as String? ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
      thumbnailUrl: json['thumbnail_url'] as String?,
      deletedAt: _parseDate(json['deleted_at']),
      // 4.1: server-stamped timestamps fall back instead of crashing.
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
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
      if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// JSON for inserts. Strips id + server-managed timestamps so the server
  /// is never asked to honor a client-supplied audit field
  /// (Ch08-Document-D021).
  Map<String, dynamic> toInsertJson() {
    final json = toJson();
    json.remove('id');
    json.remove('created_at');
    json.remove('updated_at');
    json.remove('deleted_at');
    return json;
  }

  /// Human-readable file size (e.g., "1.2 MB").
  String get fileSizeFormatted {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Whether this document is an image.
  bool get isImage => mimeType.startsWith('image/');

  /// Whether this document is a PDF.
  bool get isPdf => mimeType == 'application/pdf';

  Document copyWith({
    String? id,
    String? itemId,
    bool clearItemId = false,
    String? userId,
    DocumentType? type,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? thumbnailUrl,
    bool clearThumbnailUrl = false,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Document(
      id: id ?? this.id,
      itemId: clearItemId ? null : (itemId ?? this.itemId),
      userId: userId ?? this.userId,
      type: type ?? this.type,
      fileUrl: fileUrl ?? this.fileUrl,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      thumbnailUrl:
          clearThumbnailUrl ? null : (thumbnailUrl ?? this.thumbnailUrl),
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
