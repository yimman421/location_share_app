// lib/models/temp_group_message_model.dart
// ✅ 시간 제한 그룹 채팅 메시지 모델

//import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════
// Enums
// ═══════════════════════════════════════════════════════════

enum MessageType {
  text,      // 일반 텍스트 메시지
  image,     // 이미지 메시지
  system,    // 시스템 메시지 (입장/퇴장 등)
}

// ═══════════════════════════════════════════════════════════
// TempGroupMessageModel
// ═══════════════════════════════════════════════════════════

class TempGroupMessageModel {
  final String id;              // 메시지 ID
  final String groupId;         // 그룹 ID
  final String userId;          // 발신자 ID
  final String message;         // 메시지 내용
  final MessageType type;       // 메시지 타입
  final bool isDeleted;         // 삭제 여부
  final String? replyTo;        // 답장 대상 메시지 ID
  final DateTime createdAt;     // 생성 시간
  final DateTime updatedAt;     // 수정 시간

  TempGroupMessageModel({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.message,
    required this.type,
    required this.isDeleted,
    this.replyTo,
    required this.createdAt,
    required this.updatedAt,
  });

  // ✅ Helper Methods
  bool get isSystemMessage => type == MessageType.system;
  bool get isTextMessage => type == MessageType.text;
  bool get isImageMessage => type == MessageType.image;
  bool get canEdit => !isDeleted && type == MessageType.text;
  bool get isReply => replyTo != null;

  // ✅ Appwrite Document → Model
  factory TempGroupMessageModel.fromMap(String id, Map<String, dynamic> data) {
    return TempGroupMessageModel(
      id: id,
      groupId: data['groupId'] ?? '',
      userId: data['userId'] ?? '',
      message: data['message'] ?? '',
      type: _parseType(data['type']),
      isDeleted: data['isDeleted'] ?? false,
      replyTo: data['replyTo'],
      createdAt: data['\$createdAt'] != null
          ? DateTime.parse(data['\$createdAt'])
          : DateTime.now(),
      updatedAt: data['\$updatedAt'] != null
          ? DateTime.parse(data['\$updatedAt'])
          : DateTime.now(),
    );
  }

  // ✅ Model → Appwrite Document
  Map<String, dynamic> toMap() {
    return {
      'groupId': groupId,
      'userId': userId,
      'message': message,
      'type': type.name,
      'isDeleted': isDeleted,
      'replyTo': replyTo,
    };
  }

  // ✅ copyWith
  TempGroupMessageModel copyWith({
    String? id,
    String? groupId,
    String? userId,
    String? message,
    MessageType? type,
    bool? isDeleted,
    String? replyTo,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TempGroupMessageModel(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      userId: userId ?? this.userId,
      message: message ?? this.message,
      type: type ?? this.type,
      isDeleted: isDeleted ?? this.isDeleted,
      replyTo: replyTo ?? this.replyTo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ✅ Type 파싱 헬퍼
  static MessageType _parseType(dynamic typeData) {
    if (typeData == null) return MessageType.text;
    
    if (typeData is String) {
      switch (typeData) {
        case 'text':
          return MessageType.text;
        case 'image':
          return MessageType.image;
        case 'system':
          return MessageType.system;
        default:
          return MessageType.text;
      }
    }
    
    return MessageType.text;
  }

  // ✅ 시간 포맷 헬퍼
  String get formattedTime {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    
    // 오늘
    if (diff.inDays == 0) {
      final hour = createdAt.hour;
      final minute = createdAt.minute.toString().padLeft(2, '0');
      final period = hour < 12 ? '오전' : '오후';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$period $displayHour:$minute';
    }
    
    // 어제
    if (diff.inDays == 1) {
      return '어제';
    }
    
    // 일주일 이내
    if (diff.inDays < 7) {
      return '${diff.inDays}일 전';
    }
    
    // 그 이상
    return '${createdAt.month}월 ${createdAt.day}일';
  }

  // ✅ 날짜 구분을 위한 날짜만 추출
  String get dateOnly {
    return '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
  }

  // ✅ 수정 여부 확인
  bool get isEdited {
    return updatedAt.difference(createdAt).inSeconds > 1;
  }

  @override
  String toString() {
    return 'TempGroupMessageModel(id: $id, groupId: $groupId, userId: $userId, message: $message, type: ${type.name})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    
    return other is TempGroupMessageModel &&
        other.id == id &&
        other.groupId == groupId &&
        other.userId == userId &&
        other.message == message &&
        other.type == type &&
        other.isDeleted == isDeleted &&
        other.replyTo == replyTo;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        groupId.hashCode ^
        userId.hashCode ^
        message.hashCode ^
        type.hashCode ^
        isDeleted.hashCode ^
        replyTo.hashCode;
  }
}

// ═══════════════════════════════════════════════════════════
// 시스템 메시지 생성 헬퍼
// ═══════════════════════════════════════════════════════════

class SystemMessageHelper {
  // ✅ 그룹 생성 메시지
  static Map<String, dynamic> groupCreated(String groupName) {
    return {
      'message': '🎉 "$groupName" 그룹이 생성되었습니다',
      'type': 'system',
    };
  }

  // ✅ 멤버 입장 메시지
  static Map<String, dynamic> memberJoined(String userId) {
    return {
      'message': '👋 $userId님이 입장했습니다',
      'type': 'system',
    };
  }

  // ✅✅✅ 멤버 재참여 메시지 (NEW!)
  static Map<String, dynamic> memberRejoined(String userId) {
    return {
      'message': '🔄 $userId님이 그룹에 다시 참여했습니다',
      'type': 'system',
    };
  }

  // ✅ 멤버 퇴장 메시지
  static Map<String, dynamic> memberLeft(String userId) {
    return {
      'message': '👋 $userId님이 퇴장했습니다',
      'type': 'system',
    };
  }

  // ✅ 그룹 연장 메시지
  static Map<String, dynamic> groupExtended(int days) {
    return {
      'message': '⏰ 그룹 기간이 ${days}일 연장되었습니다',
      'type': 'system',
    };
  }

  // ✅ 그룹 만료 경고 메시지
  static Map<String, dynamic> groupExpiringWarning(int daysLeft) {
    String emoji = daysLeft <= 1 ? '🚨' : '⚠️';
    String message = daysLeft == 1
        ? '$emoji 그룹이 내일 만료됩니다'
        : '$emoji 그룹이 ${daysLeft}일 후 만료됩니다';
    
    return {
      'message': message,
      'type': 'system',
    };
  }

  // ✅ 그룹 만료 메시지
  static Map<String, dynamic> groupExpired() {
    return {
      'message': '⏰ 그룹이 만료되었습니다',
      'type': 'system',
    };
  }
}