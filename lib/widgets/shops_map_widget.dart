import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
//import 'package:provider/provider.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
//import '../providers/shops_map_provider.dart';
import '../models/shop_models.dart';
import '../constants/shop_constants.dart';
//import 'dart:math';
import 'dart:async';

// ✅ FlutterMap용 마커 생성 - 클러스터링 포함
class ShopsMapMarkers {
  static List<Marker> buildMarkers(
    List<ShopModel> shops,
    Function(ShopModel) onMarkerTap,
  ) {
    //debugPrint('');
    //debugPrint('🏪 ════════════════════ ShopsMapMarkers.buildMarkers ════════════════════');
    //debugPrint('📦 입력된 샵: ${shops.length}개');
    
    // 같은 위치의 샵들을 그룹화
    final Map<String, List<ShopModel>> groupedByLocation = {};
    
    for (final shop in shops) {
      // ✅ 좌표를 3소수점까지만 고려 (약 111m 오차 범위)
      final key = '${shop.lat.toStringAsFixed(3)}_${shop.lng.toStringAsFixed(3)}';
      groupedByLocation.putIfAbsent(key, () => []).add(shop);
    }
    
    //debugPrint('🗺️  그룹화된 위치: ${groupedByLocation.length}개');
    
    final List<Marker> markers = [];
    
    groupedByLocation.forEach((location, shopsAtLocation) {
      if (shopsAtLocation.length == 1) {
        // ✅ 단일 샵 - 일반 마커
        //debugPrint('📍 단일 샵: ${shopsAtLocation.first.shopName}');
        markers.add(
          _buildSingleShopMarker(shopsAtLocation.first, onMarkerTap),
        );
      } else {
        // ✅ 복수 샵 - 클러스터 마커 (클릭 가능하게 수정)
        //debugPrint('📍 클러스터: ${shopsAtLocation.length}개 샵');
        markers.add(
          _buildShopClusterMarker(shopsAtLocation, onMarkerTap),
        );
      }
    });
    
    //debugPrint('✅ 최종 마커: ${markers.length}개');
    //debugPrint('🏪 ════════════════════════════════════════════════════════════════');
    //debugPrint('');
    
    return markers;
  }
  
