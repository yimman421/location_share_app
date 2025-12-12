enum UserRole {
  user,      // 일반 유저
  shopOwner, // 샵 주인
}

class UserModel {
  final String userId;
  final String email;
  final String nickname;
  final String? profileImage;
  final UserRole role;
  final DateTime createdAt;
  
  UserModel({
    required this.userId,
    required this.email,
    required this.nickname,
    this.profileImage,
    this.role = UserRole.user,
    required this.createdAt,
  });
  
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      userId: json['userId'] ?? '',
      email: json['email'] ?? '',
      nickname: json['nickname'] ?? '',
      profileImage: json['profileImage'],
      role: _parseRole(json['role']),
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : DateTime.now(),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'email': email,
      'nickname': nickname,
      'profileImage': profileImage,
      'role': role.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }
  
  static UserRole _parseRole(dynamic roleData) {
    if (roleData == null) return UserRole.user;
    
    if (roleData is String) {
      if (roleData == 'shopOwner') return UserRole.shopOwner;
      return UserRole.user;
    }
    
    return UserRole.user;
  }
  
  UserModel copyWith({
    String? userId,
    String? email,
    String? nickname,
    String? profileImage,
    UserRole? role,
    DateTime? createdAt,
  }) {
    return UserModel(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      nickname: nickname ?? this.nickname,
      profileImage: profileImage ?? this.profileImage,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}