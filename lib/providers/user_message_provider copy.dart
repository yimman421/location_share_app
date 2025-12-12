// lib/providers/user_message_provider.dart - 수락 상태 추적 기능 추가

import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';
import '../models/shop_models.dart';
import '../appwriteClient.dart';
import '../constants/appwrite_config.dart';
import '../constants/shop_constants.dart';
import 'dart:async';
import 'dart:math';

class UserMessageProvider with ChangeNotifier {
  final Databases _db = appwriteDB;
  
  List<ShopMessageModel> _receivedMessages = [];
  List<ShopMessageModel> get receivedMessages => _receivedMessages;
  
  List<ShopMessageModel> _activeMessages = [];
  List<ShopMessageModel> get activeMessages => _activeMessages;

  // ✅ 새로 추가: 수락된 메시지 ID
  Set<String> _acceptedMessageIds = {};
  Set<String> get acceptedMessageIds => _acceptedMessageIds;
  
  // ✅ 새로 추가: 무시된 메시지 ID
  Set<String> _dismissedMessageIds = {};
  Set<String> get dismissedMessageIds => _dismissedMessageIds;

  // ✅ 수락된 메시지 목록 (탭에서 표시할 용도)
  List<ShopMessageModel> _acceptedMessages = [];
  List<ShopMessageModel> get acceptedMessages => _acceptedMessages;

  Map<String, ShopModel> _shopsCache = {};
  
  Timer? _messageCheckTimer;
  Timer? _expirationTimer;
  
  String? _currentUserId;
  double? _currentLat;
  double? _currentLng;
  
  // 필터 설정
  Set<String> _categoryFilter = {};
  int _maxRadius = 50000; // ✅ 최대 50km로 변경 (테스트용)
  
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  // ✅ 1. 초기화
  void initialize(String userId, double lat, double lng) {
    _currentUserId = userId;
    _currentLat = lat;
    _currentLng = lng;
    
    debugPrint('🔧 UserMessageProvider 초기화');
    debugPrint('   userId: $userId');
    debugPrint('   위치: ($lat, $lng)');

    // ✅ 이전에 무시한 메시지 복원
    _loadDismissedMessages();
    
    // ✅ 이전에 수락한 메시지 복원
    _loadAcceptedMessages();

    startMessageCheck();
    startExpirationCheck();
    
    // ✅ 초기화 직후 즉시 메시지 체크
    Future.delayed(const Duration(milliseconds: 500), () {
      debugPrint('🔄 초기화 후 첫 메시지 체크...');
      _checkMessagesInRange();
    });
    
    debugPrint('✅ UserMessageProvider 초기화 완료');
  }

