class UserProfile {
  final String userId;
  final String? nickname;
  final String? email;
  final String? profileImage;
  final DateTime? lastSeen;

  UserProfile({
    required this.userId,
    this.nickname,
    this.email,
    this.profileImage,
    this.lastSeen,
  });

  factory UserProfile.fromMap(Map<String, dynamic> m) {
    return UserProfile(
      userId: m['userId'] ?? m['\$id'] ?? '',
      nickname: m['nickname'],
      email: m['email'],
      profileImage: m['profileImage'],
      lastSeen: m['lastSeen'] != null ? DateTime.parse(m['lastSeen']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'nickname': nickname,
      'email': email,
      'profileImage': profileImage,
      'lastSeen': lastSeen?.toIso8601String(),
    };
  }
}
