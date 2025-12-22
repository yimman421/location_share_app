// lib/providers/temp_groups_provider.dart

import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';
import 'dart:math';
import '../models/temp_group_model.dart';
import '../constants/appwrite_config.dart';
import '../appwriteClient.dart';

class TempGroupsProvider with ChangeNotifier {
  final Databases _db = appwriteDB;
  final Account _account = appwriteAccount;
  final Realtime _realtime = appwriteRealtime;
  
  // 내 그룹 목록
  List<TempGroupModel> _myGroups = [];
  
  // 특정 그룹의 멤버 목록
  Map<String, List<TempGroupMemberModel>> _groupMembers = {};
  
  // 로딩 상태
  bool _isLoading = false;
  
  // Realtime 구독
  RealtimeSubscription? _groupsSub;
  RealtimeSubscription? _membersSub;
  
  // Getters
  List<TempGroupModel> get myGroups => _myGroups;
  List<TempGroupModel> get activeGroups => 
      _myGroups.where((g) => g.isActive).toList();
  bool get isLoading => _isLoading;
  
  List<TempGroupMemberModel> getMembersOfGroup(String groupId) {
    return _groupMembers[groupId] ?? [];
  }

  // ============================================
  // ✅ 1. 그룹 생성
  // ============================================
  
  Future<TempGroupModel?> createGroup({
    required String userId,
    required String groupName,
    required String description,
    required int duration, // 7, 14, 21, 28
    required bool canExtend,
    int? maxMembers,
  }) async {
    try {
      debugPrint('');
      debugPrint('📱 ════════════════════ 그룹 생성 시작 ════════════════════');
      debugPrint('👤 생성자: $userId');
      debugPrint('📝 그룹명: $groupName');
      debugPrint('⏰ 기간: ${duration}일');
      
      final now = DateTime.now();
      final expiresAt = now.add(Duration(days: duration));
      
      final data = {
        'groupName': groupName,
        'description': description,
        'creatorId': userId,
        'createdAt': now.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'status': 'active',
        'duration': duration,
        'canExtend': canExtend,
        'maxMembers': maxMembers,
        'extensionCount': 0,
        'freeExtensionUsed': false,
        'memberCount': 1,
        'messageCount': 0,
        'lastActivityAt': now.toIso8601String(),
        'notification7days': false,
        'notification3days': false,
        'notification1day': false,
        'notificationExpired': false,
      };
      
      // 그룹 문서 생성
      final groupDoc = await _db.createDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupsCollectionId,
        documentId: ID.unique(),
        data: data,
        permissions: [
          Permission.read(Role.user(userId)),
          Permission.update(Role.user(userId)),
          Permission.delete(Role.user(userId)),
        ],
      );
      
      debugPrint('✅ 그룹 생성 완료: ${groupDoc.$id}');
      
      // 생성자를 멤버로 추가
      await _addMemberToGroup(
        groupId: groupDoc.$id,
        userId: userId,
        role: MemberRole.creator,
        invitedBy: null,
      );
      
      debugPrint('✅ 생성자 멤버 추가 완료');
      debugPrint('📱 ══════════════════════════════════════════════');
      debugPrint('');
      
      // 목록 새로고침
      await fetchMyGroups(userId);
      
      final group = TempGroupModel.fromMap(groupDoc.$id, groupDoc.data);
      return group;
      
    } catch (e) {
      debugPrint('❌ 그룹 생성 실패: $e');
      return null;
    }
  }
  
  // ============================================
  // ✅ 2. 내 그룹 목록 조회
  // ============================================
  
  Future<void> fetchMyGroups(String userId) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      debugPrint('');
      debugPrint('📋 ════════════════════ 내 그룹 조회 ════════════════════');
      debugPrint('👤 userId: $userId');
      
      // 내가 멤버로 있는 그룹 ID 조회
      final memberDocs = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupMembersCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.equal('status', 'active'),
        ],
      );
      
      final groupIds = memberDocs.documents
          .map((doc) => doc.data['groupId'] as String)
          .toList();
      
      debugPrint('📦 멤버로 있는 그룹: ${groupIds.length}개');
      
      if (groupIds.isEmpty) {
        _myGroups = [];
        debugPrint('ℹ️ 참여 중인 그룹 없음');
        debugPrint('📋 ══════════════════════════════════════════════');
        debugPrint('');
        return;
      }
      
      // 그룹 정보 조회
      final groupDocs = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupsCollectionId,
        queries: [
          Query.equal('\$id', groupIds),
          Query.orderDesc('lastActivityAt'),
        ],
      );
      
      _myGroups = groupDocs.documents
          .map((doc) => TempGroupModel.fromMap(doc.$id, doc.data))
          .toList();
      
      debugPrint('✅ 그룹 조회 완료: ${_myGroups.length}개');
      for (final group in _myGroups) {
        debugPrint('   - ${group.groupName} (${group.formattedRemainingTime})');
      }
      debugPrint('📋 ══════════════════════════════════════════════');
      debugPrint('');
      
    } catch (e) {
      debugPrint('❌ 그룹 조회 실패: $e');
      _myGroups = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // ============================================
  // ✅ 3. 그룹 멤버 조회
  // ============================================
  
  Future<void> fetchGroupMembers(String groupId) async {
    try {
      debugPrint('👥 그룹 멤버 조회: $groupId');
      
      final memberDocs = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupMembersCollectionId,
        queries: [
          Query.equal('groupId', groupId),
          Query.equal('status', 'active'),
          Query.orderDesc('role'), // creator, admin, member 순서
        ],
      );
      
      final members = memberDocs.documents
          .map((doc) => TempGroupMemberModel.fromMap(doc.$id, doc.data))
          .toList();
      
      _groupMembers[groupId] = members;
      
      debugPrint('✅ 멤버 조회 완료: ${members.length}명');
      notifyListeners();
      
    } catch (e) {
      debugPrint('❌ 멤버 조회 실패: $e');
      _groupMembers[groupId] = [];
    }
  }
  
  // ============================================
  // ✅ 4. 초대 링크 생성
  // ============================================
  
  Future<TempGroupInviteModel?> createInviteLink({
    required String groupId,
    required String userId,
    int? maxUses,
    int expiryHours = 24,
  }) async {
    try {
      debugPrint('');
      debugPrint('🔗 ════════════════════ 초대 링크 생성 ════════════════════');
      debugPrint('📦 그룹: $groupId');
      
      // 6자리 초대 코드 생성
      final inviteCode = _generateInviteCode();
      
      final now = DateTime.now();
      final expiresAt = now.add(Duration(hours: expiryHours));
      
      final data = {
        'groupId': groupId,
        'inviteCode': inviteCode,
        'createdBy': userId,
        'expiresAt': expiresAt.toIso8601String(),
        'maxUses': maxUses,
        'usedCount': 0,
        'status': 'active',
      };
      
      final inviteDoc = await _db.createDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupInvitesCollectionId,
        documentId: ID.unique(),
        data: data,
        permissions: [
          Permission.read(Role.any()), // 누구나 읽기 가능
          Permission.update(Role.user(userId)),
          Permission.delete(Role.user(userId)),
        ],
      );
      
      final invite = TempGroupInviteModel.fromMap(inviteDoc.$id, inviteDoc.data);
      
      debugPrint('✅ 초대 링크 생성 완료');
      debugPrint('🔑 초대 코드: $inviteCode');
      debugPrint('⏰ 만료: ${expiryHours}시간 후');
      debugPrint('🔗 ══════════════════════════════════════════════');
      debugPrint('');
      
      return invite;
      
    } catch (e) {
      debugPrint('❌ 초대 링크 생성 실패: $e');
      return null;
    }
  }
  
  // ============================================
  // ✅ 5. 초대 코드로 그룹 참여
  // ============================================
  
  Future<TempGroupModel?> joinGroupByInvite({
    required String inviteCode,
    required String userId,
  }) async {
    try {
      debugPrint('');
      debugPrint('🚪 ════════════════════ 그룹 참여 시작 ════════════════════');
      debugPrint('🔑 초대 코드: $inviteCode');
      debugPrint('👤 userId: $userId');
      
      // 1. 초대 코드로 초대 문서 조회
      final inviteDocs = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupInvitesCollectionId,
        queries: [
          Query.equal('inviteCode', inviteCode),
          Query.equal('status', 'active'),
        ],
      );
      
      if (inviteDocs.documents.isEmpty) {
        debugPrint('❌ 유효하지 않은 초대 코드');
        return null;
      }
      
      final inviteDoc = inviteDocs.documents.first;
      final invite = TempGroupInviteModel.fromMap(inviteDoc.$id, inviteDoc.data);
      
      // 2. 초대 유효성 검사
      if (!invite.isValid) {
        debugPrint('❌ 초대가 만료되었거나 사용 불가');
        return null;
      }
      
      // 3. 그룹 정보 조회
      final groupDoc = await _db.getDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupsCollectionId,
        documentId: invite.groupId,
      );
      
      final group = TempGroupModel.fromMap(groupDoc.$id, groupDoc.data);
      
      // 4. 그룹 참여 가능 여부 확인
      if (!group.canJoin) {
        debugPrint('❌ 그룹이 만료되었거나 인원이 가득 참');
        return null;
      }
      
      // 5. 이미 멤버인지 확인
      final existingMembers = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupMembersCollectionId,
        queries: [
          Query.equal('groupId', invite.groupId),
          Query.equal('userId', userId),
        ],
      );
      
      if (existingMembers.documents.isNotEmpty) {
        debugPrint('ℹ️ 이미 그룹 멤버입니다');
        return group;
      }
      
      // 6. 멤버 추가
      await _addMemberToGroup(
        groupId: invite.groupId,
        userId: userId,
        role: MemberRole.member,
        invitedBy: invite.createdBy,
      );
      
      // 7. 그룹 멤버 수 증가
      await _db.updateDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupsCollectionId,
        documentId: invite.groupId,
        data: {
          'memberCount': group.memberCount + 1,
          'lastActivityAt': DateTime.now().toIso8601String(),
        },
      );
      
      // 8. 초대 사용 횟수 증가
      await _db.updateDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupInvitesCollectionId,
        documentId: inviteDoc.$id,
        data: {
          'usedCount': invite.usedCount + 1,
        },
      );
      
      debugPrint('✅ 그룹 참여 완료');
      debugPrint('📦 그룹: ${group.groupName}');
      debugPrint('🚪 ══════════════════════════════════════════════');
      debugPrint('');
      
      // 목록 새로고침
      await fetchMyGroups(userId);
      
      return group;
      
    } catch (e) {
      debugPrint('❌ 그룹 참여 실패: $e');
      return null;
    }
  }
  
  // ============================================
  // ✅ 6. 그룹 나가기
  // ============================================
  
  Future<bool> leaveGroup({
    required String groupId,
    required String userId,
  }) async {
    try {
      debugPrint('🚪 그룹 나가기: $groupId');
      
      // 멤버 문서 조회
      final memberDocs = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupMembersCollectionId,
        queries: [
          Query.equal('groupId', groupId),
          Query.equal('userId', userId),
        ],
      );
      
      if (memberDocs.documents.isEmpty) {
        debugPrint('❌ 멤버가 아닙니다');
        return false;
      }
      
      final memberDoc = memberDocs.documents.first;
      final member = TempGroupMemberModel.fromMap(memberDoc.$id, memberDoc.data);
      
      // 생성자는 나갈 수 없음
      if (member.role == MemberRole.creator) {
        debugPrint('❌ 생성자는 나갈 수 없습니다');
        return false;
      }
      
      // 멤버 상태를 'left'로 변경
      await _db.updateDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupMembersCollectionId,
        documentId: memberDoc.$id,
        data: {
          'status': 'left',
        },
      );
      
      // 그룹 멤버 수 감소
      final groupDoc = await _db.getDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupsCollectionId,
        documentId: groupId,
      );
      
      final group = TempGroupModel.fromMap(groupDoc.$id, groupDoc.data);
      
      await _db.updateDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupsCollectionId,
        documentId: groupId,
        data: {
          'memberCount': group.memberCount - 1,
        },
      );
      
      debugPrint('✅ 그룹 나가기 완료');
      
      // 목록 새로고침
      await fetchMyGroups(userId);
      
      return true;
      
    } catch (e) {
      debugPrint('❌ 그룹 나가기 실패: $e');
      return false;
    }
  }
  
  // ============================================
  // ✅ 7. 그룹 삭제 (생성자만 가능)
  // ============================================
  
  Future<bool> deleteGroup({
    required String groupId,
    required String userId,
  }) async {
    try {
      debugPrint('');
      debugPrint('🗑️ ════════════════════ 그룹 삭제 시작 ════════════════════');
      debugPrint('📦 그룹: $groupId');
      
      // 그룹 조회
      final groupDoc = await _db.getDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupsCollectionId,
        documentId: groupId,
      );
      
      final group = TempGroupModel.fromMap(groupDoc.$id, groupDoc.data);
      
      // 생성자 확인
      if (group.creatorId != userId) {
        debugPrint('❌ 생성자만 삭제할 수 있습니다');
        return false;
      }
      
      // 그룹 상태를 'deleted'로 변경
      await _db.updateDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupsCollectionId,
        documentId: groupId,
        data: {
          'status': 'deleted',
        },
      );
      
      debugPrint('✅ 그룹 삭제 완료');
      debugPrint('🗑️ ══════════════════════════════════════════════');
      debugPrint('');
      
      // 목록 새로고침
      await fetchMyGroups(userId);
      
      return true;
      
    } catch (e) {
      debugPrint('❌ 그룹 삭제 실패: $e');
      return false;
    }
  }
  
  // ============================================
  // ✅ 8. Realtime 구독
  // ============================================
  
  void subscribeToGroups(String userId) {
    try {
      // 그룹 업데이트 구독
      final groupsChannel = 'databases.${AppwriteConstants.databaseId}'
          '.collections.${AppwriteConstants.tempGroupsCollectionId}.documents';
      
      _groupsSub = _realtime.subscribe([groupsChannel]);
      _groupsSub!.stream.listen((event) {
        debugPrint('🔔 [Realtime] 그룹 업데이트: ${event.events}');
        
        // 그룹 목록 새로고침
        fetchMyGroups(userId);
      });
      
      // 멤버 업데이트 구독
      final membersChannel = 'databases.${AppwriteConstants.databaseId}'
          '.collections.${AppwriteConstants.tempGroupMembersCollectionId}.documents';
      
      _membersSub = _realtime.subscribe([membersChannel]);
      _membersSub!.stream.listen((event) {
        debugPrint('🔔 [Realtime] 멤버 업데이트: ${event.events}');
        
        // 관련 그룹의 멤버 목록 새로고침
        try {
          final payload = event.payload;
          final groupId = payload['groupId'] as String?;
          if (groupId != null) {
            fetchGroupMembers(groupId);
          }
        } catch (e) {
          debugPrint('⚠️ [Realtime] 멤버 업데이트 처리 실패: $e');
        }
      });
      
      debugPrint('✅ [Realtime] 그룹 & 멤버 구독 시작');
      
    } catch (e) {
      debugPrint('❌ [Realtime] 구독 실패: $e');
    }
  }
  
  // ============================================
  // ✅ 9. 헬퍼 메서드
  // ============================================
  
  // 멤버 추가 (내부용)
  Future<void> _addMemberToGroup({
    required String groupId,
    required String userId,
    required MemberRole role,
    String? invitedBy,
  }) async {
    final now = DateTime.now();
    
    final data = {
      'groupId': groupId,
      'userId': userId,
      'role': role.name,
      'status': 'active',
      'invitedBy': invitedBy,
      'invitedAt': now.toIso8601String(),
      'joinedAt': now.toIso8601String(),
      'lastReadAt': null,
      'unreadCount': 0,
      'mutedUntil': null,
    };
    
    await _db.createDocument(
      databaseId: AppwriteConstants.databaseId,
      collectionId: AppwriteConstants.tempGroupMembersCollectionId,
      documentId: ID.unique(),
      data: data,
      permissions: [
        Permission.read(Role.user(userId)),
        Permission.update(Role.user(userId)),
      ],
    );
  }
  
  // 6자리 초대 코드 생성
  String _generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(6, (index) => chars[random.nextInt(chars.length)])
        .join();
  }
  
  // 특정 그룹 조회
  TempGroupModel? getGroupById(String groupId) {
    try {
      return _myGroups.firstWhere((g) => g.id == groupId);
    } catch (e) {
      return null;
    }
  }
  
  // 내가 생성자인 그룹
  List<TempGroupModel> get myCreatedGroups {
    // creatorId는 현재 로그인한 유저 ID와 비교해야 하지만
    // 여기서는 간단히 role이 creator인 그룹만 필터링
    return _myGroups;
  }
  
  @override
  void dispose() {
    _groupsSub?.close();
    _membersSub?.close();
    super.dispose();
  }
}