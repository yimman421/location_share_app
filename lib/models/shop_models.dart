class ShopModel {
  final String shopId;
  final String ownerId;
  final String shopName;
  final String category;
  final double lat;
  final double lng;
  final String address;
  final String phone;
  final String description;
  final String bannerMessage;
  final DateTime createdAt;
  
  ShopModel({
    required this.shopId,
    required this.ownerId,
    required this.shopName,
    required this.category,
    required this.lat,
    required this.lng,
    required this.address,
    required this.phone,
    required this.description,
    this.bannerMessage = '',
    required this.createdAt,
  });
  
  factory ShopModel.fromJson(Map<String, dynamic> json, String docId) {
    return ShopModel(
      shopId: docId,
      ownerId: json['ownerId'] ?? '',
      shopName: json['shopName'] ?? '',
      category: json['category'] ?? '',
      lat: (json['lat'] ?? 0.0).toDouble(),
      lng: (json['lng'] ?? 0.0).toDouble(),
      address: json['address'] ?? '',
      phone: json['phone'] ?? '',
      description: json['description'] ?? '',
      bannerMessage: json['bannerMessage'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'ownerId': ownerId,
      'shopName': shopName,
      'category': category,
      'lat': lat,
      'lng': lng,
      'address': address,
      'phone': phone,
      'description': description,
      'bannerMessage': bannerMessage,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class ShopMessageModel {
  final String messageId;
  final String shopId;
  final String shopName;
  final String category;
  final String ownerId;
  final String message;
  final int radius; // 미터
  final int validityHours; // 시간
  final DateTime createdAt;
  final DateTime expiresAt;
  final String messageType;
  final String? targetMeetingId;
  final int reachCount;
  final int acceptCount;
  
  ShopMessageModel({
    required this.messageId,
    required this.shopId,
    required this.shopName,
    required this.category,
    required this.ownerId,
    required this.message,
    required this.radius,
    required this.validityHours,
    required this.createdAt,
    required this.expiresAt,
    this.messageType = 'promotion',
    this.targetMeetingId,
    this.reachCount = 0,
    this.acceptCount = 0,
  });
  
  factory ShopMessageModel.fromJson(Map<String, dynamic> json, String docId) {
    return ShopMessageModel(
      messageId: docId,
      shopId: json['shopId'] ?? '',
      shopName: json['shopName'] ?? '',
      category: json['category'] ?? '',
      ownerId: json['ownerId'] ?? '',
      message: json['message'] ?? '',
      radius: json['radius'] ?? 0,
      validityHours: json['validityHours'] ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'])
          : DateTime.now(),
      messageType: json['messageType'] ?? 'promotion',
      targetMeetingId: json['targetMeetingId'],
      reachCount: json['reachCount'] ?? 0,
      acceptCount: json['acceptCount'] ?? 0,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'shopId': shopId,
      'shopName': shopName,
      'category': category,
      'ownerId': ownerId,
      'message': message,
      'radius': radius,
      'validityHours': validityHours,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'messageType': messageType,
      'targetMeetingId': targetMeetingId,
      'reachCount': reachCount,
      'acceptCount': acceptCount,
    };
  }
  
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  
  Duration get remainingTime {
    final now = DateTime.now();
    if (now.isAfter(expiresAt)) return Duration.zero;
    return expiresAt.difference(now);
  }
}

class MessageAcceptanceModel {
  final String acceptanceId;
  final String messageId;
  final String userId;
  final DateTime acceptedAt;
  final double userLat;
  final double userLng;
  final bool dismissed;
  final bool accepted;
  
  MessageAcceptanceModel({
    required this.acceptanceId,
    required this.messageId,
    required this.userId,
    required this.acceptedAt,
    required this.userLat,
    required this.userLng,
    required this.dismissed,
    required this.accepted,
  });
  
  factory MessageAcceptanceModel.fromJson(Map<String, dynamic> json, String docId) {
    return MessageAcceptanceModel(
      acceptanceId: docId,
      messageId: json['messageId'] ?? '',
      userId: json['userId'] ?? '',
      acceptedAt: json['acceptedAt'] != null
          ? DateTime.parse(json['acceptedAt'])
          : DateTime.now(),
      userLat: (json['userLat'] ?? 0.0).toDouble(),
      userLng: (json['userLng'] ?? 0.0).toDouble(),
      dismissed: json['dismissed'] == true || json['dismissed'] == 1,
      accepted: json['accepted'] == true || json['accepted'] == 1,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'userId': userId,
      'acceptedAt': acceptedAt.toIso8601String(),
      'userLat': userLat,
      'userLng': userLng,
      'dismissed': dismissed,
      'accepted': accepted,
    };
  }
}

class MeetingGroupModel {
  final String meetingId;
  final String organizerId;
  final String meetingName;
  final List<String> memberIds;
  final double targetLat;
  final double targetLng;
  final DateTime meetingTime;
  final int memberCount;
  final String status; // 'pending', 'active', 'completed'
  final DateTime createdAt;
  
  MeetingGroupModel({
    required this.meetingId,
    required this.organizerId,
    required this.meetingName,
    required this.memberIds,
    required this.targetLat,
    required this.targetLng,
    required this.meetingTime,
    required this.memberCount,
    this.status = 'pending',
    required this.createdAt,
  });
  
  factory MeetingGroupModel.fromJson(Map<String, dynamic> json, String docId) {
    return MeetingGroupModel(
      meetingId: docId,
      organizerId: json['organizerId'] ?? '',
      meetingName: json['meetingName'] ?? '',
      memberIds: List<String>.from(json['memberIds'] ?? []),
      targetLat: (json['targetLat'] ?? 0.0).toDouble(),
      targetLng: (json['targetLng'] ?? 0.0).toDouble(),
      meetingTime: json['meetingTime'] != null
          ? DateTime.parse(json['meetingTime'])
          : DateTime.now(),
      memberCount: json['memberCount'] ?? 0,
      status: json['status'] ?? 'pending',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'organizerId': organizerId,
      'meetingName': meetingName,
      'memberIds': memberIds,
      'targetLat': targetLat,
      'targetLng': targetLng,
      'meetingTime': meetingTime.toIso8601String(),
      'memberCount': memberCount,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}