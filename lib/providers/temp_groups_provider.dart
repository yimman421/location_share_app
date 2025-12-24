// lib/providers/temp_groups_provider.dart

import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';
import 'dart:math';
import '../models/temp_group_model.dart';
import '../models/temp_group_message_model.dart';
import '../constants/appwrite_config.dart';
import '../appwriteClient.dart';

class TempGroupsProvider with ChangeNotifier {
  final Databases _db = appwriteDB;
  //final Account _account = appwriteAccount;
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
    // ✅✅✅ build 중에 notifyListeners 호출 방지
    _isLoading = true;
    // notifyListeners(); ← 여기서는 호출하지 않음!
    
    try {
      debugPrint('📋 ════════════════════ 내 그룹 조회 ════════════════════');
      debugPrint('👤 userId: $userId');
      
      // 1. 내가 멤버인 그룹 ID 조회
      final memberDocs = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupMembersCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.equal('status', 'active'),
        ],
      );
      
      debugPrint('📦 멤버로 있는 그룹: ${memberDocs.documents.length}개');
      
      if (memberDocs.documents.isEmpty) {
        _myGroups = [];
        _isLoading = false;
        notifyListeners(); // ✅ 여기서는 안전
        debugPrint('ℹ️ 참여 중인 그룹 없음');
        return;
      }
      
      // 2. 그룹 ID 추출
      final groupIds = memberDocs.documents
          .map((doc) => doc.data['groupId'] as String)
          .toList();
      
      // 3. 그룹 정보 조회
      final groupDocs = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupsCollectionId,
        queries: [
          Query.equal('\$id', groupIds),
          Query.orderDesc('lastActivityAt'),
        ],
      );
      
      // 4. 모델 변환
      _myGroups = groupDocs.documents
          .map((doc) => TempGroupModel.fromMap(doc.$id, doc.data))
          .toList();
      
      _isLoading = false;
      notifyListeners(); // ✅ 여기서 호출
      
      debugPrint('✅ 그룹 조회 완료: ${_myGroups.length}개');
      
    } catch (e) {
      debugPrint('❌ 그룹 조회 실패: $e');
      _myGroups = [];
      _isLoading = false;
      notifyListeners(); // ✅ 에러 시에도 호출
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
      debugPrint('');
      debugPrint('📋 Step 1: 초대 코드 조회 중...');
      
      final inviteDocs = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupInvitesCollectionId,
        queries: [
          Query.equal('inviteCode', inviteCode),
        ],
      );
      
      debugPrint('📦 조회된 초대 문서 수: ${inviteDocs.documents.length}');
      
      if (inviteDocs.documents.isEmpty) {
        debugPrint('❌ 초대 코드를 찾을 수 없음: $inviteCode');
        debugPrint('');
        debugPrint('🔍 디버깅 정보:');
        debugPrint('   - Database: ${AppwriteConstants.databaseId}');
        debugPrint('   - Collection: ${AppwriteConstants.tempGroupInvitesCollectionId}');
        debugPrint('   - 입력한 코드: $inviteCode');
        debugPrint('');
        return null;
      }
      
      final inviteDoc = inviteDocs.documents.first;
      final invite = TempGroupInviteModel.fromMap(inviteDoc.$id, inviteDoc.data);
      
      debugPrint('✅ 초대 문서 발견!');
      debugPrint('   - ID: ${invite.id}');
      debugPrint('   - 그룹 ID: ${invite.groupId}');
      debugPrint('   - 상태: ${invite.status.name}');
      debugPrint('   - 만료일: ${invite.expiresAt}');
      debugPrint('   - 사용 횟수: ${invite.usedCount}/${invite.maxUses ?? "무제한"}');
      
      // 2. 초대 유효성 검사
      debugPrint('');
      debugPrint('📋 Step 2: 초대 유효성 검사 중...');
      
      if (!invite.isValid) {
        debugPrint('❌ 초대가 유효하지 않음');
        debugPrint('   - status: ${invite.status.name}');
        debugPrint('   - isExpired: ${invite.isExpired}');
        debugPrint('   - isMaxedOut: ${invite.isMaxedOut}');
        debugPrint('');
        return null;
      }
      
      debugPrint('✅ 초대 유효함');
      
      // 3. 그룹 정보 조회
      debugPrint('');
      debugPrint('📋 Step 3: 그룹 정보 조회 중...');
      
      final groupDoc = await _db.getDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupsCollectionId,
        documentId: invite.groupId,
      );
      
      final group = TempGroupModel.fromMap(groupDoc.$id, groupDoc.data);
      
      debugPrint('✅ 그룹 발견!');
      debugPrint('   - 이름: ${group.groupName}');
      debugPrint('   - 상태: ${group.status.name}');
      debugPrint('   - 멤버 수: ${group.memberCount}/${group.maxMembers ?? "무제한"}');
      debugPrint('   - 만료일: ${group.expiresAt}');
      
      // 4. 그룹 참여 가능 여부 확인
      debugPrint('');
      debugPrint('📋 Step 4: 그룹 참여 가능 여부 확인 중...');
      
      if (!group.canJoin) {
        debugPrint('❌ 그룹 참여 불가');
        debugPrint('   - isActive: ${group.isActive}');
        debugPrint('   - isFull: ${group.isFull}');
        debugPrint('');
        return null;
      }
      
      debugPrint('✅ 그룹 참여 가능');
      
      // ✅✅✅ Step 5: 멤버 중복 확인 (status 확인 추가)
      debugPrint('');
      debugPrint('📋 Step 5: 멤버 중복 확인 중...');
      
      final existingMembers = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupMembersCollectionId,
        queries: [
          Query.equal('groupId', invite.groupId),
          Query.equal('userId', userId),
        ],
      );
      
      debugPrint('📦 기존 멤버 문서 수: ${existingMembers.documents.length}');
      
      if (existingMembers.documents.isNotEmpty) {
        final existingMember = existingMembers.documents.first;
        final memberStatus = existingMember.data['status'] as String?;
        
        debugPrint('📊 기존 멤버 상태: $memberStatus');
        
        if (memberStatus == 'active') {
          // ✅ 이미 활성 멤버
          debugPrint('ℹ️ 이미 그룹 멤버입니다');
          debugPrint('✅ 그룹 참여 완료 (기존 멤버)');
          debugPrint('🚪 ══════════════════════════════════════════════');
          debugPrint('');
          return group;
        } else if (memberStatus == 'left') {
          // ✅✅✅ 나간 멤버 → 재참여 처리
          debugPrint('🔄 나간 멤버 재참여 처리 중...');
          
          // Step 5-1: status를 active로 변경
          await _db.updateDocument(
            databaseId: AppwriteConstants.databaseId,
            collectionId: AppwriteConstants.tempGroupMembersCollectionId,
            documentId: existingMember.$id,
            data: {
              'status': 'active',
              'joinedAt': DateTime.now().toIso8601String(),
            },
          );
          
          debugPrint('✅ 멤버 상태 업데이트 완료: left → active');
          
          // Step 5-2: 그룹 멤버 수 증가
          debugPrint('📋 Step 5-2: 그룹 멤버 수 업데이트 중...');
          await _db.updateDocument(
            databaseId: AppwriteConstants.databaseId,
            collectionId: AppwriteConstants.tempGroupsCollectionId,
            documentId: groupDoc.$id,
            data: {
              'memberCount': group.memberCount + 1,
              'lastActivityAt': DateTime.now().toIso8601String(),
            },
          );
          
          debugPrint('✅ 멤버 수 업데이트 완료: ${group.memberCount} → ${group.memberCount + 1}');
          
          // ✅✅✅ 재참여 시스템 메시지
          await _sendSystemMessage(
            groupId: invite.groupId,
            message: SystemMessageHelper.memberRejoined(userId),
          );
          
          debugPrint('✅ 재참여 완료');
          debugPrint('🚪 ══════════════════════════════════════════════');
          debugPrint('');
          
          await fetchMyGroups(userId);
          return group;
        }
      }
      
      // ✅ 새로운 멤버 추가
      debugPrint('✅ 새로운 멤버');
      
      // 6. 멤버 추가
      debugPrint('');
      debugPrint('📋 Step 6: 멤버 추가 중...');
      
      await _addMemberToGroup(
        groupId: invite.groupId,
        userId: userId,
        role: MemberRole.member,
        invitedBy: invite.createdBy,
      );
      
      debugPrint('✅ 멤버 추가 완료');
      
      // 7. 그룹 멤버 수 증가
      debugPrint('');
      debugPrint('📋 Step 7: 그룹 멤버 수 업데이트 중...');
      
      await _db.updateDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupsCollectionId,
        documentId: invite.groupId,
        data: {
          'memberCount': group.memberCount + 1,
          'lastActivityAt': DateTime.now().toIso8601String(),
        },
      );
      
      debugPrint('✅ 멤버 수 업데이트 완료: ${group.memberCount} → ${group.memberCount + 1}');
      
      // 8. 초대 사용 횟수 증가
      // ✅✅✅ 입장 시스템 메시지
      await _sendSystemMessage(
        groupId: invite.groupId,
        message: SystemMessageHelper.memberJoined(userId),
      );
      debugPrint('');
      debugPrint('📋 Step 8: 초대 사용 횟수 업데이트 중...');
      try {
        await _db.updateDocument(
          databaseId: AppwriteConstants.databaseId,
          collectionId: AppwriteConstants.tempGroupInvitesCollectionId,
          documentId: inviteDoc.$id,
          data: {
            'usedCount': (inviteDoc.data['usedCount'] as int? ?? 0) + 1,
          },
        );
        debugPrint('✅ 초대 사용 횟수 업데이트 완료');
      } catch (e) {
        // ✅ 권한 없어도 무시 (멤버 추가는 이미 완료됨)
        debugPrint('⚠️ 초대 사용 횟수 업데이트 실패 (무시): $e');
      }
      
      debugPrint('');
      debugPrint('✅ 그룹 참여 완료');
      debugPrint('📦 그룹: ${group.groupName}');
      debugPrint('🚪 ══════════════════════════════════════════════');
      debugPrint('');
      
      // 목록 새로고침
      await fetchMyGroups(userId);
      
      return group;
      
    } catch (e, stackTrace) {
      debugPrint('');
      debugPrint('❌ ═══════════════ 그룹 참여 에러 ═══════════════');
      debugPrint('🔴 에러: $e');
      debugPrint('📍 Stack Trace:');
      debugPrint('$stackTrace');
      debugPrint('❌ ═══════════════════════════════════════════════');
      debugPrint('');
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
      
      // ✅✅✅ 퇴장 시스템 메시지
      await _sendSystemMessage(
        groupId: groupId,
        message: SystemMessageHelper.memberLeft(userId),
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

  // ✅✅✅ 시스템 메시지 전송
  Future<void> _sendSystemMessage({
    required String groupId,
    required Map<String, dynamic> message,
  }) async {
    try {
      await _db.createDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.tempGroupMessagesCollectionId,
        documentId: ID.unique(),
        data: {
          'groupId': groupId,
          'userId': 'system',
          'message': message['message'],
          'type': message['type'],
          'isDeleted': false,
          'replyTo': null,
        },
      );
      
      debugPrint('✅ 시스템 메시지 전송 완료');
    } catch (e) {
      debugPrint('⚠️ 시스템 메시지 전송 실패 (무시): $e');
    }
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
    return _myGroups;
  }
  
  @override
  void dispose() {
    _groupsSub?.close();
    _membersSub?.close();
    super.dispose();
  }
}