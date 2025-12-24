// lib/providers/temp_group_messages_provider.dart
// ✅ 시간 제한 그룹 채팅 메시지 Provider (전체 통합 버전)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import '../appwriteClient.dart';
import '../constants/appwrite_config.dart';
import '../models/temp_group_message_model.dart';

class TempGroupMessagesProvider extends ChangeNotifier {
  final Databases _db = appwriteDB;
  final Realtime _realtime = appwriteRealtime;

  // ═══════════════════════════════════════════════════════════
  // State
  // ═══════════════════════════════════════════════════════════
  
  final Map<String, List<TempGroupMessageModel>> _messagesByGroup = {};
  bool _isLoading = false;
  String? _error;
  RealtimeSubscription? _subscription;
  String? _currentGroupId;
  final Map<String, bool> _hasMore = {};
  final Map<String, String?> _lastMessageId = {};
  // ✅✅✅ UnreadCount 관련
  final Map<String, int> _unreadCounts = {};

  // ═══════════════════════════════════════════════════════════
  // Getters
  // ═══════════════════════════════════════════════════════════
  
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  List<TempGroupMessageModel> getMessages(String groupId) {
    return _messagesByGroup[groupId] ?? [];
  }
  
  // ✅✅✅ UnreadCount getter
  int getUnreadCount(String groupId) {
    return _unreadCounts[groupId] ?? 0;
  }
  
  // ✅✅✅ 전체 unread count 합계
  int get totalUnreadCount {
    return _unreadCounts.values.fold(0, (sum, count) => sum + count);
  }
  bool hasMoreMessages(String groupId) {
    return _hasMore[groupId] ?? true;
  }

  // ═══════════════════════════════════════════════════════════
  // 1. 메시지 조회
  // ═══════════════════════════════════════════════════════════
  
