// lib/providers/personal_places_provider.dart

import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';
import '../models/personal_place_model.dart';
import '../constants/appwrite_config.dart';
import '../appwriteClient.dart';

class PersonalPlacesProvider with ChangeNotifier {
  final Databases _db = appwriteDB;
  
  List<PersonalPlaceModel> _allPlaces = [];
  List<PersonalPlaceModel> _filteredPlaces = [];
  String _selectedGroupFilter = '전체';
  bool _isLoading = false;

  List<PersonalPlaceModel> get allPlaces => _allPlaces;
  List<PersonalPlaceModel> get filteredPlaces => _filteredPlaces;
  String get selectedGroupFilter => _selectedGroupFilter;
  bool get isLoading => _isLoading;

  // ✅ 내 장소 전체 가져오기
  Future<void> fetchMyPlaces(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.personalPlacesCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.orderDesc('createdAt'),
        ],
      );

      _allPlaces = result.documents
          .map((doc) => PersonalPlaceModel.fromMap(doc.$id, doc.data))
          .toList();

      _applyGroupFilter();
      
      debugPrint('✅ 개인 장소 로드: ${_allPlaces.length}개');
    } catch (e) {
      debugPrint('❌ 개인 장소 로드 실패: $e');
      _allPlaces = [];
      _filteredPlaces = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ✅ 그룹 필터 적용
  void setGroupFilter(String groupName) {
    _selectedGroupFilter = groupName;
    _applyGroupFilter();
    notifyListeners();
  }

  void _applyGroupFilter() {
    if (_selectedGroupFilter == '전체') {
      _filteredPlaces = List.from(_allPlaces);
    } else {
      _filteredPlaces = _allPlaces
          .where((place) => place.groups.contains(_selectedGroupFilter))
          .toList();
    }
  }

  // ✅ 장소 저장
  Future<bool> savePlace({
    required String userId,
    required String placeName,
    required String category,
    required String address,
    required double lat,
    required double lng,
    required List<String> groups,
    String? memo,
  }) async {
    try {
      debugPrint('');
      debugPrint('💾 ═══════════════ 개인 장소 저장 ═══════════════');
      debugPrint('📍 이름: $placeName');
      debugPrint('📁 카테고리: $category');
      debugPrint('📫 주소: $address');
      debugPrint('🗂️ 그룹: $groups');

      final data = {
        'userId': userId,
        'placeName': placeName,
        'category': category,
        'address': address,
        'lat': lat,
        'lng': lng,
        'groups': groups,
        'memo': memo,
        'createdAt': DateTime.now().toIso8601String(),
      };

      await _db.createDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.personalPlacesCollectionId,
        documentId: ID.unique(),
        data: data,
        permissions: [
          Permission.read(Role.user(userId)),
          Permission.write(Role.user(userId)),
        ],
      );

      debugPrint('✅ 저장 완료');
      debugPrint('💾 ═══════════════════════════════════════════');
      debugPrint('');

      // 목록 새로고침
      await fetchMyPlaces(userId);
      
      return true;
    } catch (e) {
      debugPrint('❌ 장소 저장 실패: $e');
      return false;
    }
  }

  // ✅ 장소 삭제
  Future<bool> deletePlace(String placeId, String userId) async {
    try {
      await _db.deleteDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.personalPlacesCollectionId,
        documentId: placeId,
      );

      debugPrint('✅ 장소 삭제 완료: $placeId');
      
      // 목록 새로고침
      await fetchMyPlaces(userId);
      
      return true;
    } catch (e) {
      debugPrint('❌ 장소 삭제 실패: $e');
      return false;
    }
  }

  // ✅ 장소 수정
  Future<bool> updatePlace({
    required String placeId,
    required String userId,
    String? placeName,
    String? category,
    String? address,
    double? lat,
    double? lng,
    List<String>? groups,
    String? memo,
  }) async {
    try {
      final updates = <String, dynamic>{};
      
      if (placeName != null) updates['placeName'] = placeName;
      if (category != null) updates['category'] = category;
      if (address != null) updates['address'] = address;
      if (lat != null) updates['lat'] = lat;
      if (lng != null) updates['lng'] = lng;
      if (groups != null) updates['groups'] = groups;
      if (memo != null) updates['memo'] = memo;

      if (updates.isEmpty) return false;

      await _db.updateDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.personalPlacesCollectionId,
        documentId: placeId,
        data: updates,
      );

      debugPrint('✅ 장소 수정 완료: $placeId');
      
      // 목록 새로고침
      await fetchMyPlaces(userId);
      
      return true;
    } catch (e) {
      debugPrint('❌ 장소 수정 실패: $e');
      return false;
    }
  }

  // ✅ 특정 그룹의 장소 개수
  int getPlaceCountByGroup(String groupName) {
    if (groupName == '전체') return _allPlaces.length;
    return _allPlaces.where((p) => p.groups.contains(groupName)).length;
  }

  // ✅ 카테고리별 장소 개수
  Map<String, int> getCategoryStats() {
    final stats = <String, int>{};
    for (final place in _allPlaces) {
      stats[place.category] = (stats[place.category] ?? 0) + 1;
    }
    return stats;
  }
}