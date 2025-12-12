import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/shop_models.dart';
import '../models/location_model.dart';
import 'package:appwrite/appwrite.dart';
import '../appwriteClient.dart';
import '../constants/appwrite_config.dart';

// ✅ 검색 결과 타입
enum SearchResultType {
  shop,
  friend,
  address,
}

// ✅ 통합 검색 결과 모델
class UnifiedSearchResult {
  final SearchResultType type;
  final String id;
  final String title;
  final String subtitle;
  final double lat;
  final double lng;
  final dynamic data; // ShopModel, LocationModel, or Map
  
  UnifiedSearchResult({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.lat,
    required this.lng,
    required this.data,
  });
}

// ✅ 통합 검색 패널
class UnifiedSearchPanel extends StatefulWidget {
  final List<ShopModel> allShops;
  final Map<String, LocationModel> allFriends; // userId -> LocationModel
  final Function(double lat, double lng, String title)? onLocationSelected;
  final Function(ShopModel shop)? onShopSelected;
  final Function(LocationModel friend)? onFriendSelected;
  final Function(double lat, double lng, String title)? onAddressNavigate;
  
  const UnifiedSearchPanel({
    super.key,
    required this.allShops,
    required this.allFriends,
    this.onLocationSelected,
    this.onShopSelected,
    this.onFriendSelected,
    this.onAddressNavigate,
  });

  @override
  State<UnifiedSearchPanel> createState() => _UnifiedSearchPanelState();
}

