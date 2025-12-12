// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import '../providers/locations_provider.dart';
import '../providers/auth_provider.dart';
import '../models/location_model.dart';
import 'login_page.dart';
import '../constants/appwrite_config.dart';
import '../appwriteClient.dart';
import 'package:appwrite/appwrite.dart';
import 'dart:math';
//import 'dart:ui' as ui;
import 'dart:ui' as ui;
import 'dart:typed_data';

//import 'package:flutter/material.dart';
//import 'package:provider/provider.dart';
import '../providers/user_message_provider.dart';
import '../providers/shop_provider.dart';
import '../providers/shops_map_provider.dart';
import '../widgets/shops_map_widget.dart';
import '../models/user_model.dart';
import '../models/shop_models.dart';
import '../widgets/messages_panel.dart';
import 'shop_owner_page.dart';
import '../services/navigation_service.dart';
import '../pages/user_promotions_page.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

// // ✅ 조건부 import
// import 'package:maplibre_gl/maplibre_gl.dart' if (dart.library.io) 'package:maplibre_gl/maplibre_gl.dart';
// import 'dart:html' if (dart.library.io) 'dart:html' as html; // Flutter Web 전용

class MapPage extends StatefulWidget {
  final String userId;
  const MapPage({super.key, required this.userId});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  MapLibreMapController? _mapLibreController;
  
  final latlong.Distance _distance = latlong.Distance();
  final Databases _db = appwriteDB;

  Timer? _updateTimer;
  Timer? _autoMoveTimer;
  Timer? _markerUpdateTimer;
  bool _autoMovingSon = false;
  bool _isUpdatingMarkers = false; // 업데이트 중 플래그
  DateTime? _lastManualUpdate; // 마지막 수동 업데이트 시간

  String _mapMode = 'REALTIME';
  
  // ✅ 4가지 타일 소스
  String _tileSource = 'LOCAL_TILE'; // LOCAL_TILE, LOCAL_3D, OSM_TILE, OSM_3D
  bool _is3DMode = false;

  String? _selectedGroupId = '';
  String? _selectedGroupName = '전체';
  List<Map<String, String>> _groups = [
    {'id': 'all', 'name': '전체'}
  ];

  int _dropdownKey = 0;

  final Map<String, latlong.LatLng> _lastPositions = {};
  final Map<String, DateTime?> _stopStartTimes = {};
  final Map<String, Duration> _elapsedDurations = {};
  Timer? _durationTimer;

  // ✅ 마커 관리
  final Map<String, Symbol> _symbols = {};

  double _currentZoom = 15.0; // 현재 줌 레벨 추적
  double _lastClusterZoom = 15.0; // 마지막으로 클러스터링한 줌 레벨
  final Map<String, LocationModel> _userMarkers = {}; // userId -> LocationModel
  final Map<String, List<LocationModel>> _clusterMarkers = {}; // cluster_id -> List<LocationModel>
  //StreamSubscription? _symbolClickSubscription; // Symbol만
  // ✅ 아이콘 등록 완료 여부
  bool _iconsRegistered = false;

  // ✅ 새로 추가
  UserRole _currentRole = UserRole.user;
  RouteResult? _currentRoute;
  TransportMode _selectedTransportMode = TransportMode.driving;
  Set<String> _selectedShopCategories = {};
  bool _showShopsLayer = true;

  final TextEditingController _searchController = TextEditingController();

  // ✅ 새로 추가: 경로 안내 관련
  List<dynamic> _currentInstructions = [];
  int? _selectedInstructionIndex;
  Symbol? _selectedInstructionMarker;
  bool _isInstructionPanelMinimized = false; // ✅ 최소화 상태

  // ✅ 샵 마커 관리 추가
  final Map<String, ShopModel> _shopMarkers = {}; // shopId -> ShopModel
  final Map<String, List<ShopModel>> _shopClusterMarkers = {}; // cluster_id -> List<ShopModel>


  // ✅ 플랫폼 확인
  // bool get _isDesktop {
  //   if (kIsWeb) {
  //     // Web에서는 window 객체 대신 화면 크기 기반 판단 (Flutter에서 제공)
  //     // 예: MediaQuery 사용
  //     return false; // Web 모바일/데스크탑 판단은 build 안에서 MediaQuery로 처리
  //   }

  //   try {
  //     return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  //   } catch (e) {
  //     return false;
  //   }
  // }

  bool get _isDesktop {
    if (kIsWeb) {
      //debugPrint('🌐 Web 환경 → FlutterMap(데스크탑 모드) 사용');
      return true; // ✅ Web도 데스크탑처럼 처리
    }

    try {
      final isDesktopPlatform =
          Platform.isWindows || Platform.isLinux || Platform.isMacOS;
      //debugPrint('💻 플랫폼 데스크탑 여부: $isDesktopPlatform');
      return isDesktopPlatform;
    } catch (e) {
      debugPrint('⚠️ 플랫폼 체크 실패: $e');
      return false;
    }
  }

  bool get _isMobile {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (e) {
      return false;
    }
  }

