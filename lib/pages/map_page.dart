import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/flutter_map.dart' as latlong;
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
import 'dart:ui' as ui;
import 'dart:typed_data';
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
import '../widgets/unified_search_panel.dart';
import '../models/personal_place_model.dart';
import '../providers/personal_places_provider.dart';
import '../widgets/save_place_dialog.dart';
import '../screens/temp_group_list_screen.dart';
import '../screens/temp_group_create_screen.dart';
import '../screens/temp_group_detail_screen.dart';
import '../providers/temp_groups_provider.dart';
import '../models/temp_group_model.dart';
import '../screens/temp_group_join_screen.dart';
import '../screens/temp_group_chat_screen.dart';
import '../providers/temp_group_messages_provider.dart';  // ✅ 추가

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
  bool _showShopsLayer = true;
  final Map<String, bool> _useHighwaysMap = {}; // ✅ 샵별 고속도로 옵션
  final Map<String, TransportMode> _shopTransportModeMap = {}; // ✅ 샵별 이동수단

  // ✅ 새로 추가: 경로 안내 관련
  List<dynamic> _currentInstructions = [];
  int? _selectedInstructionIndex;
  Symbol? _selectedInstructionMarker;
  bool _isInstructionPanelMinimized = false; // ✅ 최소화 상태
  
  // ✅ FlutterMap용 선택된 instruction 마커
  latlong.Marker? _selectedInstructionMarkerFlutter;

  // ✅ 샵 마커 관리 추가
  final Map<String, ShopModel> _shopMarkers = {}; // shopId -> ShopModel
  final Map<String, List<ShopModel>> _shopClusterMarkers = {}; // cluster_id -> List<ShopModel>

  Symbol? _addressPinMarker; // ✅ 주소 검색 결과 핀

  NavigationLanguage _navLanguage = NavigationLanguage.korean; // ✅ 추가

  // ✅ 핀 조정 모드 관련
  bool _isPinAdjustMode = false;
  LatLng? _adjustingPinLocation;
  String? _adjustingAddress;
  Symbol? _adjustingPinSymbol;

  // ✅ 추가: 카메라 중심 추적
  LatLng? _currentCameraCenter;

  // ✅ 개인 장소 마커 관리 추가
  final Map<String, PersonalPlaceModel> _personalPlaceMarkers = {}; // placeId -> PersonalPlaceModel
  final Map<String, List<PersonalPlaceModel>> _personalPlaceClusterMarkers = {}; // cluster_id -> List<PersonalPlaceModel>
  bool _showPersonalPlacesLayer = true; // ✅ 레이어 토글
  LocationsProvider? _locationsProvider;

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
  @override
  void initState() {
    super.initState();
    
    debugPrint('');
    debugPrint('🎬 ════════════════════ MapPage initState ════════════════════');
    debugPrint('📍 userId: ${widget.userId}');

    // ✅ 1. 기본 초기화 (동기)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _ensureDefaultGroup();
      _loadGroupsFromDB();
      
      final provider = context.read<LocationsProvider>();
      provider.resetRealtimeConnection();
      provider.startAll(startLocationStream: true);
      // ✅ Provider 참조 저장
      _locationsProvider = context.read<LocationsProvider>();
      _locationsProvider!.addListener(_handleMapMoveRequest);

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
    });

    // ✅ 2. 위치 로드 및 지도 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      
      debugPrint('🔄 위치 로드 대기 중...');
      
      // 최대 5초 동안 위치를 찾으려고 시도
      int attempts = 0;
      const maxAttempts = 10; // 5초 (0.5초 * 10)
      
      Timer.periodic(const Duration(milliseconds: 500), (timer) async {
        attempts++;
        
        if (!mounted) {
          timer.cancel();
          return;
        }
        
        final locProvider = context.read<LocationsProvider>();
        final myLocation = locProvider.locations[widget.userId];
        
        if (myLocation != null) {
          timer.cancel();
          debugPrint('✅ 위치 로드 완료: (${myLocation.lat}, ${myLocation.lng})');
          
          // 지도 이동
          if (_isDesktop) {
            _mapController.move(
              latlong.LatLng(myLocation.lat, myLocation.lng),
              16.0,
            );
            debugPrint('✅ FlutterMap 내 위치로 이동 완료');
          } else if (_mapLibreController != null) {
            await _mapLibreController!.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng(myLocation.lat, myLocation.lng),
                16.0,
              ),
              duration: const Duration(milliseconds: 800),
            );
            debugPrint('✅ MapLibre 내 위치로 이동 완료');
          }

          // ✅ UserMessageProvider 초기화
          if (mounted) {
            _initializeMessageProvider(myLocation);
          }
        } else if (attempts >= maxAttempts) {
          timer.cancel();
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
          debugPrint('⏳ 위치 대기 중... ($attempts/$maxAttempts)');
        }
      });
    });
    
    // ✅ 3. 샵 위치 선택 모드 확인 (arguments 처리)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      
      // ✅ arguments에서 샵 위치 선택 모드 확인
      final args = ModalRoute.of(context)?.settings.arguments;
      
      debugPrint('');
      debugPrint('🔍 ════════════════════ Arguments 확인 ════════════════════');
      debugPrint('🔍 Arguments: $args');
      debugPrint('🔍 Arguments type: ${args.runtimeType}');
      debugPrint('🔍 Is Map: ${args is Map}');
      if (args is Map) {
        debugPrint('🔍 Keys: ${args.keys.toList()}');
        debugPrint('🔍 Mode value: ${args['mode']}');
      }
      debugPrint('🔍 ══════════════════════════════════════════════════');
      debugPrint('');
      
      if (args != null && args is Map && args['mode'] == 'shop_location_picker') {
        debugPrint('');
        debugPrint('🏪 ════════════════════ 샵 위치 선택 모드 ════════════════════');
        debugPrint('📍 초기 위치: (${args['lat']}, ${args['lng']})');
        debugPrint('📫 초기 주소: ${args['address']}');
        
        // 약간의 딜레이 후 핀 조정 모드 시작
        await Future.delayed(const Duration(milliseconds: 1500));
        
        if (mounted) {
          debugPrint('✅ mounted 상태 확인 완료');
          _startPinAdjustMode(
            args['lat'] ?? 37.408915,
            args['lng'] ?? 127.148245,
            args['address'] ?? '',
          );
          debugPrint('✅ 핀 조정 모드 활성화 완료');
        } else {
          debugPrint('⚠️ Widget이 dispose됨');
        }
        
        debugPrint('🏪 ════════════════════════════════════════════════════════');
        debugPrint('');
      } else {
        debugPrint('ℹ️ 일반 지도 모드');
      }
    });

    // ✅ 4. Provider 초기화 (순서 보장)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      try {
        _loadUserRole();
        // ShopsMapProvider
        final shopsProvider = context.read<ShopsMapProvider>();
        debugPrint('📦 ShopsMapProvider 초기화 중...');
        shopsProvider.fetchAllShops();
        shopsProvider.startAutoRefresh();
        debugPrint('✅ ShopsMapProvider 초기화 완료');
        // PersonalPlacesProvider (try-catch로 보호)
        try {
          final placesProvider = context.read<PersonalPlacesProvider>();
          placesProvider.fetchMyPlaces(widget.userId).then((_) {
            debugPrint('✅ 개인 장소 초기 로드 완료');
            // 지도 마커 업데이트
            if (mounted && _isMobile && _mapLibreController != null) {
              final locProvider = context.read<LocationsProvider>();
              _updateMapLibreMarkers(locProvider);
            }
        });
        } catch (e) {
          debugPrint('⚠️ PersonalPlacesProvider 초기화 실패: $e');
          debugPrint('💡 PersonalPlacesProvider가 등록되지 않았을 수 있습니다.');
        }
        
        // 유저 역할 로드
        _loadUserRole();
      } catch (e) {
        debugPrint('❌ Provider 초기화 오류: $e');
      }
    try {
      final placesProvider = context.read<PersonalPlacesProvider>();
      
      debugPrint('');
      debugPrint('📍 ════════════════════ 개인 장소 초기 로드 시작 ════════════════════');
      
      placesProvider.fetchMyPlaces(widget.userId);
      
      debugPrint('✅ 개인 장소 로드 완료: ${placesProvider.allPlaces.length}개');
      
      // Desktop이면 setState로 재구성
      if (mounted && _isDesktop) {
        setState(() {});
        debugPrint('💻 Desktop: setState 호출');
      }
      
      // Mobile이면 마커 업데이트
      if (mounted && _isMobile && _mapLibreController != null) {
        Future.delayed(const Duration(milliseconds: 500));
        final locProvider = context.read<LocationsProvider>();
        _updateMapLibreMarkers(locProvider);
        debugPrint('📱 Mobile: 마커 업데이트 완료');
      }
      
      debugPrint('📍 ════════════════════ 개인 장소 초기 로드 완료 ════════════════════');
      debugPrint('');
    } catch (e) {
      debugPrint('⚠️ PersonalPlacesProvider 초기화 실패: $e');
    }
    });

    // ✅✅✅ 지도 이동 리스너 추가 (initState 끝부분에)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('🎧 지도 이동 리스너 등록 시작');
      try {
        final locationsProvider = context.read<LocationsProvider>();
        locationsProvider.addListener(_handleMapMoveRequest);
        debugPrint('✅ 지도 이동 리스너 등록 완료');
      } catch (e) {
        debugPrint('❌ 리스너 등록 실패: $e');
      }
    });

    // ✅ 그룹 Provider 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final groupProvider = context.read<TempGroupsProvider>();
      groupProvider.fetchMyGroups(widget.userId);
      groupProvider.subscribeToGroups(widget.userId);
    });
  }

  // ✅✅✅ 그룹 액션 핸들러 (새로 추가)
  void _handleGroupAction(String action) {
    switch (action) {
      case 'list':
        _openGroupList();
        break;
      case 'create':
        _createNewGroup();
        break;
      case 'join':  // ✅ 추가
        _joinWithCode();
        break;
      case 'active':
        _openGroupList(); // 활성 그룹만 표시
        break;
    }
  }

  // ✅ 그룹 목록 열기
  void _openGroupList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TempGroupListScreen(
          userId: widget.userId,
        ),
      ),
    );
  }

