// lib/models/temp_group_model.dart

import 'package:flutter/foundation.dart';

// ============================================
// ✅ 1. TempGroupModel (시간 제한 그룹)
// ============================================

enum TempGroupStatus {
  active,   // 활성
  expired,  // 만료됨
  deleted,  // 삭제됨
}

class TempGroupModel {
  final String id;
  final String groupName;
  final String description;
  final String creatorId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final TempGroupStatus status;
  
  // 설정
  final int duration;  // 일 단위 (7, 14, 21, 28)
  final bool canExtend;
  final int? maxMembers;  // null = 무제한
  final int extensionCount;
  final bool freeExtensionUsed;
  
  // 통계
  final int memberCount;
  final int messageCount;
  final DateTime lastActivityAt;
  
  // 알림
  final bool notification7days;
  final bool notification3days;
  final bool notification1day;
  final bool notificationExpired;

  TempGroupModel({
    required this.id,
    required this.groupName,
    required this.description,
    required this.creatorId,
    required this.createdAt,
    required this.expiresAt,
    required this.status,
    required this.duration,
    required this.canExtend,
    this.maxMembers,
    required this.extensionCount,
    required this.freeExtensionUsed,
    required this.memberCount,
    required this.messageCount,
    required this.lastActivityAt,
    required this.notification7days,
    required this.notification3days,
    required this.notification1day,
    required this.notificationExpired,
  });

  // ✅ Appwrite Document → Model
  factory TempGroupModel.fromMap(String id, Map<String, dynamic> data) {
    return TempGroupModel(
      id: id,
      groupName: data['groupName'] ?? '',
      description: data['description'] ?? '',
      creatorId: data['creatorId'] ?? '',
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'])
          : DateTime.now(),
      expiresAt: data['expiresAt'] != null
          ? DateTime.parse(data['expiresAt'])
          : DateTime.now().add(const Duration(days: 7)),
      status: _parseStatus(data['status']),
      duration: data['duration'] ?? 7,
      canExtend: data['canExtend'] ?? true,
      maxMembers: data['maxMembers'],
      extensionCount: data['extensionCount'] ?? 0,
      freeExtensionUsed: data['freeExtensionUsed'] ?? false,
      memberCount: data['memberCount'] ?? 1,
      messageCount: data['messageCount'] ?? 0,
      lastActivityAt: data['lastActivityAt'] != null
          ? DateTime.parse(data['lastActivityAt'])
          : DateTime.now(),
      notification7days: data['notification7days'] ?? false,
      notification3days: data['notification3days'] ?? false,
      notification1day: data['notification1day'] ?? false,
      notificationExpired: data['notificationExpired'] ?? false,
    );
  }

  // ✅ Model → Appwrite Document
  Map<String, dynamic> toMap() {
    return {
      'groupName': groupName,
      'description': description,
      'creatorId': creatorId,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'status': status.name,
      'duration': duration,
      'canExtend': canExtend,
      'maxMembers': maxMembers,
      'extensionCount': extensionCount,
      'freeExtensionUsed': freeExtensionUsed,
      'memberCount': memberCount,
      'messageCount': messageCount,
      'lastActivityAt': lastActivityAt.toIso8601String(),
      'notification7days': notification7days,
      'notification3days': notification3days,
      'notification1day': notification1day,
      'notificationExpired': notificationExpired,
    };
  }

  // ✅ copyWith
  TempGroupModel copyWith({
    String? id,
    String? groupName,
    String? description,
    String? creatorId,
    DateTime? createdAt,
    DateTime? expiresAt,
    TempGroupStatus? status,
    int? duration,
    bool? canExtend,
    int? maxMembers,
    int? extensionCount,
    bool? freeExtensionUsed,
    int? memberCount,
    int? messageCount,
    DateTime? lastActivityAt,
    bool? notification7days,
    bool? notification3days,
    bool? notification1day,
    bool? notificationExpired,
  }) {
    return TempGroupModel(
      id: id ?? this.id,
      groupName: groupName ?? this.groupName,
      description: description ?? this.description,
      creatorId: creatorId ?? this.creatorId,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      status: status ?? this.status,
      duration: duration ?? this.duration,
      canExtend: canExtend ?? this.canExtend,
      maxMembers: maxMembers ?? this.maxMembers,
      extensionCount: extensionCount ?? this.extensionCount,
      freeExtensionUsed: freeExtensionUsed ?? this.freeExtensionUsed,
      memberCount: memberCount ?? this.memberCount,
      messageCount: messageCount ?? this.messageCount,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      notification7days: notification7days ?? this.notification7days,
      notification3days: notification3days ?? this.notification3days,
      notification1day: notification1day ?? this.notification1day,
      notificationExpired: notificationExpired ?? this.notificationExpired,
    );
  }