class _UnifiedSearchPanelState extends State<UnifiedSearchPanel> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final Databases _db = appwriteDB;
  final Functions _functions = appwriteFunctions; // ✅ Appwrite Functions
  
  List<UnifiedSearchResult> _searchResults = [];
  bool _isSearching = false;
  String _currentQuery = '';
  
  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }
  
  // ✅ 통합 검색 실행
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _currentQuery = '';
      });
      return;
    }
    
    setState(() {
      _isSearching = true;
      _currentQuery = query;
    });
    
    final results = <UnifiedSearchResult>[];
    final lowerQuery = query.toLowerCase().trim();
    
    try {
      debugPrint('');
      debugPrint('🔍 ════════════════════ 통합 검색 시작 ════════════════════');
      debugPrint('   검색어: "$query"');
      
      // 1. 샵 검색
      final shopResults = await _searchShops(lowerQuery);
      results.addAll(shopResults);
      debugPrint('   📦 샵: ${shopResults.length}개');
      
      // 2. 친구 검색
      final friendResults = await _searchFriends(lowerQuery);
      results.addAll(friendResults);
      debugPrint('   👤 친구: ${friendResults.length}개');
      
      // 3. 주소 검색 (Appwrite Function + Nominatim)
      final addressResults = await _searchKoreanAddress(query);
      results.addAll(addressResults);
      debugPrint('   📍 주소: ${addressResults.length}개');
      
      debugPrint('   총 ${results.length}개 결과');
      debugPrint('🔍 ════════════════════ 검색 완료 ════════════════════');
      debugPrint('');
      
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
      
    } catch (e) {
      debugPrint('❌ 검색 실패: $e');
      setState(() {
        _isSearching = false;
      });
    }
  }
  
  // ✅ 샵 검색
  Future<List<UnifiedSearchResult>> _searchShops(String query) async {
    return widget.allShops
        .where((shop) =>
            shop.shopName.toLowerCase().contains(query) ||
            shop.address.toLowerCase().contains(query) ||
            shop.category.toLowerCase().contains(query))
        .map((shop) => UnifiedSearchResult(
              type: SearchResultType.shop,
              id: shop.shopId,
              title: shop.shopName,
              subtitle: '${shop.category} · ${shop.address}',
              lat: shop.lat,
              lng: shop.lng,
              data: shop,
            ))
        .take(10)
        .toList();
  }
  
  // ✅ 친구 검색
  Future<List<UnifiedSearchResult>> _searchFriends(String query) async {
    final results = <UnifiedSearchResult>[];
    
    for (final entry in widget.allFriends.entries) {
      final userId = entry.key;
      final location = entry.value;
      
      try {
        // ignore: deprecated_member_use
        final res = await _db.listDocuments(
          databaseId: AppwriteConstants.databaseId,
          collectionId: AppwriteConstants.usersCollectionId,
          queries: [Query.equal('userId', userId)],
        );
        
        if (res.documents.isEmpty) continue;
        
        final userData = res.documents.first.data;
        final nickname = userData['nickname'] ?? userData['name'] ?? userId;
        final email = userData['email'] ?? '';
        
        if (nickname.toLowerCase().contains(query) ||
            email.toLowerCase().contains(query) ||
            userId.toLowerCase().contains(query)) {
          results.add(UnifiedSearchResult(
            type: SearchResultType.friend,
            id: userId,
            title: nickname,
            subtitle: '친구 · ${location.lat.toStringAsFixed(4)}, ${location.lng.toStringAsFixed(4)}',
            lat: location.lat,
            lng: location.lng,
            data: location,
          ));
        }
        
        if (results.length >= 10) break;
      } catch (e) {
        debugPrint('⚠️ 친구 프로필 조회 실패 ($userId): $e');
        continue;
      }
    }
    
    return results;
  }
  
  // ✅ 한국 주소 검색 (Appwrite Function 사용)
  Future<List<UnifiedSearchResult>> _searchKoreanAddress(String query) async {
    debugPrint('');
    debugPrint('🇰🇷 ════════════════════ 한국 주소 검색 시작 ════════════════════');
    debugPrint('   검색어: "$query"');
    
    try {
      // 1️⃣ Appwrite Function 호출
      debugPrint('   [단계 1] Appwrite Function 호출 중...');
      final execution = await _functions.createExecution(
        functionId: AppwriteConstants.addressFunctionId,
        body: json.encode({'query': query}),
        xasync: false,
      );
      
      debugPrint('   [단계 2] Function 응답 받음');
      debugPrint('   Function 실행 완료: ${execution.status}');
      debugPrint('   Status 타입: ${execution.status.runtimeType}');
      debugPrint('   Status toString: ${execution.status.toString()}');
      debugPrint('   Response 상태 코드: ${execution.responseStatusCode}');
      debugPrint('   Response Body 타입: ${execution.responseBody.runtimeType}');
      
      // ✅ 너무 긴 Body는 일부만 출력
      final bodyStr = execution.responseBody.toString();
      if (bodyStr.length > 200) {
        debugPrint('   Response Body (일부): ${bodyStr.substring(0, 200)}...');
      } else {
        debugPrint('   Response Body: $bodyStr');
      }
      
      // ✅ enum과 문자열 비교 모두 지원
      execution.status.toString();
      final isCompleted = execution.status.toString().contains('completed') ||
                         execution.responseStatusCode == 200;
      
      debugPrint('   isCompleted: $isCompleted');
      
      if (!isCompleted) {
        debugPrint('❌ Function 실행 실패: ${execution.status}');
        return [];
      }
      
      debugPrint('   ✅ Function 실행 성공');
      
      // 2️⃣ 응답 파싱 (이미 Map일 수도 있음)
      debugPrint('   [단계 3] 응답 파싱 중...');
      dynamic responseData;
      
      try {
        responseData = json.decode(execution.responseBody);
        debugPrint('   ✅ String → Map 파싱 성공');
      } catch (e) {
        debugPrint('❌ JSON 파싱 실패: $e');
        debugPrint('   원본: ${execution.responseBody}');
        return [];
      }
    // ignore: dead_code
          
      debugPrint('   [단계 4] 응답 데이터 검증 중...');
      debugPrint('   응답 success 타입: ${responseData['success'].runtimeType}');
      debugPrint('   응답 success 값: ${responseData['success']}');
      debugPrint('   응답 success == true: ${responseData['success'] == true}');
      
      // ✅ success가 문자열일 수도 있음
      final isSuccess = responseData['success'] == true || 
                       responseData['success'] == 'true' ||
                       responseData['success'].toString().toLowerCase() == 'true';
      
      if (!isSuccess) {
        debugPrint('❌ 주소 변환 실패: ${responseData['error']}');
        return [];
      }
      
      debugPrint('   ✅ success 검증 통과');
      
      debugPrint('   [단계 5] addresses 및 coordinates 추출 중...');
      final addresses = responseData['addresses'] as List<dynamic>? ?? [];
      final coordinates = responseData['coordinates'];
      
      debugPrint('   addresses 타입: ${addresses.runtimeType}');
      debugPrint('   addresses 길이: ${addresses.length}');
      debugPrint('   coordinates 타입: ${coordinates.runtimeType}');
      debugPrint('   변환된 주소: ${addresses.length}개');
      
      if (coordinates != null) {
        debugPrint('   좌표 lat 타입: ${coordinates['lat'].runtimeType}');
        debugPrint('   좌표 lng 타입: ${coordinates['lng'].runtimeType}');
        debugPrint('   좌표: (${coordinates['lat']}, ${coordinates['lng']})');
      } else {
        debugPrint('⚠️  좌표 정보 없음');
      }
      
      // 3️⃣ 결과 생성
      debugPrint('   [단계 6] 결과 생성 중...');
      final results = <UnifiedSearchResult>[];
      
      debugPrint('   addresses.isNotEmpty: ${addresses.isNotEmpty}');
      debugPrint('   coordinates != null: ${coordinates != null}');
      
      // 첫 번째 주소만 결과로 사용 (좌표가 있는 경우)
      if (addresses.isNotEmpty && coordinates != null) {
        try {
          final firstAddr = addresses[0] as Map<String, dynamic>;
          
          debugPrint('   firstAddr 파싱 성공');
          debugPrint('   roadAddr: ${firstAddr['roadAddr']}');
          debugPrint('   jibunAddr: ${firstAddr['jibunAddr']}');
          
          final lat = (coordinates['lat'] as num).toDouble();
          final lng = (coordinates['lng'] as num).toDouble();
          
          debugPrint('   좌표 변환 성공: ($lat, $lng)');
          
          results.add(UnifiedSearchResult(
            type: SearchResultType.address,
            id: 'addr_${DateTime.now().millisecondsSinceEpoch}',
            title: firstAddr['roadAddr'] ?? firstAddr['jibunAddr'] ?? query,
            subtitle: '도로명 주소',
            lat: lat,
            lng: lng,
            data: {
              'roadAddr': firstAddr['roadAddr'],
              'jibunAddr': firstAddr['jibunAddr'],
              'engAddr': firstAddr['engAddr'],
              'zipNo': firstAddr['zipNo'],
              'coordinates': coordinates,
            },
          ));
          
          debugPrint('   ✅ UnifiedSearchResult 생성 성공');
          debugPrint('      제목: ${results[0].title}');
          debugPrint('      좌표: (${results[0].lat}, ${results[0].lng})');
        } catch (e, stack) {
          debugPrint('❌ 결과 생성 중 오류: $e');
          debugPrint('Stack: $stack');
        }
      } else {
        debugPrint('⚠️  주소 또는 좌표가 없어서 결과 생성 실패');
        debugPrint('      addresses.isEmpty: ${addresses.isEmpty}');
        debugPrint('      coordinates == null: ${coordinates == null}');
      }
      
      debugPrint('   [단계 7] 완료');
      debugPrint('   최종 결과: ${results.length}개');
      debugPrint('🇰🇷 ════════════════════ 한국 주소 검색 완료 ════════════════════');
      debugPrint('');
      
      return results;
      
    } catch (e, stack) {
      debugPrint('❌ 한국 주소 검색 실패 (catch 블록): $e');
      debugPrint('Stack trace:');
      debugPrint('$stack');
      debugPrint('🇰🇷 ════════════════════ 한국 주소 검색 실패 ════════════════════');
      debugPrint('');
      return [];
    }
  }
  
  // ✅ 검색 결과 선택
  void _onResultSelected(UnifiedSearchResult result) {
    debugPrint('');
    debugPrint('✅ 검색 결과 선택: ${result.type.name} - ${result.title}');
    debugPrint('');
    
    switch (result.type) {
      case SearchResultType.shop:
        Navigator.pop(context);
        widget.onShopSelected?.call(result.data as ShopModel);
        break;
        
      case SearchResultType.friend:
        Navigator.pop(context);
        widget.onFriendSelected?.call(result.data as LocationModel);
        break;
        
      case SearchResultType.address:
        _showAddressActionSheet(result);
        break;
    }
  }
  
  // ✅ 주소 선택 시 액션 시트
  void _showAddressActionSheet(UnifiedSearchResult result) {
    final addressData = result.data as Map<String, dynamic>;
    final roadAddr = addressData['roadAddr'] ?? '';
    final jibunAddr = addressData['jibunAddr'] ?? '';
    final zipNo = addressData['zipNo'] ?? '';
    
    showModalBottomSheet(
      context: context,
      builder: (bottomContext) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '주소',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        roadAddr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // 지번 주소
            if (jibunAddr.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.home, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '지번: $jibunAddr',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 8),
            
            // 우편번호
            if (zipNo.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mail, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      '우편번호: $zipNo',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 8),
            
            // 좌표
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.map, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    '${result.lat.toStringAsFixed(6)}, ${result.lng.toStringAsFixed(6)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // 버튼들
            Row(
              children: [
                // 위치만 보기
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(bottomContext);
                      Navigator.pop(context);
                      widget.onLocationSelected?.call(
                        result.lat,
                        result.lng,
                        roadAddr,
                      );
                    },
                    icon: const Icon(Icons.visibility),
                    label: const Text('위치 보기'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // 길찾기
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(bottomContext);
                      Navigator.pop(context);
                      widget.onAddressNavigate?.call(
                        result.lat,
                        result.lng,
                        roadAddr,
                      );
                    },
                    icon: const Icon(Icons.navigation),
                    label: const Text('길찾기'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(16),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '통합 검색',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // 검색창
          TextField(
            controller: _searchController,
            focusNode: _searchFocus,
            autofocus: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: '샵, 친구, 주소 검색...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchResults = [];
                          _currentQuery = '';
                        });
                      },
                    )
                  : null,
            ),
            onChanged: (value) {
              setState(() {});
            },
            onSubmitted: (value) {
              _performSearch(value);
            },
          ),
          
          const SizedBox(height: 8),
          
          // 힌트 텍스트
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '엔터를 눌러 검색 · 지번/도로명 주소 모두 지원',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          
          // 검색 결과
          if (_isSearching)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('검색 중...'),
                  ],
                ),
              ),
            )
          else if (_searchResults.isEmpty && _currentQuery.isNotEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '검색 결과가 없습니다',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '"$_currentQuery"',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_searchResults.isNotEmpty)
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final result = _searchResults[index];
                  return _buildSearchResultTile(result);
                },
              ),
            )
          else
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search,
                      size: 64,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '샵, 친구, 주소를 검색해보세요',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '예: 가락동 13-18, 송이로17길 50-5',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  // ✅ 검색 결과 타일
  Widget _buildSearchResultTile(UnifiedSearchResult result) {
    IconData icon;
    Color iconColor;
    String typeLabel;
    
    switch (result.type) {
      case SearchResultType.shop:
        icon = Icons.store;
        iconColor = Colors.deepPurple;
        typeLabel = '샵';
        break;
      case SearchResultType.friend:
        icon = Icons.person;
        iconColor = Colors.blue;
        typeLabel = '친구';
        break;
      case SearchResultType.address:
        icon = Icons.location_on;
        iconColor = Colors.red;
        typeLabel = '주소';
        break;
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          // ignore: deprecated_member_use
          backgroundColor: iconColor.withOpacity(0.1),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                // ignore: deprecated_member_use
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                typeLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: iconColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        subtitle: Text(
          result.subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => _onResultSelected(result),
      ),
    );
  }
}