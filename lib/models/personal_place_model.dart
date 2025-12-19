// lib/models/personal_place_model.dart

class PersonalPlaceModel {
  final String id; // Document ID
  final String userId;
  final String placeName;
  final String category;
  final String address;
  final double lat;
  final double lng;
  final List<String> groups;
  final String? memo;
  final DateTime createdAt;

  PersonalPlaceModel({
    required this.id,
    required this.userId,
    required this.placeName,
    required this.category,
    required this.address,
    required this.lat,
    required this.lng,
    required this.groups,
    this.memo,
    required this.createdAt,
  });

  factory PersonalPlaceModel.fromMap(String id, Map<String, dynamic> data) {
    return PersonalPlaceModel(
      id: id,
      userId: data['userId'] ?? '',
      placeName: data['placeName'] ?? '',
      category: data['category'] ?? '기타',
      address: data['address'] ?? '',
      lat: (data['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (data['lng'] as num?)?.toDouble() ?? 0.0,
      groups: List<String>.from(data['groups'] ?? []),
      memo: data['memo'],
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'placeName': placeName,
      'category': category,
      'address': address,
      'lat': lat,
      'lng': lng,
      'groups': groups,
      'memo': memo,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  PersonalPlaceModel copyWith({
    String? id,
    String? userId,
    String? placeName,
    String? category,
    String? address,
    double? lat,
    double? lng,
    List<String>? groups,
    String? memo,
    DateTime? createdAt,
  }) {
    return PersonalPlaceModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      placeName: placeName ?? this.placeName,
      category: category ?? this.category,
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      groups: groups ?? this.groups,
      memo: memo ?? this.memo,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

// 카테고리 상수
class PlaceCategory {
  static const String home = '집';
  static const String work = '회사';
  static const String frequent = '자주 가는 곳';
  static const String restaurant = '맛집';
  static const String other = '기타';
  
  static const List<String> predefined = [
    home,
    work,
    frequent,
    restaurant,
    other,
  ];
  
  static bool isPredefined(String category) {
    return predefined.contains(category);
  }
}