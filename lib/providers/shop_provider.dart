import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';
import '../models/shop_models.dart';
import '../appwriteClient.dart';
import '../constants/appwrite_config.dart';
import '../constants/shop_constants.dart';
import 'dart:math';

class ShopProvider with ChangeNotifier {
  final Databases _db = appwriteDB;
  
  ShopModel? _myShop;
  ShopModel? get myShop => _myShop;
  
  List<ShopMessageModel> _myMessages = [];
  List<ShopMessageModel> get myMessages => _myMessages;
  
  Map<String, List<MessageAcceptanceModel>> _acceptances = {};
  Map<String, List<MessageAcceptanceModel>> get acceptances => _acceptances;
  
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  // ✅ 1. 샵 생성
  Future<bool> createShop({
    required String ownerId,
    required String shopName,
    required String category,
    required double lat,
    required double lng,
    required String address,
    required String phone,
    required String description,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      final shopData = {
        'ownerId': ownerId,
        'shopName': shopName,
        'category': category,
        'lat': lat,
        'lng': lng,
        'address': address,
        'phone': phone,
        'description': description,
        'bannerMessage': '',
        'createdAt': DateTime.now().toIso8601String(),
      };
      
      // ignore: deprecated_member_use
      final result = await _db.createDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.shopsCollectionId,
        documentId: ID.unique(),
        data: shopData,
      );
      
      _myShop = ShopModel.fromJson(result.data, result.$id);
      
      debugPrint('✅ 샵 생성 완료: ${_myShop!.shopName}');
      
      _isLoading = false;
      notifyListeners();
      return true;
      
    } catch (e) {
      debugPrint('❌ 샵 생성 실패: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  // ✅ 2. 내 샵 정보 가져오기
  Future<void> fetchMyShop(String ownerId) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      // ignore: deprecated_member_use
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.shopsCollectionId,
        queries: [
          Query.equal('ownerId', ownerId),
        ],
      );
      
      if (result.documents.isNotEmpty) {
        final doc = result.documents.first;
        _myShop = ShopModel.fromJson(doc.data, doc.$id);
        debugPrint('✅ 내 샵 정보 로드: ${_myShop!.shopName}');
      } else {
        _myShop = null;
        debugPrint('ℹ️ 등록된 샵이 없습니다.');
      }
      
      _isLoading = false;
      notifyListeners();
      
    } catch (e) {
      debugPrint('❌ 샵 정보 로드 실패: $e');
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // ✅ 3. 샵 정보 업데이트
  Future<bool> updateShop({
    required String shopId,
    String? shopName,
    String? category,
    String? address,
    String? phone,
    String? description,
    String? bannerMessage,
  }) async {
    try {
      final updateData = <String, dynamic>{};
      
      if (shopName != null) updateData['shopName'] = shopName;
      if (category != null) updateData['category'] = category;
      if (address != null) updateData['address'] = address;
      if (phone != null) updateData['phone'] = phone;
      if (description != null) updateData['description'] = description;
      if (bannerMessage != null) updateData['bannerMessage'] = bannerMessage;
      
      // ignore: deprecated_member_use
      await _db.updateDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.shopsCollectionId,
        documentId: shopId,
        data: updateData,
      );
      
      await fetchMyShop(_myShop!.ownerId);
      
      debugPrint('✅ 샵 정보 업데이트 완료');
      return true;
      
    } catch (e) {
      debugPrint('❌ 샵 정보 업데이트 실패: $e');
      return false;
    }
  }
  
  // ✅ 4. 홍보 메시지 전송
  Future<ShopMessageModel?> sendMessage({
    required String shopId,
    required String ownerId,
    required String message,
    required int radius,
    required int validityHours,
    String messageType = 'promotion',
    String? targetMeetingId,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      final now = DateTime.now();
      final expiresAt = now.add(Duration(hours: validityHours));
      
      final messageData = {
        'shopId': shopId,
        'ownerId': ownerId,
        'message': message,
        'radius': radius,
        'validityHours': validityHours,
        'createdAt': now.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'messageType': messageType,
        'targetMeetingId': targetMeetingId,
        'reachCount': 0,
        'acceptCount': 0,
      };
      
      // ignore: deprecated_member_use
      final result = await _db.createDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.shopMessagesCollectionId,
        documentId: ID.unique(),
        data: messageData,
      );
      
      final newMessage = ShopMessageModel.fromJson(result.data, result.$id);
      
      _myMessages.insert(0, newMessage);
      
      debugPrint('✅ 홍보 메시지 전송 완료: $message');
      debugPrint('   반경: ${radius}m, 유효시간: $validityHours시간');
      
      _isLoading = false;
      notifyListeners();
      
      return newMessage;
      
    } catch (e) {
      debugPrint('❌ 메시지 전송 실패: $e');
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }
  
  // ✅ 5. 내 메시지 목록 가져오기
  Future<void> fetchMyMessages(String shopId) async {
    try {
      // ignore: deprecated_member_use
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.shopMessagesCollectionId,
        queries: [
          Query.equal('shopId', shopId),
          Query.orderDesc('createdAt'),
          Query.limit(50),
        ],
      );
      
      _myMessages = result.documents
          .map((doc) => ShopMessageModel.fromJson(doc.data, doc.$id))
          .toList();
      
      debugPrint('✅ 내 메시지 ${_myMessages.length}개 로드');
      notifyListeners();
      
    } catch (e) {
      debugPrint('❌ 메시지 로드 실패: $e');
    }
  }
  
  // ✅ 6. 특정 메시지의 수락 목록 가져오기
  Future<void> fetchAcceptances(String messageId) async {
    try {
      // ignore: deprecated_member_use
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.messageAcceptancesCollectionId,
        queries: [
          Query.equal('messageId', messageId),
          Query.orderDesc('acceptedAt'),
        ],
      );
      
      final acceptanceList = result.documents
          .map((doc) => MessageAcceptanceModel.fromJson(doc.data, doc.$id))
          .toList();
      
      _acceptances[messageId] = acceptanceList;
      
      debugPrint('✅ 메시지 $messageId 수락자 ${acceptanceList.length}명');
      notifyListeners();
      
    } catch (e) {
      debugPrint('❌ 수락 목록 로드 실패: $e');
    }
  }
  
  // ✅ 7. 거리 계산 (미터 단위)
  double calculateDistance(
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
  
  // ✅ 8. 메시지 통계 업데이트
  Future<void> updateMessageStats(
    String messageId, {
    int? reachCount,
    int? acceptCount,
  }) async {
    try {
      final updateData = <String, dynamic>{};
      
      if (reachCount != null) updateData['reachCount'] = reachCount;
      if (acceptCount != null) updateData['acceptCount'] = acceptCount;
      
      // ignore: deprecated_member_use
      await _db.updateDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.shopMessagesCollectionId,
        documentId: messageId,
        data: updateData,
      );
      
    } catch (e) {
      debugPrint('❌ 메시지 통계 업데이트 실패: $e');
    }
  }
  
  // ✅ 9. 만료된 메시지 자동 정리
  Future<void> cleanupExpiredMessages() async {
    try {
      _myMessages.removeWhere((msg) => msg.isExpired);
      notifyListeners();
    } catch (e) {
      debugPrint('❌ 만료 메시지 정리 실패: $e');
    }
  }
  
  void reset() {
    _myShop = null;
    _myMessages = [];
    _acceptances = {};
    _isLoading = false;
    notifyListeners();
  }
}