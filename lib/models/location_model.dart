class LocationModel {
  final String id; // Appwrite 문서 ID ($id)
  final String userId; // users 컬렉션 참조
  final String? groupId; // groups 컬렉션 참조 (nullable)
  final double lat;
  final double lng;
  final double? speed;
  final double? heading;
  final double? accuracy;
  final DateTime timestamp;
  final double? stayDuration; // 체류 시간 (초 단위, nullable)

  LocationModel({
    required this.id,
    required this.userId,
    this.groupId,
    required this.lat,
    required this.lng,
    this.speed,
    this.heading,
    this.accuracy,
    required this.timestamp,
    this.stayDuration,
  });

  /// Map → Model
  factory LocationModel.fromMap(Map<String, dynamic> map) {
    return LocationModel(
      id: map['\$id'] ?? '',
      userId: map['userId'] ?? '',
      groupId: map['groupId'],
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
      speed: (map['speed'] as num?)?.toDouble(),
      heading: (map['heading'] as num?)?.toDouble(),
      accuracy: (map['accuracy'] as num?)?.toDouble(),
      timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
      stayDuration: (map['stayDuration'] as num?)?.toDouble(),
    );
  }

  /// Model → Map (Appwrite 저장용)
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'groupId': groupId,
      'lat': lat,
      'lng': lng,
      'speed': speed,
      'heading': heading,
      'accuracy': accuracy,
      'timestamp': timestamp.toIso8601String(),
      if (stayDuration != null) 'stayDuration': stayDuration,
    };
  }

  /// 복사본 생성 (불변 객체 유지)
  LocationModel copyWith({
    String? id,
    String? userId,
    String? groupId,
    double? lat,
    double? lng,
    double? speed,
    double? heading,
    double? accuracy,
    DateTime? timestamp,
    double? stayDuration,
  }) {
    return LocationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      groupId: groupId ?? this.groupId,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      accuracy: accuracy ?? this.accuracy,
      timestamp: timestamp ?? this.timestamp,
      stayDuration: stayDuration ?? this.stayDuration,
    );
  }
}
