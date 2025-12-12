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

  Set<String> _acceptedMessageIds = {};
  Set<String> get acceptedMessageIds => _acceptedMessageIds;
  
  Set<String> _dismissedMessageIds = {};
  Set<String> get dismissedMessageIds => _dismissedMessageIds;

  // ✅ 수락된 메시지 실제 데이터 (탭에 표시할 용도)
  List<ShopMessageModel> _acceptedMessages = [];
  List<ShopMessageModel> get acceptedMessages => _acceptedMessages;

  // ✅ 무시된 메시지 실제 데이터 (탭에 표시할 용도)
  List<ShopMessageModel> _dismissedMessages = [];
  List<ShopMessageModel> get dismissedMessages => _dismissedMessages;

  Map<String, ShopModel> _shopsCache = {};
  
  Timer? _messageCheckTimer;
  Timer? _expirationTimer;
  
  String? _currentUserId;
  double? _currentLat;
  double? _currentLng;
  
  Set<String> _categoryFilter = {};
  int _maxRadius = 50000;
  
  final bool _isLoading = false;
  bool get isLoading => _isLoading;

  // ✅ 1. 초기화
  void initialize(String userId, double lat, double lng) {
    _currentUserId = userId;
    _currentLat = lat;
    _currentLng = lng;
    
    debugPrint('🔧 UserMessageProvider 초기화');
    debugPrint('   userId: $userId');
    debugPrint('   위치: ($lat, $lng)');

    _loadDismissedMessages();
    _loadAcceptedMessages();

    startMessageCheck();
    startExpirationCheck();
    
    Future.delayed(const Duration(milliseconds: 500), () {
      debugPrint('🔄 초기화 후 첫 메시지 체크...');
      _checkMessagesInRange();
    });
    
    debugPrint('✅ UserMessageProvider 초기화 완료');
  }

  // ✅ 무시한 메시지 로드 (만료되지 않은 메시지만)
  Future<void> _loadDismissedMessages() async {
    if (_currentUserId == null) return;
    
    try {
      debugPrint('');
      debugPrint('🔄 ════════════════════ 무시한 메시지 복원 시작 ════════════════════');
      
      // ignore: deprecated_member_use
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.messageAcceptancesCollectionId,
        queries: [
          Query.equal('userId', _currentUserId!),
          Query.equal('status', 'dismissed'), // ✅ 명확한 쿼리
          Query.orderDesc('dismissedAt'), // ✅ 최신순 정렬
        ],
      );
      
      debugPrint('📦 조회된 무시 기록: ${result.documents.length}개');
      
      _dismissedMessageIds.clear(); // ✅ 먼저 초기화
      final dismissedIds = <String>{};
      
      for (final doc in result.documents) {
        final msgId = doc.data['messageId'];
        _dismissedMessageIds.add(msgId);
        dismissedIds.add(msgId);
        debugPrint('   ✅ 무시 ID: $msgId');
      }
      
      debugPrint('✅ 무시한 메시지 ${_dismissedMessageIds.length}개 복원');
      
      // ✅ 무시된 메시지 상세 정보도 로드 (만료되지 않은 것만)
      _dismissedMessages.clear();
      
      if (dismissedIds.isNotEmpty) {
        debugPrint('');
        debugPrint('📥 무시된 메시지 상세 정보 로드 중...');
        
        final now = DateTime.now();
        
        // ignore: deprecated_member_use
        final messagesResult = await _db.listDocuments(
          databaseId: AppwriteConstants.databaseId,
          collectionId: ShopConstants.shopMessagesCollectionId,
          queries: [
            Query.greaterThan('expiresAt', now.toIso8601String()), // ✅ 만료 안 된 것만
            Query.limit(100),
          ],
        );
        
        debugPrint('📥 DB에서 활성 메시지 ${messagesResult.documents.length}개 조회');
        
        for (final doc in messagesResult.documents) {
          if (dismissedIds.contains(doc.$id)) {
            final msg = ShopMessageModel.fromJson(doc.data, doc.$id);
            _dismissedMessages.add(msg);
            debugPrint('   ✅ 무시된 메시지 추가: "${msg.message}" (${msg.messageId})');
          }
        }
      }
      
      debugPrint('');
      debugPrint('✅ 무시한 메시지 ${_dismissedMessages.length}개 로드 완료');
      debugPrint('🔄 ════════════════════ 복원 완료 ════════════════════');
      debugPrint('');
      
      // ✅ UI 업데이트
      notifyListeners();
      
    } catch (e) {
      debugPrint('⚠️ 무시한 메시지 복원 실패: $e');
    }
  }

  // ✅ 수락한 메시지 로드 (수정됨 - 만료되지 않은 메시지만 로드)
  Future<void> _loadAcceptedMessages() async {
    if (_currentUserId == null) return;
    
    try {
      debugPrint('');
      debugPrint('🔄 ════════════════════ 수락한 메시지 복원 시작 ════════════════════');
      
      // ✅ STEP 1: 수락한 메시지 ID만 조회
      // ignore: deprecated_member_use
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.messageAcceptancesCollectionId,
        queries: [
          Query.equal('userId', _currentUserId!),
          Query.equal('status', 'accepted'), // ✅ 명확한 쿼리
          Query.orderDesc('acceptedAt'), // ✅ 최신순 정렬
        ],
      );
      
      debugPrint('📦 조회된 수락 기록: ${result.documents.length}개');
      
      _acceptedMessageIds.clear(); // ✅ 먼저 초기화
      final acceptedIds = <String>{};
      
      for (final doc in result.documents) {
        final msgId = doc.data['messageId'];
        _acceptedMessageIds.add(msgId);
        acceptedIds.add(msgId);
        debugPrint('   ✅ 수락 ID: $msgId');
      }
      
      debugPrint('✅ 수락한 메시지 ID ${_acceptedMessageIds.length}개 추출');
      
      // ✅ STEP 2: 수락된 메시지의 실제 정보 로드 (만료되지 않은 것만)
      _acceptedMessages.clear(); // ✅ 먼저 초기화
      
      if (acceptedIds.isNotEmpty) {
        debugPrint('');
        debugPrint('📥 수락된 메시지 상세 정보 로드 중...');
        
        final now = DateTime.now();
        
        // shopMessages에서 만료되지 않은 메시지만 조회
        // ignore: deprecated_member_use
        final messagesResult = await _db.listDocuments(
          databaseId: AppwriteConstants.databaseId,
          collectionId: ShopConstants.shopMessagesCollectionId,
          queries: [
            Query.greaterThan('expiresAt', now.toIso8601String()), // ✅ 만료 안 된 것만
            Query.limit(100),
          ],
        );
        
        debugPrint('📥 DB에서 활성 메시지 ${messagesResult.documents.length}개 조회');
        
        for (final doc in messagesResult.documents) {
          if (acceptedIds.contains(doc.$id)) {
            final msg = ShopMessageModel.fromJson(doc.data, doc.$id);
            _acceptedMessages.add(msg);
            debugPrint('   ✅ 수락된 메시지 추가: "${msg.message}" (${msg.messageId})');
          }
        }
      }
      
      debugPrint('');
      debugPrint('✅ 수락한 메시지 ${_acceptedMessages.length}개 로드 완료');
      debugPrint('🔄 ════════════════════ 복원 완료 ════════════════════');
      debugPrint('');
      
      // ✅ STEP 3: UI 업데이트
      notifyListeners();
      
    } catch (e) {
      debugPrint('❌ 수락한 메시지 복원 실패: $e');
    }
  }

  // ✅ 위치 업데이트
  void updateLocation(double lat, double lng) {
    _currentLat = lat;
    _currentLng = lng;
    debugPrint('📍 위치 업데이트: ($lat, $lng)');
    _checkMessagesInRange();
  }
  
  void startMessageCheck() {
    _messageCheckTimer?.cancel();
    _messageCheckTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkMessagesInRange(),
    );
    _checkMessagesInRange();
  }
  
  void startExpirationCheck() {
    _expirationTimer?.cancel();
    _expirationTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _removeExpiredMessages(),
    );
  }
  
  // ✅ 반경 내 메시지 확인
  Future<void> _checkMessagesInRange() async {
    if (_currentLat == null || _currentLng == null || _currentUserId == null) {
      debugPrint('⚠️ 위치 정보 없음');
      return;
    }
    
    try {
      final now = DateTime.now();
      /*
      debugPrint('');
      debugPrint('🔍 ════════════════════ 메시지 체크 시작 ════════════════════');
      debugPrint('⏰ 현재 시간: ${now.toIso8601String()}');
      debugPrint('📍 현재 위치: ($_currentLat, $_currentLng)');
      debugPrint('👤 사용자 ID: $_currentUserId');
      debugPrint('📊 수락된 메시지: ${_acceptedMessageIds.length}개');
      debugPrint('📊 무시된 메시지: ${_dismissedMessageIds.length}개');
      */
      // ignore: deprecated_member_use
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.shopMessagesCollectionId,
        queries: [
          Query.greaterThan('expiresAt', now.toIso8601String()),
          Query.orderDesc('createdAt'),
          Query.limit(100),
        ],
      );
      
      //debugPrint('📥 DB에서 활성 메시지 ${result.documents.length}개 조회');
      
      final allMessages = result.documents
          .map((doc) => ShopMessageModel.fromJson(doc.data, doc.$id))
          .toList();
      
      final inRangeMessages = <ShopMessageModel>[];
      
      for (final msg in allMessages) {
        //debugPrint('🔎 메시지 검사: "${msg.message}"');
        
        final shop = await _getShop(msg.shopId);
        if (shop == null) {
          //debugPrint('   ❌ 샵 정보 없음');
          continue;
        }
        
        //debugPrint('   ✅ 샵: ${shop.shopName}');
        
        final distance = _calculateDistance(
          _currentLat!,
          _currentLng!,
          shop.lat,
          shop.lng,
        );
        
        //debugPrint('   📏 거리: ${distance.toStringAsFixed(1)}m / 반경: ${msg.radius}m');
        
        if (distance > msg.radius) {
          debugPrint('   ❌ 반경 초과');
          continue;
        }
        
        if (distance > _maxRadius) {
          debugPrint('   ❌ 최대 반경 초과');
          continue;
        }
        
        //debugPrint('   ✅ 반경 내!');
        
        if (_categoryFilter.isNotEmpty) {
          final categoryOk = _categoryFilter.contains(shop.category);
          debugPrint('   카테고리: ${shop.category} - ${categoryOk ? '✅' : '❌'}');
          if (!categoryOk) continue;
        }
        
        //debugPrint('   ✨ 수신 메시지 추가!');
        inRangeMessages.add(msg);
      }
      /*
      debugPrint('');
      debugPrint('📊 최종 결과:');
      debugPrint('   총 조회: ${allMessages.length}개');
      debugPrint('   반경 내: ${inRangeMessages.length}개');
      */
      // 새 메시지 추가
      final newMessages = inRangeMessages.where((msg) {
        return !_receivedMessages.any((m) => m.messageId == msg.messageId);
      }).toList();
      
      if (newMessages.isNotEmpty) {
        debugPrint('');
        debugPrint('🔔 새 메시지 ${newMessages.length}개 수신!');
        _receivedMessages.addAll(newMessages);
      }
      
      // 제거된 메시지 처리
      final removedMessages = _receivedMessages.where((msg) {
        return !inRangeMessages.any((m) => m.messageId == msg.messageId);
      }).toList();
      
      if (removedMessages.isNotEmpty) {
        debugPrint('🗑️  제거된 메시지 ${removedMessages.length}개');
        for (final msg in removedMessages) {
          _receivedMessages.removeWhere((m) => m.messageId == msg.messageId);
        }
      }
      
      // ✅ 활성 메시지 = 반경 내 + 수락 안 함 + 무시 안 함
      final activeOnlyMessages = inRangeMessages.where((msg) {
        final isAccepted = _acceptedMessageIds.contains(msg.messageId);
        final isDismissed = _dismissedMessageIds.contains(msg.messageId);
        
        if (isAccepted) {
          //debugPrint('⏭️  수락됨 제외: "${msg.message}"');
        } else if (isDismissed) {
          debugPrint('⏭️  무시됨 제외: "${msg.message}"');
        }
        
        return !isAccepted && !isDismissed;
      }).toList();
      
      if (activeOnlyMessages.length != _activeMessages.length) {
        _activeMessages = activeOnlyMessages;
        debugPrint('✨ 활성 메시지 목록 업데이트! (${_activeMessages.length}개)');
        notifyListeners();
      }
      
      //debugPrint('🔍 ════════════════════ 메시지 체크 종료 ════════════════════');
      //debugPrint('');
      
    } catch (e) {
      debugPrint('❌ 메시지 확인 실패: $e');
    }
  }
  
  // ✅ 메시지 수락 (notifyListeners 추가)
  Future<bool> acceptMessage(
    ShopMessageModel message,
    double userLat,
    double userLng,
  ) async {
    if (_currentUserId == null) return false;
    
    try {
      debugPrint('');
      debugPrint('✅ ════════════════════ acceptMessage 시작 ════════════════════');
      debugPrint('   메시지 ID: ${message.messageId}');
      debugPrint('   메시지: "${message.message}"');
      
      // ✅ Step 1: 이미 수락했는지 확인
      if (_acceptedMessageIds.contains(message.messageId)) {
        debugPrint('⚠️  이미 수락한 메시지');
        return true;
      }
      
      // ✅ Step 2: 기존 기록이 있는지 확인 (dismissed든 accepted든)
      debugPrint('⏳ 기존 기록 조회 중...');
      
      // ignore: deprecated_member_use
      final existingResult = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.messageAcceptancesCollectionId,
        queries: [
          Query.equal('userId', _currentUserId!),
          Query.equal('messageId', message.messageId),
        ],
      );
      
      String? existingDocId;
      if (existingResult.documents.isNotEmpty) {
        existingDocId = existingResult.documents.first.$id;
        debugPrint('✅ 기존 기록 발견: $existingDocId');
        debugPrint('   현재 status: ${existingResult.documents.first.data['status']}');
      }
      
      // ✅ Step 3: UPDATE 또는 INSERT
      if (existingDocId != null) {
        // UPDATE: 기존 기록이 있으면 status 변경
        debugPrint('🔄 UPDATE 실행: $existingDocId');
        
        // ignore: deprecated_member_use
        await _db.updateDocument(
          databaseId: AppwriteConstants.databaseId,
          collectionId: ShopConstants.messageAcceptancesCollectionId,
          documentId: existingDocId,
          data: {
            'status': 'accepted', // ← dismissed → accepted로 변경
            'acceptedAt': DateTime.now().toIso8601String(),
            'userLat': userLat,
            'userLng': userLng,
          },
        );
        
        debugPrint('✅ UPDATE 완료: status = "accepted"');
        
      } else {
        // INSERT: 기존 기록이 없으면 새로 생성
        debugPrint('➕ INSERT 실행');
        
        // ignore: deprecated_member_use
        await _db.createDocument(
          databaseId: AppwriteConstants.databaseId,
          collectionId: ShopConstants.messageAcceptancesCollectionId,
          documentId: ID.unique(),
          data: {
            'messageId': message.messageId,
            'userId': _currentUserId!,
            'status': 'accepted',
            'acceptedAt': DateTime.now().toIso8601String(),
            'userLat': userLat,
            'userLng': userLng,
          },
        );
        
        debugPrint('✅ INSERT 완료: 새로운 기록 생성');
      }
      
      // ✅ Step 4: 로컬 상태 업데이트
      _acceptedMessageIds.add(message.messageId);
      _dismissedMessageIds.remove(message.messageId); // 무시 상태 제거
      _activeMessages.removeWhere((m) => m.messageId == message.messageId);
      _dismissedMessages.removeWhere((m) => m.messageId == message.messageId);
      
      // 수락된 메시지 리스트에 추가
      if (!_acceptedMessages.any((m) => m.messageId == message.messageId)) {
        _acceptedMessages.add(message);
        debugPrint('✅ 수락 메시지 리스트에 추가 (${_acceptedMessages.length}개)');
      }
      
      debugPrint('✅ 로컬 상태 업데이트 완료');
      debugPrint('   acceptedMessages: ${_acceptedMessages.length}개');
      debugPrint('   activeMessages: ${_activeMessages.length}개');
      
      // ✅ CRITICAL: UI 업데이트!
      notifyListeners();
      debugPrint('✅ notifyListeners() 호출 완료');
      
      debugPrint('✅ ════════════════════ acceptMessage 완료 ════════════════════');
      debugPrint('');
      
      return true;
      
    } catch (e) {
      debugPrint('❌ acceptMessage 실패: $e');
      debugPrint('✅ ════════════════════ acceptMessage 실패 ════════════════════');
      debugPrint('');
      return false;
    }
  }
  
  // ✅ 메시지 무시 (notifyListeners 위치 확인)
  Future<void> dismissMessage(String messageId) async {
    if (_currentUserId == null) return;

    debugPrint('');
    debugPrint('🗑️ ════════════════════ dismissMessage 시작 ════════════════════');
    debugPrint('📌 messageId: $messageId');
    
    try {
      // ✅ Step 1: 기존 기록이 있는지 확인
      debugPrint('⏳ 기존 기록 조회 중...');
      
      // ignore: deprecated_member_use
      final existingResult = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.messageAcceptancesCollectionId,
        queries: [
          Query.equal('userId', _currentUserId!),
          Query.equal('messageId', messageId),
        ],
      );
      
      String? existingDocId;
      if (existingResult.documents.isNotEmpty) {
        existingDocId = existingResult.documents.first.$id;
        debugPrint('✅ 기존 기록 발견: $existingDocId');
        debugPrint('   현재 status: ${existingResult.documents.first.data['status']}');
      }
      
      // ✅ Step 2: UPDATE 또는 INSERT
      if (existingDocId != null) {
        // UPDATE: 기존 기록이 있으면 status 변경
        debugPrint('🔄 UPDATE 실행: $existingDocId');
        
        // ignore: deprecated_member_use
        await _db.updateDocument(
          databaseId: AppwriteConstants.databaseId,
          collectionId: ShopConstants.messageAcceptancesCollectionId,
          documentId: existingDocId,
          data: {
            'status': 'dismissed', // ← accepted → dismissed로 변경
            'dismissedAt': DateTime.now().toIso8601String(),
          },
        );
        
        debugPrint('✅ UPDATE 완료: status = "dismissed"');
        
      } else {
        // INSERT: 기존 기록이 없으면 새로 생성
        debugPrint('➕ INSERT 실행');
        
        // ignore: deprecated_member_use
        await _db.createDocument(
          databaseId: AppwriteConstants.databaseId,
          collectionId: ShopConstants.messageAcceptancesCollectionId,
          documentId: ID.unique(),
          data: {
            'messageId': messageId,
            'userId': _currentUserId!,
            'status': 'dismissed',
            'dismissedAt': DateTime.now().toIso8601String(),
          },
        );
        
        debugPrint('✅ INSERT 완료: 새로운 기록 생성');
      }
      
      // ✅ Step 3: 로컬 상태 업데이트
      _dismissedMessageIds.add(messageId);
      _acceptedMessageIds.remove(messageId); // 수락 상태 제거
      
      // 해당 메시지를 찾아서 dismissedMessages에 추가
      final message = _activeMessages.firstWhere(
        (m) => m.messageId == messageId,
        orElse: () => _acceptedMessages.firstWhere(
          (m) => m.messageId == messageId,
          orElse: () => _receivedMessages.firstWhere(
            (m) => m.messageId == messageId,
            orElse: () => ShopMessageModel(
              messageId: messageId,
              ownerId: '',
              shopId: '',
              shopName: '',
              category: '',
              message: '',
              radius: 0,
              validityHours: 0,
              expiresAt: DateTime.now(),
              createdAt: DateTime.now(),
            ),
          ),
        ),
      );
      
      // dismissedMessages에 추가
      if (!_dismissedMessages.any((m) => m.messageId == messageId)) {
        _dismissedMessages.add(message);
        debugPrint('✅ 무시 메시지 리스트에 추가 (${_dismissedMessages.length}개)');
      }
      
      // 모든 활성 리스트에서 제거
      _activeMessages.removeWhere((m) => m.messageId == messageId);
      _acceptedMessages.removeWhere((m) => m.messageId == messageId);
      _receivedMessages.removeWhere((m) => m.messageId == messageId);
      
      debugPrint('✅ 로컬 상태 업데이트 완료');
      debugPrint('   dismissedMessages: ${_dismissedMessages.length}개');
      debugPrint('   activeMessages: ${_activeMessages.length}개');
      
      // ✅ CRITICAL: UI 업데이트!
      notifyListeners();
      debugPrint('✅ notifyListeners() 호출 완료');
      
      debugPrint('🗑️ ════════════════════ dismissMessage 완료 ════════════════════');
      debugPrint('');
      
    } catch (e) {
      debugPrint('❌ dismissMessage 실패: $e');
      debugPrint('🗑️ ════════════════════ dismissMessage 실패 ════════════════════');
      debugPrint('');
    }
  }
  
  // ✅ 무시된 메시지 정보 로드 (UI 표시용)
  Future<List<ShopMessageModel>> fetchDismissedMessagesForUI() async {
    if (_dismissedMessageIds.isEmpty) {
      return [];
    }
    
    try {
      debugPrint('');
      debugPrint('🔄 ════════════════════ 무시된 메시지 UI 로드 ════════════════════');
      debugPrint('📦 무시된 메시지 ID: ${_dismissedMessageIds.length}개');
      
      // shopMessages에서 무시된 메시지들의 정보 조회
      // ignore: deprecated_member_use
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.shopMessagesCollectionId,
        queries: [Query.limit(100)],
      );
      
      final messages = <ShopMessageModel>[];
      
      for (final doc in result.documents) {
        if (_dismissedMessageIds.contains(doc.$id)) {
          messages.add(ShopMessageModel.fromJson(doc.data, doc.$id));
          debugPrint('✅ 무시된 메시지 로드: "${doc.data['message']}"');
        }
      }
      
      debugPrint('✅ 총 ${messages.length}개 무시된 메시지 로드 완료');
      debugPrint('🔄 ════════════════════ 로드 완료 ════════════════════');
      debugPrint('');
      
      return messages;
      
    } catch (e) {
      debugPrint('❌ 무시된 메시지 로드 실패: $e');
      return [];
    }
  }
  
  void _removeExpiredMessages() {
    final now = DateTime.now();
    final before = _receivedMessages.length;
    
    _receivedMessages.removeWhere((msg) => now.isAfter(msg.expiresAt));
    _activeMessages.removeWhere((msg) => now.isAfter(msg.expiresAt));
    _acceptedMessages.removeWhere((msg) => now.isAfter(msg.expiresAt));
    _dismissedMessages.removeWhere((msg) => now.isAfter(msg.expiresAt));
    
    final after = _receivedMessages.length;
    
    if (before != after) {
      debugPrint('🗑️  만료 메시지 ${before - after}개 제거');
      notifyListeners();
    }
  }
  
  Future<ShopModel?> _getShop(String shopId) async {
    if (_shopsCache.containsKey(shopId)) {
      return _shopsCache[shopId];
    }
    
    try {
      // ignore: deprecated_member_use
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
  
  Future<ShopModel?> getShop(String shopId) async {
    return _getShop(shopId);
  }
  
  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000;
    
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
  
  Future<void> forceRefresh() async {
    debugPrint('');
    debugPrint('🔄 ════════════════════ 강제 메시지 새로고침 ════════════════════');
    debugPrint('✅ 수락된 메시지: ${_acceptedMessageIds.length}개');
    debugPrint('✅ 무시된 메시지: ${_dismissedMessageIds.length}개');
    await _checkMessagesInRange();
    debugPrint('🔄 ════════════════════ 새로고침 완료 ════════════════════');
    debugPrint('');
  }
  
  void reset() {
    _messageCheckTimer?.cancel();
    _expirationTimer?.cancel();
    
    _receivedMessages = [];
    _activeMessages = [];
    _acceptedMessages = [];
    _dismissedMessages = [];
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