  // ✅ 무시한 메시지 복원
  Future<void> _loadDismissedMessages() async {
    if (_currentUserId == null) return;
    
    try {
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.messageAcceptancesCollectionId,
        queries: [
          Query.equal('userId', _currentUserId!),
          Query.equal('dismissed', true),
        ],
      );
      
      for (final doc in result.documents) {
        _dismissedMessageIds.add(doc.data['messageId']);
      }
      
      if (_dismissedMessageIds.isNotEmpty) {
        debugPrint('✅ 무시한 메시지 ${_dismissedMessageIds.length}개 복원');
      }
    } catch (e) {
      debugPrint('⚠️ 무시한 메시지 복원 실패: $e');
    }
  }

  // ✅ 수락한 메시지 복원
  Future<void> _loadAcceptedMessages() async {
    if (_currentUserId == null) return;
    
    try {
      debugPrint('🔄 수락한 메시지 복원 시작');
      
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.messageAcceptancesCollectionId,
        queries: [
          Query.equal('userId', _currentUserId!),
          Query.notEqual('dismissed', true), // ✅ dismissed가 true인 것 제외
        ],
      );
      
      debugPrint('📦 조회된 수락 기록: ${result.documents.length}개');
      
      final acceptedMessageIds = <String>{};
      final acceptedMessages = <ShopMessageModel>[];
      
      for (final doc in result.documents) {
        final messageId = doc.data['messageId'];
        final isDismissed = doc.data['dismissed'] ?? false;
        
        if (!isDismissed) {
          _acceptedMessageIds.add(messageId);
          acceptedMessageIds.add(messageId);
        }
      }
      
      // ✅ 수락된 메시지의 실제 정보도 로드
      if (acceptedMessageIds.isNotEmpty) {
        final allMessagesResult = await _db.listDocuments(
          databaseId: AppwriteConstants.databaseId,
          collectionId: ShopConstants.shopMessagesCollectionId,
          queries: [
            Query.limit(100),
          ],
        );
        
        for (final doc in allMessagesResult.documents) {
          if (acceptedMessageIds.contains(doc.$id)) {
            acceptedMessages.add(
              ShopMessageModel.fromJson(doc.data, doc.$id),
            );
          }
        }
      }
      
      _acceptedMessages = acceptedMessages;
      
      if (_acceptedMessageIds.isNotEmpty) {
        debugPrint('✅ 수락한 메시지 ${_acceptedMessageIds.length}개 복원 완료');
      }
    } catch (e) {
      debugPrint('⚠️  수락한 메시지 복원 실패: $e');
    }
  }

  // ✅ 2. 위치 업데이트
  void updateLocation(double lat, double lng) {
    _currentLat = lat;
    _currentLng = lng;
    
    debugPrint('📍 위치 업데이트: ($lat, $lng)');
    
    // 위치 변경 시 메시지 재확인
    _checkMessagesInRange();
  }
  
  // ✅ 3. 주기적 메시지 체크 (5초마다)
  void startMessageCheck() {
    _messageCheckTimer?.cancel();
    
    _messageCheckTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkMessagesInRange(),
    );
    
    // 초기 실행
    _checkMessagesInRange();
  }
  
  // ✅ 4. 만료 메시지 체크 (1분마다)
  void startExpirationCheck() {
    _expirationTimer?.cancel();
    
    _expirationTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _removeExpiredMessages(),
    );
  }
  
  // ✅ 5. 반경 내 메시지 확인 - 수락/무시된 메시지 제외
  Future<void> _checkMessagesInRange() async {
    if (_currentLat == null || _currentLng == null || _currentUserId == null) {
      debugPrint('⚠️  위치 정보 없음');
      return;
    }
    
    try {
      final now = DateTime.now();
      
      debugPrint('');
      debugPrint('🔍 ════════════════════ 메시지 체크 시작 ════════════════════');
      debugPrint('⏰ 현재 시간: ${now.toIso8601String()}');
      debugPrint('📍 현재 위치: ($_currentLat, $_currentLng)');
      debugPrint('👤 사용자 ID: $_currentUserId');
      debugPrint('📊 수락된 메시지: ${_acceptedMessageIds.length}개');
      debugPrint('📊 무시된 메시지: ${_dismissedMessageIds.length}개');
      
      // 활성화된 메시지만 가져오기
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.shopMessagesCollectionId,
        queries: [
          Query.greaterThan('expiresAt', now.toIso8601String()),
          Query.orderDesc('createdAt'),
          Query.limit(100),
        ],
      );
      
      debugPrint('📥 DB에서 활성 메시지 ${result.documents.length}개 조회');
      
      final allMessages = result.documents
          .map((doc) => ShopMessageModel.fromJson(doc.data, doc.$id))
          .toList();
      
      final inRangeMessages = <ShopMessageModel>[];
      
      for (final msg in allMessages) {
        // ✅ 수락된 메시지는 제외
        if (_acceptedMessageIds.contains(msg.messageId)) {
          //debugPrint('⏭️  수락됨 제외: "${msg.message}"');
          continue;
        }
        
        // ✅ 무시된 메시지는 제외
        if (_dismissedMessageIds.contains(msg.messageId)) {
          debugPrint('⏭️  무시됨 제외: "${msg.message}"');
          continue;
        }
        
        debugPrint('🔎 메시지 검사: "${msg.message}"');
        
        // 샵 정보 가져오기
        final shop = await _getShop(msg.shopId);
        if (shop == null) {
          debugPrint('   ❌ 샵 정보 없음');
          continue;
        }
        
        //debugPrint('   ✅ 샵: ${shop.shopName}');
        
        // 거리 계산
        final distance = _calculateDistance(
          _currentLat!,
          _currentLng!,
          shop.lat,
          shop.lng,
        );
        
        debugPrint('   📏 거리: ${distance.toStringAsFixed(1)}m / 반경: ${msg.radius}m');
        
        // 반경 체크
        if (distance > msg.radius) {
          debugPrint('   ❌ 반경 초과');
          continue;
        }
        
        if (distance > _maxRadius) {
          debugPrint('   ❌ 최대 반경 초과');
          continue;
        }
        
        //debugPrint('   ✅ 반경 내!');
        
        // 카테고리 필터
        if (_categoryFilter.isNotEmpty) {
          final categoryOk = _categoryFilter.contains(shop.category);
          debugPrint('   카테고리: ${shop.category} - ${categoryOk ? '✅' : '❌'}');
          if (!categoryOk) continue;
        }
        
        debugPrint('   ✨ 수신 메시지 추가!');
        inRangeMessages.add(msg);
      }
      
      debugPrint('');
      debugPrint('📊 최종 결과:');
      debugPrint('   총 조회: ${allMessages.length}개');
      debugPrint('   반경 내: ${inRangeMessages.length}개');
      debugPrint('   활성: ${_activeMessages.length}개');
      
      // ✅ 새 메시지 확인 + 기존 메시지 제거 감지
      final newMessages = inRangeMessages.where((msg) {
        return !_receivedMessages.any((m) => m.messageId == msg.messageId);
      }).toList();
      
      final removedMessages = _receivedMessages.where((msg) {
        return !inRangeMessages.any((m) => m.messageId == msg.messageId);
      }).toList();
      
      if (newMessages.isNotEmpty) {
        debugPrint('');
        debugPrint('🔔 새 메시지 ${newMessages.length}개 수신!');
        _receivedMessages.addAll(newMessages);
      }
      
      if (removedMessages.isNotEmpty) {
        debugPrint('🗑️  제거된 메시지 ${removedMessages.length}개');
      }
      
      // ✅ 활성 메시지 업데이트 (이전 것과 다르면)
      if (inRangeMessages.length != _activeMessages.length ||
          !inRangeMessages.every((msg) => _activeMessages.any((m) => m.messageId == msg.messageId))) {
        _activeMessages = inRangeMessages;
        debugPrint('✨ 활성 메시지 목록 업데이트!');
        notifyListeners(); // ✅ UI 업데이트
      }
      
      debugPrint('🔍 ════════════════════ 메시지 체크 종료 ════════════════════');
      debugPrint('');
      
    } catch (e) {
      debugPrint('❌ 메시지 확인 실패: $e');
    }
  }
  
  // ✅ 6. 메시지 수락 - 개선 버전
  Future<bool> acceptMessage(
    ShopMessageModel message,
    double userLat,
    double userLng,
  ) async {
    if (_currentUserId == null) {
      debugPrint('❌ _currentUserId가 null입니다');
      return false;
    }
    
    try {
      debugPrint('');
      debugPrint('✅ ════════════════════ acceptMessage 시작 ════════════════════');
      debugPrint('📌 메시지 ID: ${message.messageId}');
      debugPrint('📌 메시지: "${message.message}"');
      debugPrint('👤 현재 사용자: $_currentUserId');
      
      // ✅ Step 1: 이미 수락했는지 확인
      debugPrint('⏳ Step 1: 중복 수락 확인 중...');
      if (_acceptedMessageIds.contains(message.messageId)) {
        debugPrint('⚠️  이미 수락한 메시지입니다');
        return true; // 이미 수락했으면 true 반환
      }
      debugPrint('✅ Step 1: 새로운 메시지입니다');
      
      // ✅ Step 2: DB에 수락 기록 저장
      debugPrint('⏳ Step 2: DB에 수락 기록 저장 중...');
      
      final acceptanceData = {
        'messageId': message.messageId,
        'userId': _currentUserId!,
        'acceptedAt': DateTime.now().toIso8601String(),
        'userLat': userLat,
        'userLng': userLng,
        'dismissed': false, // ✅ 명시적으로 false 설정
      };
      
      debugPrint('📦 저장 데이터: $acceptanceData');
      
      final docId = ID.unique();
      await _db.createDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.messageAcceptancesCollectionId,
        documentId: docId,
        data: acceptanceData,
      );
      
      debugPrint('✅ Step 2: 수락 기록 저장 완료 (docId: $docId)');
      
      // ✅ Step 3: 메시지 수락 카운트 증가
      debugPrint('⏳ Step 3: 수락 카운트 업데이트 중...');
      try {
        await _db.updateDocument(
          databaseId: AppwriteConstants.databaseId,
          collectionId: ShopConstants.shopMessagesCollectionId,
          documentId: message.messageId,
          data: {
            'acceptCount': (message.acceptCount) + 1,
          },
        );
        debugPrint('✅ Step 3: 수락 카운트 업데이트 완료 (${(message.acceptCount) + 1})');
      } catch (e) {
        debugPrint('⚠️  카운트 업데이트 실패 (무시해도 괜찮음): $e');
      }
      
      // ✅ Step 4: 메모리에 수락 메시지 추가
      debugPrint('⏳ Step 4: 메모리 상태 업데이트 중...');
      _acceptedMessageIds.add(message.messageId);
      _acceptedMessages.add(message);
      debugPrint('✅ Step 4-1: 수락된 메시지 ID 추가 (총 ${_acceptedMessageIds.length}개)');
      
      // ✅ Step 5: 활성 목록에서 제거
      debugPrint('⏳ Step 5: 활성 목록에서 제거 중...');
      
      final beforeCount = _receivedMessages.length;
      _receivedMessages.removeWhere((m) => m.messageId == message.messageId);
      final afterReceived = _receivedMessages.length;
      debugPrint('✅ Step 5-1: receivedMessages 제거 (${beforeCount} → ${afterReceived})');
      
      final beforeActive = _activeMessages.length;
      _activeMessages.removeWhere((m) => m.messageId == message.messageId);
      final afterActive = _activeMessages.length;
      debugPrint('✅ Step 5-2: activeMessages 제거 (${beforeActive} → ${afterActive})');
      
      // ✅ Step 6: UI 업데이트 콜 (중요!)
      debugPrint('⏳ Step 6: notifyListeners() 호출 중...');
      notifyListeners();
      debugPrint('✅ Step 6: UI 업데이트 완료');
      
      debugPrint('✅ ════════════════════ acceptMessage 완료 ════════════════════');
      debugPrint('');
      
      return true;
      
    } catch (e, stack) {
      debugPrint('❌ acceptMessage 실패: $e');
      debugPrint('Stack Trace: $stack');
      debugPrint('✅ ════════════════════ acceptMessage 실패 ════════════════════');
      debugPrint('');
      return false;
    }
  }
  
  Future<void> dismissMessage(String messageId) async {
  if (_currentUserId == null) return;

    debugPrint('');
    debugPrint('🗑️ ════════════════════ 메시지 무시 ════════════════════');
    debugPrint('📌 messageId: $messageId');
    
    try {
      // ✅ 무시된 메시지를 새 컬렉션에 저장 (선택사항)
      // 또는 기존 메시지에 '무시' 상태 마크
      
      // 방법 1: messageAcceptances 컬렉션에 dismissed=true로 저장
      await _db.createDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.messageAcceptancesCollectionId,
        documentId: ID.unique(),
        data: {
          'messageId': messageId,
          'userId': _currentUserId!,
          'dismissed': true,
          'dismissedAt': DateTime.now().toIso8601String(),
        },
      );
      
      debugPrint('✅ 무시한 메시지를 DB에 저장 완료');
      
      // ✅ 로컬 메모리에도 저장
      _dismissedMessageIds.add(messageId);
      debugPrint('✅ 무시된 메시지 목록에 추가');
      
      _receivedMessages.removeWhere((m) => m.messageId == messageId);
      _activeMessages.removeWhere((m) => m.messageId == messageId);
      _acceptedMessages.removeWhere((m) => m.messageId == messageId);
      
      debugPrint('✅ 활성 목록에서 제거');
      
      notifyListeners();
      
      debugPrint('🗑️ ════════════════════ 메시지 무시 완료 ════════════════════');
      debugPrint('');
      
    } catch (e) {
      debugPrint('❌ 무시 저장 실패: $e');
    }
  }
  
  // ✅ 8. 만료된 메시지 제거
  void _removeExpiredMessages() {
    final now = DateTime.now();
    
    final before = _receivedMessages.length;
    
    _receivedMessages.removeWhere((msg) => now.isAfter(msg.expiresAt));
    _activeMessages.removeWhere((msg) => now.isAfter(msg.expiresAt));
    _acceptedMessages.removeWhere((msg) => now.isAfter(msg.expiresAt));
    
    final after = _receivedMessages.length;
    
    if (before != after) {
      debugPrint('🗑️  만료 메시지 ${before - after}개 제거');
      notifyListeners();
    }
  }
  
  // ✅ 9. 샵 정보 가져오기 (캐시 사용)
  Future<ShopModel?> _getShop(String shopId) async {
    if (_shopsCache.containsKey(shopId)) {
      return _shopsCache[shopId];
    }
    
    try {
      final doc = await _db.getDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.shopsCollectionId,
        documentId: shopId,
      );
      
      final shop = ShopModel.fromJson(doc.data, doc.$id);
      _shopsCache[shopId] = shop;
      
      return shop;
      
    } catch (e) {
      debugPrint('❌ 샵 정보 로드 실패 ($shopId): $e');
      return null;
    }
  }
  
  // ✅ 10. 샵 정보 가져오기 (public)
  Future<ShopModel?> getShop(String shopId) async {
    return _getShop(shopId);
  }

  // ✅ 12. 거리 계산
  double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371000; // 미터
    
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }
  
  double _toRadians(double degree) {
    return degree * pi / 180;
  }
  
  // ✅ 13. 필터 설정
  void setCategoryFilter(Set<String> categories) {
    _categoryFilter = categories;
    _checkMessagesInRange();
    notifyListeners();
  }
  
  void setMaxRadius(int radius) {
    _maxRadius = radius;
    _checkMessagesInRange();
    notifyListeners();
  }
  
  // ✅ 15. 강제 메시지 조회 (수동 새로고침)
  Future<void> forceRefresh() async {
    debugPrint('');
    debugPrint('🔄 ════════════════════ 강제 메시지 새로고침 ════════════════════');
    debugPrint('✅ 수락된 메시지: ${_acceptedMessageIds.length}개');
    debugPrint('✅ 무시된 메시지: ${_dismissedMessageIds.length}개');
    await _checkMessagesInRange();
    debugPrint('🔄 ════════════════════ 새로고침 완료 ════════════════════');
    debugPrint('');
  }
  
  // ✅ 14. 초기화
  void reset() {
    _messageCheckTimer?.cancel();
    _expirationTimer?.cancel();
    
    _receivedMessages = [];
    _activeMessages = [];
    _acceptedMessages = [];
    _shopsCache = {};
    _acceptedMessageIds = {};
    _dismissedMessageIds = {};
    _currentUserId = null;
    _currentLat = null;
    _currentLng = null;
    
    notifyListeners();
  }
  
  @override
  void dispose() {
    _messageCheckTimer?.cancel();
    _expirationTimer?.cancel();
    super.dispose();
  }
}