  // ✅ 헬퍼 메서드
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isActive => status == TempGroupStatus.active && !isExpired;
  
  Duration get remainingTime {
    final now = DateTime.now();
    if (now.isAfter(expiresAt)) return Duration.zero;
    return expiresAt.difference(now);
  }
  
  int get remainingDays => remainingTime.inDays;
  int get remainingHours => remainingTime.inHours;
  
  String get formattedRemainingTime {
    final days = remainingDays;
    if (days > 0) return '$days일 남음';
    
    final hours = remainingHours;
    if (hours > 0) return '$hours시간 남음';
    
    final minutes = remainingTime.inMinutes;
    if (minutes > 0) return '$minutes분 남음';
    
    return '곧 만료';
  }
  
  bool get isFull => maxMembers != null && memberCount >= maxMembers!;
  bool get canJoin => isActive && !isFull;

  static TempGroupStatus _parseStatus(dynamic statusData) {
    if (statusData == null) return TempGroupStatus.active;
    
    if (statusData is String) {
      switch (statusData) {
        case 'expired':
          return TempGroupStatus.expired;
        case 'deleted':
          return TempGroupStatus.deleted;
        default:
          return TempGroupStatus.active;
      }
    }
    
    return TempGroupStatus.active;
  }
}

// ============================================
// ✅ 2. TempGroupMemberModel (그룹 멤버)
// ============================================

enum MemberRole {
  creator,  // 생성자
  admin,    // 관리자
  member,   // 일반 멤버
}

enum MemberStatus {
  invited,  // 초대됨
  active,   // 활성
  left,     // 나감
  kicked,   // 강퇴됨
}

class TempGroupMemberModel {
  final String id;
  final String groupId;
  final String userId;
  final MemberRole role;
  final MemberStatus status;
  
  // 초대 정보
  final String? invitedBy;
  final DateTime invitedAt;
  final DateTime? joinedAt;
  
  // 채팅 정보
  final DateTime? lastReadAt;
  final int unreadCount;
  final DateTime? mutedUntil;
  
  final DateTime createdAt;
  final DateTime updatedAt;

