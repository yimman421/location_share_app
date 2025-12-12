class LocationModel {
  final String userId;
  final double lat;
  final double lng;
  final double? speed;
  final double? heading;
  final double? accuracy;
  final DateTime timestamp;

  // 추가
  final String? nickname;
  final String? avatarUrl;
  final String? group;
  final int? stayDuration; // 초 단위(옵션)

  LocationModel({
    required this.userId,
    required this.lat,
    required this.lng,
    this.speed,
    this.heading,
    this.accuracy,
    required this.timestamp,
    this.nickname,
    this.avatarUrl,
    this.group,
    this.stayDuration
  });

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'lat': lat,
        'lng': lng,
        'speed': speed,
        'heading': heading,
        'accuracy': accuracy,
        'timestamp': timestamp.toIso8601String(),
        if (nickname != null) 'nickname': nickname,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (group != null) 'group': group,
        if (stayDuration != null) 'stayDuration': stayDuration,
      };

  factory LocationModel.fromMap(Map<String, dynamic> map) => LocationModel(
        userId: map['userId'],
        lat: (map['lat'] as num).toDouble(),
        lng: (map['lng'] as num).toDouble(),
        speed: (map['speed'] as num?)?.toDouble(),
        heading: (map['heading'] as num?)?.toDouble(),
        accuracy: (map['accuracy'] as num?)?.toDouble(),
        timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
        nickname: map['nickname']?.toString(),
        avatarUrl: map['avatarUrl']?.toString(),
        group: map['group']?.toString(),
        stayDuration: map['stayDuration'] is int ? map['stayDuration'] as int : int.tryParse(map['stayDuration']?.toString() ?? ''),
      );

  // ✅ 추가
  LocationModel copyWith({
    double? lat,
    double? lng,
    double? accuracy,
    double? speed,
    double? heading,
    DateTime? timestamp,
    String? nickname,
    String? avatarUrl,
    String? group,
    int? stayDuration
  }) {
    return LocationModel(
      userId: userId,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      accuracy: accuracy ?? this.accuracy,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      timestamp: timestamp ?? this.timestamp,
      nickname: nickname ?? this.nickname,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      group: group ?? this.group,
      stayDuration: stayDuration ?? this.stayDuration,
    );
  }
}