  // ============================================
  // 수정 1: initState - 타이머 복원 + 충돌 방지
  // ============================================
  // lib/pages/map_page.dart - initState 부분 수정
  @override
  void initState() {
    super.initState();
    
    debugPrint('');
    debugPrint('🎬 ════════════════════ MapPage initState ════════════════════');
    debugPrint('📍 userId: ${widget.userId}');
    
    final provider = context.read<LocationsProvider>();

    // ✅ 위치 로드 후 지도 카메라 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      final provider = context.read<LocationsProvider>();
      final myLocation = provider.locations[widget.userId];
      
      if (myLocation != null) {
        if (_isDesktop) {
          // FlutterMap 초기화
          _mapController.move(
            latlong.LatLng(myLocation.lat, myLocation.lng),
            16.0,
          );
          debugPrint('✅ FlutterMap 초기 위치 설정: (${myLocation.lat}, ${myLocation.lng})');
        } else if (_mapLibreController != null) {
          // MapLibre 초기화
          _mapLibreController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(myLocation.lat, myLocation.lng),
              16.0,
            ),
            duration: const Duration(milliseconds: 500),
          );
          debugPrint('✅ MapLibre 초기 위치 설정: (${myLocation.lat}, ${myLocation.lng})');
        }
      }
    });

    provider.resetRealtimeConnection();
    provider.startAll(startLocationStream: true);

    if (_mapMode == 'LOCAL') {
      _activateLocalMode(provider);
    } else {
      _activateRealtimeMode(provider);
    }

    _startStopTracking(provider);
    _startElapsedTimer(provider);

    if (_isMobile) {
      _startMarkerUpdateTimer(provider);
    }

    // ✅ 위치 로드 대기 + 첫 카메라 이동
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      debugPrint('🔄 위치 로드 대기 중...');
      
      // 최대 5초 동안 위치를 찾으려고 시도
      int attempts = 0;
      const maxAttempts = 10; // 5초 (0.5초 * 10)
      
      Timer.periodic(const Duration(milliseconds: 500), (timer) {
        attempts++;
        
        final locProvider = context.read<LocationsProvider>();
        final myLocation = locProvider.locations[widget.userId];
        
        if (myLocation != null) {
          timer.cancel();
          debugPrint('✅ 위치 로드 완료: (${myLocation.lat}, ${myLocation.lng})');
          
          // ✅ 내 위치로 카메라 즉시 이동 (중요!)
          if (_isDesktop) {
            _mapController.move(
              latlong.LatLng(myLocation.lat, myLocation.lng),
              16.0,
            );
            debugPrint('✅ FlutterMap 내 위치로 이동 완료');
          } else if (_mapLibreController != null) {
            _mapLibreController!.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng(myLocation.lat, myLocation.lng),
                16.0,
              ),
              duration: const Duration(milliseconds: 800),
            );
            debugPrint('✅ MapLibre 내 위치로 이동 완료');
          }
          
          // ✅ UserMessageProvider 초기화
          _initializeMessageProvider(myLocation);
          
        } else if (attempts >= maxAttempts) {
          timer.cancel();
          debugPrint('⚠️  위치 로드 타임아웃');
          debugPrint('📍 현재 위치 목록: ${locProvider.locations.keys.toList()}');
          
          // 더미 위치로라도 초기화 (서울 시청)
          final dummyLocation = LocationModel(
            id: 'dummy_${widget.userId}',
            userId: widget.userId,
            lat: 37.566,
            lng: 126.978,
            accuracy: 10.0,
            speed: 0.0,
            heading: 0.0,
            timestamp: DateTime.now(),
          );
          
          // ✅ 더미 위치로도 이동
          if (_isDesktop) {
            _mapController.move(
              latlong.LatLng(dummyLocation.lat, dummyLocation.lng),
              14.0,
            );
          } else if (_mapLibreController != null) {
            _mapLibreController!.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng(dummyLocation.lat, dummyLocation.lng),
                14.0,
              ),
              duration: const Duration(milliseconds: 500),
            );
          }
          
          _initializeMessageProvider(dummyLocation);
        } else {
          debugPrint('⏳ 위치 대기 중... ($attempts/${maxAttempts})');
        }
      });
    });
    
    // ShopsMapProvider 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final shopsProvider = context.read<ShopsMapProvider>();
        debugPrint('📦 ShopsMapProvider 초기화 중...');
        shopsProvider.fetchAllShops();
        shopsProvider.startAutoRefresh();
        debugPrint('✅ ShopsMapProvider 초기화 완료');
      }
    });
    
    // 유저 역할 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadUserRole();
      }
    });
    
    debugPrint('🎬 ════════════════════ initState 완료 ════════════════════');
    debugPrint('');
  }

  // ============================================
  // ✅ Symbol 클릭 핸들러 - 샵 클러스터링 완전 통합
  // ============================================
  Future<void> _handleSymbolClickWithShops(
    LatLng clickedLatLng,
    LocationsProvider provider,
    ShopsMapProvider shopsProvider,
  ) async {
    const tolerance = 0.0001; // 약 11m
    
    debugPrint('');
    debugPrint('🎯 ════════════════════ Symbol 클릭 감지 ════════════════════');
    debugPrint('📍 클릭 좌표: (${clickedLatLng.latitude.toStringAsFixed(6)}, ${clickedLatLng.longitude.toStringAsFixed(6)})');
    debugPrint('🔍 현재 샵 클러스터: ${_shopClusterMarkers.length}개');
    debugPrint('🔍 현재 단일 샵: ${_shopMarkers.length}개');
    debugPrint('🔍 현재 유저 클러스터: ${_clusterMarkers.length}개');
    debugPrint('🔍 현재 단일 유저: ${_userMarkers.length}개');
    
    // ✅ Step 1: 샵 클러스터 확인
    debugPrint('⏳ Step 1: 샵 클러스터 확인 중...');
    
    for (var entry in _shopClusterMarkers.entries) {
      final clusterId = entry.key;
      final cluster = entry.value;
      
      if (cluster.isEmpty) continue;
      
      double sumLat = 0, sumLng = 0;
      for (final shop in cluster) {
        sumLat += shop.lat;
        sumLng += shop.lng;
      }
      final centerLat = sumLat / cluster.length;
      final centerLng = sumLng / cluster.length;
      
      final distance = sqrt(
        pow(centerLat - clickedLatLng.latitude, 2) + 
        pow(centerLng - clickedLatLng.longitude, 2)
      );
      
      debugPrint('   📍 클러스터 $clusterId: 중심(${centerLat.toStringAsFixed(6)}, ${centerLng.toStringAsFixed(6)}), 거리=${distance.toStringAsFixed(6)}');
      
      if (distance < tolerance) {
        debugPrint('✅ 샵 클러스터 매치! ${cluster.length}개 샵');
        _showShopsListBottomSheet(cluster);
        debugPrint('🎯 ════════════════════ 샵 클러스터 BottomSheet 열림 ════════════════════');
        debugPrint('');
        return;
      }
    }
    
    // ✅ Step 2: 단일 샵 확인
    debugPrint('⏳ Step 2: 단일 샵 확인 중...');
    
    for (var entry in _shopMarkers.entries) {
      final shopId = entry.key;
      final shop = entry.value;
      
      final distance = sqrt(
        pow(shop.lat - clickedLatLng.latitude, 2) + 
        pow(shop.lng - clickedLatLng.longitude, 2)
      );
      
      debugPrint('   📍 샵 $shopId (${shop.shopName}): (${shop.lat.toStringAsFixed(6)}, ${shop.lng.toStringAsFixed(6)}), 거리=${distance.toStringAsFixed(6)}');
      
      if (distance < tolerance) {
        debugPrint('✅ 단일 샵 매치! ${shop.shopName}');
        _showShopInfo(shop);
        debugPrint('🎯 ════════════════════ 샵 정보 표시 ════════════════════');
        debugPrint('');
        return;
      }
    }
    
    // ✅ Step 3: 유저 클러스터 확인
    debugPrint('⏳ Step 3: 유저 클러스터 확인 중...');
    
    for (var entry in _clusterMarkers.entries) {
      final cluster = entry.value;
      
      if (cluster.isEmpty) continue;
      
      double sumLat = 0, sumLng = 0;
      for (final loc in cluster) {
        sumLat += loc.lat;
        sumLng += loc.lng;
      }
      final centerLat = sumLat / cluster.length;
      final centerLng = sumLng / cluster.length;
      
      final distance = sqrt(
        pow(centerLat - clickedLatLng.latitude, 2) + 
        pow(centerLng - clickedLatLng.longitude, 2)
      );
      
      if (distance < tolerance) {
        debugPrint('✅ 유저 클러스터 ${cluster.length}명 발견');
        _showClusterUsersBottomSheet(cluster, provider);
        debugPrint('🎯 ════════════════════ 유저 BottomSheet 열림 ════════════════════');
        debugPrint('');
        return;
      }
    }
    
    // ✅ Step 4: 단일 유저 확인
    debugPrint('⏳ Step 4: 단일 유저 확인 중...');
    
    for (var entry in _userMarkers.entries) {
      final loc = entry.value;
      
      final distance = sqrt(
        pow(loc.lat - clickedLatLng.latitude, 2) + 
        pow(loc.lng - clickedLatLng.longitude, 2)
      );
      
      if (distance < tolerance) {
        debugPrint('✅ 유저 발견: ${loc.userId}');
        _showUserInfo(loc);
        debugPrint('🎯 ════════════════════ 유저 정보 표시 ════════════════════');
        debugPrint('');
        return;
      }
    }
    
    debugPrint('❌ 일치하는 마커 없음');
    debugPrint('🎯 ════════════════════ Symbol 클릭 실패 ════════════════════');
    debugPrint('');
  }

  // ============================================
  // ✅ 샵 목록 BottomSheet - 유저 클러스터처럼 각 샵 선택 가능하도록 개선
  // ============================================
  void _showShopsListBottomSheet(List<ShopModel> shops) {
    debugPrint('');
    debugPrint('📍 ════════════════════ 샵 목록 BottomSheet 열기 ════════════════════');
    debugPrint('📦 샵 개수: ${shops.length}개');
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // ✅ 헤더
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '이 위치의 가게',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${shops.length}개 가게',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            // ✅ 샵 목록 - 각 샵마다 상세 정보와 길찾기 버튼 추가
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: shops.length,
                itemBuilder: (context, index) {
                  final shop = shops[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          onTap: () {
                            debugPrint('🎯 샵 클릭: ${shop.shopName}');
                            // 클릭 시 상세 정보 토글
                          },
                          leading: CircleAvatar(
                            backgroundColor: Colors.deepPurple,
                            child: Text(
                              shop.shopName[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            shop.shopName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(shop.category),
                              Text(
                                shop.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        // ✅ 길찾기 버튼 추가
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    debugPrint('🗺️ 길찾기 버튼 클릭: ${shop.shopName}');
                                    Navigator.pop(context);
                                    _navigateToShop(shop, null);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepPurple,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  icon: const Icon(Icons.navigation, size: 18),
                                  label: const Text('길찾기'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () {
                                  debugPrint('ℹ️ 상세 정보 버튼 클릭: ${shop.shopName}');
                                  Navigator.pop(context);
                                  _showShopInfo(shop);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey[600],
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                ),
                                icon: const Icon(Icons.info_outline, size: 18),
                                label: const Text('상세'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ 샵 정보 표시
  void _showShopInfo(ShopModel shop) {
    showModalBottomSheet(
      context: context,
      builder: (_) => ShopInfoBottomSheet(
        shop: shop,
        onNavigate: (shop) {
          _navigateToShop(shop, null);
        },
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  // ✅ MessageProvider 초기화 함수 추출
  void _initializeMessageProvider(LocationModel myLocation) {
    debugPrint('');
    debugPrint('🔧 ════════════════════ UserMessageProvider 초기화 ════════════════════');
    
    final msgProvider = context.read<UserMessageProvider>();
    
    debugPrint('📍 위치: (${myLocation.lat}, ${myLocation.lng})');
    debugPrint('👤 사용자: ${widget.userId}');
    
    msgProvider.initialize(
      widget.userId,
      myLocation.lat,
      myLocation.lng,
    );
    
    debugPrint('✅ UserMessageProvider 초기화 완료');
    debugPrint('🔧 ════════════════════ 초기화 완료 ════════════════════');
    debugPrint('');
  }

  // ✅ 2. 유저 역할 로드
  Future<void> _loadUserRole() async {
    try {
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.usersCollectionId,
        queries: [Query.equal('userId', widget.userId)],
      );
      
      if (result.documents.isNotEmpty) {
        final userData = result.documents.first.data;
        final role = userData['role'] ?? 'user';
        
        setState(() {
          _currentRole = role == 'shopOwner' 
              ? UserRole.shopOwner 
              : UserRole.user;
        });
      }
    } catch (e) {
      debugPrint('❌ 역할 로드 실패: $e');
    }
  }
  
  // ✅ 3. 역할 전환
  Future<void> _switchRole(UserRole newRole) async {
    try {
      // DB에 역할 업데이트
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.usersCollectionId,
        queries: [Query.equal('userId', widget.userId)],
      );
      
      if (result.documents.isNotEmpty) {
        await _db.updateDocument(
          databaseId: AppwriteConstants.databaseId,
          collectionId: AppwriteConstants.usersCollectionId,
          documentId: result.documents.first.$id,
          data: {'role': newRole.name},
        );
        
        setState(() {
          _currentRole = newRole;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newRole == UserRole.shopOwner 
                  ? '✅ 샵 주인 모드로 전환'
                  : '✅ 유저 모드로 전환'
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ 역할 전환 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('역할 전환 실패')),
      );
    }
  }
  
  // ✅ 4. 샵 주인 페이지로 이동
  void _openShopOwnerPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => ShopProvider(),
          child: ShopOwnerPage(userId: widget.userId),
        ),
      ),
    );
  }
  
  // ✅ 3. 길찾기 실행 (개선된 버전 - 이동수단 고려)
  Future<void> _navigateToShop(ShopModel shop, ShopMessageModel? message) async {
    final provider = context.read<LocationsProvider>();
    final myLocation = provider.locations[widget.userId];
    
    if (myLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 위치를 확인할 수 없습니다')),
      );
      return;
    }
    
    try {
      debugPrint('');
      debugPrint('🗺️ ════════════════════ _navigateToShop 호출됨 ════════════════════');
      debugPrint('🏪 가게: ${shop.shopName}');
      // ✅ toOSRMProfile() 대신 문자열로 직접 표시
      debugPrint('🚗 현재 선택된 이동수단: ${_selectedTransportMode == TransportMode.driving ? 'driving' : _selectedTransportMode == TransportMode.walking ? 'walking' : 'cycling'}');
      
      // ✅ 현재 선택된 이동수단으로 경로 생성
      final navigationService = NavigationService();
      final route = await navigationService.getRoute(
        start: latlong.LatLng(myLocation.lat, myLocation.lng),
        end: latlong.LatLng(shop.lat, shop.lng),
        mode: _selectedTransportMode, // ✅ 선택된 이동수단 사용
      );
      
      if (route == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ 경로를 찾을 수 없습니다')),
          );
        }
        return;
      }
      
      debugPrint('✅ 경로 생성 성공');
      debugPrint('   이동수단: ${route.transportModeString}');
      debugPrint('   거리: ${route.formattedDistance}');
      debugPrint('   시간: ${route.formattedDuration}');
      
      // ✅ setState로 경로 업데이트
      if (mounted) {
        setState(() {
          _currentRoute = route;
        });
        debugPrint('✅ setState 호출 - 경로 업데이트');
      }
      
      // 지도에 경로 표시
      if (_isDesktop) {
        _showRouteOnFlutterMap(route, shop);
      } else {
        await _showRouteOnMapLibre(route, shop);
      }
      
      // ✅ 네비게이션 패널 표시
      if (mounted) {
        _showNavigationPanel(shop, route);
      }
      
      debugPrint('🗺️ ════════════════════ _navigateToShop 완료 ════════════════════');
      debugPrint('');
      
    } catch (e) {
      debugPrint('❌ _navigateToShop 오류: $e');
    }
  }
  
  // ✅ 4. FlutterMap에 경로 표시
  void _showRouteOnFlutterMap(RouteResult route, ShopModel shop) {
    debugPrint('');
    debugPrint('🗺️ ════════════════════ FlutterMap 경로 표시 ════════════════════');
    debugPrint('   경로 포인트: ${route.coordinates.length}개');
    debugPrint('   거리: ${route.formattedDistance}');
    debugPrint('   시간: ${route.formattedDuration}');
    debugPrint('   이동수단: ${route.transportModeString}');
    debugPrint('🗺️ ════════════════════════════════════════════════════════');
    debugPrint('');
    
    // ✅ setState로 지도를 다시 그림
    setState(() {
      _currentRoute = route;
    });
    
    // ✅ 맵 컨트롤러로 경로 중심 이동
    if (route.coordinates.isNotEmpty) {
      final centerLat = route.coordinates
          .map((p) => p.latitude)
          .reduce((a, b) => (a + b) / 2);
      final centerLng = route.coordinates
          .map((p) => p.longitude)
          .reduce((a, b) => (a + b) / 2);
      
      _mapController.move(
        latlong.LatLng(centerLat, centerLng),
        14.0,
      );
    }
  }

  Widget _buildFlutterMapWithShopsAndRoute(LocationsProvider provider) {
    final allLocs = provider.getDisplayLocations();
    
    return Consumer<ShopsMapProvider>(
      builder: (context, shopsProvider, _) {
        // 샵 마커 생성
        final List<Marker> shopMarkers = _showShopsLayer
            ? ShopsMapMarkers.buildMarkers(
                shopsProvider.filteredShops,
                _onShopMarkerTap,
              )
            : <Marker>[];
        
        return FutureBuilder<List<LocationModel>>(
          future: _filterLocationsByGroup(allLocs),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final locs = snapshot.data!;
            
            // 사용자 위치 마커 생성
            final userMarkers = locs.map((l) {
              final stay = _formatDuration(l.userId, provider);
              final isMe = l.userId == widget.userId;
              final displayName = l.userId;
              final initials = displayName.isNotEmpty 
                  ? displayName[0].toUpperCase() 
                  : '?';

              return Marker(
                key: ValueKey(l.userId),
                point: latlong.LatLng(l.lat, l.lng),
                width: 80,
                height: 90,
                child: GestureDetector(
                  onTap: () => _showUserInfo(l),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: isMe ? Colors.blue : Colors.grey,
                            child: Text(
                              initials,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          if (stay.isNotEmpty)
                            Positioned(
                              bottom: -25,
                              child: Text(
                                stay,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Icon(
                        Icons.place,
                        color: isMe ? Colors.blue : Colors.red,
                        size: 30,
                      ),
                      Text(
                        _short(displayName),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              );
            }).toList();

            final me = provider.locations[widget.userId];
            final center = me != null 
                ? LatLng(me.lat, me.lng) 
                : const LatLng(37.5665, 126.9780);

            // ✅ 경로 표시 레이어 생성
            final routeLayers = <Widget>[];
            
            if (_currentRoute != null) {
              // 경로 폴리라인
              routeLayers.add(
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _currentRoute!.coordinates,
                      color: Colors.blue,
                      strokeWidth: 4.0,
                    ),
                  ],
                ),
              );
              
              // 시작점 마커
              routeLayers.add(
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentRoute!.coordinates.first,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.green,
                        ),
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    // 목적지 마커
                    Marker(
                      point: _currentRoute!.coordinates.last,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red,
                        ),
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: latlong.LatLng(center.latitude, center.longitude),
                    initialZoom: 14.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _tileSource == 'LOCAL_TILE'
                          ? 'http://vranks.iptime.org:8080/styles/maptiler-basic/{z}/{x}/{y}.png'
                          : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.location_share_app',
                    ),
                    // ✅ 경로 레이어 추가 (사용자 마커 전에)
                    ...routeLayers,
                    
                    // 샵 마커 레이어
                    if (_showShopsLayer)
                      MarkerLayer(markers: shopMarkers),
                    
                    // 사용자 마커
                    MarkerClusterLayerWidget(
                      options: MarkerClusterLayerOptions(
                        maxClusterRadius: 45,
                        size: const Size(50, 50),
                        markers: userMarkers,
                        onClusterTap: (cluster) => 
                            _showClusterUsers(cluster.markers),
                        builder: (context, clusterMarkers) => Container(
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.orange,
                          ),
                          child: Text(
                            '${clusterMarkers.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                _buildFloatingButtons(provider, isDesktop: true),
              ],
            );
          },
        );
      },
    );
  }

  // ✅ 5. MapLibre에 경로 표시
  Future<void> _showRouteOnMapLibre(RouteResult route, ShopModel shop) async {
    if (_mapLibreController == null) return;
    
    try {
      debugPrint('🎯 MapLibre에 경로 추가 중...');
      debugPrint('   이동수단: ${route.transportModeString}');
      
      // 경로 라인 추가
      await _mapLibreController!.addLine(
        maplibre.LineOptions(
          geometry: route.coordinates.map((coord) {
            return maplibre.LatLng(coord.latitude, coord.longitude);
          }).toList(),
          lineColor: '#2196F3',
          lineWidth: 5.0,
          lineOpacity: 0.8,
        ),
      );
      
      debugPrint('✅ 경로 라인 추가 완료');
      
    } catch (e) {
      debugPrint('❌ 경로 표시 실패: $e');
    }
  }

  // ✅ 6. 네비게이션 패널 - 완전 개선 (이동수단 선택 유지)
  void _showNavigationPanel(ShopModel shop, RouteResult route) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 헤더
                Row(
                  children: [
                    const Icon(Icons.navigation, color: Colors.blue, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shop.shopName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${route.formattedDistance} · ${route.formattedDuration}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() => _currentRoute = null);
                      },
                    ),
                  ],
                ),
                
                const Divider(),
                const SizedBox(height: 12),
                
                // 이동 수단 선택
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '이동 수단 선택',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildTransportModeButton(
                            icon: Icons.directions_car,
                            label: '자동차',
                            mode: TransportMode.driving,
                            onChanged: () async {
                              setModalState(() => _selectedTransportMode = TransportMode.driving);
                              debugPrint('🚗 자동차 모드 선택');
                              
                              final navigationService = NavigationService();
                              final locProvider = context.read<LocationsProvider>();
                              final myLocation = locProvider.locations[widget.userId];
                              
                              if (myLocation != null) {
                                final newRoute = await navigationService.getRoute(
                                  start: latlong.LatLng(myLocation.lat, myLocation.lng),
                                  end: latlong.LatLng(shop.lat, shop.lng),
                                  mode: TransportMode.driving,
                                );
                                
                                if (newRoute != null) {
                                  setModalState(() => _currentRoute = newRoute);
                                  if (_isMobile) {
                                    await _showRouteOnMapLibre(newRoute, shop);
                                  } else {
                                    _showRouteOnFlutterMap(newRoute, shop);
                                  }
                                }
                              }
                            },
                          ),
                          _buildTransportModeButton(
                            icon: Icons.directions_walk,
                            label: '도보',
                            mode: TransportMode.walking,
                            onChanged: () async {
                              setModalState(() => _selectedTransportMode = TransportMode.walking);
                              debugPrint('🚶 도보 모드 선택');
                              
                              final navigationService = NavigationService();
                              final locProvider = context.read<LocationsProvider>();
                              final myLocation = locProvider.locations[widget.userId];
                              
                              if (myLocation != null) {
                                final newRoute = await navigationService.getRoute(
                                  start: latlong.LatLng(myLocation.lat, myLocation.lng),
                                  end: latlong.LatLng(shop.lat, shop.lng),
                                  mode: TransportMode.walking,
                                );
                                
                                if (newRoute != null) {
                                  setModalState(() => _currentRoute = newRoute);
                                  if (_isMobile) {
                                    await _showRouteOnMapLibre(newRoute, shop);
                                  } else {
                                    _showRouteOnFlutterMap(newRoute, shop);
                                  }
                                }
                              }
                            },
                          ),
                          _buildTransportModeButton(
                            icon: Icons.directions_bike,
                            label: '자전거',
                            mode: TransportMode.cycling,
                            onChanged: () async {
                              setModalState(() => _selectedTransportMode = TransportMode.cycling);
                              debugPrint('🚴 자전거 모드 선택');
                              
                              final navigationService = NavigationService();
                              final locProvider = context.read<LocationsProvider>();
                              final myLocation = locProvider.locations[widget.userId];
                              
                              if (myLocation != null) {
                                final newRoute = await navigationService.getRoute(
                                  start: latlong.LatLng(myLocation.lat, myLocation.lng),
                                  end: latlong.LatLng(shop.lat, shop.lng),
                                  mode: TransportMode.cycling,
                                );
                                
                                if (newRoute != null) {
                                  setModalState(() => _currentRoute = newRoute);
                                  if (_isMobile) {
                                    await _showRouteOnMapLibre(newRoute, shop);
                                  } else {
                                    _showRouteOnFlutterMap(newRoute, shop);
                                  }
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // 길찾기 정보
                if (_currentRoute != null)
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info, color: Colors.blue[700]),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_currentRoute!.transportModeString} · ${_currentRoute!.formattedDuration}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                  Text(
                                    _currentRoute!.formattedDistance,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // ✅ 길찾기 시작 버튼 (중요한 부분!)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            debugPrint('');
                            debugPrint('🚀 ════════════════════ 길찾기 시작 ════════════════════');
                            debugPrint('   목적지: ${shop.shopName}');
                            debugPrint('   이동 수단: ${_currentRoute!.transportModeString}');
                            debugPrint('   거리: ${_currentRoute!.formattedDistance}');
                            debugPrint('   시간: ${_currentRoute!.formattedDuration}');
                            debugPrint('   안내 스텝: ${_currentRoute!.instructions.length}개');
                            debugPrint('🚀 ════════════════════════════════════════════════');
                            debugPrint('');
                            
                            // ✅ 이것이 핵심! setState를 사용해야 UI 업데이트됨
                            setState(() {
                              _currentInstructions = _currentRoute!.instructions;
                              _selectedInstructionIndex = null;
                              debugPrint('✅ setState 완료: _currentInstructions = ${_currentInstructions.length}개');
                            });
                            
                            Navigator.pop(context);
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '🚀 ${shop.shopName}으로 가는 길입니다!\n'
                                  '${_currentRoute!.transportModeString} ${_currentRoute!.formattedDuration}',
                                ),
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.navigation),
                          label: const Text(
                            '길찾기 시작',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      )
    );
  }
  
  // ✅ 2. 지도 위 안내 패널 (왼쪽 아래에 표시)
  Widget _buildRouteInstructionPanel() {
    if (_currentInstructions.isEmpty || _currentRoute == null) {
      return const SizedBox.shrink();
    }

    // ✅ 최소화된 상태
    if (_isInstructionPanelMinimized) {
      return Positioned(
        bottom: 18,
        left: 18,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _isInstructionPanelMinimized = false;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.navigation, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  '${_currentInstructions.length}개 스텝',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ✅ 전체 패널 표시
    return Positioned(
      bottom: 18,
      left: 18,
      child: Container(
        width: 320,
        height: 420,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // ✅ 헤더 (종료 alert + 최소화 버튼)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '경로 안내',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_currentInstructions.length}개 스텝',
                        style: const TextStyle(
                          color: Colors.lightBlueAccent,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // ✅ 최소화 버튼 (_)
                      IconButton(
                        icon: const Icon(Icons.minimize, color: Colors.white, size: 20),
                        onPressed: () {
                          setState(() {
                            _isInstructionPanelMinimized = true;
                          });
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: '최소화',
                      ),
                      const SizedBox(width: 4),
                      // ✅ 종료 버튼 (X)
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 20),
                        onPressed: () {
                          // ✅ Alert 띄우기
                          showDialog(
                            context: context,
                            builder: (BuildContext dialogContext) {
                              return AlertDialog(
                                title: const Text('길찾기 종료'),
                                content: const Text('길찾기를 종료하시겠습니까?'),
                                actions: [
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(dialogContext);
                                    },
                                    child: const Text('취소'),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(dialogContext);
                                      
                                      // ✅ 상태 초기화
                                      setState(() {
                                        _currentInstructions = [];
                                        _selectedInstructionIndex = null;
                                        _currentRoute = null;
                                        
                                        // 선택된 마커 제거
                                        if (_selectedInstructionMarker != null && _mapLibreController != null) {
                                          try {
                                            _mapLibreController!.removeSymbol(_selectedInstructionMarker!);
                                          } catch (e) {
                                            debugPrint('⚠️ 마커 제거 실패: $e');
                                          }
                                          _selectedInstructionMarker = null;
                                        }
                                      });
                                      
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('길찾기가 종료되었습니다'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    child: const Text('종료'),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: '길찾기 종료',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ✅ 스텝 리스트 (스크롤 가능)
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _currentInstructions.length,
                itemBuilder: (context, index) {
                  final instruction = _currentInstructions[index];
                  final isSelected = _selectedInstructionIndex == index;

                  // ✅ 상세한 안내 텍스트 추출
                  final detailedInstruction = _getDetailedInstructionText(instruction);
                  final formattedDistance = instruction.formattedDistance ?? '0m';
                  final duration = instruction.duration ?? 0;

                  return GestureDetector(
                    onTap: () async {
                      setState(() {
                        _selectedInstructionIndex = index;
                      });

                      // 이전 마커 제거
                      if (_selectedInstructionMarker != null && _mapLibreController != null) {
                        try {
                          await _mapLibreController!.removeSymbol(_selectedInstructionMarker!);
                        } catch (e) {
                          debugPrint('⚠️ 이전 마커 제거 실패: $e');
                        }
                      }

                      // 새 마커 추가
                      if (_mapLibreController != null && _isMobile) {
                        try {
                          final stepStartIndex = (index * _currentRoute!.coordinates.length ~/ _currentInstructions.length);
                          final stepCoord = _currentRoute!.coordinates[stepStartIndex];

                          debugPrint('');
                          debugPrint('📍 ════════════════════ 스텝 마커 추가 ════════════════════');
                          debugPrint('   스텝: ${index + 1}/${_currentInstructions.length}');
                          debugPrint('   안내: $detailedInstruction');
                          debugPrint('   거리: $formattedDistance');
                          debugPrint('   좌표: (${stepCoord.latitude.toStringAsFixed(6)}, ${stepCoord.longitude.toStringAsFixed(6)})');

                          _selectedInstructionMarker = await _mapLibreController!.addSymbol(
                            SymbolOptions(
                              geometry: LatLng(stepCoord.latitude, stepCoord.longitude),
                              iconImage: 'circle_orange',
                              iconSize: 1.2,
                              iconAnchor: 'center',
                            ),
                          );

                          await _mapLibreController!.animateCamera(
                            CameraUpdate.newLatLng(
                              LatLng(stepCoord.latitude, stepCoord.longitude),
                            ),
                            duration: const Duration(milliseconds: 800),
                          );

                          debugPrint('✅ 마커 추가 완료: ${_selectedInstructionMarker!.id}');
                          debugPrint('📍 ════════════════════════════════════════════════');
                          debugPrint('');
                        } catch (e) {
                          debugPrint('❌ 마커 추가 실패: $e');
                        }
                      } else if (_isDesktop) {
                        try {
                          final stepStartIndex = (index * _currentRoute!.coordinates.length ~/ _currentInstructions.length);
                          final stepCoord = _currentRoute!.coordinates[stepStartIndex];

                          debugPrint('📍 Desktop에서 위치 이동: (${stepCoord.latitude}, ${stepCoord.longitude})');

                          _mapController.move(
                            latlong.LatLng(stepCoord.latitude, stepCoord.longitude),
                            16.0,
                          );
                        } catch (e) {
                          debugPrint('❌ Desktop 이동 실패: $e');
                        }
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blue[100] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? Colors.blue : Colors.grey[300]!,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // ✅ 스텝 번호
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected ? Colors.blue : Colors.grey[400],
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // ✅ 상세한 안내 텍스트
                              Expanded(
                                child: Text(
                                  detailedInstruction,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected ? Colors.blue[700] : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // ✅ 거리 및 시간
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 12,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                formattedDistance,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(
                                Icons.schedule,
                                size: 12,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                duration > 0 ? '${duration}분' : '-',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ 이동 수단 버튼
  Widget _buildTransportModeButton({
    required IconData icon,
    required String label,
    required TransportMode mode,
    required Future<void> Function() onChanged,
  }) {
    final isSelected = _selectedTransportMode == mode;
    
    return InkWell(
      onTap: () async {
        setState(() => _selectedTransportMode = mode);
        // ✅ onChanged 콜백 호출 (새 경로 계산)
        await onChanged();
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[600],
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isSelected ? Colors.blue : Colors.grey[600],
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // 2. 커스텀 원형 아이콘 등록 (각 유저별로 동적 생성)
  // ============================================
  Future<void> _registerCustomIcons() async {
    if (_mapLibreController == null || _iconsRegistered) return;
    
    debugPrint('🎨 커스텀 아이콘 등록 중...');
    
    try {
      // ✅ 기본 원형 아이콘만 등록 (텍스트 없이)
      await _mapLibreController!.addImage(
        'circle_blue',
        await _createCircleImage(Colors.blue, 44),
      );
      
      await _mapLibreController!.addImage(
        'circle_red',
        await _createCircleImage(Colors.red, 44),
      );
      
      await _mapLibreController!.addImage(
        'circle_orange',
        await _createCircleImage(Colors.orange, 60),
      );
      
      _iconsRegistered = true;
      debugPrint('✅ 커스텀 아이콘 등록 완료');
      
    } catch (e) {
      debugPrint('❌ 아이콘 등록 실패: $e');
    }
  }

  // ============================================
  // 2-1. 텍스트가 포함된 동적 아이콘 생성 및 등록
  // ============================================
  Future<void> _registerIconWithText(
    String iconKey,
    Color color,
    String text,
    int size,
  ) async {
    if (_mapLibreController == null) return;
    
    try {
      final imageData = await _createCircleImageWithText(color, size, text);
      await _mapLibreController!.addImage(iconKey, imageData);
      debugPrint('✅ 아이콘 등록: $iconKey ($text)');
    } catch (e) {
      debugPrint('❌ 아이콘 등록 실패 ($iconKey): $e');
    }
  }

  // ============================================
  // 3. 텍스트 포함 원형 이미지 생성
  // ============================================
  Future<Uint8List> _createCircleImageWithText(
    Color color,
    int size,
    String text,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // 원 그리기
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..isAntiAlias = true;
    
    final center = Offset(size / 2.0, size / 2.0);
    final radius = (size / 2.0) - 3;
    
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(center, radius, strokePaint);
    
  // ✅ 텍스트 그리기
  final textPainter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: Colors.white,
        fontSize: size * 0.4, // 크기에 비례
        fontWeight: FontWeight.bold,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
  );
    
    textPainter.layout();
    
    // 텍스트를 중앙에 배치
    final textOffset = Offset(
      center.dx - textPainter.width / 2,
      center.dy - textPainter.height / 2,
    );
    
    textPainter.paint(canvas, textOffset);
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    
    if (byteData == null) {
      throw Exception('Failed to create circle image with text');
    }
    
    return byteData.buffer.asUint8List();
  }

  // ============================================
  // 3. 원형 이미지 생성 (PNG Uint8List) - 개선 버전
  // ============================================
  Future<Uint8List> _createCircleImage(Color color, int size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // ✅ 배경을 투명하게
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true; // 안티앨리어싱 추가
    
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0 // 더 두껍게
      ..isAntiAlias = true;
    
    final center = Offset(size / 2.0, size / 2.0);
    final radius = (size / 2.0) - 3; // 여백 확보
    
    // 원 그리기
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(center, radius, strokePaint);
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    
    if (byteData == null) {
      debugPrint('❌ byteData is null!');
      throw Exception('Failed to create circle image');
    }
    
    debugPrint('✅ Circle image created: ${byteData.lengthInBytes} bytes');
    return byteData.buffer.asUint8List();
  }

  // ============================================
  // 수정 2: 마커 업데이트 타이머 - 충돌 방지 로직 추가
  // ============================================
  void _startMarkerUpdateTimer(LocationsProvider provider) {
    _markerUpdateTimer?.cancel();
    _markerUpdateTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      // ✅ 이미 업데이트 중이면 스킵
      if (_isUpdatingMarkers) {
        debugPrint('⏭️  마커 업데이트 중... 스킵');
        return;
      }
      
      // ✅ 최근 1초 이내에 수동 업데이트가 있었으면 스킵 (onCameraIdle과 충돌 방지)
      if (_lastManualUpdate != null && 
          DateTime.now().difference(_lastManualUpdate!) < const Duration(seconds: 1)) {
        debugPrint('⏭️  최근 수동 업데이트 있음... 스킵');
        return;
      }
      
      if (_mapLibreController != null && mounted && _isMobile) {
        debugPrint('🔄 [타이머] 주기적 마커 업데이트');
        await _updateMapLibreMarkers(provider, isAutoUpdate: true);
      }
    });
  }

  // ✅ 3D 모드 토글 (모바일 전용)
  Future<void> _toggle3DMode() async {
    if (!_isMobile || _mapLibreController == null) return;

    setState(() => _is3DMode = !_is3DMode);

    if (_is3DMode) {
      await _mapLibreController!.animateCamera(
        CameraUpdate.tiltTo(60.0),
        duration: const Duration(milliseconds: 1000),
      );
    } else {
      await _mapLibreController!.animateCamera(
        CameraUpdate.tiltTo(0.0),
        duration: const Duration(milliseconds: 1000),
      );
      await _mapLibreController!.animateCamera(
        CameraUpdate.bearingTo(0.0),
        duration: const Duration(milliseconds: 500),
      );
    }
  }

  // ✅ 타일 소스 순환 변경
  void _toggleTileSource() {
    setState(() {
      if (_isMobile) {
        // 모바일: 4가지 소스 순환
        switch (_tileSource) {
          case 'LOCAL_TILE':
            _tileSource = 'LOCAL_3D';
            _is3DMode = true;
            break;
          case 'LOCAL_3D':
            _tileSource = 'OSM_TILE';
            _is3DMode = false;
            break;
          case 'OSM_TILE':
            _tileSource = 'OSM_3D';
            _is3DMode = true;
            break;
          case 'OSM_3D':
            _tileSource = 'LOCAL_TILE';
            _is3DMode = false;
            break;
        }
      } else {
        // 데스크톱: 2가지 소스만 (2D)
        _tileSource = _tileSource == 'LOCAL_TILE' ? 'OSM_TILE' : 'LOCAL_TILE';
      }
    });
  }

  // ✅ 타일 소스 URL 가져오기
  String _getMapLibreStyleUrl() {
    switch (_tileSource) {
      case 'LOCAL_TILE':
        return 'http://vranks.iptime.org:8080/styles/maptiler-basic/style.json';
      case 'LOCAL_3D':
        return 'http://vranks.iptime.org:8080/styles/maptiler-3d/style.json';
      case 'OSM_TILE':
        return 'https://demotiles.maplibre.org/style.json';
      case 'OSM_3D':
        // OSM 3D 스타일 (MapTiler Streets 3D)
        return 'https://api.maptiler.com/maps/basic/style.json?key=get_openmaptiles_org';
      default:
        return 'https://demotiles.maplibre.org/style.json';
    }
  }

  String _getTileSourceName() {
    if (_isDesktop) {
      return _tileSource == 'LOCAL_TILE' ? '로컬 타일' : 'OSM 타일';
    }
    switch (_tileSource) {
      case 'LOCAL_TILE':
        return '로컬 2D';
      case 'LOCAL_3D':
        return '로컬 3D';
      case 'OSM_TILE':
        return 'OSM 2D';
      case 'OSM_3D':
        return 'OSM 3D';
      default:
        return '알 수 없음';
    }
  }

  // ============================================
  // ✅ 마커 업데이트 - 유저와 샵 통합 관리
  // ============================================
  Future<void> _updateMapLibreMarkers(
    LocationsProvider provider, {
    bool isAutoUpdate = false,
  }) async {
    if (_mapLibreController == null || !_isMobile) return;
    if (_isUpdatingMarkers) return;

    _isUpdatingMarkers = true;
    if (!isAutoUpdate) _lastManualUpdate = DateTime.now();

    try {
      debugPrint('');
      debugPrint('🔄 ════════════════════ 마커 업데이트 시작 ════════════════════');
      
      // ✅ 1. 모든 기존 Symbol 제거
      final symbolsList = _symbols.values.toList();
      _symbols.clear();
      
      for (var symbol in symbolsList) {
        try {
          await _mapLibreController!.removeSymbol(symbol);
        } catch (e) {
          // 이미 제거된 심볼 무시
        }
      }
      
      debugPrint('🧹 기존 심볼 ${symbolsList.length}개 제거 완료');

      // ✅ 2. 유저 마커 업데이트
      final allLocs = provider.getDisplayLocations();
      final locs = await _filterLocationsByGroup(allLocs);
      
      _userMarkers.clear();
      _clusterMarkers.clear();

      if (locs.isNotEmpty) {
        final userClusters = _clusterLocations(locs);
        debugPrint('👥 유저 클러스터: ${userClusters.length}개');

        for (int i = 0; i < userClusters.length; i++) {
          final cluster = userClusters[i];
          
          if (cluster.length == 1) {
            _userMarkers[cluster[0].userId] = cluster[0];
            await _addSymbolSingleMarker(cluster[0], provider);
          } else {
            _clusterMarkers['user_cluster_$i'] = cluster;
            await _addSymbolClusterMarker(cluster, i, provider);
          }
        }
      }

      // ✅ 3. 샵 마커 업데이트
      if (_showShopsLayer) {
        final shopsProvider = context.read<ShopsMapProvider>();
        await _updateShopMarkers(shopsProvider);
      }

      debugPrint('✅ 마커 업데이트 완료');
      debugPrint('   - 유저: 단일 ${_userMarkers.length}개, 클러스터 ${_clusterMarkers.length}개');
      debugPrint('   - 샵: 단일 ${_shopMarkers.length}개, 클러스터 ${_shopClusterMarkers.length}개');
      debugPrint('🔄 ════════════════════ 마커 업데이트 종료 ════════════════════');
      debugPrint('');

    } catch (e) {
      debugPrint('❌ 마커 업데이트 실패: $e');
    } finally {
      _isUpdatingMarkers = false;
    }
  }

  // ============================================
  // ✅ 샵 마커 클러스터링 및 추가
  // ============================================
  Future<void> _updateShopMarkers(ShopsMapProvider shopsProvider) async {
    if (_mapLibreController == null) return;

    try {
      debugPrint('');
      debugPrint('🏪 ════════════════════ 샵 마커 업데이트 시작 ════════════════════');
      
      _shopMarkers.clear();
      _shopClusterMarkers.clear();

      final shops = shopsProvider.filteredShops;
      debugPrint('📦 필터링된 샵: ${shops.length}개');

      if (shops.isEmpty) {
        debugPrint('⚠️  샵이 없음');
        debugPrint('🏪 ════════════════════ 샵 마커 업데이트 종료 ════════════════════');
        debugPrint('');
        return;
      }

      // ✅ 샵 클러스터링
      final shopClusters = _clusterShops(shops);
      debugPrint('📦 클러스터링 결과: ${shopClusters.length}개');

      for (int i = 0; i < shopClusters.length; i++) {
        final cluster = shopClusters[i];
        
        if (cluster.length == 1) {
          // 단일 샵
          final shop = cluster[0];
          _shopMarkers[shop.shopId] = shop;
          await _addSymbolSingleShop(shop);
          debugPrint('   ✅ 단일 샵: ${shop.shopName}');
        } else {
          // 샵 클러스터
          _shopClusterMarkers['shop_cluster_$i'] = cluster;
          await _addSymbolShopCluster(cluster, i);
          debugPrint('   ✅ 샵 클러스터 $i: ${cluster.length}개 (${cluster.map((s) => s.shopName).join(", ")})');
        }
      }

      debugPrint('🏪 ════════════════════ 샵 마커 업데이트 완료 ════════════════════');
      debugPrint('');

    } catch (e, stack) {
      debugPrint('❌ 샵 마커 업데이트 실패: $e');
      debugPrint('Stack: $stack');
    }
  }

  // ============================================
  // ✅ 샵 클러스터링 로직
  // ============================================
  List<List<ShopModel>> _clusterShops(List<ShopModel> shops) {
    if (shops.isEmpty) return [];
    
    // ✅ 줌 레벨에 따른 클러스터 반경 결정 (유저와 동일)
    double clusterRadiusMeters;
    if (_currentZoom >= 18) {
      clusterRadiusMeters = 15;
    } else if (_currentZoom >= 17) {
      clusterRadiusMeters = 30;
    } else if (_currentZoom >= 16) {
      clusterRadiusMeters = 60;
    } else if (_currentZoom >= 15) {
      clusterRadiusMeters = 100;
    } else if (_currentZoom >= 14) {
      clusterRadiusMeters = 200;
    } else if (_currentZoom >= 13) {
      clusterRadiusMeters = 400;
    } else if (_currentZoom >= 12) {
      clusterRadiusMeters = 800;
    } else if (_currentZoom >= 11) {
      clusterRadiusMeters = 1500;
    } else {
      clusterRadiusMeters = 3000;
    }
    
    debugPrint('📦 [샵 클러스터링] 줌: ${_currentZoom.toStringAsFixed(2)}, 반경: ${clusterRadiusMeters.toStringAsFixed(0)}m');
    
    final List<List<ShopModel>> clusters = [];
    final Set<String> processed = {};

    for (final shop in shops) {
      if (processed.contains(shop.shopId)) continue;

      final cluster = <ShopModel>[shop];
      processed.add(shop.shopId);

      for (final other in shops) {
        if (processed.contains(other.shopId)) continue;
        
        final distanceDegrees = sqrt(
          pow(shop.lat - other.lat, 2) + pow(shop.lng - other.lng, 2)
        );
        final distanceMeters = distanceDegrees * 111320.0;
        
        if (distanceMeters < clusterRadiusMeters) {
          cluster.add(other);
          processed.add(other.shopId);
          debugPrint('   └─ ${other.shopName} 추가 (${distanceMeters.toStringAsFixed(1)}m)');
        }
      }

      clusters.add(cluster);
    }

    debugPrint('📦 결과: ${clusters.length}개 (단일: ${clusters.where((c) => c.length == 1).length}, 그룹: ${clusters.where((c) => c.length > 1).length})');
    return clusters;
  }

  // ============================================
  // ✅ 단일 샵 심볼 추가
  // ============================================
  Future<void> _addSymbolSingleShop(ShopModel shop) async {
    if (_mapLibreController == null) return;
    
    if (!_iconsRegistered) {
      await _registerCustomIcons();
    }

    try {
      // ✅ 샵 이름 첫 글자
      final initial = shop.shopName.isNotEmpty 
          ? shop.shopName[0].toUpperCase() 
          : 'S';
      
      // ✅ 샵용 아이콘 동적 생성 (보라색으로 구분)
      final iconKey = 'shop_${shop.shopId}';
      await _registerIconWithText(iconKey, Colors.deepPurple, initial, 44);

      debugPrint('🎨 샵 아이콘 등록: $iconKey (${shop.shopName})');

      // ✅ 아이콘 추가
      final mainSymbol = await _mapLibreController!.addSymbol(
        SymbolOptions(
          geometry: LatLng(shop.lat, shop.lng),
          iconImage: iconKey,
          iconSize: 1.0,
          iconAnchor: 'center',
        ),
      );
      
      _symbols['shop_${shop.shopId}'] = mainSymbol;
      debugPrint('✅ 샵 심볼 추가: ${mainSymbol.id}');

      // ✅ 샵 이름 라벨 추가
      final labelSymbol = await _mapLibreController!.addSymbol(
        SymbolOptions(
          geometry: LatLng(shop.lat, shop.lng),
          textField: _short(shop.shopName, 6),
          textSize: 11.0,
          textColor: '#000000',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 2.0,
          textAnchor: 'top',
          textOffset: const Offset(0, 1.2),
        ),
      );
      _symbols['shop_${shop.shopId}_label'] = labelSymbol;

    } catch (e, stack) {
      debugPrint('❌ 샵 마커 추가 실패: ${shop.shopName} - $e');
      debugPrint('Stack: $stack');
    }
  }

  // ============================================
  // ✅ 샵 클러스터 심볼 추가
  // ============================================
  Future<void> _addSymbolShopCluster(
    List<ShopModel> cluster,
    int index,
  ) async {
    if (_mapLibreController == null || cluster.isEmpty) return;
    
    if (!_iconsRegistered) {
      await _registerCustomIcons();
    }

    try {
      // ✅ 클러스터 중심 계산
      double sumLat = 0, sumLng = 0;
      for (final shop in cluster) {
        sumLat += shop.lat;
        sumLng += shop.lng;
      }
      final centerLat = sumLat / cluster.length;
      final centerLng = sumLng / cluster.length;

      debugPrint('🎨 샵 클러스터 $index 중심: ($centerLat, $centerLng)');

      // ✅ 처음 3개 샵의 이니셜
      final initials = <String>[];
      for (int i = 0; i < min(3, cluster.length); i++) {
        final initial = cluster[i].shopName.isNotEmpty 
            ? cluster[i].shopName[0].toUpperCase() 
            : 'S';
        initials.add(initial);
      }

      String initialsText;
      if (cluster.length <= 3) {
        initialsText = initials.join(' ');
      } else {
        initialsText = '${initials[0]}${initials[1]}${initials[2]}';
      }

      // ✅ 클러스터 아이콘 생성 (오렌지색)
      final iconKey = 'shop_cluster_$index';
      await _registerIconWithText(iconKey, Colors.orange, initialsText, 60);

      debugPrint('🎨 샵 클러스터 아이콘 등록: $iconKey ($initialsText)');

      // ✅ 아이콘 추가
      final clusterSymbol = await _mapLibreController!.addSymbol(
        SymbolOptions(
          geometry: LatLng(centerLat, centerLng),
          iconImage: iconKey,
          iconSize: 1.0,
          iconAnchor: 'center',
        ),
      );
      
      _symbols['shop_cluster_$index'] = clusterSymbol;
      debugPrint('✅ 샵 클러스터 심볼 추가: ${clusterSymbol.id}');

      // ✅ 개수 라벨 추가
      final labelSymbol = await _mapLibreController!.addSymbol(
        SymbolOptions(
          geometry: LatLng(centerLat, centerLng),
          textField: '${cluster.length}개',
          textSize: 11.0,
          textColor: '#000000',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 2.0,
          textAnchor: 'top',
          textOffset: const Offset(0, 1.5),
        ),
      );
      _symbols['shop_cluster_${index}_label'] = labelSymbol;

    } catch (e, stack) {
      debugPrint('❌ 샵 클러스터 추가 실패: $e');
      debugPrint('Stack: $stack');
    }
  }

  // ============================================
  // 6. 단일 마커 함수 - 텍스트 포함 아이콘 사용
  // ============================================
  Future<void> _addSymbolSingleMarker(LocationModel loc, LocationsProvider provider) async {
    if (_mapLibreController == null) {
      debugPrint('❌ MapLibre controller is null');
      return;
    }
    
    if (!_iconsRegistered) {
      debugPrint('⚠️ Icons not registered yet, registering now...');
      await _registerCustomIcons();
    }

    try {
      final profile = await _fetchUserProfile(loc.userId);
      final nickname = profile?['nickname'] ?? profile?['name'] ?? loc.userId;
      final initial = _getInitial(nickname);
      
      final stay = _formatDuration(loc.userId, provider);
      final isMe = loc.userId == widget.userId;
      final color = isMe ? Colors.blue : Colors.red;
      
      // ✅ 텍스트 포함 아이콘 동적 생성
      final iconKey = 'marker_${loc.userId}';
      await _registerIconWithText(iconKey, color, initial, 44);

      debugPrint('🎨 Adding marker for ${loc.userId} with icon: $iconKey');

      // ✅ 텍스트가 포함된 아이콘 하나만 추가
      final mainSymbol = await _mapLibreController!.addSymbol(
        SymbolOptions(
          geometry: LatLng(loc.lat, loc.lng),
          iconImage: iconKey,
          iconSize: 1.0,
          iconAnchor: 'center',
        ),
      );
      
      _symbols['user_${loc.userId}'] = mainSymbol;
      debugPrint('✅ Icon symbol added: ${mainSymbol.id}');

      // ✅ 라벨만 별도로 추가 (원 아래)
      if (stay.isNotEmpty || !isMe) {
        final label = stay.isNotEmpty ? stay : _short(nickname, 6);
        
        // 텍스트 없이 halo만 사용하여 배경 만들기
        final labelSymbol = await _mapLibreController!.addSymbol(
          SymbolOptions(
            geometry: LatLng(loc.lat, loc.lng),
            textField: label,
            textSize: 11.0,
            textColor: '#000000',
            textHaloColor: '#FFFFFF',
            textHaloWidth: 2.0,
            textAnchor: 'top',
            textOffset: const Offset(0, 1.2),
          ),
        );
        _symbols['user_${loc.userId}_label'] = labelSymbol;
      }
      
      debugPrint('✅ 단일 마커 추가 완료: ${loc.userId}');

    } catch (e, stack) {
      debugPrint('❌ 마커 추가 실패: $e');
      debugPrint('Stack: $stack');
    }
  }

  // ============================================
  // 7. 클러스터 마커 함수 - 텍스트 포함 아이콘 사용
  // ============================================
  Future<void> _addSymbolClusterMarker(
    List<LocationModel> cluster,
    int index,
    LocationsProvider provider,
  ) async {
    if (_mapLibreController == null || cluster.isEmpty) return;
    
    if (!_iconsRegistered) {
      await _registerCustomIcons();
    }

    try {
      double sumLat = 0, sumLng = 0;
      for (final loc in cluster) {
        sumLat += loc.lat;
        sumLng += loc.lng;
      }
      final centerLat = sumLat / cluster.length;
      final centerLng = sumLng / cluster.length;

      final initials = <String>[];
      for (int i = 0; i < min(3, cluster.length); i++) {
        final profile = await _fetchUserProfile(cluster[i].userId);
        final nickname = profile?['nickname'] ?? profile?['name'] ?? cluster[i].userId;
        initials.add(_getInitial(nickname));
      }

      // ✅ 이니셜 텍스트 생성
      String initialsText;
      if (cluster.length <= 3) {
        initialsText = initials.join(' ');
      } else {
        initialsText = '${initials[0]}${initials[1]}${initials[2]}';
      }

      debugPrint('🎨 Adding cluster marker for ${cluster.length} users');

      // ✅ 텍스트 포함 클러스터 아이콘 동적 생성
      final iconKey = 'cluster_$index';
      await _registerIconWithText(iconKey, Colors.orange, initialsText, 60);

      // ✅ 텍스트가 포함된 아이콘 하나만 추가
      final clusterSymbol = await _mapLibreController!.addSymbol(
        SymbolOptions(
          geometry: LatLng(centerLat, centerLng),
          iconImage: iconKey,
          iconSize: 1.0,
          iconAnchor: 'center',
        ),
      );
      
      _symbols['cluster_$index'] = clusterSymbol;
      debugPrint('✅ Cluster icon added: ${clusterSymbol.id}');

      // ✅ 인원수만 별도로 추가 (원 아래)
      final labelSymbol = await _mapLibreController!.addSymbol(
        SymbolOptions(
          geometry: LatLng(centerLat, centerLng),
          textField: '${cluster.length}명',
          textSize: 11.0,
          textColor: '#000000',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 2.0,
          textAnchor: 'top',
          textOffset: const Offset(0, 1.5),
        ),
      );
      _symbols['cluster_${index}_label'] = labelSymbol;
      
      debugPrint('✅ 클러스터 마커 추가 완료: ${cluster.length}명');

    } catch (e, stack) {
      debugPrint('❌ 클러스터 추가 실패: $e');
      debugPrint('Stack: $stack');
    }
  }

  // ✅ 10. 유틸리티 함수들
  String _getInitial(String name) {
    if (name.isEmpty) return '?';
    
    final firstChar = name[0];
    final code = firstChar.codeUnitAt(0);
    
    if (code >= 0xAC00 && code <= 0xD7A3) {
      final cho = [
        'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ',
        'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'
      ];
      final choIndex = ((code - 0xAC00) / 28 / 21).floor();
      return cho[choIndex];
    }
    
    return firstChar.toUpperCase();
  }

  // ============================================
  // 수정 2: 클러스터링 - 디버깅 강화
  // ============================================
  List<List<LocationModel>> _clusterLocations(List<LocationModel> locs) {
    if (locs.isEmpty) return [];
    
    double clusterRadiusMeters;
    if (_currentZoom >= 18) {
      clusterRadiusMeters = 15;
    } else if (_currentZoom >= 17) {
      clusterRadiusMeters = 30;
    } else if (_currentZoom >= 16) {
      clusterRadiusMeters = 60;
    } else if (_currentZoom >= 15) {
      clusterRadiusMeters = 100;
    } else if (_currentZoom >= 14) {
      clusterRadiusMeters = 200;
    } else if (_currentZoom >= 13) {
      clusterRadiusMeters = 400;
    } else if (_currentZoom >= 12) {
      clusterRadiusMeters = 800;
    } else if (_currentZoom >= 11) {
      clusterRadiusMeters = 1500;
    } else {
      clusterRadiusMeters = 3000;
    }
    
    debugPrint('📦 [클러스터링] 줌: ${_currentZoom.toStringAsFixed(2)}, 반경: ${clusterRadiusMeters.toStringAsFixed(0)}m');
    
    final List<List<LocationModel>> clusters = [];
    final Set<String> processed = {};

    for (final loc in locs) {
      if (processed.contains(loc.userId)) continue;

      final cluster = <LocationModel>[loc];
      processed.add(loc.userId);

      for (final other in locs) {
        if (processed.contains(other.userId)) continue;
        
        final distanceDegrees = sqrt(
          pow(loc.lat - other.lat, 2) + pow(loc.lng - other.lng, 2)
        );
        final distanceMeters = distanceDegrees * 111320.0;
        
        if (distanceMeters < clusterRadiusMeters) {
          cluster.add(other);
          processed.add(other.userId);
          debugPrint('   └─ ${other.userId.substring(0, 8)} 추가 (${distanceMeters.toStringAsFixed(1)}m)');
        }
      }

      clusters.add(cluster);
    }

    debugPrint('📦 결과: ${clusters.length}개 (단일: ${clusters.where((c) => c.length == 1).length}, 그룹: ${clusters.where((c) => c.length > 1).length})');
    return clusters;
  }

  Future<String?> _addGroupToDB(String name) async {
    try {
      final check = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.groupsCollectionId,
        queries: [
          Query.equal('userId', widget.userId),
          Query.equal('groupName', name),
        ],
      );

      if (check.documents.isNotEmpty) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미 같은 이름의 그룹 [$name] 이(가) 존재합니다.')),
        );
        return null;
      }

      final res = await _db.createDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.groupsCollectionId,
        documentId: ID.unique(),
        data: {
          'groupName': name,
          'userId': widget.userId,
        },
      );

      final id = (res as dynamic).$id?.toString() ?? '';
      debugPrint('✅ 그룹 [$name] 저장 성공 (id=$id)');
      return id;
    } catch (e) {
      debugPrint('❌ 그룹 저장 실패: $e');
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('그룹 [$name] 저장 중 오류 발생')),
      );
      return null;
    }
  }

  Future<void> _onAddGroup() async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('새 그룹 추가'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '그룹 이름을 입력하세요',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;

                final existsInUI = _groups.any((g) => g['name'] == name);
                if (existsInUI) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('이미 같은 이름의 그룹 [$name] 이(가) 존재합니다.')),
                  );
                  Navigator.pop(context);
                  return;
                }

                Navigator.pop(context);
                final id = await _addGroupToDB(name);

                if (id != null) {
                  setState(() {
                    _groups.add({'id': id, 'name': name});
                    _dropdownKey++;
                  });
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('✅ 그룹 [$name] 추가 완료')),
                  );
                } else {
                  debugPrint('❌ 그룹 [$name] 추가 실패 — DB 저장 안 됨');
                }
              },
              child: const Text('추가'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _deleteGroupFromDB(String docId) async {
    try {
      await _db.deleteDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.groupsCollectionId,
        documentId: docId,
      );
      debugPrint('✅ 그룹 (id=$docId) 삭제 성공');
      return true;
    } catch (e) {
      debugPrint('❌ 그룹 삭제 실패: $e');
      return false;
    }
  }

  void _activateLocalMode(LocationsProvider provider) {
    provider.addDummyLocations([
      LocationModel(
        id: 'dummy1',
        userId: widget.userId,
        lat: 37.400766,
        lng: 127.1122054,
        accuracy: 3.5,
        speed: 0.0,
        heading: 90.0,
        timestamp: DateTime.now(),
        groupId: 'family_id',
      ),
      LocationModel(
        id: 'dummy2',
        userId: 'son',
        lat: 37.401266,
        lng: 127.1127054,
        accuracy: 5.0,
        speed: 0.8,
        heading: 120.0,
        timestamp: DateTime.now(),
        groupId: 'family_id',
      ),
      LocationModel(
        id: 'dummy3',
        userId: 'brother',
        lat: 37.400266,
        lng: 127.1117054,
        accuracy: 7.0,
        speed: 1.1,
        heading: 270.0,
        timestamp: DateTime.now(),
        groupId: 'club_id',
      ),
    ]);
  }

  void _activateRealtimeMode(LocationsProvider provider) {
    provider.fetchAllLocations();
    provider.startRealtime();
    provider.startLocationUpdates();
  }

  // ✅ 위치 추적 타이머 - 메시지 프로바이더 동기화 강화
  void _startStopTracking(LocationsProvider provider) {
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      try {
        final locs = provider.getDisplayLocations();

        for (final entry in locs.entries) {
          final userId = entry.key;
          final loc = entry.value;
          final currentPos = latlong.LatLng(loc.lat, loc.lng);

          final lastPos = _lastPositions[userId];
          if (lastPos == null) {
            _lastPositions[userId] = currentPos;
            
            // ✅ 현재 사용자 위치 업데이트
            if (userId == widget.userId) {
              try {
                final msgProvider = context.read<UserMessageProvider>();
                msgProvider.updateLocation(loc.lat, loc.lng);
                debugPrint('📍 [타이머] 유저 위치 업데이트: (${loc.lat}, ${loc.lng})');
              } catch (e) {
                debugPrint('⚠️ MessageProvider 업데이트 실패: $e');
              }
            }
            
            continue;
          }

          final moved = _distance(lastPos, currentPos);
          if (moved < 2) {
            _stopStartTimes[userId] ??= DateTime.now();
          } else {
            _stopStartTimes[userId] = null;
            _lastPositions[userId] = currentPos;
            provider.resetStayDuration(userId);
            _elapsedDurations[userId] = Duration.zero;
            
            // ✅ 움직임 감지 시 업데이트
            if (userId == widget.userId) {
              try {
                final msgProvider = context.read<UserMessageProvider>();
                msgProvider.updateLocation(loc.lat, loc.lng);
                debugPrint('📍 [이동] 유저 위치 업데이트: (${loc.lat}, ${loc.lng})');
              } catch (e) {
                debugPrint('⚠️ MessageProvider 업데이트 실패: $e');
              }
            }
            
            if (mounted) setState(() {});
          }
        }

        if (mounted && timer.tick % 6 == 0) setState(() {});
      } catch (e) {
        debugPrint('❌ _startStopTracking 에러: $e');
      }
    });
  }

  void _startElapsedTimer(LocationsProvider provider) {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final locs = provider.getDisplayLocations();
      for (final entry in locs.entries) {
        final userId = entry.key;
        final stay = provider.getStayDuration(userId);

        _elapsedDurations[userId] =
            (_elapsedDurations[userId] ?? stay) + const Duration(seconds: 1);
      }
      if (mounted) setState(() {});
    });
  }

  // ============================================
  // 수정 9: dispose
  // ============================================
  @override
  void dispose() {
    debugPrint('');
    debugPrint('🛑 ════════════════════ MapPage dispose ════════════════════');
    
    _updateTimer?.cancel();
    _autoMoveTimer?.cancel();
    _durationTimer?.cancel();
    _markerUpdateTimer?.cancel();

    final provider = context.read<LocationsProvider>();
    provider.saveAllStayDurations();
    
    try {
      final msgProvider = context.read<UserMessageProvider>();
      msgProvider.forceRefresh();
      debugPrint('✅ UserMessageProvider 정리 완료');
    } catch (e) {
      debugPrint('⚠️ MessageProvider 정리 실패: $e');
    }
    
    debugPrint('🛑 ════════════════════ dispose 완료 ════════════════════');
    debugPrint('');

    super.dispose();
  }

  // ✅ 3. 샵 마커 클릭 핸들러
  void _onShopMarkerTap(ShopModel shop) {
    showModalBottomSheet(
      context: context,
      builder: (_) => ShopInfoBottomSheet(
        shop: shop,
        onNavigate: (shop) {
          // 길찾기 기능
          _navigateToShop(shop, null);
        },
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

    // ✅ 4. 샵 필터 표시
    void _showShopFilterPanel() {
      final provider = context.read<ShopsMapProvider>();
      
      showModalBottomSheet(
        context: context,
        builder: (_) => ShopFilterPanel(
          selectedCategories: _selectedShopCategories,
          searchController: _searchController,  // 🔥 유지됨
          onCategoryChanged: (categories) {
            setState(() {
              _selectedShopCategories = categories;
            });
            provider.setCategoryFilter(categories);
          },
          onSearch: (query) {
            provider.searchShops(query);
          },
        ),
        isScrollControlled: true,
      );
    }

  Future<void> _logout() async {
    final provider = context.read<LocationsProvider>();
    final auth = AuthProvider();

    try {
      await provider.saveAllStayDurations();
      provider.resetRealtimeConnection();
      // ignore: use_build_context_synchronously
      await auth.logout(context);

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('로그아웃 실패: $e')));
    }
  }

  // ✅ 10. 유틸리티 함수들
  String _short(String s, [int len = 4]) =>
      s.length <= len ? s : s.substring(0, len);

  String _formatDuration(String userId, LocationsProvider provider) {
    final duration = provider.getStayDuration(userId);
    if (duration.inSeconds == 0) return '';

    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    final s = duration.inSeconds % 60;
    if (h > 0) {
      return '$h시간 $m분';
    } else if (m > 0) {
      return '$m분 $s초';
    } else {
      return '$s초';
    }
  }

  // ✅ 7. 유저 프로필 가져오기
  Future<Map<String, dynamic>?> _fetchUserProfile(String userId) async {
    try {
      final res = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.usersCollectionId,
        queries: [Query.equal('userId', userId)],
      );
      if (res.documents.isNotEmpty) {
        return res.documents.first.data;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

// ✅ 8. 유저 정보 표시 함수 - 간단한 길찾기 버튼으로 변경
void _showUserInfo(LocationModel user) async {
  final profile = await _fetchUserProfile(user.userId);
  final provider = context.read<LocationsProvider>();
  
  final nickname = profile?['nickname'] ?? profile?['name'] ?? user.userId;
  final profileImage = profile?['profileImage'];
  final stayInfo = _formatDuration(user.userId, provider);

  if (!mounted) return;
  
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (bottomSheetContext) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundImage: profileImage != null
                    ? NetworkImage(profileImage)
                    : null,
                child: profileImage == null
                    ? Text(nickname.isNotEmpty
                        ? nickname[0].toUpperCase()
                        : '?')
                    : null,
              ),
              const SizedBox(height: 10),
              Text(
                '$nickname ${stayInfo.isNotEmpty ? "($stayInfo)" : ""}',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text('(${user.lat.toStringAsFixed(5)}, ${user.lng.toStringAsFixed(5)})'),
              const SizedBox(height: 8),
              Text('업데이트: ${DateFormat('HH:mm:ss').format(user.timestamp)}'),
              
              const SizedBox(height: 16),
              
              // ✅ 간단한 길찾기 버튼
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    debugPrint('');
                    debugPrint('🗺️ ════════════════════ 유저 길찾기 시작 ════════════════════');
                    debugPrint('   목적지: $nickname');
                    
                    // ✅ 다이얼로그 닫기
                    Navigator.pop(bottomSheetContext);
                    
                    // ✅ 임시 ShopModel 생성
                    final tempShop = ShopModel(
                      shopId: user.userId,
                      ownerId: user.userId,
                      shopName: nickname,
                      category: '사용자',
                      lat: user.lat,
                      lng: user.lng,
                      address: '',
                      phone: '',
                      description: '',
                      createdAt: DateTime.now(),
                    );
                    
                    // ✅ 경로 계산
                    final myLocation = provider.locations[widget.userId];
                    if (myLocation == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('현재 위치를 확인할 수 없습니다')),
                      );
                      return;
                    }
                    
                    // ✅ 기존 경로 데이터 초기화
                    if (mounted) {
                      setState(() {
                        _currentInstructions = [];
                        _selectedInstructionIndex = null;
                        _currentRoute = null;
                        
                        if (_selectedInstructionMarker != null && _mapLibreController != null) {
                          try {
                            _mapLibreController!.removeSymbol(_selectedInstructionMarker!);
                          } catch (e) {
                            debugPrint('⚠️ 마커 제거 실패: $e');
                          }
                          _selectedInstructionMarker = null;
                        }
                      });
                    }
                    
                    // ✅ 새 경로 계산
                    final navigationService = NavigationService();
                    final route = await navigationService.getRoute(
                      start: latlong.LatLng(myLocation.lat, myLocation.lng),
                      end: latlong.LatLng(user.lat, user.lng),
                      mode: _selectedTransportMode,
                    );
                    
                    if (route == null) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('❌ 경로를 찾을 수 없습니다')),
                        );
                      }
                      return;
                    }
                    
                    debugPrint('✅ 경로 생성 성공');
                    debugPrint('   이동수단: ${route.transportModeString}');
                    debugPrint('   거리: ${route.formattedDistance}');
                    debugPrint('   시간: ${route.formattedDuration}');
                    debugPrint('   안내 스텝: ${route.instructions.length}개');
                    
                    // ✅ 경로 업데이트
                    if (mounted) {
                      setState(() {
                        _currentRoute = route;
                      });
                    }
                    
                    // ✅ 지도에 경로 표시
                    if (_isDesktop) {
                      _showRouteOnFlutterMap(route, tempShop);
                    } else {
                      await _showRouteOnMapLibre(route, tempShop);
                    }
                    
                    // ✅ 네비게이션 패널 표시
                    if (mounted) {
                      _showNavigationPanelForUser(tempShop, route, nickname);
                    }
                    
                    debugPrint('🗺️ ════════════════════ 유저 길찾기 완료 ════════════════════');
                    debugPrint('');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.navigation),
                  label: const Text(
                    '길찾기',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

  // ✅ 이동수단 선택 패널 (유저 정보 다이얼로그용)
  Widget _buildNavigationTransportPanel(LocationModel user, String nickname) {
    return Consumer<LocationsProvider>(
      builder: (context, provider, _) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.deepPurple[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🗺️ 길찾기 (이동수단 선택)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // ✅ 3개 이동수단 버튼
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildTransportModeButtonForUser(
                        icon: Icons.directions_car,
                        label: '자동차',
                        mode: TransportMode.driving,
                        isSelected: _selectedTransportMode == TransportMode.driving,
                        onTap: () async {
                          debugPrint('');
                          debugPrint('🚗 ════════════════════ 자동차 길찾기 ════════════════════');
                          debugPrint('   목적지: $nickname');
                          
                          setState(() => _selectedTransportMode = TransportMode.driving);
                          
                          // ✅ 임시 ShopModel 생성
                          final tempShop = ShopModel(
                            shopId: user.userId,
                            ownerId: user.userId,
                            shopName: nickname,
                            category: '사용자',
                            lat: user.lat,
                            lng: user.lng,
                            address: '',
                            phone: '',
                            description: '',
                            createdAt: DateTime.now(),
                          );
                          
                          // ✅ 경로 계산 후 네비게이션 패널 표시
                          await _navigateToShopForUser(tempShop, nickname, setState);
                        },
                      ),
                      _buildTransportModeButtonForUser(
                        icon: Icons.directions_walk,
                        label: '도보',
                        mode: TransportMode.walking,
                        isSelected: _selectedTransportMode == TransportMode.walking,
                        onTap: () async {
                          debugPrint('');
                          debugPrint('🚶 ════════════════════ 도보 길찾기 ════════════════════');
                          debugPrint('   목적지: $nickname');
                          
                          setState(() => _selectedTransportMode = TransportMode.walking);
                          
                          final tempShop = ShopModel(
                            shopId: user.userId,
                            ownerId: user.userId,
                            shopName: nickname,
                            category: '사용자',
                            lat: user.lat,
                            lng: user.lng,
                            address: '',
                            phone: '',
                            description: '',
                            createdAt: DateTime.now(),
                          );
                          
                          await _navigateToShopForUser(tempShop, nickname, setState);
                        },
                      ),
                      _buildTransportModeButtonForUser(
                        icon: Icons.directions_bike,
                        label: '자전거',
                        mode: TransportMode.cycling,
                        isSelected: _selectedTransportMode == TransportMode.cycling,
                        onTap: () async {
                          debugPrint('');
                          debugPrint('🚴 ════════════════════ 자전거 길찾기 ════════════════════');
                          debugPrint('   목적지: $nickname');
                          
                          setState(() => _selectedTransportMode = TransportMode.cycling);
                          
                          final tempShop = ShopModel(
                            shopId: user.userId,
                            ownerId: user.userId,
                            shopName: nickname,
                            category: '사용자',
                            lat: user.lat,
                            lng: user.lng,
                            address: '',
                            phone: '',
                            description: '',
                            createdAt: DateTime.now(),
                          );
                          
                          await _navigateToShopForUser(tempShop, nickname, setState);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ✅ 유저 길찾기 메서드 (수정됨 - _currentInstructions 초기화 추가)
  Future<void> _navigateToShopForUser(
    ShopModel shop,
    String nickname,
    StateSetter setState,
  ) async {
    final provider = context.read<LocationsProvider>();
    final myLocation = provider.locations[widget.userId];
    
    if (myLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 위치를 확인할 수 없습니다')),
      );
      return;
    }
    
    try {
      debugPrint('');
      debugPrint('🗺️ ════════════════════ 유저 길찾기 시작 ════════════════════');
      debugPrint('🏘️ 유저: $nickname');
      
      // ✅ 기존 경로 안내 초기화 (중요!)
      debugPrint('🧹 기존 경로 안내 데이터 초기화');
      this.setState(() {
        _currentInstructions = [];
        _selectedInstructionIndex = null;
        _currentRoute = null;
        
        // 선택된 마커 제거
        if (_selectedInstructionMarker != null && _mapLibreController != null) {
          try {
            _mapLibreController!.removeSymbol(_selectedInstructionMarker!);
          } catch (e) {
            debugPrint('⚠️ 마커 제거 실패: $e');
          }
          _selectedInstructionMarker = null;
        }
      });
      
      // ✅ 현재 선택된 이동수단으로 경로 생성
      final navigationService = NavigationService();
      final route = await navigationService.getRoute(
        start: latlong.LatLng(myLocation.lat, myLocation.lng),
        end: latlong.LatLng(shop.lat, shop.lng),
        mode: _selectedTransportMode,
      );
      
      if (route == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ 경로를 찾을 수 없습니다')),
          );
        }
        return;
      }
      
      debugPrint('✅ 경로 생성 성공');
      debugPrint('   이동수단: ${route.transportModeString}');
      debugPrint('   거리: ${route.formattedDistance}');
      debugPrint('   시간: ${route.formattedDuration}');
      debugPrint('   안내 스텝: ${route.instructions.length}개');
      
      // ✅ setState로 경로 업데이트
      if (mounted) {
        this.setState(() {
          _currentRoute = route;
        });
        debugPrint('✅ setState 호출 - 경로 업데이트');
      }
      
      // 지도에 경로 표시
      if (_isDesktop) {
        _showRouteOnFlutterMap(route, shop);
      } else {
        await _showRouteOnMapLibre(route, shop);
      }
      
      // ✅ 네비게이션 패널 표시 (유저용)
      if (mounted) {
        _showNavigationPanelForUser(shop, route, nickname);
      }
      
      debugPrint('🗺️ ════════════════════ 유저 길찾기 완료 ════════════════════');
      debugPrint('');
      
    } catch (e) {
      debugPrint('❌ 유저 길찾기 오류: $e');
    }
  }

  // ✅ 유저 길찾기 네비게이션 패널 (수정됨 - 길찾기 시작 버튼에 instructions 설정 추가)
  void _showNavigationPanelForUser(ShopModel shop, RouteResult route, String nickname) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 헤더
                Row(
                  children: [
                    const Icon(Icons.navigation, color: Colors.blue, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nickname,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${route.formattedDistance} · ${route.formattedDuration}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _currentRoute = null;
                          _currentInstructions = [];
                          _selectedInstructionIndex = null;
                        });
                      },
                    ),
                  ],
                ),
                
                const Divider(),
                const SizedBox(height: 12),
                
                // ✅ 이동 수단 선택
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '이동 수단 선택',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildTransportModeButton(
                            icon: Icons.directions_car,
                            label: '자동차',
                            mode: TransportMode.driving,
                            onChanged: () async {
                              setModalState(() => _selectedTransportMode = TransportMode.driving);
                              debugPrint('🚗 자동차 모드 선택 (유저 길찾기)');
                              
                              final navigationService = NavigationService();
                              final locProvider = context.read<LocationsProvider>();
                              final myLocation = locProvider.locations[widget.userId];
                              
                              if (myLocation != null) {
                                final newRoute = await navigationService.getRoute(
                                  start: latlong.LatLng(myLocation.lat, myLocation.lng),
                                  end: latlong.LatLng(shop.lat, shop.lng),
                                  mode: TransportMode.driving,
                                );
                                
                                if (newRoute != null) {
                                  setModalState(() => _currentRoute = newRoute);
                                  if (_isMobile) {
                                    await _showRouteOnMapLibre(newRoute, shop);
                                  } else {
                                    _showRouteOnFlutterMap(newRoute, shop);
                                  }
                                }
                              }
                            },
                          ),
                          _buildTransportModeButton(
                            icon: Icons.directions_walk,
                            label: '도보',
                            mode: TransportMode.walking,
                            onChanged: () async {
                              setModalState(() => _selectedTransportMode = TransportMode.walking);
                              debugPrint('🚶 도보 모드 선택 (유저 길찾기)');
                              
                              final navigationService = NavigationService();
                              final locProvider = context.read<LocationsProvider>();
                              final myLocation = locProvider.locations[widget.userId];
                              
                              if (myLocation != null) {
                                final newRoute = await navigationService.getRoute(
                                  start: latlong.LatLng(myLocation.lat, myLocation.lng),
                                  end: latlong.LatLng(shop.lat, shop.lng),
                                  mode: TransportMode.walking,
                                );
                                
                                if (newRoute != null) {
                                  setModalState(() => _currentRoute = newRoute);
                                  if (_isMobile) {
                                    await _showRouteOnMapLibre(newRoute, shop);
                                  } else {
                                    _showRouteOnFlutterMap(newRoute, shop);
                                  }
                                }
                              }
                            },
                          ),
                          _buildTransportModeButton(
                            icon: Icons.directions_bike,
                            label: '자전거',
                            mode: TransportMode.cycling,
                            onChanged: () async {
                              setModalState(() => _selectedTransportMode = TransportMode.cycling);
                              debugPrint('🚴 자전거 모드 선택 (유저 길찾기)');
                              
                              final navigationService = NavigationService();
                              final locProvider = context.read<LocationsProvider>();
                              final myLocation = locProvider.locations[widget.userId];
                              
                              if (myLocation != null) {
                                final newRoute = await navigationService.getRoute(
                                  start: latlong.LatLng(myLocation.lat, myLocation.lng),
                                  end: latlong.LatLng(shop.lat, shop.lng),
                                  mode: TransportMode.cycling,
                                );
                                
                                if (newRoute != null) {
                                  setModalState(() => _currentRoute = newRoute);
                                  if (_isMobile) {
                                    await _showRouteOnMapLibre(newRoute, shop);
                                  } else {
                                    _showRouteOnFlutterMap(newRoute, shop);
                                  }
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // ✅ 현재 경로 정보 및 시작 버튼
                if (_currentRoute != null)
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info, color: Colors.blue[700]),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_currentRoute!.transportModeString} · ${_currentRoute!.formattedDuration}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                  Text(
                                    _currentRoute!.formattedDistance,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // ✅ 길찾기 시작 버튼 (중요: _currentInstructions 설정!)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            debugPrint('');
                            debugPrint('🚀 ════════════════════ 유저 길찾기 시작 ════════════════════');
                            debugPrint('   목적지: $nickname');
                            debugPrint('   이동 수단: ${_currentRoute!.transportModeString}');
                            debugPrint('   거리: ${_currentRoute!.formattedDistance}');
                            debugPrint('   시간: ${_currentRoute!.formattedDuration}');
                            debugPrint('   안내 스텝: ${_currentRoute!.instructions.length}개');
                            debugPrint('🚀 ════════════════════════════════════════════════');
                            debugPrint('');
                            
                            // ✅ 핵심! setState로 _currentInstructions 설정
                            setState(() {
                              _currentInstructions = _currentRoute!.instructions;
                              _selectedInstructionIndex = null;
                              debugPrint('✅ setState 완료: _currentInstructions = ${_currentInstructions.length}개');
                            });
                            
                            Navigator.pop(context);
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '🚀 $nickname님에게 가는 길입니다!\n'
                                  '${_currentRoute!.transportModeString} ${_currentRoute!.formattedDuration}',
                                ),
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.navigation),
                          label: const Text(
                            '길찾기 시작',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                
                const SizedBox(height: 12),
                
                // ✅ 턴 바이 턴 (처음 3개만 표시)
                if (_currentRoute != null && _currentRoute!.instructions.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '길 안내',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._currentRoute!.instructions.take(3).map((step) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.blue,
                                child: Text(
                                  '${_currentRoute!.instructions.indexOf(step) + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      step.instruction,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      step.formattedDistance,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ✅ 유저 길찾기용 이동수단 버튼
  Widget _buildTransportModeButtonForUser({
    required IconData icon,
    required String label,
    required TransportMode mode,
    required bool isSelected,
    required Future<void> Function() onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelected ? Colors.deepPurple : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? Colors.deepPurple : Colors.grey[300]!,
                width: 2,
              ),
              boxShadow: [
                if (isSelected)
                  BoxShadow(
                    color: Colors.deepPurple.withOpacity(0.3),
                    blurRadius: 4,
                  ),
              ],
            ),
            child: Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[600],
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.deepPurple : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleAutoMove(LocationsProvider provider) {
    if (_autoMovingSon) {
      _autoMoveTimer?.cancel();
      setState(() => _autoMovingSon = false);
      return;
    }

    setState(() => _autoMovingSon = true);
    _autoMoveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final son = provider.locations['son'];
      final brother = provider.locations['brother'];
      if (son == null || brother == null) return;

      final moveRatio = 0.1;
      final newLat = son.lat + (brother.lat - son.lat) * moveRatio;
      final newLng = son.lng + (brother.lng - son.lng) * moveRatio;

      provider.onUserMove('son', latlong.LatLng(newLat, newLng));

      _elapsedDurations['son'] = Duration.zero;
      if (mounted) setState(() {});
    });
  }

  void _toggleMapMode() {
    final provider = context.read<LocationsProvider>();
    setState(() {
      _mapMode = _mapMode == 'REALTIME' ? 'LOCAL' : 'REALTIME';
    });

    if (_mapMode == 'LOCAL') {
      _activateLocalMode(provider);
    } else {
      _activateRealtimeMode(provider);
    }
  }

  Future<void> _onLongPressGroupItem(Map<String, String> group) async {
    final name = group['name'] ?? '';
    final id = group['id'] ?? '';

    if (name == '전체') return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('그룹 삭제'),
        content: Text('그룹 "$name"을(를) 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final ok = await _deleteGroupFromDB(id);

    if (ok) {
      setState(() {
        _groups.removeWhere((g) => g['id'] == id);

        if (_selectedGroupId == id) {
          final allGroup = _groups.firstWhere(
            (g) => g['name'] == '전체',
            orElse: () => {'id': 'all', 'name': '전체'},
          );
          _selectedGroupId = allGroup['id'];
          _selectedGroupName = allGroup['name'];
        }

        _dropdownKey++;
      });

      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('그룹 "$name"이(가) 삭제되었습니다.')),
      );
    } else {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('그룹 "$name" 삭제에 실패했습니다.')),
      );
    }
  }

  // ✅ 9. 그룹 관리 다이얼로그 (BuildContext async 에러 수정)
  Future<void> _showGroupManagementDialog() async {
    final searchController = TextEditingController();
    Map<String, dynamic>? foundUser;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.8,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('그룹 관리', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 16),

                    const Text('유저 추가', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchController,
                            decoration: const InputDecoration(
                              labelText: '이메일 검색',
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) async {
                              final email = searchController.text.trim();
                              if (email.isEmpty) return;
                              final result = await _searchUserByEmail(email);
                              setDialogState(() => foundUser = result);
                              if (result == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('해당 이메일로 가입된 사용자가 없습니다.')),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.search),
                          label: const Text('검색'),
                          onPressed: () async {
                            final email = searchController.text.trim();
                            if (email.isEmpty) return;
                            final result = await _searchUserByEmail(email);
                            setDialogState(() => foundUser = result);
                            if (result == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('해당 이메일로 가입된 사용자가 없습니다.')),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (foundUser != null)
                      Card(
                        color: Colors.blue.shade50,
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(foundUser!['nickname'] ?? foundUser!['email']),
                          subtitle: Text(foundUser!['email']),
                          trailing: ElevatedButton.icon(
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('추가'),
                            onPressed: () async {
                              final userId = foundUser!['userId'];
                              final email = foundUser!['email'];

                              final added = await _addPersonToPeoples(
                                peopleUserId: userId,
                                groups: ['전체'],
                              );

                              if (added) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('$email 님이 전체 그룹에 추가되었습니다.')),
                                );
                                setDialogState(() {
                                  foundUser = null;
                                  searchController.clear();
                                });
                                Future.delayed(const Duration(milliseconds: 100), () {
                                  setDialogState(() {});
                                });
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('이미 추가된 유저입니다.')),
                                );
                              }
                            },
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),

                    const Text('등록된 유저', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),

                    Expanded(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: _fetchPeoplesList(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return const Center(
                              child: Text(
                                '등록된 유저가 없습니다.\n위에서 이메일로 검색하여 유저를 추가하세요.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            );
                          }

                          final displayList = snapshot.data!;

                          return ListView.builder(
                            itemCount: displayList.length,
                            itemBuilder: (context, index) {
                              final item = displayList[index];
                              final groups = (item['groups'] as List<dynamic>).join(', ');

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  leading: const CircleAvatar(child: Icon(Icons.person)),
                                  title: Text(item['nickname']),
                                  subtitle: Text('${item['email']}\n그룹: $groups'),
                                  isThreeLine: true,
                                  trailing: PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert),
                                    onSelected: (value) async {
                                      if (value == 'change_group') {
                                        await _showChangeUserGroupDialog(item, setDialogState);
                                      } else if (value == 'remove') {
                                        await _removePersonFromPeoples(
                                          item['peopleDocId'],
                                          item['email'],
                                          setDialogState,
                                        );
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'change_group',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit, size: 18),
                                            SizedBox(width: 8),
                                            Text('그룹 변경'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'remove',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete, size: 18, color: Colors.red),
                                            SizedBox(width: 8),
                                            Text('삭제', style: TextStyle(color: Colors.red)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  // ✅ 유저 클릭 시 해당 위치로 이동
                                  onTap: () async {
                                    final userId = item['peopleUserId'];
                                    Navigator.pop(context); // 다이얼로그 닫기
                                    await _moveToUserLocation(userId);
                                  },
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ✅ 10. 특정 유저 위치로 이동 (BuildContext 에러 수정)
  Future<void> _moveToUserLocation(String userId) async {
    final provider = context.read<LocationsProvider>();
    final userLoc = provider.locations[userId];
    
    if (userLoc == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$userId의 위치 정보를 찾을 수 없습니다.')),
        );
      }
      return;
    }

    debugPrint('📍 유저 위치로 이동: $userId (${userLoc.lat}, ${userLoc.lng})');

    if (_isDesktop) {
      _mapController.move(latlong.LatLng(userLoc.lat, userLoc.lng), 17);
    } else if (_mapLibreController != null) {
      await _mapLibreController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(userLoc.lat, userLoc.lng),
          17.0,
        ),
        duration: const Duration(milliseconds: 1000),
      );
    }

    // 0.5초 후 유저 정보 표시
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _showUserInfo(userLoc);
      }
    });
  }

  // ✅ Peoples에서 유저 제거 (BuildContext 에러 수정)
  Future<void> _removePersonFromPeoples(
    String peopleDocId,
    String email,
    StateSetter setDialogState,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('유저 삭제'),
        content: Text('$email 님을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _db.deleteDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.peoplesCollectionId,
        documentId: peopleDocId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$email 님이 삭제되었습니다.')),
        );
      }

      setDialogState(() {});
    } catch (e) {
      debugPrint('❌ 유저 삭제 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('삭제에 실패했습니다.')),
        );
      }
    }
  }

  // ✅ 유저 이메일로 검색
  Future<Map<String, dynamic>?> _searchUserByEmail(String email) async {
    try {
      final res = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.usersCollectionId,
        queries: [Query.equal('email', email)],
      );

      if (res.documents.isNotEmpty) {
        final doc = res.documents.first;
        return {
          'userId': doc.data['userId'],
          'email': doc.data['email'],
          'nickname': doc.data['nickname'],
        };
      }
      return null;
    } catch (e) {
      debugPrint('❌ 유저 검색 실패: $e');
      return null;
    }
  }

  // ✅ Peoples에 유저 추가
  Future<bool> _addPersonToPeoples({
    required String peopleUserId,
    required List<String> groups,
  }) async {
    try {
      final existing = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.peoplesCollectionId,
        queries: [
          Query.equal('userId', widget.userId),
          Query.equal('peopleUserId', peopleUserId),
        ],
      );

      if (existing.total > 0) {
        debugPrint("⚠️ 이미 존재하는 사람: $peopleUserId");
        return false;
      }

      await _db.createDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.peoplesCollectionId,
        documentId: ID.unique(),
        data: {
          'userId': widget.userId,
          'peopleUserId': peopleUserId,
          'groups': groups,
        },
      );

      debugPrint("✅ peoples에 [$peopleUserId] 추가 완료");
      return true;
    } catch (e) {
      debugPrint("❌ peoples 추가 실패: $e");
      return false;
    }
  }

  // ✅ 그룹 변경 다이얼로그 (BuildContext 에러 수정)
  Future<void> _showChangeUserGroupDialog(
    Map<String, dynamic> userItem,
    StateSetter setDialogState,
  ) async {
    String selectedGroup = (userItem['groups'] as List<dynamic>?)?.first ?? '전체';

    final uniqueGroupNames = _groups.map((g) => g['name']!).toSet().toList();
    if (!uniqueGroupNames.contains(selectedGroup)) selectedGroup = '전체';

    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, localSetState) => AlertDialog(
          title: Text('그룹 변경: ${userItem['nickname'] ?? '알 수 없는 사용자'}'),
          content: DropdownButton<String>(
            value: selectedGroup,
            isExpanded: true,
            items: uniqueGroupNames.map((name) => DropdownMenuItem(
              value: name,
              child: Text(name),
            )).toList(),
            onChanged: (value) => localSetState(() => selectedGroup = value!),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
            ElevatedButton(onPressed: () => Navigator.pop(context, selectedGroup), child: const Text('저장')),
          ],
        ),
      ),
    );

    if (result != null) {
      userItem['groups'] = [result];

      await _updatePersonGroups(
        userDocId: userItem['peopleDocId'],
        newGroups: [result],
      );

      setDialogState(() {});

      if (mounted) setState(() {});
    }
  }

  // ✅ 그룹 업데이트
  Future<void> _updatePersonGroups({
    required String userDocId,
    required List<String> newGroups,
  }) async {
    try {
      await _db.updateDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.peoplesCollectionId,
        documentId: userDocId,
        data: {'groups': newGroups},
      );
      debugPrint("✅ 그룹 변경 완료: $newGroups");
    } catch (e) {
      debugPrint("❌ 그룹 변경 실패: $e");
    }
  }

  Future<List<LocationModel>> _filterLocationsByGroup(
    Map<String, LocationModel> allLocs,
  ) async {
    if (_selectedGroupName == '전체') {
      return allLocs.values.toList();
    }

    try {
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.peoplesCollectionId,
        queries: [
          Query.equal('userId', widget.userId),
        ],
      );

      final filteredUserIds = <String>{};
      for (var doc in result.documents) {
        final groups = List<String>.from(doc.data['groups'] ?? []);
        if (groups.contains(_selectedGroupName)) {
          filteredUserIds.add(doc.data['peopleUserId']);
        }
      }

      filteredUserIds.add(widget.userId);

      return allLocs.entries
          .where((entry) => filteredUserIds.contains(entry.key))
          .map((entry) => entry.value)
          .toList();
    } catch (e) {
      debugPrint('❌ 그룹 필터링 실패: $e');
      return allLocs.values.toList();
    }
  }

  // ✅ 클러스터 내 사용자 목록 (실시간 반영)
  void _showClusterUsers(List<Marker> clusterMarkers) {
    final ticker = ValueNotifier<int>(0);
    Timer.periodic(const Duration(seconds: 1), (_) {
      // ignore: invalid_use_of_protected_member
      if (ticker.hasListeners) ticker.value++;
    });

    showModalBottomSheet(
      context: context,
      builder: (_) {
        return ValueListenableBuilder<int>(
          valueListenable: ticker,
          builder: (context, _, __) {
            return Consumer<LocationsProvider>(
              builder: (context, provider, _) {
                final matchedUsers = clusterMarkers.map((m) {
                  final userId = (m.key is ValueKey)
                      ? (m.key as ValueKey).value.toString()
                      : 'unknown';
                  return provider.locations[userId] ??
                      LocationModel(
                        id: userId,
                        userId: userId,
                        lat: m.point.latitude,
                        lng: m.point.longitude,
                        timestamp: DateTime.now(),
                      );
                }).toList();

                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: matchedUsers.length,
                  itemBuilder: (_, i) {
                    final u = matchedUsers[i];
                    final stay = _formatDuration(u.userId, provider);

                    return FutureBuilder<Map<String, dynamic>?>(
                      future: _fetchUserProfile(u.userId),
                      builder: (context, snapshot) {
                        final profile = snapshot.data;
                        final nickname =
                            profile?['nickname'] ?? profile?['name'] ?? u.userId;
                        final profileImage = profile?['profileImage'];

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: profileImage != null
                                ? NetworkImage(profileImage)
                                : null,
                            child: profileImage == null
                                ? Text(nickname.isNotEmpty
                                    ? nickname[0].toUpperCase()
                                    : '?')
                                : null,
                          ),
                          title: Text(nickname),
                          subtitle: Text(
                            stay.isNotEmpty
                                ? '($stay)'
                                : '(${u.lat.toStringAsFixed(5)}, ${u.lng.toStringAsFixed(5)})',
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _showUserInfo(u);
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    ).whenComplete(() => ticker.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
//        title: Text(_isDesktop ? '실시간 위치 공유 (Desktop)' : '실시간 위치 공유'),
        title: Text(
          _currentRole == UserRole.shopOwner
              ? '실시간 위치 공유 (샵 주인)'
              : '실시간 위치 공유'
        ),
        actions: [
            // 유저 모드일 때 홍보 리스트 버튼
            if (_currentRole == UserRole.user)
              Tooltip(
                message: '홍보 메시지',
                child: IconButton(
                  icon: const Icon(Icons.mail),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserPromotionsPage(
                          userId: widget.userId,
                          onNavigateToShop: _navigateToShop,
                        ),
                      ),
                    );
                  },
                ),
              ),
          // ✅ 샵 필터 버튼 추가
          if (_isDesktop)
            Tooltip(
              message: '샵 검색',
              child: IconButton(
                icon: const Icon(Icons.store),
                onPressed: _showShopFilterPanel,
              ),
            ),
          // ✅ 역할 전환 메뉴
          PopupMenuButton<String>(
            icon: Icon(
              _currentRole == UserRole.shopOwner
                  ? Icons.store
                  : Icons.person,
            ),
            onSelected: (value) {
              if (value == 'switch_role') {
                final newRole = _currentRole == UserRole.user
                    ? UserRole.shopOwner
                    : UserRole.user;
                _switchRole(newRole);
              } else if (value == 'shop_management') {
                _openShopOwnerPage();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'switch_role',
                child: Row(
                  children: [
                    Icon(
                      _currentRole == UserRole.user
                          ? Icons.store
                          : Icons.person,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _currentRole == UserRole.user
                          ? '샵 주인 모드로 전환'
                          : '유저 모드로 전환',
                    ),
                  ],
                ),
              ),
              if (_currentRole == UserRole.shopOwner)
                const PopupMenuItem(
                  value: 'shop_management',
                  child: Row(
                    children: [
                      Icon(Icons.dashboard),
                      SizedBox(width: 8),
                      Text('샵 관리'),
                    ],
                  ),
                ),],),
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: '그룹 관리',
            onPressed: _showGroupManagementDialog,
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: ValueKey(_dropdownKey),
              value: _selectedGroupName?.trim().isEmpty ?? true ? '전체' : _selectedGroupName,
              icon: const Icon(Icons.group, color: Colors.white),
              dropdownColor: Colors.blueGrey[50],
              items: [
                const DropdownMenuItem<String>(value: '전체', child: Text('전체')),
                ..._groups
                    .where((g) => g['name'] != '전체')
                    .map((g) => DropdownMenuItem<String>(
                          value: g['name'] ?? '',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onLongPress: () {
                              if (g['name'] != '전체') _onLongPressGroupItem(g);
                            },
                            child: Text(g['name'] ?? ''),
                          ),
                        )),
                const DropdownMenuItem<String>(
                  value: '__add_group__',
                  child: Row(
                    children: [
                      Icon(Icons.add, size: 16),
                      SizedBox(width: 8),
                      Text('그룹 추가'),
                    ],
                  ),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                if (value == '__add_group__') {
                  _onAddGroup();
                } else {
                  final selected = _groups.firstWhere(
                    (g) => g['name'] == value,
                    orElse: () => {'id': 'all', 'name': '전체'},
                  );
                  setState(() {
                    _selectedGroupName = selected['name'];
                    _selectedGroupId = selected['id'];
                  });
                }
              },
            ),
          ),
          IconButton(
            icon: Icon(_mapMode == 'REALTIME' ? Icons.public : Icons.map_outlined),
            tooltip: _mapMode == 'REALTIME' ? 'Local 더미모드로 전환' : '실시간 모드로 전환',
            onPressed: _toggleMapMode,
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Consumer<LocationsProvider>(
        builder: (context, provider, _) {
          final width = MediaQuery.of(context).size.width;
          final isDesktop = width >= 800;

          return Stack(
            children: [
              // ✅ 지도
              isDesktop
                  ? _buildFlutterMapWithShopsAndRoute(provider)
                  : _buildMapLibreMapWithShops(provider),
              
              // ✅ 메시지 패널
              if (_currentRole == UserRole.user)
                MessagesPanel(
                  userId: widget.userId,
                  onNavigateToShop: _navigateToShop,
                ),
              
              // ✅ 길찾기 안내 패널 (새로 추가!)
              _buildRouteInstructionPanel(),
              
              // ✅ 샵 레이어 토글 버튼 (Desktop은 제외)
              if (!_isDesktop)
                Positioned(
                  bottom: 18,
                  left: 18,
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: _showShopsLayer 
                        ? Colors.deepPurple 
                        : Colors.grey[600],
                    tooltip: _showShopsLayer ? '샵 숨기기' : '샵 보이기',
                    onPressed: () {
                      setState(() => _showShopsLayer = !_showShopsLayer);
                    },
                    child: const Icon(Icons.store),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ✅ 7. MapLibre에 샵 마커 추가
  Widget _buildMapLibreMapWithShops(LocationsProvider provider) {
    return Consumer<ShopsMapProvider>(
      builder: (context, shopsProvider, _) {
        return Stack(
          children: [
            MapLibreMap(
              key: ValueKey('map_${_tileSource}_${_is3DMode}'),
              styleString: _getMapLibreStyleUrl(),
              initialCameraPosition: CameraPosition(
                target: const LatLng(37.408915, 127.148245),
                zoom: _currentZoom,
                tilt: _is3DMode ? 60.0 : 0.0,
              ),
              onMapCreated: (controller) async {
                _mapLibreController = controller;
                debugPrint("✅ MapLibre controller created");

                _setupSymbolClickListener();
                
                Future.delayed(const Duration(milliseconds: 1500), () {
                  if (mounted && _mapLibreController != null) {
                    _lastClusterZoom = _currentZoom;
                    _updateMapLibreMarkers(provider);
                  }
                });
              },
              onStyleLoadedCallback: () async {
                debugPrint("✅ MapLibre style loaded");

                await _registerCustomIcons();

                await Future.delayed(const Duration(milliseconds: 500));
                if (_mapLibreController != null && mounted) {
                  _lastClusterZoom = _currentZoom;
                  debugPrint('🎬 스타일 로드 후 마커 표시');
                  await _updateMapLibreMarkers(provider);
                }
              },
              onMapClick: (Point<double> point, LatLng coordinates) async {
                debugPrint('🗺️ 빈 공간 클릭');
              },
              onCameraMove: (CameraPosition position) {
                final oldZoom = _currentZoom;
                _currentZoom = position.zoom;
                
                if ((oldZoom - _currentZoom).abs() > 0.01) {
                  debugPrint('📷 줌: ${oldZoom.toStringAsFixed(2)} → ${_currentZoom.toStringAsFixed(2)}');
                }
              },
              onCameraIdle: () async {
                final zoomDiff = (_currentZoom - _lastClusterZoom).abs();
                
                debugPrint('📷 onCameraIdle: 줌 차이 = ${zoomDiff.toStringAsFixed(2)}');
                
                if (zoomDiff > 0.5) {
                  debugPrint('📷 ✅ 줌 변경 감지! 재클러스터링 시작');
                  _lastClusterZoom = _currentZoom;
                  
                  if (mounted) {
                    await Future.delayed(const Duration(milliseconds: 100));
                    await _updateMapLibreMarkers(provider);
                  }
                } else {
                  debugPrint('📷 줌 변경 미미함, 스킵');
                }
              },
              myLocationEnabled: true,
              myLocationTrackingMode: MyLocationTrackingMode.none,
              compassEnabled: _is3DMode && _tileSource.contains('3D'),
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: true,
            ),
            
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: (_is3DMode ? Colors.purple : Colors.blue)
                      .withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _is3DMode ? Icons.view_in_ar : Icons.map,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _getTileSourceName(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            _buildFloatingButtons(provider, isDesktop: false),
          ],
        );
      },
    );
  }

  // ============================================
  // map_page.dart의 _setupSymbolClickListener 메서드 수정
  // ============================================
  void _setupSymbolClickListener() {
    if (_mapLibreController == null) return;
    
    debugPrint('🔧 Symbol 클릭 리스너 설정');
    
    _mapLibreController!.onSymbolTapped.add((Symbol symbol) {
      debugPrint('');
      debugPrint('🎯 ════════════════════ Symbol 탭 ════════════════════');
      debugPrint('🎯 Symbol ID: ${symbol.id}');
      
      final provider = context.read<LocationsProvider>();
      final shopsProvider = context.read<ShopsMapProvider>();
      final clickedLatLng = symbol.options.geometry;
      
      if (clickedLatLng != null) {
        // ✅ 샵 클러스터링도 포함한 버전 호출
        _handleSymbolClickWithShops(clickedLatLng, provider, shopsProvider);
      }
      
      debugPrint('🎯 ════════════════════════════════════════════════');
      debugPrint('');
    });
    
    debugPrint('✅ Symbol 클릭 리스너 등록 완료');
  }

  // ============================================
  // 클릭 위치 근처의 모든 샵 가져오기
  // ============================================
  List<ShopModel> _getShopsAtLocation(
    LatLng clickedLatLng,
    List<ShopModel> shops,
    double tolerance,
  ) {
    final nearby = <ShopModel>[];
    
    debugPrint('🔍 샵 검색 중...');
    debugPrint('   중심: (${clickedLatLng.latitude.toStringAsFixed(6)}, ${clickedLatLng.longitude.toStringAsFixed(6)})');
    debugPrint('   반경: ${(tolerance * 111000).toStringAsFixed(0)}m');
    
    for (final shop in shops) {
      // ✅ 유저 클러스터링과 동일한 거리 계산
      final distance = sqrt(
        pow(shop.lat - clickedLatLng.latitude, 2) + 
        pow(shop.lng - clickedLatLng.longitude, 2)
      );
      
      if (distance < tolerance) {
        nearby.add(shop);
        debugPrint('   ✅ ${shop.shopName}: ${(distance * 111000).toStringAsFixed(1)}m');
      }
    }
    
    debugPrint('📊 결과: ${nearby.length}개 샵 발견');
    return nearby;
  }

  // ============================================
  // 수정 1: 줌 버튼 - cameraPosition 사용 안 함
  // ============================================
  Widget _buildFloatingButtons(LocationsProvider provider, {required bool isDesktop}) {
    return Positioned(
      bottom: 18,
      right: 18,
      child: Column(
        children: [
          // ✅ 줌 인 버튼 - 완전 재작성
          if (!isDesktop)
            FloatingActionButton(
              heroTag: "zoom_in",
              mini: true,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              tooltip: "확대",
              onPressed: () async {
                debugPrint('');
                debugPrint('➕➕➕ [줌 인 버튼 클릭] ➕➕➕');
                
                if (_mapLibreController == null) {
                  debugPrint('❌ MapLibre controller 없음');
                  return;
                }
                
                // 1. 현재 줌 저장
                final oldZoom = _currentZoom;
                debugPrint('   현재 줌: ${oldZoom.toStringAsFixed(2)}');
                
                // 2. 줌 인 (1.0 증가 예상)
                debugPrint('   줌 인 실행...');
                await _mapLibreController!.animateCamera(
                  CameraUpdate.zoomIn(),
                  duration: const Duration(milliseconds: 300),
                );
                
                // 3. 애니메이션 완료 대기
                await Future.delayed(const Duration(milliseconds: 500));
                
                // 4. onCameraMove에서 자동으로 _currentZoom 업데이트됨
                // 하지만 혹시 모르니 수동으로 1.0 증가
                _currentZoom = oldZoom + 1.0;
                debugPrint('   새 줌: ${_currentZoom.toStringAsFixed(2)} (강제 설정)');
                
                // 5. 강제로 클러스터 재계산 트리거
                _lastClusterZoom = oldZoom; // 이전 값으로 설정
                debugPrint('   _lastClusterZoom: ${_lastClusterZoom.toStringAsFixed(2)}');
                debugPrint('   줌 차이: ${(_currentZoom - _lastClusterZoom).toStringAsFixed(2)}');
                
                // 6. 마커 업데이트
                if (mounted) {
                  await _updateMapLibreMarkers(provider);
                }
                
                debugPrint('➕ [줌 인 완료]');
                debugPrint('');
              },
              child: const Icon(Icons.add, size: 24),
            ),
          if (!isDesktop) const SizedBox(height: 8),

          // ✅ 줌 아웃 버튼 - 완전 재작성
          if (!isDesktop)
            FloatingActionButton(
              heroTag: "zoom_out",
              mini: true,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              tooltip: "축소",
              onPressed: () async {
                debugPrint('');
                debugPrint('➖➖➖ [줌 아웃 버튼 클릭] ➖➖➖');
                
                if (_mapLibreController == null) {
                  debugPrint('❌ MapLibre controller 없음');
                  return;
                }
                
                final oldZoom = _currentZoom;
                debugPrint('   현재 줌: ${oldZoom.toStringAsFixed(2)}');
                
                debugPrint('   줌 아웃 실행...');
                await _mapLibreController!.animateCamera(
                  CameraUpdate.zoomOut(),
                  duration: const Duration(milliseconds: 300),
                );
                
                await Future.delayed(const Duration(milliseconds: 500));
                
                // onCameraMove가 업데이트 안 하면 수동으로 1.0 감소
                _currentZoom = oldZoom - 1.0;
                debugPrint('   새 줌: ${_currentZoom.toStringAsFixed(2)} (강제 설정)');
                
                _lastClusterZoom = oldZoom;
                debugPrint('   _lastClusterZoom: ${_lastClusterZoom.toStringAsFixed(2)}');
                debugPrint('   줌 차이: ${(_currentZoom - _lastClusterZoom).abs().toStringAsFixed(2)}');
                
                if (mounted) {
                  await _updateMapLibreMarkers(provider);
                }
                
                debugPrint('➖ [줌 아웃 완료]');
                debugPrint('');
              },
              child: const Icon(Icons.remove, size: 24),
            ),
          if (!isDesktop) const SizedBox(height: 12),

          FloatingActionButton(
            heroTag: "move_my_location",
            mini: true,
            backgroundColor: Colors.blue,
            tooltip: "내 위치로 이동",
            onPressed: () => _moveToMyLocation(provider),
            child: const Icon(Icons.my_location, size: 20),
          ),
          const SizedBox(height: 12),
          
          if (!isDesktop && _tileSource.contains('3D'))
            FloatingActionButton(
              heroTag: "toggle_3d",
              mini: true,
              backgroundColor: _is3DMode ? Colors.purple : Colors.grey[600],
              tooltip: _is3DMode ? "3D 모드 끄기" : "3D 모드 켜기",
              onPressed: _toggle3DMode,
              child: Icon(
                _is3DMode ? Icons.view_in_ar : Icons.view_in_ar_outlined,
                size: 20,
              ),
            ),
          if (!isDesktop && _tileSource.contains('3D')) const SizedBox(height: 12),

          if (!isDesktop && _is3DMode && _tileSource.contains('3D'))
            FloatingActionButton(
              heroTag: "reset_bearing",
              mini: true,
              backgroundColor: Colors.indigo,
              tooltip: "방향 초기화",
              onPressed: () async {
                if (_mapLibreController != null) {
                  await _mapLibreController!.animateCamera(
                    CameraUpdate.bearingTo(0.0),
                    duration: const Duration(milliseconds: 500),
                  );
                }
              },
              child: const Icon(Icons.navigation, size: 20),
            ),
          if (!isDesktop && _is3DMode && _tileSource.contains('3D')) const SizedBox(height: 12),

          FloatingActionButton(
            heroTag: "auto_move_son",
            mini: true,
            backgroundColor: _autoMovingSon ? Colors.redAccent : Colors.green,
            tooltip: _autoMovingSon ? "자동 이동 중지" : "자동 이동 시작",
            onPressed: () => _toggleAutoMove(provider),
            child: Icon(
              _autoMovingSon ? Icons.pause : Icons.play_arrow,
              size: 20,
            ),
          ),
          const SizedBox(height: 12),
          
          FloatingActionButton(
            heroTag: "toggle_tile_source",
            mini: true,
            backgroundColor: Colors.orange,
            tooltip: "지도 타일 변경",
            onPressed: _toggleTileSource,
            child: const Icon(Icons.layers, size: 20),
          ),
        ],
      ),
    );
  }

  // ✅ 내 위치로 이동 (수정본 - 더 확실한 이동)
  void _moveToMyLocation(LocationsProvider provider) async {
    debugPrint('➡️ [버튼 클릭] _moveToMyLocation 호출됨');

    final me = provider.locations[widget.userId];
    if (me == null) {
      debugPrint('❌ 내 위치 정보가 없음 (widget.userId: ${widget.userId})');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('내 위치 정보를 가져올 수 없습니다.')),
      );
      return;
    }

    debugPrint('ℹ️ _isDesktop: $_isDesktop');
    debugPrint('ℹ️ 내 좌표: (${me.lat}, ${me.lng})');

    if (_isDesktop) {
      debugPrint('💻 FlutterMap 경로로 이동 시도');
      _mapController.move(latlong.LatLng(me.lat, me.lng), 16);
    } else if (_mapLibreController != null) {
      debugPrint('📱 MapLibre 경로로 이동 시도');
      try {
        await _mapLibreController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(me.lat, me.lng),
            16.0,
          ),
          duration: const Duration(milliseconds: 800),
        );
        debugPrint('✅ 카메라 이동 완료');
      } catch (e) {
        debugPrint('❌ 카메라 이동 실패: $e');
      }
    } else {
      debugPrint('❌ 이동 실패: MapLibreController가 null');
    }
  }

  // ✅ 7. 클러스터 유저 목록 표시 (hasListeners 완전 수정)
  void _showClusterUsersBottomSheet(List<LocationModel> clusterUsers, LocationsProvider provider) {
    final ticker = ValueNotifier<int>(0);
    Timer? timer;
    bool isDialogOpen = true; // ✅ 다이얼로그 상태 추적
    
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isDialogOpen) {
        ticker.value++;
      } else {
        timer?.cancel();
      }
    });

    showModalBottomSheet(
      context: context,
      builder: (_) {
        return ValueListenableBuilder<int>(
          valueListenable: ticker,
          builder: (context, _, __) {
            return Consumer<LocationsProvider>(
              builder: (context, provider, _) {
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: clusterUsers.length,
                  itemBuilder: (_, i) {
                    final u = clusterUsers[i];
                    final stay = _formatDuration(u.userId, provider);

                    return FutureBuilder<Map<String, dynamic>?>(
                      future: _fetchUserProfile(u.userId),
                      builder: (context, snapshot) {
                        final profile = snapshot.data;
                        final nickname = profile?['nickname'] ?? profile?['name'] ?? u.userId;
                        final profileImage = profile?['profileImage'];

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: profileImage != null
                                ? NetworkImage(profileImage)
                                : null,
                            child: profileImage == null
                                ? Text(nickname.isNotEmpty ? nickname[0].toUpperCase() : '?')
                                : null,
                          ),
                          title: Text(nickname),
                          subtitle: Text(
                            stay.isNotEmpty
                                ? '($stay)'
                                : '(${u.lat.toStringAsFixed(5)}, ${u.lng.toStringAsFixed(5)})',
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _showUserInfo(u);
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    ).whenComplete(() {
      isDialogOpen = false; // ✅ 다이얼로그 닫힘 표시
      ticker.dispose();
      timer?.cancel();
    });
  }

  // ✅ Peoples 목록 가져오기 (누락된 함수 추가)
  Future<List<Map<String, dynamic>>> _fetchPeoplesList() async {
    try {
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.peoplesCollectionId,
        queries: [
          Query.equal('userId', widget.userId),
        ],
      );

      final peoples = result.documents;
      final List<Map<String, dynamic>> displayList = [];

      for (var p in peoples) {
        final peopleUserId = p.data['peopleUserId'];

        if (peopleUserId == widget.userId) continue;

        try {
          final userDoc = await _db.getDocument(
            databaseId: AppwriteConstants.databaseId,
            collectionId: AppwriteConstants.usersCollectionId,
            documentId: peopleUserId,
          );
          displayList.add({
            'peopleDocId': p.$id,
            'peopleUserId': peopleUserId,
            'email': userDoc.data['email'] ?? '알 수 없음',
            'nickname': userDoc.data['nickname'] ?? '알 수 없음',
            'groups': List<String>.from(p.data['groups'] ?? []),
          });
        } catch (e) {
          displayList.add({
            'peopleDocId': p.$id,
            'peopleUserId': peopleUserId,
            'email': '조회 실패',
            'nickname': '조회 실패',
            'groups': List<String>.from(p.data['groups'] ?? []),
          });
        }
      }

      return displayList;
    } catch (e) {
      debugPrint('❌ peoples 목록 불러오기 실패: $e');
      return [];
    }
  }
  // ✅ 1. 상세한 경로 안내 텍스트 추출 함수
  String _getDetailedInstructionText(dynamic instruction) {
    try {
      final instructionText = instruction.instruction ?? '';
      final type = instruction.type ?? '';
      final modifier = instruction.modifier ?? '';
      final distance = instruction.formattedDistance ?? '';
      /*
      debugPrint('');
      debugPrint('📍 안내 텍스트 분석:');
      debugPrint('   원본: $instructionText');
      debugPrint('   타입: $type');
      debugPrint('   방향: $modifier');
      debugPrint('   거리: $distance');
      */
      String directionText = '';
      
      // ✅ OSRM maneuver type + modifier 기반 한글 변환 (존댓말)
      switch (type) {
        case 'turn':
          if (modifier == 'left') {
            directionText = '좌회전하세요';
          } else if (modifier == 'right') {
            directionText = '우회전하세요';
          } else if (modifier == 'slight left') {
            directionText = '왼쪽으로 살짝 꺾으세요';
          } else if (modifier == 'slight right') {
            directionText = '오른쪽으로 살짝 꺾으세요';
          } else if (modifier == 'sharp left') {
            directionText = '왼쪽으로 급하게 꺾으세요';
          } else if (modifier == 'sharp right') {
            directionText = '오른쪽으로 급하게 꺾으세요';
          } else if (modifier == 'uturn') {
            directionText = 'U턴하세요';
          } else {
            directionText = '회전하세요';
          }
          break;
          
        case 'new name':
        case 'continue':
          if (modifier == 'straight') {
            directionText = '직진하세요';
          } else if (modifier == 'slight left') {
            directionText = '왼쪽 방향으로 계속 가세요';
          } else if (modifier == 'slight right') {
            directionText = '오른쪽 방향으로 계속 가세요';
          } else {
            directionText = '계속 가세요';
          }
          break;
          
        case 'depart':
          if (modifier == 'left') {
            directionText = '왼쪽으로 출발하세요';
          } else if (modifier == 'right') {
            directionText = '오른쪽으로 출발하세요';
          } else if (modifier == 'straight') {
            directionText = '직진으로 출발하세요';
          } else {
            directionText = '출발하세요';
          }
          break;
          
        case 'arrive':
          if (modifier == 'left') {
            directionText = '왼쪽에 목적지가 있습니다';
          } else if (modifier == 'right') {
            directionText = '오른쪽에 목적지가 있습니다';
          } else if (modifier == 'straight') {
            directionText = '앞에 목적지가 있습니다';
          } else {
            directionText = '목적지에 도착했습니다';
          }
          break;
          
        case 'merge':
          if (modifier == 'left') {
            directionText = '왼쪽 차로로 합류하세요';
          } else if (modifier == 'right') {
            directionText = '오른쪽 차로로 합류하세요';
          } else if (modifier == 'slight left') {
            directionText = '왼쪽으로 합류하세요';
          } else if (modifier == 'slight right') {
            directionText = '오른쪽으로 합류하세요';
          } else {
            directionText = '합류하세요';
          }
          break;
          
        case 'on ramp':
          if (modifier == 'left') {
            directionText = '왼쪽 진입로로 진입하세요';
          } else if (modifier == 'right') {
            directionText = '오른쪽 진입로로 진입하세요';
          } else if (modifier == 'slight left') {
            directionText = '왼쪽 진입로 방향으로 가세요';
          } else if (modifier == 'slight right') {
            directionText = '오른쪽 진입로 방향으로 가세요';
          } else {
            directionText = '진입로로 진입하세요';
          }
          break;
          
        case 'off ramp':
          if (modifier == 'left') {
            directionText = '왼쪽 진출로로 나가세요';
          } else if (modifier == 'right') {
            directionText = '오른쪽 진출로로 나가세요';
          } else if (modifier == 'slight left') {
            directionText = '왼쪽 진출로 방향으로 가세요';
          } else if (modifier == 'slight right') {
            directionText = '오른쪽 진출로 방향으로 가세요';
          } else {
            directionText = '진출로로 나가세요';
          }
          break;
          
        case 'fork':
          if (modifier == 'left') {
            directionText = '왼쪽 길로 가세요';
          } else if (modifier == 'right') {
            directionText = '오른쪽 길로 가세요';
          } else if (modifier == 'slight left') {
            directionText = '왼쪽 방향 길로 가세요';
          } else if (modifier == 'slight right') {
            directionText = '오른쪽 방향 길로 가세요';
          } else {
            directionText = '분기점에서 길을 선택하세요';
          }
          break;
          
        case 'end of road':
          if (modifier == 'left') {
            directionText = '도로 끝에서 좌회전하세요';
          } else if (modifier == 'right') {
            directionText = '도로 끝에서 우회전하세요';
          } else {
            directionText = '도로가 끝납니다';
          }
          break;
          
        case 'use lane':
          if (modifier.contains('left')) {
            directionText = '왼쪽 차로를 이용하세요';
          } else if (modifier.contains('right')) {
            directionText = '오른쪽 차로를 이용하세요';
          } else {
            directionText = '차로를 유지하세요';
          }
          break;
          
        case 'roundabout':
        case 'rotary':
          if (modifier.contains('1')) {
            directionText = '로터리에서 첫 번째 출구로 나가세요';
          } else if (modifier.contains('2')) {
            directionText = '로터리에서 두 번째 출구로 나가세요';
          } else if (modifier.contains('3')) {
            directionText = '로터리에서 세 번째 출구로 나가세요';
          } else if (modifier.contains('4')) {
            directionText = '로터리에서 네 번째 출구로 나가세요';
          } else if (modifier == 'left') {
            directionText = '로터리에서 왼쪽으로 나가세요';
          } else if (modifier == 'right') {
            directionText = '로터리에서 오른쪽으로 나가세요';
          } else if (modifier == 'straight') {
            directionText = '로터리에서 직진으로 나가세요';
          } else {
            directionText = '로터리에 진입하세요';
          }
          break;
          
        case 'roundabout turn':
          if (modifier == 'left') {
            directionText = '로터리에서 좌회전하세요';
          } else if (modifier == 'right') {
            directionText = '로터리에서 우회전하세요';
          } else {
            directionText = '로터리에서 회전하세요';
          }
          break;
          
        case 'notification':
          if (modifier.contains('straight')) {
            directionText = '직진 방향을 유지하세요';
          } else {
            directionText = '경로를 따라 가세요';
          }
          break;
          
        default:
          // ✅ 기본값: instruction 텍스트에서 키워드 찾기
          final lower = instructionText.toLowerCase();
          
          if (lower.contains('turn left') || lower.contains('left turn')) {
            directionText = '좌회전하세요';
          } else if (lower.contains('turn right') || lower.contains('right turn')) {
            directionText = '우회전하세요';
          } else if (lower.contains('slight left')) {
            directionText = '왼쪽으로 살짝 꺾으세요';
          } else if (lower.contains('slight right')) {
            directionText = '오른쪽으로 살짝 꺾으세요';
          } else if (lower.contains('sharp left')) {
            directionText = '왼쪽으로 급하게 꺾으세요';
          } else if (lower.contains('sharp right')) {
            directionText = '오른쪽으로 급하게 꺾으세요';
          } else if (lower.contains('straight') || lower.contains('continue')) {
            directionText = '직진하세요';
          } else if (lower.contains('u-turn')) {
            directionText = 'U턴하세요';
          } else if (lower.contains('depart')) {
            directionText = '출발하세요';
          } else if (lower.contains('arrive')) {
            directionText = '도착했습니다';
          } else {
            directionText = '계속 진행하세요';
          }
      }
      
      // ✅ 거리 정보와 결합
      String result;
      if (distance.isNotEmpty && distance != '0m') {
        result = '$distance 전방에서 $directionText';
      } else {
        result = directionText;
      }
      
      //debugPrint('   결과: $result');
      //debugPrint('');
      
      return result;
      
    } catch (e) {
      debugPrint('⚠️ 안내 텍스트 추출 실패: $e');
      return '계속 진행하세요';
    }
  }
}