import 'enums.dart';

/// A home/property that contains tracked items.
class Home {
  final String id;
  final String userId;
  final String name;
  final String? address;
  final String? city;
  final String? state;
  final String? zip;
  final HomeType homeType;
  final DateTime? moveInDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Home({
    required this.id,
    required this.userId,
    required this.name,
    this.address,
    this.city,
    this.state,
    this.zip,
    this.homeType = HomeType.house,
    this.moveInDate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Home.fromJson(Map<String, dynamic> json) {
    return Home(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      address: json['address'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      zip: json['zip'] as String?,
      homeType: json['home_type'] != null
          ? HomeType.fromJson(json['home_type'] as String)
          : HomeType.house,
      moveInDate: json['move_in_date'] != null
          ? DateTime.parse(json['move_in_date'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'address': address,
      'city': city,
      'state': state,
      'zip': zip,
      'home_type': homeType.toJson(),
      'move_in_date': moveInDate?.toIso8601String().split('T').first,
    };
  }

  /// Full address string for display.
  String get fullAddress {
    final parts = [address, city, state, zip]
        .where((p) => p != null && p.isNotEmpty)
        .toList();
    return parts.join(', ');
  }

  Home copyWith({
    String? id,
    String? userId,
    String? name,
    String? address,
    bool clearAddress = false,
    String? city,
    bool clearCity = false,
    String? state,
    bool clearState = false,
    String? zip,
    bool clearZip = false,
    HomeType? homeType,
    DateTime? moveInDate,
    bool clearMoveInDate = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Home(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      address: clearAddress ? null : (address ?? this.address),
      city: clearCity ? null : (city ?? this.city),
      state: clearState ? null : (state ?? this.state),
      zip: clearZip ? null : (zip ?? this.zip),
      homeType: homeType ?? this.homeType,
      moveInDate: clearMoveInDate ? null : (moveInDate ?? this.moveInDate),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'Home(id: $id, name: $name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Home && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
