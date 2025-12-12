import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';
import '../models/shop_models.dart';
import '../appwriteClient.dart';
import '../constants/appwrite_config.dart';
import '../constants/shop_constants.dart';
import 'dart:async';
import 'dart:math';

class ShopsMapProvider with ChangeNotifier {
  final Databases _db = appwriteDB;
  
  List<ShopModel> _allShops = [];
  List<ShopModel> get allShops => _allShops;
  
  Map<String, ShopModel> _shopsById = {};
  
  List<ShopModel> _filteredShops = [];
  List<ShopModel> get filteredShops => _filteredShops;
  
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  Timer? _refreshTimer;
  
  // 필터 설정
  Set<String> _categoryFilter = {};
  String _searchQuery = '';
  
  // ✅ 1. 모든 샵 로드
  Future<void> fetchAllShops() async {
    try {
      _isLoading = true;
      notifyListeners();
      
      // ignore: deprecated_member_use
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.shopsCollectionId,
        queries: [
          Query.orderDesc('createdAt'),
          Query.limit(100),
        ],
      );
      
      _allShops = result.documents
          .map((doc) => ShopModel.fromJson(doc.data, doc.$id))
          .toList();
      
      // 맵에 저장
      for (final shop in _allShops) {
        _shopsById[shop.shopId] = shop;
      }
      
      _applyFilters();
      
      debugPrint('✅ 샵 ${_allShops.length}개 로드 완료');
      
      _isLoading = false;
      notifyListeners();
      
    } catch (e) {
      debugPrint('❌ 샵 로드 실패: $e');
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // ✅ 2. 주기적 샵 업데이트 (실시간 반영)
  void startAutoRefresh({Duration interval = const Duration(minutes: 5)}) {
    _refreshTimer?.cancel();
    
    _refreshTimer = Timer.periodic(interval, (_) {
      debugPrint('🔄 샵 목록 자동 새로고침');
      fetchAllShops();
    });
  }
  
  // ✅ 3. 샵 검색
  void searchShops(String query) {
    _searchQuery = query.toLowerCase().trim();

    // 🔥 검색어가 비어있으면 전체 리셋
    if (_searchQuery.isEmpty) {
      _applyFilters(); // 전체 목록 적용
      notifyListeners();
      return;
    }

    // 일반적인 검색
    _applyFilters();
    notifyListeners();
  }
  
  // ✅ 4. 카테고리 필터
  void setCategoryFilter(Set<String> categories) {
    _categoryFilter = categories;
    _applyFilters();
    notifyListeners();
  }
  
  // ✅ 5. 필터 적용
  void _applyFilters() {
    _filteredShops = _allShops.where((shop) {
      // 카테고리 필터
      if (_categoryFilter.isNotEmpty && !_categoryFilter.contains(shop.category)) {
        return false;
      }
      
      // 검색어 필터
      if (_searchQuery.isNotEmpty) {
        final matches = shop.shopName.toLowerCase().contains(_searchQuery) ||
            shop.address.toLowerCase().contains(_searchQuery) ||
            shop.category.toLowerCase().contains(_searchQuery);
        if (!matches) return false;
      }
      
      return true;
    }).toList();
    
    debugPrint('🔍 필터링 결과: ${_filteredShops.length}개 샵');
  }
  
  // ✅ 6. 특정 샵 정보 가져오기
  ShopModel? getShopById(String shopId) {
    return _shopsById[shopId];
  }
  
  // ✅ 7. 거리 내 샵 검색
  List<ShopModel> getShopsNearby(
    double userLat,
    double userLng, {
    double radiusInMeters = 1000,
  }) {
    return _filteredShops.where((shop) {
      final distance = _calculateDistance(
        userLat,
        userLng,
        shop.lat,
        shop.lng,
      );
      return distance <= radiusInMeters;
    }).toList();
  }
  
  // ✅ 8. 거리 계산
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
    return degree * 3.14159265359 / 180;
  }
  
  // ✅ 9. 초기화
  void reset() {
    _allShops = [];
    _shopsById = {};
    _filteredShops = [];
    _categoryFilter = {};
    _searchQuery = '';
    _refreshTimer?.cancel();
    notifyListeners();
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}