// ✅ 새 그룹 만들기
Future<void> _createNewGroup() async {
  final result = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => TempGroupCreateScreen(
        userId: widget.userId,
      ),
    ),
  );
  
  // 그룹 생성 성공 시
  if (result != null && mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ "${result.groupName}" 그룹이 생성되었습니다!'),
        backgroundColor: Colors.green,
        action: SnackBarAction(
          label: '보기',
          textColor: Colors.white,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TempGroupDetailScreen(
                  userId: widget.userId,
                  groupId: result.id,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
    debugPrint('🎬 ════════════════════ initState 완료 ════════════════════');
    debugPrint('');
  }

  // ✅✅✅ 초대 코드로 참여 (새로 추가)
  void _joinWithCode() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TempGroupJoinScreen(
          userId: widget.userId,
        ),
      ),
    );
  }

  // ============================================
  // ✅ 개인 장소 클러스터링 로직
  // ============================================
  List<List<PersonalPlaceModel>> _clusterPersonalPlaces(List<PersonalPlaceModel> places) {
    if (places.isEmpty) return [];
    
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
    
    final List<List<PersonalPlaceModel>> clusters = [];
    final Set<String> processed = {};

    for (final place in places) {
      if (processed.contains(place.id)) continue;

      final cluster = <PersonalPlaceModel>[place];
      processed.add(place.id);

      for (final other in places) {
        if (processed.contains(other.id)) continue;
        
        final distanceDegrees = sqrt(
          pow(place.lat - other.lat, 2) + pow(place.lng - other.lng, 2)
        );
        final distanceMeters = distanceDegrees * 111320.0;
        
        if (distanceMeters < clusterRadiusMeters) {
          cluster.add(other);
          processed.add(other.id);
        }
      }

      clusters.add(cluster);
    }

    return clusters;
  }

  // ═══════════════════════════════════════════════════════════
  // ✅ 4. 핀 조정 모드 시작
  // ═══════════════════════════════════════════════════════════
  void _startPinAdjustMode(double lat, double lng, String address) async {
    debugPrint('📍 ═══════════════ 핀 조정 모드 시작 ═══════════════');
    
    // ✅ 함수 시작 시 mounted 체크
    if (!mounted) {
      debugPrint('⚠️ _startPinAdjustMode: Widget not mounted at start');
      return;
    }
    
    debugPrint('📫 주소: $address');
    debugPrint('📍 좌표: ($lat, $lng)');
    debugPrint('🔧 현재 _isPinAdjustMode: $_isPinAdjustMode');
    
    // ✅ setState 전 체크
    try {
      _setStateWrapper(() {
        _isPinAdjustMode = true;
        _adjustingPinLocation = LatLng(lat, lng);
        _adjustingAddress = address;
      });
      debugPrint('✅ setState 완료');
      debugPrint('✅ 변경 후 _isPinAdjustMode: $_isPinAdjustMode');
    } catch (e) {
      debugPrint('❌ setState 오류: $e');
      return;
    }
    
    // 지도 이동
    if (_isDesktop) {
      _mapController.move(latlong.LatLng(lat, lng), 16.0);
    } else if (_mapLibreController != null) {
      await _mapLibreController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(lat, lng),
          16.0,
        ),
        duration: const Duration(milliseconds: 800),
      );
      
      // ✅ 비동기 작업 후 mounted 체크
      if (!mounted) {
        debugPrint('⚠️ Widget disposed after camera animation');
        return;
      }
    }
    
    debugPrint('✅ 핀 조정 모드 활성화');
    debugPrint('📍 ═══════════════════════════════════════════════');
  }

  // ═══════════════════════════════════════════════════════════
  // ✅ 5. 핀 위치 확정
  // ═══════════════════════════════════════════════════════════
  Future<void> _confirmPinLocation() async {
    debugPrint('');
    debugPrint('✅ ═══════════════ 핀 위치 확정 ═══════════════');
    
    LatLng finalLocation;
    
    // 현재 지도 중심 좌표 가져오기
    if (_isDesktop) {
      final center = _mapController.camera.center;
      finalLocation = LatLng(center.latitude, center.longitude);
      debugPrint('🖥️ Desktop 모드: FlutterMap 중심 사용');
    } else {
      // ✅ MapLibre는 추적 중인 카메라 중심 또는 조정 중인 위치 사용
      if (_adjustingPinLocation != null) {
        finalLocation = _adjustingPinLocation!;
        debugPrint('📱 Mobile 모드: 추적 중인 위치 사용');
      } else if (_currentCameraCenter != null) {
        finalLocation = _currentCameraCenter!;
        debugPrint('📱 Mobile 모드: 카메라 중심 사용');
      } else {
        debugPrint('⚠️ 위치 정보 없음, 함수 종료');
        return;
      }
    }
    
    debugPrint('📍 최종 좌표: (${finalLocation.latitude.toStringAsFixed(6)}, ${finalLocation.longitude.toStringAsFixed(6)})');
    
    // ✅ 핀 심볼 추가 (MapLibre만)
    if (!_isDesktop && _mapLibreController != null) {
      // 기존 조정 핀 제거
      if (_adjustingPinSymbol != null) {
        try {
          await _mapLibreController!.removeSymbol(_adjustingPinSymbol!);
          debugPrint('🗑️ 기존 조정 핀 제거');
        } catch (e) {
          debugPrint('⚠️ 조정 핀 제거 실패: $e');
        }
      }
      
      // 새 핀 추가
      try {
        if (!_iconsRegistered) {
          await _registerCustomIcons();
        }
        
        _adjustingPinSymbol = await _mapLibreController!.addSymbol(
          SymbolOptions(
            geometry: finalLocation,
            iconImage: 'circle_red',
            iconSize: 1.5,
            iconAnchor: 'center',
          ),
        );
        debugPrint('✅ 핀 심볼 추가 완료');
      } catch (e) {
        debugPrint('❌ 핀 심볼 추가 실패: $e');
      }
    }
    
    // ✅ 저장/길찾기 다이얼로그 표시
    _showPinActionDialog(
      finalLocation.latitude,
      finalLocation.longitude,
      _adjustingAddress ?? '주소 정보 없음',
    );
    
    // 조정 모드 종료
    setState(() {
      _isPinAdjustMode = false;
    });
    
    debugPrint('✅ ═══════════════════════════════════════════════');
    debugPrint('');
  }

  // ═══════════════════════════════════════════════════════════
  // ✅ 6. 핀 액션 다이얼로그 (저장/길찾기)
  // ═══════════════════════════════════════════════════════════
  void _showPinActionDialog(double lat, double lng, String address) {
    // ✅ 샵 위치 선택 모드인지 확인
    final args = ModalRoute.of(context)?.settings.arguments;
    final isShopLocationPicker = args is Map && args['mode'] == 'shop_location_picker';
    
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Row(
              children: [
                const Icon(Icons.place, color: Colors.deepPurple, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '장소 관리',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 24),
            
            // 주소 정보
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      address,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // ✅ 샵 위치 선택 모드일 때 "이 위치 사용하기" 버튼
            if (isShopLocationPicker)
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context); // BottomSheet 닫기
                        Navigator.pop(context, { // MapPage 닫기 + 결과 반환
                          'lat': lat,
                          'lng': lng,
                          'address': address,
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.check_circle, size: 24),
                      label: const Text(
                        '이 위치 사용하기',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            
            // 버튼들 (샵 위치 선택 모드가 아닐 때만)
            if (!isShopLocationPicker)
              Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      
                      // ✅ 다이얼로그 표시 및 저장 완료 대기
                      final saved = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => ChangeNotifierProvider.value(
                          value: context.read<PersonalPlacesProvider>(),
                          child: SavePlaceDialog(
                            userId: widget.userId,
                            address: address,
                            lat: lat,
                            lng: lng,
                            availableGroups: _groups,
                          ),
                        ),
                      );
                      
                      // ✅ 저장 완료 시 마커 업데이트
                      if (saved == true && mounted) {
                        debugPrint('');
                        debugPrint('🔄 ════════════════════ 저장 후 마커 업데이트 ════════════════════');
                        
                        // 약간의 지연 (DB 동기화 대기)
                        await Future.delayed(const Duration(milliseconds: 800));
                        
                        if (!mounted) return;
                        
                        if (_isDesktop) {
                          // Desktop: setState로 위젯 트리 재구성
                          debugPrint('💻 Desktop 모드: setState로 재구성');
                          setState(() {
                            // FlutterMap은 Consumer로 감싸져 있어서 자동으로 업데이트됨
                          });
                        } else if (_mapLibreController != null) {
                          // Mobile: 마커 업데이트
                          debugPrint('📱 Mobile 모드: 마커 업데이트');
                          final locProvider = context.read<LocationsProvider>();
                          await _updateMapLibreMarkers(locProvider);
                        }
                        
                        debugPrint('✅ 마커 업데이트 완료');
                        debugPrint('🔄 ════════════════════════════════════════════════════════');
                        debugPrint('');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.save),
                    label: const Text('주소 저장'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _navigateToAddress(lat, lng, address);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.navigation),
                    label: const Text('길찾기'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ✅ 8. 주소로 길찾기
  // ═══════════════════════════════════════════════════════════
  Future<void> _navigateToAddress(double lat, double lng, String address) async {
    if (!mounted) return;
    
    final provider = context.read<LocationsProvider>();
    final myLocation = provider.locations[widget.userId];
    
    if (myLocation == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('현재 위치를 확인할 수 없습니다')),
        );
      }
      return;
    }
    
    try {
      final navigationService = NavigationService();
      final route = await navigationService.getRoute(
        start: latlong.LatLng(myLocation.lat, myLocation.lng),
        end: latlong.LatLng(lat, lng),
        mode: _selectedTransportMode,
      );
      
      // ✅ 비동기 작업 후 mounted 체크
      if (!mounted) return;
      
      if (route == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ 경로를 찾을 수 없습니다')),
          );
        }
        return;
      }
      
      // ✅ setState 전 체크
      if (!mounted) return;
      
      setState(() => _currentRoute = route);
      
      if (_isDesktop) {
        _showRouteOnFlutterMap(route, null);
      } else {
        await _showRouteOnMapLibre(route, null);
      }
      
      // ✅ 다시 체크
      if (!mounted) return;
      
      _showNavigationPanelForAddress(address, lat, lng, route);
    } catch (e) {
      debugPrint('❌ 길찾기 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('경로 생성 실패: $e')),
        );
      }
    }
  }

  // ============================================
  // ✅ 3. Symbol 클릭 핸들러 - 샵 클러스터링 제거
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

    // ✅ Step 2.5: 개인 장소 클러스터
    debugPrint('⏳ Step 2.5: 개인 장소 클러스터 확인 중...');
    
    for (var entry in _personalPlaceClusterMarkers.entries) {
      final cluster = entry.value;
      
      if (cluster.isEmpty) continue;
      
      double sumLat = 0, sumLng = 0;
      for (final place in cluster) {
        sumLat += place.lat;
        sumLng += place.lng;
      }
      final centerLat = sumLat / cluster.length;
      final centerLng = sumLng / cluster.length;
      
      final distance = sqrt(
        pow(centerLat - clickedLatLng.latitude, 2) + 
        pow(centerLng - clickedLatLng.longitude, 2)
      );
      
      if (distance < tolerance) {
        debugPrint('✅ 개인 장소 클러스터 매치! ${cluster.length}개');
        _showPersonalPlacesListBottomSheet(cluster);
        return;
      }
    }
    
    // ✅ Step 2.6: 단일 개인 장소
    debugPrint('⏳ Step 2.6: 단일 개인 장소 확인 중...');
    
    for (var entry in _personalPlaceMarkers.entries) {
      final place = entry.value;
      
      final distance = sqrt(
        pow(place.lat - clickedLatLng.latitude, 2) + 
        pow(place.lng - clickedLatLng.longitude, 2)
      );
      
      if (distance < tolerance) {
        debugPrint('✅ 단일 개인 장소 매치! ${place.placeName}');
        _showPersonalPlaceInfo(place);
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
  // ✅ 개인 장소 정보 표시
  // ============================================
  void _showPersonalPlaceInfo(PersonalPlaceModel place) {
    _showNavigationBottomSheet(
      entityId: place.id,
      entityName: place.placeName, // ✅ placeName
      subtitle: place.category,
      lat: place.lat,
      lng: place.lng,
      headerColor: Colors.green,
      icon: Icons.place,
      additionalInfo: [
        _buildInfoRow(Icons.location_on, '주소', place.address),
        // ✅ null 체크
        if (place.memo != null && place.memo!.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildInfoRow(Icons.note, '메모', place.memo!),
        ],
      ],
      // ✅ 삭제 로직 인라인
      onDelete: () async {
        Navigator.pop(context);
        
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('장소 삭제'),
            content: Text('${place.placeName}을(를) 삭제하시겠습니까?'),
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
        
        if (confirm == true && mounted) {
          final placesProvider = context.read<PersonalPlacesProvider>();
          final success = await placesProvider.deletePlace(
            place.id,
            widget.userId,
          );
          
          if (success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ 장소가 삭제되었습니다')),
            );
            
            // 마커 업데이트
            if (_isMobile && _mapLibreController != null) {
              final locProvider = context.read<LocationsProvider>();
              await _updateMapLibreMarkers(locProvider);
            }
          }
        }
      },
    );
  }

  // ============================================
  // ✅ 개인 장소 목록 BottomSheet
  // ============================================
  void _showPersonalPlacesListBottomSheet(List<PersonalPlaceModel> places) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // 헤더
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '내 장소',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${places.length}개 장소',
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
                
                // 장소 목록
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: places.length,
                    itemBuilder: (context, index) {
                      final place = places[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green,
                            child: Text(
                              place.placeName[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(place.placeName),
                          subtitle: Text(place.category),
                          onTap: () {
                            Navigator.pop(context);
                            _showPersonalPlaceInfo(place);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
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
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 헤더
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
            
            // 샵 목록
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
                        
                        // ✅ 버튼
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    debugPrint('🗺️ 길찾기 버튼 클릭: ${shop.shopName}');
                                    Navigator.pop(context);
                                    
                                    // ✅ _showShopNavigationWithMessage 호출 (통합 함수)
                                    _showShopNavigationWithMessage(shop);
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

  // ============================================
  // ✅ 새로운 통합 함수: 샵 네비게이션 + 홍보 메시지
  // ============================================
  void _showShopNavigationWithMessage(ShopModel shop) {
    debugPrint('');
    debugPrint('🗺️ ════════════════════ _showShopNavigationWithMessage 호출 ════════════════════');
    debugPrint('📦 샵: ${shop.shopName}');
    debugPrint('🆔 샵 ID: ${shop.shopId}');
    
    // ✅ 홍보 메시지 조회 (activeMessages + acceptedMessages)
    ShopMessageModel? displayMessage;
    
    try {
      final msgProvider = context.read<UserMessageProvider>();
      
      debugPrint('🔍 홍보 메시지 조회 시작...');
      debugPrint('📊 전체 activeMessages: ${msgProvider.activeMessages.length}개');
      debugPrint('📊 전체 acceptedMessages: ${msgProvider.acceptedMessages.length}개');
      
      // ✅ 1. activeMessages에서 먼저 찾기
      var messages = msgProvider.activeMessages
          .where((m) => m.shopId == shop.shopId)
          .toList();
      
      debugPrint('🎯 activeMessages 중 이 샵의 메시지: ${messages.length}개');
      
      // ✅ 2. 없으면 acceptedMessages에서 찾기
      if (messages.isEmpty) {
        debugPrint('🔍 acceptedMessages에서 조회 중...');
        messages = msgProvider.acceptedMessages
            .where((m) => m.shopId == shop.shopId)
            .toList();
        
        debugPrint('🎯 acceptedMessages 중 이 샵의 메시지: ${messages.length}개');
      }
      
      if (messages.isNotEmpty) {
        displayMessage = messages.first;
        debugPrint('✅ 홍보 메시지 발견: "${displayMessage.message}"');
      } else {
        debugPrint('ℹ️ 홍보 메시지 없음');
      }
    } catch (e) {
      debugPrint('⚠️ 홍보 메시지 조회 실패: $e');
    }
    
    debugPrint('📋 additionalInfo 구성 중...');
    debugPrint('   displayMessage: ${displayMessage != null ? "있음" : "없음"}');
    
    // ✅ additionalInfo 구성
    final List<Widget> additionalInfo = [
      // ✅ 홍보 메시지
      if (displayMessage != null) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber[200]!, width: 2),
          ),
          child: Row(
            children: [
              const Icon(Icons.campaign, color: Colors.orange, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '홍보 메시지',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      displayMessage.message,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ] else ...[
        // 메시지 없을 때
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!, width: 1),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.grey, size: 18),
              SizedBox(width: 8),
              Text(
                '현재 진행 중인 홍보가 없습니다',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      
      // 기본 정보
      _buildInfoRow(Icons.location_on, '주소', shop.address),
      const SizedBox(height: 8),
      _buildInfoRow(Icons.phone, '전화', shop.phone),
      if (shop.description.isNotEmpty) ...[
        const SizedBox(height: 8),
        _buildInfoRow(Icons.description, '설명', shop.description),
      ],
    ];
    
    debugPrint('✅ additionalInfo 구성 완료: ${additionalInfo.length}개 위젯');
    
    // ✅ _showNavigationBottomSheet 호출
    _showNavigationBottomSheet(
      entityId: shop.shopId,
      entityName: shop.shopName,
      subtitle: shop.category,
      lat: shop.lat,
      lng: shop.lng,
      headerColor: Colors.deepPurple,
      icon: Icons.store,
      additionalInfo: additionalInfo,
    );
    
    debugPrint('🗺️ ════════════════════ _showShopNavigationWithMessage 완료 ════════════════════');
    debugPrint('');
  }

  // ============================================
  // ✅ 샵 정보 표시 (디버깅 강화 버전)
  // ============================================
  void _showShopInfo(ShopModel shop) {
    debugPrint('');
    debugPrint('📍 ════════════════════ _showShopInfo 호출 ════════════════════');
    debugPrint('📦 샵: ${shop.shopName}');
    
    // ✅ 홍보 메시지 조회
    ShopMessageModel? displayMessage;
    
    try {
      final msgProvider = context.read<UserMessageProvider>();
      
      debugPrint('🔍 홍보 메시지 조회 시작...');
      debugPrint('📊 전체 activeMessages 개수: ${msgProvider.activeMessages.length}');
      
      // 전체 메시지 출력
      for (var msg in msgProvider.activeMessages) {
        debugPrint('   📨 메시지: shopId=${msg.shopId}, message="${msg.message}"');
      }
      
      final messages = msgProvider.activeMessages
          .where((m) => m.shopId == shop.shopId)
          .toList();
      
      debugPrint('🎯 이 샵(${shop.shopId})의 메시지: ${messages.length}개');
      
      if (messages.isNotEmpty) {
        displayMessage = messages.first;
        debugPrint('✅ 홍보 메시지 발견: "${displayMessage.message}"');
      } else {
        debugPrint('ℹ️ 활성화된 홍보 메시지 없음');
      }
    } catch (e) {
      debugPrint('⚠️ 홍보 메시지 조회 실패: $e');
    }
    
    debugPrint('📋 ShopInfoBottomSheet 호출 준비');
    debugPrint('   displayMessage: ${displayMessage != null ? "있음 (${displayMessage.message})" : "없음"}');
    debugPrint('');
    
    showModalBottomSheet(
      context: context,
      builder: (_) => ShopInfoBottomSheet(
        shop: shop,
        promotionMessage: displayMessage,  // ✅ 홍보 메시지 전달
        onNavigate: (shop) {
          _navigateToShop(shop, displayMessage);  // ✅ 메시지도 함께 전달
        },
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
    
    debugPrint('📍 ════════════════════ _showShopInfo 완료 ════════════════════');
    debugPrint('');
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
      // ignore: deprecated_member_use
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
      // ignore: deprecated_member_use
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.usersCollectionId,
        queries: [Query.equal('userId', widget.userId)],
      );
      
      if (result.documents.isNotEmpty) {
        // ignore: deprecated_member_use
        await _db.updateDocument(
          databaseId: AppwriteConstants.databaseId,
          collectionId: AppwriteConstants.usersCollectionId,
          documentId: result.documents.first.$id,
          data: {'role': newRole.name},
        );
        
        setState(() {
          _currentRole = newRole;
        });
        
        // ignore: use_build_context_synchronously
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
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('역할 전환 실패')),
      );
    }
  }
  
  // ✅ 4. 샵 주인 페이지로 이동
  void _openShopOwnerPage() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => ShopProvider(),
          child: ShopOwnerPage(userId: widget.userId),
        ),
      ),
    );
    
    // ✅ 돌아올 때 처리
    if (result != null && result is Map) {
      final action = result['action'];
      
      if (action == 'view_location') {
        // ✅ 위치 보기만 (길찾기 없음)
        final lat = result['lat'] as double;
        final lng = result['lng'] as double;
        final userId = result['userId'] as String;
        
        debugPrint('');
        debugPrint('👁️ ════════════════════ 수락자 위치로 이동 ════════════════════');
        debugPrint('👤 사용자: $userId');
        debugPrint('📍 위치: ($lat, $lng)');
        
        // ✅ 지도 이동만 (경로 생성 없음)
        if (_isDesktop) {
          _mapController.move(latlong.LatLng(lat, lng), 17.0);
        } else if (_mapLibreController != null) {
          await _mapLibreController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(lat, lng),
              17.0,
            ),
            duration: const Duration(milliseconds: 1000),
          );
        }
        
        debugPrint('✅ 지도 이동 완료');
        debugPrint('👁️ ════════════════════════════════════════════════════════');
        debugPrint('');
        
        // ✅ 간단한 마커 표시 (선택사항)
        if (_mapLibreController != null) {
          try {
            await _mapLibreController!.addSymbol(
              SymbolOptions(
                geometry: LatLng(lat, lng),
                iconImage: 'circle_blue',
                iconSize: 1.5,
                iconAnchor: 'center',
              ),
            );
            debugPrint('✅ 마커 추가 완료');
          } catch (e) {
            debugPrint('⚠️ 마커 추가 실패: $e');
          }
        }
      }
    }
  }
  
  // ============================================
  // ✅ 샵 길찾기 (통합 버전 - _showShopInfo만 호출)
  // ============================================
  Future<void> _navigateToShop(ShopModel shop, ShopMessageModel? message) async {
    debugPrint('');
    debugPrint('🗺️ ════════════════════ _navigateToShop 호출 ════════════════════');
    debugPrint('📦 샵: ${shop.shopName}');
    debugPrint('📨 전달받은 메시지: ${message?.message}');
    
    await Future.delayed(const Duration(milliseconds: 100));
    
    if (!mounted) {
      debugPrint('⚠️ Widget disposed');
      return;
    }
    
    // ✅ 홍보 메시지 조회
    ShopMessageModel? displayMessage = message;
    
    if (displayMessage == null) {
      debugPrint('🔍 홍보 메시지 조회 시작...');
      try {
        final msgProvider = context.read<UserMessageProvider>();
        
        debugPrint('📊 전체 activeMessages 개수: ${msgProvider.activeMessages.length}');
        
        for (var msg in msgProvider.activeMessages) {
          debugPrint('   📨 메시지: shopId=${msg.shopId}, message="${msg.message}"');
        }
        
        final messages = msgProvider.activeMessages
            .where((m) => m.shopId == shop.shopId)
            .toList();
        
        debugPrint('🎯 이 샵(${shop.shopId})의 메시지: ${messages.length}개');
        
        if (messages.isNotEmpty) {
          displayMessage = messages.first;
          debugPrint('✅ 홍보 메시지 발견: "${displayMessage.message}"');
        } else {
          debugPrint('ℹ️ 활성화된 홍보 메시지 없음');
        }
      } catch (e) {
        debugPrint('⚠️ 홍보 메시지 조회 실패: $e');
      }
    }
    
    debugPrint('');
    debugPrint('📋 _showShopInfo 호출');
    debugPrint('   displayMessage: ${displayMessage != null ? "있음" : "없음"}');
    debugPrint('');
    
    // ✅ _showShopInfo 호출 (displayMessage 전달)
    _showShopInfoWithMessage(shop, displayMessage);
    
    debugPrint('✅ _navigateToShop 완료');
    debugPrint('🗺️ ═══════════════════════════════════════════════════');
    debugPrint('');
  }

  // ============================================================================
  // ✅ 샵 정보 표시 (메시지 파라미터 포함) - 새로 추가
  // ============================================================================
  void _showShopInfoWithMessage(ShopModel shop, ShopMessageModel? message) {
    debugPrint('');
    debugPrint('📍 ════════════════════ 샵 정보 표시 ════════════════════');
    debugPrint('📦 샵: ${shop.shopName}');
    debugPrint('📨 메시지: ${message?.message ?? "없음"}');
    
    // ✅ 메시지가 전달되지 않았으면 조회
    ShopMessageModel? displayMessage = message;
    
    if (displayMessage == null) {
      debugPrint('🔍 홍보 메시지 조회 시작...');
      try {
        final msgProvider = context.read<UserMessageProvider>();
        
        debugPrint('📊 전체 activeMessages 개수: ${msgProvider.activeMessages.length}');
        
        final messages = msgProvider.activeMessages
            .where((m) => m.shopId == shop.shopId)
            .toList();
        
        debugPrint('🎯 이 샵의 메시지: ${messages.length}개');
        
        if (messages.isNotEmpty) {
          displayMessage = messages.first;
          debugPrint('✅ 홍보 메시지 발견: "${displayMessage.message}"');
        }
      } catch (e) {
        debugPrint('⚠️ 조회 실패: $e');
      }
    }
    
    showModalBottomSheet(
      context: context,
      builder: (_) => ShopInfoBottomSheet(
        shop: shop,
        promotionMessage: displayMessage,  // ✅ 메시지 전달
        onNavigate: (shop) {
          _navigateToShop(shop, displayMessage);  // ✅ 메시지와 함께 전달
        },
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
    
    debugPrint('📍 ════════════════════ 샵 정보 표시 완료 ════════════════════');
    debugPrint('');
  }

  // ✅ 4. FlutterMap에 경로 표시
  void _showRouteOnFlutterMap(RouteResult route, ShopModel? shop) {
    // ✅ 함수 시작 시 mounted 체크
    if (!mounted) {
      debugPrint('⚠️ _showRouteOnFlutterMap: Widget not mounted');
      return;
    }
    
    debugPrint('');
    debugPrint('🗺️ ════════════════════ FlutterMap 경로 표시 ════════════════════');
    debugPrint('   경로 포인트: ${route.coordinates.length}개');
    debugPrint('   거리: ${route.formattedDistance}');
    debugPrint('   시간: ${route.formattedDuration}');
    debugPrint('   이동수단: ${route.transportModeString}');
    if (shop != null) {
      debugPrint('   목적지: ${shop.shopName}');
    }
    debugPrint('🗺️ ════════════════════════════════════════════════════════');
    debugPrint('');
    
    // ✅ setState 전에 한 번 더 체크
    if (!mounted) return;
    
    setState(() {
      _currentRoute = route;
    });
    
    // 지도 이동
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

  // ============================================
  // ✅ 4. FlutterMap (Desktop) - 샵 클러스터링 추가
  // ============================================
  Widget _buildFlutterMapWithShopsAndRoute(LocationsProvider provider) {
    final allLocs = provider.getDisplayLocations();
    
    return Consumer<ShopsMapProvider>(
      builder: (context, shopsProvider, _) {
        // ✅ 샵 마커 생성 - 유저 클러스터링과 동일하게 처리
        final List<Marker> shopMarkers = _showShopsLayer
            ? _buildFlutterMapShopClusters(shopsProvider.filteredShops)
            : <Marker>[];
      // ✅ 개인 장소 마커 생성 추가
      return Consumer<PersonalPlacesProvider>(
        builder: (context, placesProvider, _) {
          final List<Marker> placeMarkers = _showPersonalPlacesLayer
              ? _buildFlutterMapPersonalPlaceClusters(placesProvider.filteredPlaces)
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
                      color: Colors.blue.withOpacity(0.7),
                      strokeWidth: 5.0,
                    ),
                  ],
                ),
              );
              
              // ✅ 화살표 마커 추가
              final arrowMarkers = _buildArrowMarkers(_currentRoute!.coordinates);
              if (arrowMarkers.isNotEmpty) {
                routeLayers.add(
                  MarkerLayer(markers: arrowMarkers),
                );
              }
              
              // 시작점/도착점 마커
              routeLayers.add(
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentRoute!.coordinates.first,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.green,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
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
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
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
                    
                    // ✅ 선택된 instruction 마커
                    if (_selectedInstructionMarkerFlutter != null)
                      MarkerLayer(
                        markers: [_selectedInstructionMarkerFlutter!],
                      ),
                    
                    // ✅ 개인 장소 마커 레이어 추가
                    if (_showPersonalPlacesLayer)
                      MarkerLayer(markers: placeMarkers),
                    
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
        );});
      },
    );
  }

  // ============================================
  // ✅ FlutterMap용 개인 장소 클러스터 마커 생성
  // ============================================
  List<Marker> _buildFlutterMapPersonalPlaceClusters(List<PersonalPlaceModel> places) {
    if (places.isEmpty) return [];
    
    final List<Marker> markers = [];
    final placeClusters = _clusterPersonalPlaces(places);
    
    //debugPrint('🗺️ Desktop 개인 장소 클러스터: ${placeClusters.length}개');
    
    for (final cluster in placeClusters) {
      if (cluster.length == 1) {
        // 단일 장소
        final place = cluster[0];
        markers.add(
          Marker(
            key: ValueKey('place_${place.id}'),
            point: latlong.LatLng(place.lat, place.lng),
            width: 120,
            height: 140,
            child: GestureDetector(
              onTap: () => _showPersonalPlaceInfo(place),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
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
                          place.placeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          place.category,
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
                    Icons.bookmark,
                    color: Colors.green,
                    size: 26,
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        // 장소 클러스터
        double sumLat = 0, sumLng = 0;
        for (final place in cluster) {
          sumLat += place.lat;
          sumLng += place.lng;
        }
        final centerLat = sumLat / cluster.length;
        final centerLng = sumLng / cluster.length;
        
        markers.add(
          Marker(
            key: ValueKey('place_cluster_${cluster.hashCode}'),
            point: latlong.LatLng(centerLat, centerLng),
            width: 140,
            height: 160,
            child: GestureDetector(
              onTap: () => _showPersonalPlacesListBottomSheet(cluster),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.teal,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
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
                        const Text(
                          '내 장소',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${cluster.length}개',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          cluster.take(3).map((p) => p.placeName).join(', '),
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
                    Icons.bookmark,
                    color: Colors.teal,
                    size: 26,
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    
    //debugPrint('✅ Desktop 개인 장소 마커 ${markers.length}개 생성 완료');
    return markers;
  }

  // ✅ 5. MapLibre에 경로 표시
  Future<void> _showRouteOnMapLibre(RouteResult route, ShopModel? shop) async {
    if (_mapLibreController == null) return;
    
    try {
      debugPrint('🎯 MapLibre에 경로 추가 중...');
      debugPrint('   이동수단: ${route.transportModeString}');
      if (shop != null) {
        debugPrint('   목적지: ${shop.shopName}');
      }
      
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
                  // ignore: deprecated_member_use
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
                  _navLanguage == NavigationLanguage.korean
                      ? '${_currentInstructions.length}개 스텝'
                      : '${_currentInstructions.length} Steps',
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
            // ignore: deprecated_member_use
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ✅ 헤더 (언어 선택 버튼 추가)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                // ✅ 첫 번째 줄: 제목 + 버튼들
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 제목
                    Text(
                      _navLanguage == NavigationLanguage.korean
                          ? '경로 안내'
                          : 'Navigation',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        // ✅ 언어 변경 버튼
                        IconButton(
                          icon: Icon(
                            _navLanguage == NavigationLanguage.korean
                                ? Icons.language
                                : Icons.g_translate,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _navLanguage = _navLanguage == NavigationLanguage.korean
                                  ? NavigationLanguage.english
                                  : NavigationLanguage.korean;
                            });
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: _navLanguage == NavigationLanguage.korean
                              ? 'English'
                              : '한국어',
                        ),
                        const SizedBox(width: 4),
                        // ✅ 최소화 버튼
                        IconButton(
                          icon: const Icon(Icons.minimize, color: Colors.white, size: 20),
                          onPressed: () {
                            setState(() {
                              _isInstructionPanelMinimized = true;
                            });
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: _navLanguage == NavigationLanguage.korean ? '최소화' : 'Minimize',
                        ),
                        const SizedBox(width: 4),
                        // ✅ 종료 버튼
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 20),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext dialogContext) {
                                return AlertDialog(
                                  title: Text(
                                    _navLanguage == NavigationLanguage.korean
                                        ? '길찾기 종료'
                                        : 'End Navigation',
                                  ),
                                  content: Text(
                                    _navLanguage == NavigationLanguage.korean
                                        ? '길찾기를 종료하시겠습니까?'
                                        : 'Do you want to end navigation?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(dialogContext);
                                      },
                                      child: Text(
                                        _navLanguage == NavigationLanguage.korean
                                            ? '취소'
                                            : 'Cancel',
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(dialogContext);
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
                                        
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              _navLanguage == NavigationLanguage.korean
                                                  ? '길찾기가 종료되었습니다'
                                                  : 'Navigation ended',
                                            ),
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                      },
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                      child: Text(
                                        _navLanguage == NavigationLanguage.korean
                                            ? '종료'
                                            : 'End',
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: _navLanguage == NavigationLanguage.korean ? '종료' : 'Close',
                        ),
                      ],
                    ),
                  ],
                ),
                
                // ✅ 두 번째 줄: 전체 거리 + 시간 + 스텝 수
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // 전체 거리
                      Row(
                        children: [
                          const Icon(Icons.straighten, color: Colors.white70, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            _currentRoute!.formattedDistance,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      // 구분선
                      Container(
                        height: 16,
                        width: 1,
                        color: Colors.white30,
                      ),
                      // 전체 시간
                      Row(
                        children: [
                          const Icon(Icons.schedule, color: Colors.white70, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            _currentRoute!.formattedDuration,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      // 구분선
                      Container(
                        height: 16,
                        width: 1,
                        color: Colors.white30,
                      ),
                      // 스텝 수
                      Row(
                        children: [
                          const Icon(Icons.list_alt, color: Colors.white70, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            _navLanguage == NavigationLanguage.korean
                                ? '${_currentInstructions.length}개'
                                : '${_currentInstructions.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
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

          // ✅ 스텝 리스트 (언어 반영)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _currentInstructions.length,
              itemBuilder: (context, index) {
                final instruction = _currentInstructions[index];
                final isSelected = _selectedInstructionIndex == index;

                // ✅ 언어별 설명 가져오기
                final detailedInstruction = instruction.getFullDescription(_navLanguage);
                final formattedDistance = instruction.formattedDistance;
                final duration = instruction.duration ?? 0;

                return GestureDetector(
                  onTap: () async {
                    setState(() {
                      _selectedInstructionIndex = index;
                    });

                    if (_selectedInstructionMarker != null && _mapLibreController != null) {
                      try {
                        await _mapLibreController!.removeSymbol(_selectedInstructionMarker!);
                      } catch (e) {
                        debugPrint('⚠️ 이전 마커 제거 실패: $e');
                      }
                    }

                    final stepLocation = instruction.location;

                    if (_isDesktop) {
                      setState(() {
                        _selectedInstructionIndex = index;
                        // ✅ 선택된 instruction 마커 생성
                        _selectedInstructionMarkerFlutter = latlong.Marker(
                          key: const ValueKey('selected_instruction'),
                          point: latlong.LatLng(
                            stepLocation.latitude,
                            stepLocation.longitude,
                          ),
                          width: 60,
                          height: 80,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // 펄스 효과 배경
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.orange.withOpacity(0.3),
                                ),
                              ),
                              // 메인 마커
                              Container(
                                width: 45,
                                height: 45,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.orange,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.5),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.navigation,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                              // 위치 표시 핀
                              Positioned(
                                bottom: 0,
                                child: Container(
                                  width: 4,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      });
                      
                      _mapController.move(
                        latlong.LatLng(stepLocation.latitude, stepLocation.longitude),
                        17.0,
                      );
                    } else if (_mapLibreController != null) {
                      try {
                        if (!_iconsRegistered) {
                          await _registerCustomIcons();
                        }
                        
                        _selectedInstructionMarker = await _mapLibreController!.addSymbol(
                          SymbolOptions(
                            geometry: LatLng(stepLocation.latitude, stepLocation.longitude),
                            iconImage: 'circle_red',
                            iconSize: 1.5,
                            iconAnchor: 'center',
                          ),
                        );

                        await _mapLibreController!.animateCamera(
                          CameraUpdate.newLatLngZoom(
                            LatLng(stepLocation.latitude, stepLocation.longitude),
                            17.0,
                          ),
                          duration: const Duration(milliseconds: 800),
                        );
                      } catch (e) {
                        debugPrint('❌ 마커 추가 실패: $e');
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
                            // ✅ 방향 아이콘
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected ? Colors.blue : Colors.grey[400],
                              ),
                              child: Icon(
                                instruction.getDirectionIcon(),
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
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
                              duration > 0
                                  ? _formatNavigationTime(duration, _navLanguage)
                                  : '-',
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
      //debugPrint('✅ 아이콘 등록: $iconKey ($text)');
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

  Future<void> _updateMapLibreMarkers(
    LocationsProvider provider, {
    bool isAutoUpdate = false,
  }) async {
    if (_mapLibreController == null || !_isMobile) return;
    if (_isUpdatingMarkers) return;

    _isUpdatingMarkers = true;
    if (!isAutoUpdate) _lastManualUpdate = DateTime.now();

    try {
      // 1. 기존 Symbol 제거
      final symbolsList = _symbols.values.toList();
      _symbols.clear();
      
      for (var symbol in symbolsList) {
        try {
          await _mapLibreController!.removeSymbol(symbol);
        } catch (e) {
          // 이미 제거된 심볼 무시
        }
      }

      // 2. 유저 마커
      final allLocs = provider.getDisplayLocations();
      final locs = await _filterLocationsByGroup(allLocs);
      
      _userMarkers.clear();
      _clusterMarkers.clear();

      if (locs.isNotEmpty) {
        final userClusters = _clusterLocations(locs);

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

      // 3. 샵 마커
      if (_showShopsLayer) {
        final shopsProvider = context.read<ShopsMapProvider>();
        await _addShopMarkersWithClustering(shopsProvider);
      }
      
      // ✅ 4. 개인 장소 마커 추가
      if (_showPersonalPlacesLayer) {
        try {
          final placesProvider = context.read<PersonalPlacesProvider>();
          await _addPersonalPlaceMarkersWithClustering(placesProvider);
        } catch (e) {
          debugPrint('⚠️ 개인 장소 마커 추가 실패: $e');
        }
      }

    } catch (e) {
      debugPrint('❌ 마커 업데이트 실패: $e');
    } finally {
      _isUpdatingMarkers = false;
    }
  }

  // ============================================
  // ✅ 개인 장소 마커 클러스터링 추가
  // ============================================
  Future<void> _addPersonalPlaceMarkersWithClustering(
    PersonalPlacesProvider placesProvider,
  ) async {
    if (_mapLibreController == null) {
      debugPrint('❌ MapLibre controller 없음');
      return;
    }

    try {
      debugPrint('');
      debugPrint('📍 ════════════════════ 개인 장소 클러스터링 시작 ════════════════════');
      
      _personalPlaceMarkers.clear();
      _personalPlaceClusterMarkers.clear();

      final places = placesProvider.filteredPlaces;
      debugPrint('📦 표시할 개인 장소: ${places.length}개');
      
      if (places.isEmpty) {
        debugPrint('⚠️ 개인 장소 없음 - 전체: ${placesProvider.allPlaces.length}개');
        debugPrint('📍 ════════════════════════════════════════════════════════');
        debugPrint('');
        return;
      }

      // ✅ 각 장소 정보 출력
      for (var place in places) {
        debugPrint('   📍 ${place.placeName} (${place.category}) - (${place.lat.toStringAsFixed(6)}, ${place.lng.toStringAsFixed(6)})');
      }

      final placeClusters = _clusterPersonalPlaces(places);
      debugPrint('📦 개인 장소 클러스터: ${placeClusters.length}개');

      for (int i = 0; i < placeClusters.length; i++) {
        final cluster = placeClusters[i];
        
        if (cluster.length == 1) {
          final place = cluster[0];
          _personalPlaceMarkers[place.id] = place;
          await _addSymbolSinglePersonalPlace(place);
          debugPrint('   ✅ 단일 장소 심볼 추가: ${place.placeName}');
        } else {
          _personalPlaceClusterMarkers['place_cluster_$i'] = cluster;
          await _addSymbolPersonalPlaceCluster(cluster, i);
          debugPrint('   ✅ 장소 클러스터 $i: ${cluster.length}개');
        }
      }

      debugPrint('✅ 최종 결과:');
      debugPrint('   - 단일 장소: ${_personalPlaceMarkers.length}개');
      debugPrint('   - 클러스터: ${_personalPlaceClusterMarkers.length}개');
      debugPrint('   - 총 심볼: ${_symbols.keys.where((k) => k.startsWith('place_')).length}개');
      debugPrint('📍 ════════════════════ 개인 장소 클러스터링 완료 ════════════════════');
      debugPrint('');

    } catch (e, stack) {
      debugPrint('❌ 개인 장소 클러스터링 실패: $e');
      debugPrint('Stack: $stack');
    }
  }

  // ============================================
  // ✅ 단일 개인 장소 심볼 추가
  // ============================================
  Future<void> _addSymbolSinglePersonalPlace(PersonalPlaceModel place) async {
    if (_mapLibreController == null) return;
    
    if (!_iconsRegistered) {
      await _registerCustomIcons();
    }

    try {
      // ✅ 장소 이름 첫 글자
      final initial = place.placeName.isNotEmpty 
          ? place.placeName[0].toUpperCase() 
          : 'P';
      
      // ✅ 개인 장소용 아이콘 동적 생성 (초록색으로 구분)
      final iconKey = 'place_${place.id}';
      await _registerIconWithText(iconKey, Colors.green, initial, 44);

      debugPrint('🎨 개인 장소 아이콘 등록: $iconKey (${place.placeName})');

      // ✅ 아이콘 추가
      final mainSymbol = await _mapLibreController!.addSymbol(
        SymbolOptions(
          geometry: LatLng(place.lat, place.lng),
          iconImage: iconKey,
          iconSize: 1.0,
          iconAnchor: 'center',
        ),
      );
      
      _symbols['place_${place.id}'] = mainSymbol;

      // ✅ 장소 이름 라벨 추가
      final labelSymbol = await _mapLibreController!.addSymbol(
        SymbolOptions(
          geometry: LatLng(place.lat, place.lng),
          textField: _short(place.placeName, 6),
          textSize: 11.0,
          textColor: '#000000',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 2.0,
          textAnchor: 'top',
          textOffset: const Offset(0, 1.2),
        ),
      );
      _symbols['place_${place.id}_label'] = labelSymbol;

    } catch (e, stack) {
      debugPrint('❌ 개인 장소 마커 추가 실패: ${place.placeName} - $e');
      debugPrint('Stack: $stack');
    }
  }

  // ============================================
  // ✅ 개인 장소 클러스터 심볼 추가
  // ============================================
  Future<void> _addSymbolPersonalPlaceCluster(
    List<PersonalPlaceModel> cluster,
    int index,
  ) async {
    if (_mapLibreController == null || cluster.isEmpty) return;
    
    if (!_iconsRegistered) {
      await _registerCustomIcons();
    }

    try {
      // ✅ 클러스터 중심 계산
      double sumLat = 0, sumLng = 0;
      for (final place in cluster) {
        sumLat += place.lat;
        sumLng += place.lng;
      }
      final centerLat = sumLat / cluster.length;
      final centerLng = sumLng / cluster.length;

      // ✅ 처음 3개 장소의 이니셜
      final initials = <String>[];
      for (int i = 0; i < min(3, cluster.length); i++) {
        final initial = cluster[i].placeName.isNotEmpty 
            ? cluster[i].placeName[0].toUpperCase() 
            : 'P';
        initials.add(initial);
      }

      String initialsText;
      if (cluster.length <= 3) {
        initialsText = initials.join(' ');
      } else {
        initialsText = '${initials[0]}${initials[1]}${initials[2]}';
      }

      // ✅ 클러스터 아이콘 생성 (초록색)
      final iconKey = 'place_cluster_$index';
      await _registerIconWithText(iconKey, Colors.teal, initialsText, 60);

      // ✅ 아이콘 추가
      final clusterSymbol = await _mapLibreController!.addSymbol(
        SymbolOptions(
          geometry: LatLng(centerLat, centerLng),
          iconImage: iconKey,
          iconSize: 1.0,
          iconAnchor: 'center',
        ),
      );
      
      _symbols['place_cluster_$index'] = clusterSymbol;

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
      _symbols['place_cluster_${index}_label'] = labelSymbol;

    } catch (e, stack) {
      debugPrint('❌ 개인 장소 클러스터 추가 실패: $e');
      debugPrint('Stack: $stack');
    }
  }

  // ============================================
  // ✅ 2. 샵 마커 클러스터링 (유저 클러스터링 로직 재사용)
  // ============================================
  Future<void> _addShopMarkersWithClustering(ShopsMapProvider shopsProvider) async {
    if (_mapLibreController == null) return;

    try {
      // debugPrint('');
      // debugPrint('🏪 ════════════════════ 샵 클러스터링 시작 ════════════════════');
      
      _shopMarkers.clear();
      _shopClusterMarkers.clear();

      final shops = shopsProvider.filteredShops;
      debugPrint('📦 표시할 샵: ${shops.length}개');

      if (shops.isEmpty) {
        debugPrint('⚠️  샵이 없음');
        debugPrint('🏪 ════════════════════════════════════════════════════════');
        debugPrint('');
        return;
      }

      // ✅ 유저 클러스터링 로직 재사용
      final shopClusters = _clusterShops(shops);
      debugPrint('📦 샵 클러스터: ${shopClusters.length}개');

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
          debugPrint('   ✅ 샵 클러스터 $i: ${cluster.length}개');
        }
      }

      // debugPrint('🏪 ════════════════════ 샵 클러스터링 완료 ════════════════════');
      // debugPrint('');

    } catch (e, stack) {
      debugPrint('❌ 샵 클러스터링 실패: $e');
      debugPrint('Stack: $stack'    );
    }
  }

  // ============================================
  // ✅ 5. FlutterMap용 샵 클러스터 마커 생성
  // ============================================
  List<Marker> _buildFlutterMapShopClusters(List<ShopModel> shops) {
    if (shops.isEmpty) return [];
    
    final List<Marker> markers = [];
    final shopClusters = _clusterShops(shops);
    
    //debugPrint('🗺️  Desktop 샵 클러스터: ${shopClusters.length}개');
    
    for (final cluster in shopClusters) {
      if (cluster.length == 1) {
        // 단일 샵
        final shop = cluster[0];
        markers.add(
          Marker(
            key: ValueKey(shop.shopId),
            point: latlong.LatLng(shop.lat, shop.lng),
            width: 120,
            height: 140,
            child: GestureDetector(
              onTap: () => _onShopMarkerTap(shop),
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
          ),
        );
      } else {
        // 샵 클러스터
        double sumLat = 0, sumLng = 0;
        for (final shop in cluster) {
          sumLat += shop.lat;
          sumLng += shop.lng;
        }
        final centerLat = sumLat / cluster.length;
        final centerLng = sumLng / cluster.length;
        
        markers.add(
          Marker(
            key: ValueKey('shop_cluster_${cluster.hashCode}'),
            point: latlong.LatLng(centerLat, centerLng),
            width: 140,
            height: 160,
            child: GestureDetector(
              onTap: () => _showShopsListBottomSheet(cluster),
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
                        const Text(
                          '이 위치에',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${cluster.length}개 가게',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          cluster.take(3).map((s) => s.shopName).join(', '),
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
          ),
        );
      }
    }
    
    return markers;
  }

  // ============================================
  // ✅ 샵 클러스터링 로직
  // ============================================
  List<List<ShopModel>> _clusterShops(List<ShopModel> shops) {
    if (shops.isEmpty) return [];
    
    // ✅ 유저 클러스터링과 동일한 줌 레벨별 반경 사용
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
    
    //debugPrint('📦 [샵 클러스터링] 줌: ${_currentZoom.toStringAsFixed(2)}, 반경: ${clusterRadiusMeters.toStringAsFixed(0)}m');
    
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
        }
      }

      clusters.add(cluster);
    }

    //debugPrint('📦 결과: ${clusters.length}개 (단일: ${clusters.where((c) => c.length == 1).length}, 그룹: ${clusters.where((c) => c.length > 1).length})');
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

      //debugPrint('🎨 Adding marker for ${loc.userId} with icon: $iconKey');

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
      //debugPrint('✅ Icon symbol added: ${mainSymbol.id}');

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
      
      //debugPrint('✅ 단일 마커 추가 완료: ${loc.userId}');

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

    //debugPrint('📦 결과: ${clusters.length}개 (단일: ${clusters.where((c) => c.length == 1).length}, 그룹: ${clusters.where((c) => c.length > 1).length})');
    return clusters;
  }

  Future<String?> _addGroupToDB(String name) async {
    try {
      // ignore: deprecated_member_use
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

      // ignore: deprecated_member_use
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
      // ignore: deprecated_member_use
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
    debugPrint('🛑 ════════════════════ MapPage dispose ════════════════════');
    
    // ✅ 1. 타이머 정리
    _updateTimer?.cancel();
    _autoMoveTimer?.cancel();
    _durationTimer?.cancel();
    _markerUpdateTimer?.cancel();
    
    // ✅ 2. 지도 마커 정리 (비동기 작업 없이)
    if (_adjustingPinSymbol != null && _mapLibreController != null) {
      _mapLibreController!.removeSymbol(_adjustingPinSymbol!).catchError((e) {
        debugPrint('⚠️ 조정 핀 제거 실패: $e');
      });
    }
    
    if (_addressPinMarker != null && _mapLibreController != null) {
      _mapLibreController!.removeSymbol(_addressPinMarker!).catchError((e) {
        debugPrint('⚠️ 주소 핀 제거 실패: $e');
      });
    }

    // ✅ 저장된 참조 사용 (context 사용 안 함!)
    _locationsProvider?.removeListener(_handleMapMoveRequest);
    _locationsProvider = null;

    // ✅✅✅ 리스너 제거 (dispose 시작 부분에)
    try {
      final locationsProvider = context.read<LocationsProvider>();
      locationsProvider.removeListener(_handleMapMoveRequest);
      debugPrint('✅ 지도 이동 리스너 제거 완료');
    } catch (e) {
      debugPrint('⚠️ 리스너 제거 오류 (무시 가능): $e');
    }

    debugPrint('🛑 ════════════════════ dispose 완료 ════════════════════');
    
    super.dispose();
  }

  // ✅✅✅ 지도 이동 요청 처리 (State 클래스 안에 추가)
  void _handleMapMoveRequest() {
    //debugPrint('');
    //debugPrint('🎧 ════════════════════ _handleMapMoveRequest 호출됨 ════════════════════');

    if (!mounted) {
      debugPrint('⚠️ MapPage가 이미 dispose되어 지도 이동 무시');
      return;
    }

    //final provider = context.read<LocationsProvider>();

    try {
      final locationsProvider = context.read<LocationsProvider>();
      final target = locationsProvider.targetMapLocation;
      
      //debugPrint('📍 타겟 위치: $target');
      
      if (target == null) {
        // debugPrint('ℹ️ 타겟이 null - 아무 작업 안 함');
        // debugPrint('🎧 ══════════════════════════════════════════════════');
        // debugPrint('');
        return;
      }
      
      // debugPrint('✅ 타겟 발견! 지도 이동 시작');
      // debugPrint('   - latitude: ${target.latitude}');
      // debugPrint('   - longitude: ${target.longitude}');
      // debugPrint('   - _isDesktop: $_isDesktop');
      // debugPrint('   - _mapLibreController: ${_mapLibreController != null}');
      
      if (_isDesktop) {
        debugPrint('🖥️ 데스크톱: FlutterMap으로 이동');
        _mapController.move(
          latlong.LatLng(target.latitude, target.longitude),
          17.0,
        );
        debugPrint('✅ FlutterMap 이동 완료');
      } else if (_mapLibreController != null) {
        debugPrint('📱 모바일: MapLibre로 이동');
        _mapLibreController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(target.latitude, target.longitude),
            17.0,
          ),
          duration: const Duration(milliseconds: 1000),
        );
        debugPrint('✅ MapLibre 이동 애니메이션 시작');
      } else {
        debugPrint('⚠️ 지도 컨트롤러가 준비되지 않음');
      }
      
      debugPrint('🎧 ══════════════════════════════════════════════════');
      debugPrint('');
      
    } catch (e, stackTrace) {
      debugPrint('❌ _handleMapMoveRequest 에러: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('🎧 ══════════════════════════════════════════════════');
      debugPrint('');
    }
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

  // ✅ 통합 검색 패널 표시
  void _showUnifiedSearchPanel() async {
    // ✅ BuildContext 저장 (중요!)
    final scaffoldContext = context;
    
    final shopsProvider = context.read<ShopsMapProvider>();
    final locProvider = context.read<LocationsProvider>();
    
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) => UnifiedSearchPanel(
        allShops: shopsProvider.allShops,
        allFriends: locProvider.locations,
        
        // ✅ 위치 보기 - mounted 체크 강화
        onLocationSelected: (lat, lng, title) async {
          debugPrint('📍 주소 보기: $title');
          
          // 1. 모달 닫기 (modalContext 사용!)
          Navigator.pop(modalContext);
          
          // 2. 모달 완전히 닫힐 때까지 대기
          await Future.delayed(const Duration(milliseconds: 300));
          
          // 3. ✅ 저장한 scaffoldContext로 mounted 체크
          if (!scaffoldContext.mounted) {
            debugPrint('⚠️ Widget disposed after modal close');
            return;
          }
          
          // 4. setState 호출
          if (scaffoldContext.mounted) {
            _startPinAdjustMode(lat, lng, title);
          }
          
          debugPrint('📍 ════════════════════════════════════════════════');
        },
        
        // ✅ 주소 길찾기도 동일하게 수정
        onAddressNavigate: (lat, lng, title) async {
          debugPrint('🗺️ 주소 길찾기: $title');
          
          Navigator.pop(modalContext);
          await Future.delayed(const Duration(milliseconds: 300));
          
          if (!scaffoldContext.mounted) return;
          
          final provider = locProvider;
          final myLocation = provider.locations[widget.userId];
          
          if (myLocation == null) {
            if (scaffoldContext.mounted) {
              ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                const SnackBar(content: Text('현재 위치를 확인할 수 없습니다')),
              );
            }
            return;
          }
          
          try {
            final navigationService = NavigationService();
            final route = await navigationService.getRoute(
              start: latlong.LatLng(myLocation.lat, myLocation.lng),
              end: latlong.LatLng(lat, lng),
              mode: _selectedTransportMode,
            );
            
            if (!scaffoldContext.mounted) return;
            
            if (route == null) {
              if (scaffoldContext.mounted) {
                ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                  const SnackBar(content: Text('❌ 경로를 찾을 수 없습니다')),
                );
              }
              return;
            }
            
            if (scaffoldContext.mounted) {
              // ✅ 일반 setState 대신 _MapPageState의 메서드 호출
              _setStateWrapper(() {
                _currentRoute = route;
              });
            }
            
            if (_isDesktop) {
              _showRouteOnFlutterMap(route, null);
            } else {
              if (_addressPinMarker != null && _mapLibreController != null) {
                try {
                  await _mapLibreController!.removeSymbol(_addressPinMarker!);
                } catch (e) {
                  debugPrint('⚠️ 이전 핀 제거 실패: $e');
                }
              }
              
              await _showRouteOnMapLibre(route, null);
              
              if (scaffoldContext.mounted && _mapLibreController != null) {
                try {
                  _addressPinMarker = await _mapLibreController!.addSymbol(
                    SymbolOptions(
                      geometry: LatLng(lat, lng),
                      iconImage: 'circle_red',
                      iconSize: 1.5,
                      iconAnchor: 'center',
                    ),
                  );
                } catch (e) {
                  debugPrint('⚠️ 핀 추가 실패: $e');
                }
              }
            }
            
            if (scaffoldContext.mounted) {
              _showNavigationPanelForAddress(title, lat, lng, route);
            }
            
          } catch (e) {
            debugPrint('❌ 주소 길찾기 오류: $e');
            if (scaffoldContext.mounted) {
              ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                SnackBar(content: Text('경로 생성 실패: $e')),
              );
            }
          }
        },
        
        onShopSelected: (shop) {
          Navigator.pop(modalContext);
          if (scaffoldContext.mounted) {
            _showShopInfo(shop);
          }
        },
        
        onFriendSelected: (friend) {
          Navigator.pop(modalContext);
          if (scaffoldContext.mounted) {
            _showUserInfo(friend);
          }
        },
      ),
    );
  }

  // MapPage 클래스에 추가
  void _setStateWrapper(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    } else {
      debugPrint('⚠️ setState 스킵: Widget not mounted');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ✅ 10. 핀 조정 UI 오버레이
  // ═══════════════════════════════════════════════════════════
  Widget _buildPinAdjustOverlay() {
    //debugPrint('🎨 _buildPinAdjustOverlay 호출: _isPinAdjustMode = $_isPinAdjustMode');
    
    if (!_isPinAdjustMode) {
      //debugPrint('🎨 핀 조정 모드 아님 → SizedBox.shrink() 반환');
      return const SizedBox.shrink();
    }
    
    debugPrint('🎨 핀 조정 UI 렌더링 중...');
    
    return Stack(
      children: [
        // 중앙 고정 핀
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.place,
                color: Colors.red,
                size: 50,
                shadows: [
                  Shadow(
                    blurRadius: 10,
                    color: Colors.black45,
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Text(
                  '지도를 움직여 위치를 조정하세요',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // 상단 안내 배너
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.deepPurple,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Row(
              children: [
                Icon(Icons.info, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '📍 핀 위치 조정 중\n지도를 드래그하여 정확한 위치로 이동하세요',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // 하단 버튼
        Positioned(
          bottom: 80,
          left: 16,
          right: 16,
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isPinAdjustMode = false;
                      _adjustingPinLocation = null;
                      _adjustingAddress = null;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[600],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.close),
                  label: const Text('취소'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _confirmPinLocation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.check),
                  label: const Text(
                    '위치 확정',
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
      ],
    );
  }

  // ===================================
  // 6. 주소용 경로 재계산 헬퍼 (새로 추가)
  // ===================================
  // ✅ 주소 경로 재계산
  Future<void> _recalculateRouteForAddress(
    double destLat,
    double destLng,
    StateSetter setModalState,
  ) async {
    final navigationService = NavigationService();
    final locProvider = context.read<LocationsProvider>();
    final myLocation = locProvider.locations[widget.userId];
    
    if (myLocation == null) return;
    
    final newRoute = await navigationService.getRoute(
      start: latlong.LatLng(myLocation.lat, myLocation.lng),
      end: latlong.LatLng(destLat, destLng),
      mode: _selectedTransportMode,
    );
    
    if (newRoute != null) {
      setModalState(() => _currentRoute = newRoute);
      
      if (_isMobile) {
        await _showRouteOnMapLibre(newRoute, null); // ✅ nullable ShopModel
      } else {
        _showRouteOnFlutterMap(newRoute, null); // ✅ nullable ShopModel
      }
    }
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

  String _formatNavigationTime(double seconds, NavigationLanguage language) {
    if (seconds < 60) {
      // 1분 미만: 초 단위로 표시
      return language == NavigationLanguage.korean
          ? '${seconds.toInt()}초'
          : '${seconds.toInt()}s';
    } else if (seconds < 3600) {
      // 1시간 미만: 분 단위로 표시
      final minutes = (seconds / 60).round();
      return language == NavigationLanguage.korean
          ? '${minutes}분'
          : '${minutes} min';
    } else {
      // 1시간 이상: 시간과 분으로 표시
      final hours = (seconds / 3600).floor();
      final minutes = ((seconds % 3600) / 60).round();
      if (minutes == 0) {
        return language == NavigationLanguage.korean
            ? '${hours}시간'
            : '${hours}h';
      }
      return language == NavigationLanguage.korean
          ? '${hours}시간 ${minutes}분'
          : '${hours}h ${minutes}m';
    }
  }

  // ===================================
  // 5. 주소 네비게이션 패널 (새로 추가)
  // ===================================

  // ✅ 주소 길찾기 네비게이션 패널
  void _showNavigationPanelForAddress(
    String address,
    double lat,
    double lng,
    RouteResult route,
  ) {
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
                            address,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
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
                          
                          // 핀 제거
                          if (_addressPinMarker != null && _mapLibreController != null) {
                            try {
                              _mapLibreController!.removeSymbol(_addressPinMarker!);
                            } catch (e) {
                              debugPrint('⚠️ 핀 제거 실패: $e');
                            }
                            _addressPinMarker = null;
                          }
                        });
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
                              await _recalculateRouteForAddress(lat, lng, setModalState);
                            },
                          ),
                          _buildTransportModeButton(
                            icon: Icons.directions_walk,
                            label: '도보',
                            mode: TransportMode.walking,
                            onChanged: () async {
                              setModalState(() => _selectedTransportMode = TransportMode.walking);
                              await _recalculateRouteForAddress(lat, lng, setModalState);
                            },
                          ),
                          _buildTransportModeButton(
                            icon: Icons.directions_bike,
                            label: '자전거',
                            mode: TransportMode.cycling,
                            onChanged: () async {
                              setModalState(() => _selectedTransportMode = TransportMode.cycling);
                              await _recalculateRouteForAddress(lat, lng, setModalState);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // 현재 경로 정보
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
                      
                      // 길찾기 시작 버튼
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            debugPrint('🚀 주소 길찾기 시작: $address');
                            
                            setState(() {
                              _currentInstructions = _currentRoute!.instructions;
                              _selectedInstructionIndex = null;
                            });
                            
                            Navigator.pop(context);
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '🚀 $address로 가는 길입니다!\n'
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
      ),
    );
  }


  // ✅ 7. 유저 프로필 가져오기
  Future<Map<String, dynamic>?> _fetchUserProfile(String userId) async {
    try {
      // ignore: deprecated_member_use
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
    // ✅ 사용자 이름 가져오기 (locations에는 name이 없음)
    final locProvider = context.read<LocationsProvider>();
    final userName = user.userId; // 기본값은 userId
    
    // ✅ users 컬렉션에서 이름 조회 (선택사항)
    // 만약 이름이 필요하다면 별도 조회 필요
    
    _showNavigationBottomSheet(
      entityId: user.userId,
      entityName: userName,
      subtitle: '사용자',
      lat: user.lat,
      lng: user.lng,
      headerColor: Colors.lightBlue,
      icon: Icons.person,
      additionalInfo: [
        _buildInfoRow(
          Icons.access_time,
          '위치 업데이트',
          _formatTimestamp(user.timestamp), // ✅ timestamp
        ),
        const SizedBox(height: 8),
        _buildInfoRow(
          Icons.timer,
          '체류 시간',
          _formatDuration(user.userId, locProvider),
        ),
      ],
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
                                // ignore: use_build_context_synchronously
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
                              // ignore: use_build_context_synchronously
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
                                // ignore: use_build_context_synchronously
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
                                // ignore: use_build_context_synchronously
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
      // ignore: deprecated_member_use
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
      // ignore: deprecated_member_use
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
      // ignore: deprecated_member_use
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

      // ignore: deprecated_member_use
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
      // ignore: deprecated_member_use
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
      // ignore: deprecated_member_use
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


  // ============================================
  // ✅ 경로를 따라 화살표 마커 생성
  // ============================================
  List<latlong.Marker> _buildArrowMarkers(List<latlong.LatLng> coordinates) {
    final arrows = <latlong.Marker>[];
    
    if (coordinates.length < 2) return arrows;
    
    // 100m마다 화살표 추가
    const double intervalMeters = 100.0;
    double accumulatedDistance = 0.0;
    
    for (int i = 0; i < coordinates.length - 1; i++) {
      final p1 = coordinates[i];
      final p2 = coordinates[i + 1];
      
      final distance = _distance.distance(p1, p2);
      accumulatedDistance += distance;
      
      if (accumulatedDistance >= intervalMeters) {
        accumulatedDistance = 0.0;
        
        // 진행 방향 계산
        final bearing = _calculateBearing(p1, p2);
        
        arrows.add(
          latlong.Marker(
            key: ValueKey('arrow_$i'),
            point: p1,
            width: 32,
            height: 32,
            child: Transform.rotate(
              angle: bearing * pi / 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 배경 원
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  // 화살표 아이콘
                  Icon(
                    Icons.navigation,
                    color: Colors.blue[700],
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    
    return arrows;
  }
  
  double _calculateBearing(latlong.LatLng from, latlong.LatLng to) {
    final lat1 = from.latitude * pi / 180;
    final lat2 = to.latitude * pi / 180;
    final dLon = (to.longitude - from.longitude) * pi / 180;
    
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    
    return (atan2(y, x) * 180 / pi + 360) % 360;
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
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          // ✅✅✅ 그룹 채팅 버튼 (새로 추가!)
          Consumer<TempGroupMessagesProvider>(
            builder: (context, msgProvider, _) {
              final totalUnread = msgProvider.totalUnreadCount;
              
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline),
                    onPressed: () => _showGroupChatList(context),
                    tooltip: '그룹 채팅',
                  ),
                  if (totalUnread > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          totalUnread > 99 ? '99+' : '$totalUnread',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          // ✅✅✅ 시간 제한 그룹 메뉴 (새로 추가)
          Consumer<TempGroupsProvider>(
            builder: (context, groupProvider, _) {
              final activeCount = groupProvider.activeGroups.length;
              final hasActiveGroups = groupProvider.myGroups.isNotEmpty;
              
              return PopupMenuButton<String>(
                icon: Stack(
                  children: [
                    const Icon(Icons.group),
                      if (hasActiveGroups)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          width: 8,   // ✅ 작은 점으로 변경
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            '$activeCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                tooltip: '그룹',
                onSelected: _handleGroupAction,
                itemBuilder: (context) => [
                  // 내 그룹 목록
                  const PopupMenuItem(
                    value: 'list',
                    child: Row(
                      children: [
                        Icon(Icons.list, size: 20),
                        SizedBox(width: 12),
                        Text('내 그룹'),
                      ],
                    ),
                  ),
                  
                  // 새 그룹 만들기
                  const PopupMenuItem(
                    value: 'create',
                    child: Row(
                      children: [
                        Icon(Icons.add_circle, size: 20, color: Colors.green),
                        SizedBox(width: 12),
                        Text('새 그룹 만들기'),
                      ],
                    ),
                  ),

                  // ✅✅✅ 초대 코드로 참여 (새로 추가됨)
                  const PopupMenuItem(
                    value: 'join',
                    child: Row(
                      children: [
                        Icon(Icons.vpn_key, size: 20, color: Colors.orange),
                        SizedBox(width: 12),
                        Text('초대 코드로 참여'),
                      ],
                    ),
                  ),

                  const PopupMenuDivider(),
                  
                  // 활성 그룹 수 표시
                  PopupMenuItem(
                    value: 'active',
                    enabled: activeCount > 0,
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 20,
                          color: activeCount > 0 ? Colors.blue : Colors.grey,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '활성 그룹 ($activeCount개)',
                          style: TextStyle(
                            color: activeCount > 0 ? Colors.black : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          // ✅ 유저 모드일 때 홍보 리스트 버튼
          if (_currentRole == UserRole.user)
            Tooltip(
              message: '홍보 메시지',
              child: IconButton(
                icon: const Icon(Icons.mail),
                onPressed: () async {
                  debugPrint('📧 홍보 페이지 열기');
                  
                  // ✅ MapPage의 BuildContext 저장
                  final mapPageContext = context;
                  
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserPromotionsPage(
                        userId: widget.userId,
                        onNavigateToShop: (shop, message) async {
                          debugPrint('');
                          debugPrint('🔙 ════════════════════ 길찾기 요청 ════════════════════');
                          
                          // ✅ MapPage context를 사용해서 BottomSheet 표시
                          // 홍보 페이지는 닫지 않음!
                          if (mapPageContext.mounted && mounted) {
                            debugPrint('✅ Context mounted 확인');
                            
                            // ✅ 약간의 딜레이
                            await Future.delayed(const Duration(milliseconds: 100));
                            
                            if (mapPageContext.mounted && mounted) {
                              _showNavigationBottomSheet(
                                entityId: shop.shopId,
                                entityName: shop.shopName,
                                subtitle: shop.category,
                                lat: shop.lat,
                                lng: shop.lng,
                                headerColor: Colors.deepPurple,
                                icon: Icons.store,
                                additionalInfo: [
                                  _buildInfoRow(Icons.location_on, '주소', shop.address),
                                  const SizedBox(height: 8),
                                  _buildInfoRow(Icons.phone, '전화', shop.phone),
                                  if (shop.description.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _buildInfoRow(Icons.description, '설명', shop.description),
                                  ],
                                  // ✅ 홍보 메시지
                                  if (message != null) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.amber[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.amber[200]!, width: 2),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.campaign, color: Colors.orange, size: 22),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  '홍보 메시지',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.orange,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  message.message,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              );
                              
                              debugPrint('✅ BottomSheet 표시 완료');
                            }
                          }
                          
                          debugPrint('🔙 ════════════════════ 완료 ════════════════════');
                          debugPrint('');
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          // ✅ 샵 필터 버튼 추가
          if (_isDesktop)
            Tooltip(
              message: '통합 검색 (샵/친구/주소)',
              child: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _showUnifiedSearchPanel,
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
                    
                    // ✅ 개인 장소도 그룹 필터 적용
                    try {
                      context.read<PersonalPlacesProvider>().setGroupFilter(_selectedGroupName!);
                    } catch (e) {
                      debugPrint('⚠️ PersonalPlacesProvider 필터링 실패: $e');
                    }
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
                // ✅ 핀 조정 오버레이 추가
                _buildPinAdjustOverlay(),
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
              key: ValueKey('map_${_tileSource}_$_is3DMode'),
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

                // ✅ 추가: 카메라 중심 항상 추적
                _currentCameraCenter = position.target;
                
                // ✅ 추가: 핀 조정 모드일 때 실시간 업데이트
                if (_isPinAdjustMode) {
                  setState(() {
                    _adjustingPinLocation = position.target;
                  });
                }

                if ((oldZoom - _currentZoom).abs() > 0.01) {
                  debugPrint('📷 줌: ${oldZoom.toStringAsFixed(2)} → ${_currentZoom.toStringAsFixed(2)}');
                }
              },
              // ✅ 핵심 수정: 더 민감한 클러스터 재계산
              onCameraIdle: () async {
                final zoomDiff = (_currentZoom - _lastClusterZoom).abs();
                
                debugPrint('📷 onCameraIdle: 줌 차이 = ${zoomDiff.toStringAsFixed(2)}');
                
                // ✅ 0.3 이상 차이나면 재클러스터링 (기존 0.5에서 완화)
                if (zoomDiff > 0.3) {
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
                      // ignore: deprecated_member_use
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
  // ✅ 줌 인/아웃 버튼 - 강제 재클러스터링
  // ============================================
  Widget _buildFloatingButtons(LocationsProvider provider, {required bool isDesktop}) {
    return Positioned(
      bottom: 18,
      right: 18,
      child: Column(
        children: [
          // ✅ 줌 인 버튼
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
                
                final oldZoom = _currentZoom;
                debugPrint('   현재 줌: ${oldZoom.toStringAsFixed(2)}');
                
                await _mapLibreController!.animateCamera(
                  CameraUpdate.zoomIn(),
                  duration: const Duration(milliseconds: 300),
                );
                
                await Future.delayed(const Duration(milliseconds: 500));
                
                _currentZoom = oldZoom + 1.0;
                debugPrint('   새 줌: ${_currentZoom.toStringAsFixed(2)}');
                
                // ✅ 강제 재클러스터링
                _lastClusterZoom = oldZoom;
                
                if (mounted) {
                  await _updateMapLibreMarkers(provider);
                }
                
                debugPrint('➕ [줌 인 완료]');
                debugPrint('');
              },
              child: const Icon(Icons.add, size: 24),
            ),
          if (!isDesktop) const SizedBox(height: 8),

          // ✅ 줌 아웃 버튼
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
                
                await _mapLibreController!.animateCamera(
                  CameraUpdate.zoomOut(),
                  duration: const Duration(milliseconds: 300),
                );
                
                await Future.delayed(const Duration(milliseconds: 500));
                
                _currentZoom = oldZoom - 1.0;
                debugPrint('   새 줌: ${_currentZoom.toStringAsFixed(2)}');
                
                // ✅ 강제 재클러스터링
                _lastClusterZoom = oldZoom;
                
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
      // ignore: deprecated_member_use
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
          // ignore: deprecated_member_use
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

// ✅ 통합 길찾기 BottomSheet (UI 크기 고정 버전)
  void _showNavigationBottomSheet({
    required String entityId,
    required String entityName,
    required String subtitle,
    required double lat,
    required double lng,
    required Color headerColor,
    required IconData icon,
    List<Widget>? additionalInfo,
    VoidCallback? onDelete,
  }) {
    debugPrint('');
    debugPrint('📍 ════════════════════ 길찾기 BottomSheet 열기 ════════════════════');
    debugPrint('📦 이름: $entityName');
    debugPrint('📍 위치: ($lat, $lng)');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          // ✅ 현재 선택된 이동수단 및 고속도로 옵션
          final currentMode = _shopTransportModeMap[entityId] ?? TransportMode.driving;
          final currentHighway = _useHighwaysMap[entityId] ?? false;
          
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ✅ 헤더
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: headerColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(icon, color: Colors.white, size: 28),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entityName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
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
                
                // ✅ 내용
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ✅ 추가 정보 (선택사항)
                        if (additionalInfo != null) ...additionalInfo,
                        
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 16),
                        
                        // ✅ 이동 수단 선택
                        const Text(
                          '이동 수단',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTransportButton(
                                icon: Icons.directions_car,
                                label: '자동차',
                                isSelected: currentMode == TransportMode.driving,
                                onTap: () {
                                  setModalState(() {
                                    _shopTransportModeMap[entityId] = TransportMode.driving;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildTransportButton(
                                icon: Icons.directions_walk,
                                label: '도보',
                                isSelected: currentMode == TransportMode.walking,
                                onTap: () {
                                  setModalState(() {
                                    _shopTransportModeMap[entityId] = TransportMode.walking;
                                    _useHighwaysMap[entityId] = false;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildTransportButton(
                                icon: Icons.directions_bike,
                                label: '자전거',
                                isSelected: currentMode == TransportMode.cycling,
                                onTap: () {
                                  setModalState(() {
                                    _shopTransportModeMap[entityId] = TransportMode.cycling;
                                    _useHighwaysMap[entityId] = false;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        
                        // ✅✅✅ 고속도로 옵션 (UI 크기 고정!)
                        const SizedBox(height: 16),
                        Visibility(
                          visible: currentMode == TransportMode.driving,
                          maintainSize: true,        // ✅ 핵심! 크기 유지
                          maintainAnimation: true,
                          maintainState: true,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.settings, size: 20, color: Colors.blue[700]),
                                        const SizedBox(width: 8),
                                        Text(
                                          currentHighway ? '고속도로 우선' : '최단 경로',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue[900],
                                          ),
                                        ),
                                      ],
                                    ),
                                    Switch(
                                      value: currentHighway,
                                      onChanged: (value) {
                                        setModalState(() {
                                          _useHighwaysMap[entityId] = value;
                                        });
                                      },
                                      activeColor: Colors.blue,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      currentHighway ? Icons.info_outline : Icons.location_on,
                                      size: 14,
                                      color: Colors.grey[600],
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        currentHighway
                                            ? '고속도로를 이용한 빠른 경로로 안내합니다'
                                            : '일반 도로로 최단 거리 안내합니다',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // ✅ 길찾기 버튼
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              debugPrint('🧭 길찾기 시작: $entityName');
                              
                              // ✅ 1. Provider 미리 가져오기
                              final provider = context.read<LocationsProvider>();
                              
                              // ✅ 2. BottomSheet 닫기
                              Navigator.pop(context);
                              
                              // ✅ 3. 안정화 대기
                              await Future.delayed(const Duration(milliseconds: 100));
                              
                              // ✅ 4. mounted 체크
                              if (!mounted) return;
                              
                              // ✅ 5. 길찾기 실행
                              final myLocation = provider.locations[widget.userId];
                              if (myLocation == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('현재 위치를 확인할 수 없습니다')),
                                );
                                return;
                              }

                              try {
                                final transportMode = _shopTransportModeMap[entityId] ?? TransportMode.driving;
                                final useHighways = _useHighwaysMap[entityId] ?? false;
                                
                                debugPrint('🚗 이동수단: $transportMode');
                                debugPrint('🛣️ 고속도로: $useHighways');
                                
                                final navigationService = NavigationService();
                                final route = await navigationService.getRoute(
                                  start: latlong.LatLng(myLocation.lat, myLocation.lng),
                                  end: latlong.LatLng(lat, lng),
                                  mode: transportMode,
                                  useHighways: useHighways,
                                );

                                if (route == null) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('❌ 경로를 찾을 수 없습니다')),
                                    );
                                  }
                                  return;
                                }

                                debugPrint('✅ 경로 생성 성공: ${route.formattedDistance}');

                                if (mounted) {
                                  setState(() {
                                    _currentRoute = route;
                                    _selectedTransportMode = transportMode;
                                    _currentInstructions = route.instructions;
                                  });

                                  debugPrint('   거리: ${route.formattedDistance}');
                                  debugPrint('   시간: ${route.formattedDuration}');
                                  debugPrint('   스텝: ${route.instructions.length}개');
  
                                  // 지도에 경로 표시
                                  if (_isDesktop) {
                                    _showRouteOnFlutterMap(route, null);
                                  } else {
                                    await _showRouteOnMapLibre(route, null);
                                  }

                                  // ✅ 안내 시작 UI는 _currentInstructions 설정으로 자동 표시됨
                                  // _buildRouteInstructionPanel()이 자동으로 감지
                                }
                              } catch (e) {
                                debugPrint('❌ 길찾기 오류: $e');
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('길찾기 오류: $e')),
                                  );
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: headerColor,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            icon: const Icon(Icons.navigation, size: 20),
                            label: const Text(
                              '길찾기',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        
                        // ✅ 삭제 버튼 (선택사항)
                        if (onDelete != null) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: onDelete,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              icon: const Icon(Icons.delete, size: 20),
                              label: const Text('삭제', style: TextStyle(fontSize: 16)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ✅ 이동수단 버튼 (간단한 버전)
  Widget _buildTransportButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[50] : Colors.grey[100],
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.blue : Colors.grey[600],
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.blue : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ 정보 행 표시
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
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

  // ✅ 날짜/시간 포맷
  String _formatTimestamp(DateTime timestamp) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);
  }

  Future<void> _ensureDefaultGroup() async {
    try {
      final dbId = AppwriteConstants.databaseId;
      final groupsCollectionId = AppwriteConstants.groupsCollectionId;

      // ignore: deprecated_member_use
      final existing = await _db.listDocuments(
        databaseId: dbId,
        collectionId: groupsCollectionId,
        queries: [
          Query.equal('userId', widget.userId),
          Query.equal('groupName', '전체'),
        ],
      );

      if (existing.total == 0) {
        // ignore: deprecated_member_use
        await _db.createDocument(
          databaseId: dbId,
          collectionId: groupsCollectionId,
          documentId: ID.unique(),
          data: {
            'userId': widget.userId,
            'groupName': '전체',
          },
          permissions: [
            Permission.read(Role.user(widget.userId)),
            Permission.write(Role.user(widget.userId)),
          ],
        );
        debugPrint('✅ groups 컬렉션에 기본 그룹 "전체" 생성 완료');
      } else {
        debugPrint('ℹ️ groups 컬렉션에 이미 기본 그룹 존재');
      }
    } catch (e) {
      debugPrint('❌ 기본 그룹 생성 실패: $e');
    }
  }

  // ✅✅✅ 그룹 채팅 리스트 모달
  void _showGroupChatList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Consumer2<TempGroupsProvider, TempGroupMessagesProvider>(
            builder: (context, groupsProvider, msgProvider, _) {
            // ✅ 삭제되지 않은 활성 그룹만 필터링
            //final groups = groupsProvider.myGroups;
            final groups = groupsProvider.myGroups
                .where((g) => g.status != TempGroupStatus.deleted)
                .toList();
              
              return Column(
                children: [
                  // 헤더
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '그룹 채팅',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.pushNamed(context, '/temp_groups');
                          },
                          child: const Text('전체 보기'),
                        ),
                      ],
                    ),
                  ),
                  
                  // 채팅 리스트
                  Expanded(
                    child: groups.isEmpty
                        ? const Center(
                            child: Text('참여 중인 그룹이 없습니다'),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: groups.length,
                            itemBuilder: (context, index) {
                              final group = groups[index];
                              final unreadCount = msgProvider.getUnreadCount(group.id);
                              
                              return ListTile(
                                leading: CircleAvatar(
                                  child: Text(group.groupName[0]),
                                ),
                                title: Text(
                                  group.groupName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '${group.memberCount}명 · ${group.formattedRemainingTime}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                trailing: unreadCount > 0
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          unreadCount > 99 ? '99+' : '$unreadCount',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                    : null,
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => TempGroupChatScreen(
                                        groupId: group.id,
                                        userId: widget.userId,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _loadGroupsFromDB() async {
    try {
      // ignore: deprecated_member_use
      final res = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.groupsCollectionId,
        queries: [Query.equal('userId', widget.userId)],
      );

      final fetched = <Map<String, String>>[];

      for (final doc in res.documents) {
        try {
          final data = (doc as dynamic).data;
          final id = doc.$id;
          final name = data['groupName']?.toString() ?? '';
          if (name.isNotEmpty) {
            fetched.add({'id': id, 'name': name});
          }
        } catch (_) {}
      }

      final uniqueByName = <String, Map<String, String>>{};
      for (final g in fetched) {
        uniqueByName[g['name']!] = g;
      }

      setState(() {
        _groups = [
          {'id': 'all', 'name': '전체'},
          ...uniqueByName.values,
        ];

        final validIds = _groups.map((e) => e['id']).toSet();
        if (!validIds.contains(_selectedGroupId)) {
          _selectedGroupId = 'all';
          _selectedGroupName = '전체';
        }

        _dropdownKey++;
      });

      debugPrint('✅ 그룹 불러오기 성공: ${_groups.length}개');
    } catch (e) {
      debugPrint('❌ 그룹 불러오기 실패: $e');
    }
  }
}