  // ✅ 단일 샵 마커
  static Marker _buildSingleShopMarker(
    ShopModel shop,
    Function(ShopModel) onMarkerTap,
  ) {
    return Marker(
      key: ValueKey(shop.shopId),
      point: LatLng(shop.lat, shop.lng),
      width: 120,
      height: 140,
      child: GestureDetector(
        onTap: () => onMarkerTap(shop),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    // ignore: deprecated_member_use
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    shop.shopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    shop.category,
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Icon(
              Icons.location_on,
              color: Colors.deepPurple,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
  
  // ✅ 샵 클러스터 마커 - Desktop에서만 사용
  static Marker _buildShopClusterMarker(
    List<ShopModel> shops,
    Function(ShopModel) onMarkerTap,
  ) {
    final firstShop = shops.first;
    
    return Marker(
      key: ValueKey('shop_cluster_${firstShop.lat}_${firstShop.lng}'),
      point: LatLng(firstShop.lat, firstShop.lng),
      width: 140,
      height: 160,
      child: GestureDetector(
        // ✅ Desktop: 첫 번째 샵의 정보를 표시 (간단하게)
        onTap: () => onMarkerTap(firstShop),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    // ignore: deprecated_member_use
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '이 위치에',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${shops.length}개의 가게',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    shops.map((s) => s.shopName).join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Icon(
              Icons.location_on,
              color: Colors.orange,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}

// ✅ GlobalKey for Navigator (main.dart에서 설정 필요)
final navigatorKey = GlobalKey<NavigatorState>();

// ✅ 샵 정보 바텀시트
class ShopInfoBottomSheet extends StatelessWidget {
  final ShopModel shop;
  final Function(ShopModel)? onNavigate;
  
  const ShopInfoBottomSheet({
    super.key,
    required this.shop,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Container(
              decoration: BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shop.shopName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          shop.category,
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 설명
                  if (shop.description.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '설명',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          shop.description,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  
                  // 배너 메시지
                  if (shop.bannerMessage.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber),
                      ),
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.campaign,
                            color: Colors.amber,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              shop.bannerMessage,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  // 주소
                  _buildInfoRow(
                    Icons.location_on,
                    '주소',
                    shop.address,
                  ),
                  const SizedBox(height: 12),
                  
                  // 전화번호
                  _buildInfoRow(
                    Icons.phone,
                    '전화',
                    shop.phone,
                  ),
                  const SizedBox(height: 12),
                  
                  // 좌표
                  _buildInfoRow(
                    Icons.map,
                    '위치',
                    '${shop.lat.toStringAsFixed(4)}, ${shop.lng.toStringAsFixed(4)}',
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // 액션 버튼
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('전화: ${shop.phone}'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.call),
                          label: const Text('전화'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.deepPurple,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            onNavigate?.call(shop);
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.navigation),
                          label: const Text('길찾기'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.deepPurple),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ✅ 샵 필터 패널
class ShopFilterPanel extends StatefulWidget {
  final Set<String> selectedCategories;
  final TextEditingController searchController;
  final Function(Set<String>) onCategoryChanged;
  final Function(String) onSearch;
  
  const ShopFilterPanel({
    super.key,
    required this.selectedCategories,
    required this.searchController,
    required this.onCategoryChanged,
    required this.onSearch,
  });

  @override
  State<ShopFilterPanel> createState() => _ShopFilterPanelState();
}

class _ShopFilterPanelState extends State<ShopFilterPanel> {
  late TextEditingController _searchController;
  late Set<String> _localSelectedCategories;
  
  @override
  void initState() {
    super.initState();
    _searchController = widget.searchController;
    _localSelectedCategories = Set<String>.from(widget.selectedCategories);
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 검색
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: '샵 이름, 주소 검색...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  widget.onSearch('');
                },
              ),
            ),
            onChanged: widget.onSearch,
          ),
          
          const SizedBox(height: 16),
          
          const Text(
            '카테고리',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          
          // ✅ 카테고리 칩
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildCategoryChip(
                label: '전체',
                selected: _localSelectedCategories.isEmpty,
                onSelected: (selected) {
                  setState(() {
                    _localSelectedCategories.clear();
                    widget.onCategoryChanged({});
                  });
                },
              ),
              
              ...ShopConstants.shopCategories.map((cat) {
                return _buildCategoryChip(
                  label: cat,
                  selected: _localSelectedCategories.contains(cat),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _localSelectedCategories.add(cat);
                      } else {
                        _localSelectedCategories.remove(cat);
                      }
                      widget.onCategoryChanged(_localSelectedCategories);
                    });
                  },
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildCategoryChip({
    required String label,
    required bool selected,
    required Function(bool) onSelected,
  }) {
    return Material(
      child: InkWell(
        onTap: () => onSelected(!selected),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: selected ? Colors.deepPurple : Colors.grey[100],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? Colors.deepPurple : Colors.grey[300]!,
              width: 2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

// ✅ MapLibre용 심볼 추가
class ShopsMapLibreMarkers {
  static Future<void> addShopMarkers(
    maplibre.MapLibreMapController controller,
    List<ShopModel> shops,
  ) async {
    try {
      debugPrint('');
      debugPrint('📍 MapLibre에 ${shops.length}개 샵 마커 추가 중...');
      
      // 기존 심볼 제거
      try {
        await controller.clearLines();
      } catch (e) {
        debugPrint('⚠️  기존 라인 제거 실패 (무시): $e');
      }
      
      // 각 샵마다 심볼 추가
      for (final shop in shops) {
        try {
          await controller.addSymbol(
            maplibre.SymbolOptions(
              geometry: maplibre.LatLng(shop.lat, shop.lng),
              iconImage: 'marker-shop',
              iconSize: 1.5,
              textField: shop.shopName,
              textSize: 10,
              textColor: '#FFFFFF',
              textHaloColor: '#6200EA',
              textHaloWidth: 1.0,
              textAnchor: 'top',
              textOffset: const Offset(0, 1),
            ),
          );
        } catch (e) {
          debugPrint('⚠️  샵 마커 추가 실패: ${shop.shopName} - $e');
        }
      }
      
      debugPrint('✅ 모든 샵 마커 추가 완료');
      
    } catch (e) {
      debugPrint('❌ 샵 마커 추가 실패: $e');
    }
  }
}