  Future<void> fetchMessages(String groupId, {int limit = 50}) async {
    try {
      debugPrint('📨 메시지 조회: $groupId (limit: $limit)');
      
      _isLoading = true;
      _error = null;
      notifyListeners();

      final response = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupMessagesCollectionId,
        queries: [
          Query.equal('groupId', groupId),
          Query.orderDesc('\$createdAt'),
          Query.limit(limit),
        ],
      );

      final messages = response.documents
          .map((doc) => TempGroupMessageModel.fromMap(doc.$id, doc.data))
          .toList();

      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      _messagesByGroup[groupId] = messages;
      _hasMore[groupId] = response.documents.length >= limit;
      if (messages.isNotEmpty) {
        _lastMessageId[groupId] = messages.first.id;
      }

      debugPrint('✅ 메시지 ${messages.length}개 로드 완료');

      _isLoading = false;
      _error = null;
      notifyListeners();

    } catch (e) {
      debugPrint('❌ 메시지 조회 실패: $e');
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadMoreMessages(String groupId, {int limit = 50}) async {
    if (!hasMoreMessages(groupId) || _isLoading) return;

    try {
      debugPrint('📨 이전 메시지 로딩: $groupId');
      
      _isLoading = true;
      notifyListeners();

      final lastId = _lastMessageId[groupId];
      if (lastId == null) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      final response = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupMessagesCollectionId,
        queries: [
          Query.equal('groupId', groupId),
          Query.orderDesc('\$createdAt'),
          Query.cursorBefore(lastId),
          Query.limit(limit),
        ],
      );

      if (response.documents.isEmpty) {
        _hasMore[groupId] = false;
        _isLoading = false;
        notifyListeners();
        return;
      }

      final newMessages = response.documents
          .map((doc) => TempGroupMessageModel.fromMap(doc.$id, doc.data))
          .toList();

      newMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      final existingMessages = _messagesByGroup[groupId] ?? [];
      _messagesByGroup[groupId] = [...newMessages, ...existingMessages];

      _hasMore[groupId] = response.documents.length >= limit;
      _lastMessageId[groupId] = newMessages.first.id;

      debugPrint('✅ 이전 메시지 ${newMessages.length}개 추가');

      _isLoading = false;
      notifyListeners();

    } catch (e) {
      debugPrint('❌ 이전 메시지 로딩 실패: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 2. 메시지 전송
  // ═══════════════════════════════════════════════════════════
  Future<bool> sendMessage({
    required String groupId,
    required String userId,
    required String message,
    String? replyTo,
    MessageType type = MessageType.text,
  }) async {
    try {
      debugPrint('📤 메시지 전송 시작');
      
      // 1. 멤버 ID 조회
      final memberIds = await _getGroupMemberIds(groupId);
      if (memberIds.isEmpty) {
        debugPrint('❌ 멤버가 없습니다');
        return false;
      }
      debugPrint('👥 멤버: ${memberIds.length}명 - $memberIds');
      
      // 2. Permission 생성 (문자열 배열)
      final permissions = <String>[
        ...memberIds.map((id) => 'read("user:$id")'),
        'update("user:$userId")',
        'delete("user:$userId")',
      ];
      
      debugPrint('🔒 생성된 Permissions:');
      permissions.forEach((p) => debugPrint('   $p'));

      // 3. 메시지 데이터
      final messageData = <String, dynamic>{
        'groupId': groupId,
        'userId': userId,
        'message': message,
        'type': type.name,
        'isDeleted': false,
      };
      
      if (replyTo != null) {
        messageData['replyTo'] = replyTo;
      }

      // 4. Appwrite에 저장
      final doc = await _db.createDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupMessagesCollectionId,
        documentId: ID.unique(),
        data: messageData,
      );

      debugPrint('✅ 메시지 저장 성공: ${doc.$id}');

      // 5. 로컬 업데이트
      final newMessage = TempGroupMessageModel.fromMap(doc.$id, doc.data);
      final messages = _messagesByGroup[groupId] ?? [];
      _messagesByGroup[groupId] = [...messages, newMessage];

      // 6. 그룹 활동 시간 업데이트
      await _updateGroupActivity(groupId);

      notifyListeners();
      return true;

    } catch (e, stackTrace) {
      debugPrint('❌ 메시지 전송 실패');
      debugPrint('   에러: $e');
      debugPrint('   스택: $stackTrace');
      return false;
    }
  }

  Future<bool> sendSystemMessage({
    required String groupId,
    required String message,
  }) async {
    return await sendMessage(
      groupId: groupId,
      userId: 'system',
      message: message,
      type: MessageType.system,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 3. 메시지 수정/삭제
  // ═══════════════════════════════════════════════════════════
  
  Future<bool> updateMessage({
    required String messageId,
    required String newMessage,
  }) async {
    try {
      debugPrint('✏️ 메시지 수정: $messageId');

      await _db.updateDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupMessagesCollectionId,
        documentId: messageId,
        data: {'message': newMessage},
      );

      debugPrint('✅ 메시지 수정 완료');
      return true;

    } catch (e) {
      debugPrint('❌ 메시지 수정 실패: $e');
      return false;
    }
  }

  Future<bool> deleteMessage(String messageId) async {
    try {
      debugPrint('🗑️ 메시지 삭제: $messageId');

      await _db.updateDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupMessagesCollectionId,
        documentId: messageId,
        data: {
          'isDeleted': true,
          'message': '삭제된 메시지입니다',
        },
      );

      debugPrint('✅ 메시지 삭제 완료');
      return true;

    } catch (e) {
      debugPrint('❌ 메시지 삭제 실패: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 4. Realtime
  // ═══════════════════════════════════════════════════════════
  
  Future<void> subscribeToMessages(String groupId) async {
    try {
      debugPrint('🎧 Realtime 구독: $groupId');

      await unsubscribeFromMessages();
      _currentGroupId = groupId;

      final channel = 'databases.${AppwriteConstants.databaseId}.collections.${AppwriteConstants.tempGroupMessagesCollectionId}.documents';
      
      _subscription = _realtime.subscribe([channel]);

      _subscription!.stream.listen((event) {
        final eventType = event.events.first;
        
        if (eventType.contains('create')) {
          _handleMessageCreated(event.payload);
        } else if (eventType.contains('update')) {
          _handleMessageUpdated(event.payload);
        } else if (eventType.contains('delete')) {
          _handleMessageDeleted(event.payload);
        }
      });

      debugPrint('✅ Realtime 구독 완료');

    } catch (e) {
      debugPrint('❌ Realtime 구독 실패: $e');
    }
  }

  Future<void> unsubscribeFromMessages() async {
    if (_subscription != null) {
      debugPrint('🎧 Realtime 구독 취소');
      _subscription!.close();
      _subscription = null;
      _currentGroupId = null;
    }
  }

  void _handleMessageCreated(Map<String, dynamic> payload) {
    try {
      final message = TempGroupMessageModel.fromMap(payload['\$id'], payload);
      
      if (message.groupId != _currentGroupId) return;

      final messages = _messagesByGroup[message.groupId] ?? [];
      if (messages.any((m) => m.id == message.id)) return;

      _messagesByGroup[message.groupId] = [...messages, message];
      notifyListeners();

      debugPrint('✅ 새 메시지 수신: ${message.id}');

    } catch (e) {
      debugPrint('❌ 메시지 생성 이벤트 처리 실패: $e');
    }
  }

  void _handleMessageUpdated(Map<String, dynamic> payload) {
    try {
      final updatedMessage = TempGroupMessageModel.fromMap(payload['\$id'], payload);
      
      if (updatedMessage.groupId != _currentGroupId) return;

      final messages = _messagesByGroup[updatedMessage.groupId] ?? [];
      final index = messages.indexWhere((m) => m.id == updatedMessage.id);
      
      if (index != -1) {
        messages[index] = updatedMessage;
        _messagesByGroup[updatedMessage.groupId] = [...messages];
        notifyListeners();
      }

      debugPrint('✅ 메시지 수정 수신: ${updatedMessage.id}');

    } catch (e) {
      debugPrint('❌ 메시지 수정 이벤트 처리 실패: $e');
    }
  }

  void _handleMessageDeleted(Map<String, dynamic> payload) {
    try {
      final messageId = payload['\$id'] as String;
      final groupId = payload['groupId'] as String;
      
      if (groupId != _currentGroupId) return;

      final messages = _messagesByGroup[groupId] ?? [];
      _messagesByGroup[groupId] = messages.where((m) => m.id != messageId).toList();
      notifyListeners();

      debugPrint('✅ 메시지 삭제 수신: $messageId');

    } catch (e) {
      debugPrint('❌ 메시지 삭제 이벤트 처리 실패: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 5. 읽음 처리 (UnreadCount)
  // ═══════════════════════════════════════════════════════════
  
  // ✅✅✅ unread count 계산
  Future<void> calculateUnreadCount(String groupId, String userId) async {
    try {
      final messages = _messagesByGroup[groupId] ?? [];
      
      // 마지막으로 읽은 시간 가져오기
      final memberDoc = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupMembersCollectionId,
        queries: [
          Query.equal('groupId', groupId),
          Query.equal('userId', userId),
        ],
      );
      
      if (memberDoc.documents.isEmpty) {
        _unreadCounts[groupId] = 0;
        notifyListeners();
        return;
      }
      
      final lastReadAt = memberDoc.documents.first.data['lastReadAt'] as String?;
      
      if (lastReadAt == null) {
        // 한 번도 읽지 않음
        _unreadCounts[groupId] = messages.where((m) => 
          m.userId != userId && !m.isDeleted && !m.isSystemMessage
        ).length;
      } else {
        final lastReadTime = DateTime.parse(lastReadAt);
        
        // lastReadAt 이후 메시지 개수
        _unreadCounts[groupId] = messages.where((m) => 
          m.createdAt.isAfter(lastReadTime) && 
          m.userId != userId && 
          !m.isDeleted &&
          !m.isSystemMessage
        ).length;
      }
      
      debugPrint('📊 Unread count ($groupId): ${_unreadCounts[groupId]}');
      notifyListeners();
      
    } catch (e) {
      debugPrint('❌ Unread count 계산 실패: $e');
      _unreadCounts[groupId] = 0;
    }
  }
  
  // ✅✅✅ 읽음 처리
  Future<void> markAsRead(String groupId, String userId) async {
    try {
      final memberDoc = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupMembersCollectionId,
        queries: [
          Query.equal('groupId', groupId),
          Query.equal('userId', userId),
        ],
      );
      
      if (memberDoc.documents.isEmpty) return;
      
      await _db.updateDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupMembersCollectionId,
        documentId: memberDoc.documents.first.$id,
        data: {
          'lastReadAt': DateTime.now().toIso8601String(),
        },
      );
      
      _unreadCounts[groupId] = 0;
      notifyListeners();
      
      debugPrint('✅ 읽음 처리 완료 ($groupId)');
      
    } catch (e) {
      debugPrint('❌ 읽음 처리 실패: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 헬퍼
  // ═══════════════════════════════════════════════════════════
  
  Future<List<String>> _getGroupMemberIds(String groupId) async {
    try {
      final response = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupMembersCollectionId,
        queries: [
          Query.equal('groupId', groupId),
          Query.equal('status', 'active'),
        ],
      );

      return response.documents
          .map((doc) => doc.data['userId'] as String)
          .toList();

    } catch (e) {
      debugPrint('❌ 멤버 ID 조회 실패: $e');
      return [];
    }
  }

  Future<void> _updateGroupActivity(String groupId) async {
    try {
      await _db.updateDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupsCollectionId,
        documentId: groupId,
        data: {
          'lastActivityAt': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('⚠️ 그룹 활동 시간 업데이트 실패: $e');
    }
  }

  void clearMessages(String groupId) {
    _messagesByGroup.remove(groupId);
    _hasMore.remove(groupId);
    _lastMessageId.remove(groupId);
    _unreadCounts.remove(groupId);
    notifyListeners();
  }

  void clearAllMessages() {
    _messagesByGroup.clear();
    _hasMore.clear();
    _lastMessageId.clear();
    _unreadCounts.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    debugPrint('🗑️ TempGroupMessagesProvider dispose');
    unsubscribeFromMessages();
    super.dispose();
  }
}