  TempGroupMemberModel({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.role,
    required this.status,
    this.invitedBy,
    required this.invitedAt,
    this.joinedAt,
    this.lastReadAt,
    required this.unreadCount,
    this.mutedUntil,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TempGroupMemberModel.fromMap(String id, Map<String, dynamic> data) {
    return TempGroupMemberModel(
      id: id,
      groupId: data['groupId'] ?? '',
      userId: data['userId'] ?? '',
      role: _parseRole(data['role']),
      status: _parseStatus(data['status']),
      invitedBy: data['invitedBy'],
      invitedAt: data['invitedAt'] != null
          ? DateTime.parse(data['invitedAt'])
          : DateTime.now(),
      joinedAt: data['joinedAt'] != null
          ? DateTime.parse(data['joinedAt'])
          : null,
      lastReadAt: data['lastReadAt'] != null
          ? DateTime.parse(data['lastReadAt'])
          : null,
      unreadCount: data['unreadCount'] ?? 0,
      mutedUntil: data['mutedUntil'] != null
          ? DateTime.parse(data['mutedUntil'])
          : null,
      createdAt: data['\$createdAt'] != null
          ? DateTime.parse(data['\$createdAt'])
          : DateTime.now(),
      updatedAt: data['\$updatedAt'] != null
          ? DateTime.parse(data['\$updatedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'groupId': groupId,
      'userId': userId,
      'role': role.name,
      'status': status.name,
      'invitedBy': invitedBy,
      'invitedAt': invitedAt.toIso8601String(),
      'joinedAt': joinedAt?.toIso8601String(),
      'lastReadAt': lastReadAt?.toIso8601String(),
      'unreadCount': unreadCount,
      'mutedUntil': mutedUntil?.toIso8601String(),
    };
  }

  TempGroupMemberModel copyWith({
    String? id,
    String? groupId,
    String? userId,
    MemberRole? role,
    MemberStatus? status,
    String? invitedBy,
    DateTime? invitedAt,
    DateTime? joinedAt,
    DateTime? lastReadAt,
    int? unreadCount,
    DateTime? mutedUntil,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TempGroupMemberModel(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      status: status ?? this.status,
      invitedBy: invitedBy ?? this.invitedBy,
      invitedAt: invitedAt ?? this.invitedAt,
      joinedAt: joinedAt ?? this.joinedAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      unreadCount: unreadCount ?? this.unreadCount,
      mutedUntil: mutedUntil ?? this.mutedUntil,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isMuted {
    if (mutedUntil == null) return false;
    return DateTime.now().isBefore(mutedUntil!);
  }

  static MemberRole _parseRole(dynamic roleData) {
    if (roleData == null) return MemberRole.member;
    
    if (roleData is String) {
      switch (roleData) {
        case 'creator':
          return MemberRole.creator;
        case 'admin':
          return MemberRole.admin;
        default:
          return MemberRole.member;
      }
    }
    
    return MemberRole.member;
  }

  static MemberStatus _parseStatus(dynamic statusData) {
    if (statusData == null) return MemberStatus.invited;
    
    if (statusData is String) {
      switch (statusData) {
        case 'active':
          return MemberStatus.active;
        case 'left':
          return MemberStatus.left;
        case 'kicked':
          return MemberStatus.kicked;
        default:
          return MemberStatus.invited;
      }
    }
    
    return MemberStatus.invited;
  }
}

// ============================================
// ✅ 3. TempGroupInviteModel (초대 링크)
// ============================================

enum InviteStatus {
  active,    // 활성
  expired,   // 만료됨
  disabled,  // 비활성화됨
}

class TempGroupInviteModel {
  final String id;
  final String groupId;
  final String inviteCode;
  final String createdBy;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int? maxUses;  // null = 무제한
  final int usedCount;
  final InviteStatus status;

  TempGroupInviteModel({
    required this.id,
    required this.groupId,
    required this.inviteCode,
    required this.createdBy,
    required this.createdAt,
    required this.expiresAt,
    this.maxUses,
    required this.usedCount,
    required this.status,
  });

  factory TempGroupInviteModel.fromMap(String id, Map<String, dynamic> data) {
    return TempGroupInviteModel(
      id: id,
      groupId: data['groupId'] ?? '',
      inviteCode: data['inviteCode'] ?? '',
      createdBy: data['createdBy'] ?? '',
      createdAt: data['\$createdAt'] != null
          ? DateTime.parse(data['\$createdAt'])
          : DateTime.now(),
      expiresAt: data['expiresAt'] != null
          ? DateTime.parse(data['expiresAt'])
          : DateTime.now().add(const Duration(days: 1)),
      maxUses: data['maxUses'],
      usedCount: data['usedCount'] ?? 0,
      status: _parseStatus(data['status']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'groupId': groupId,
      'inviteCode': inviteCode,
      'createdBy': createdBy,
      'expiresAt': expiresAt.toIso8601String(),
      'maxUses': maxUses,
      'usedCount': usedCount,
      'status': status.name,
    };
  }

  TempGroupInviteModel copyWith({
    String? id,
    String? groupId,
    String? inviteCode,
    String? createdBy,
    DateTime? createdAt,
    DateTime? expiresAt,
    int? maxUses,
    int? usedCount,
    InviteStatus? status,
  }) {
    return TempGroupInviteModel(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      inviteCode: inviteCode ?? this.inviteCode,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      maxUses: maxUses ?? this.maxUses,
      usedCount: usedCount ?? this.usedCount,
      status: status ?? this.status,
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isMaxedOut => maxUses != null && usedCount >= maxUses!;
  bool get isValid => status == InviteStatus.active && !isExpired && !isMaxedOut;

  static InviteStatus _parseStatus(dynamic statusData) {
    if (statusData == null) return InviteStatus.active;
    
    if (statusData is String) {
      switch (statusData) {
        case 'expired':
          return InviteStatus.expired;
        case 'disabled':
          return InviteStatus.disabled;
        default:
          return InviteStatus.active;
      }
    }
    
    return InviteStatus.active;
  }
}

// ============================================
// ✅ 4. 헬퍼 클래스
// ============================================

class TempGroupDuration {
  static const int week1 = 7;
  static const int week2 = 14;
  static const int week3 = 21;
  static const int week4 = 28;
  
  static const List<int> all = [week1, week2, week3, week4];
  
  static String label(int days) {
    switch (days) {
      case 7:
        return '1주';
      case 14:
        return '2주';
      case 21:
        return '3주';
      case 28:
        return '4주';
      default:
        return '$days일';
    }
  }
}