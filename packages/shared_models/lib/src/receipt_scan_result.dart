/// Result from receipt OCR scanning.
///
/// Represents the structured data extracted from a receipt image
/// via the `scan-receipt` Edge Function.
class ReceiptScanResult {
  final String? merchant;
  final String? date;
  final double? total;
  final List<ReceiptLineItem> items;
  final String? categoryGuess;

  const ReceiptScanResult({
    this.merchant,
    this.date,
    this.total,
    this.items = const [],
    this.categoryGuess,
  });

  factory ReceiptScanResult.fromJson(Map<String, dynamic> json) {
    return ReceiptScanResult(
      merchant: json['merchant'] as String?,
      date: json['date'] as String?,
      total: json['total'] != null ? (json['total'] as num).toDouble() : null,
      items: (json['items'] as List<dynamic>?)
              ?.map((e) =>
                  ReceiptLineItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      categoryGuess: json['category_guess'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'merchant': merchant,
      'date': date,
      'total': total,
      'items': items.map((e) => e.toJson()).toList(),
      'category_guess': categoryGuess,
    };
  }

  /// Whether the scan returned any useful data.
  bool get hasData =>
      merchant != null || date != null || total != null || items.isNotEmpty;

  @override
  String toString() =>
      'ReceiptScanResult(merchant: $merchant, total: $total, items: ${items.length})';
}

/// A single line item from a scanned receipt.
class ReceiptLineItem {
  final String description;
  final double? amount;

  const ReceiptLineItem({
    required this.description,
    this.amount,
  });

  factory ReceiptLineItem.fromJson(Map<String, dynamic> json) {
    return ReceiptLineItem(
      description: json['description'] as String? ?? '',
      amount: json['amount'] != null ? (json['amount'] as num).toDouble() : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'amount': amount,
    };
  }

  @override
  String toString() => 'ReceiptLineItem($description, \$$amount)';
}
