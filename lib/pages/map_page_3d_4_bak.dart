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
  final Map<String, Circle> _circles = {};
  final Map<String, Symbol> _symbols = {};
  final Map<String, Circle> _clusterCircles = {}; // 클러스터용

  double _currentZoom = 15.0; // 현재 줌 레벨 추적
  double _lastClusterZoom = 15.0; // 마지막으로 클러스터링한 줌 레벨
  final Map<String, LocationModel> _userMarkers = {}; // userId -> LocationModel
  final Map<String, List<LocationModel>> _clusterMarkers = {}; // cluster_id -> List<LocationModel>


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
      debugPrint('🌐 Web 환경 → FlutterMap(데스크탑 모드) 사용');
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
    final provider = context.read<LocationsProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureDefaultGroup();
      _loadGroupsFromDB();
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

    // ✅ 모바일에서 마커 업데이트 타이머 복원 (실시간 위치 업데이트용)
    if (_isMobile) {
      _startMarkerUpdateTimer(provider);
    }
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
  // 수정 4: _updateMapLibreMarkers - 마커 정보 저장
  // ============================================
  Future<void> _updateMapLibreMarkers(
    LocationsProvider provider, {
    bool isAutoUpdate = false,
  }) async {
    if (_mapLibreController == null || !_isMobile) {
      debugPrint('❌ MapLibre controller 없음 또는 데스크탑 환경');
      return;
    }

    if (_isUpdatingMarkers) {
      debugPrint('⏭️  이미 업데이트 중... 중복 호출 방지');
      return;
    }

    _isUpdatingMarkers = true;
    if (!isAutoUpdate) {
      _lastManualUpdate = DateTime.now();
    }

    try {
      debugPrint('');
      debugPrint('🔄 ========================================');
      debugPrint('🔄 [마커 업데이트 시작] ${isAutoUpdate ? "(자동)" : "(수동)"}');
      debugPrint('🔄 줌: ${_currentZoom.toStringAsFixed(2)}');
      debugPrint('🔄 ========================================');
      
      final allLocs = provider.getDisplayLocations();
      debugPrint('📍 [위치 정보] 전체: ${allLocs.length}개');
      
      if (allLocs.isEmpty) {
        debugPrint('⚠️  위치 정보가 없습니다!');
        _isUpdatingMarkers = false;
        return;
      }

      final locs = await _filterLocationsByGroup(allLocs);
      debugPrint('📍 [필터링 후] ${locs.length}개');
      
      if (locs.isEmpty) {
        debugPrint('⚠️  필터링 후 위치 정보가 없습니다!');
        _isUpdatingMarkers = false;
        return;
      }

      // ✅ 기존 마커 정보 초기화
      _userMarkers.clear();
      _clusterMarkers.clear();

      // 기존 심볼 제거
      debugPrint('🗑️  [1단계] 기존 심볼 제거 중... (${_symbols.length}개)');
      final symbolsList = _symbols.values.toList();
      _symbols.clear();
      for (int i = 0; i < symbolsList.length; i++) {
        try {
          await _mapLibreController!.removeSymbol(symbolsList[i]);
        } catch (e) {
          debugPrint('   ⚠️  심볼 제거 실패 [$i]: $e');
        }
      }

      // 기존 원 제거
      debugPrint('🗑️  [2단계] 기존 원 제거 중... (${_circles.length}개)');
      final circlesList = _circles.values.toList();
      _circles.clear();
      for (int i = 0; i < circlesList.length; i++) {
        try {
          await _mapLibreController!.removeCircle(circlesList[i]);
        } catch (e) {
          debugPrint('   ⚠️  원 제거 실패 [$i]: $e');
        }
      }

      // 기존 클러스터 제거
      debugPrint('🗑️  [3단계] 기존 클러스터 제거 중... (${_clusterCircles.length}개)');
      final clustersList = _clusterCircles.values.toList();
      _clusterCircles.clear();
      for (int i = 0; i < clustersList.length; i++) {
        try {
          await _mapLibreController!.removeCircle(clustersList[i]);
        } catch (e) {
          debugPrint('   ⚠️  클러스터 제거 실패 [$i]: $e');
        }
      }

      // 클러스터 생성
      debugPrint('📦 [4단계] 클러스터 생성 중...');
      final clusters = _clusterLocations(locs);

      if (clusters.isEmpty) {
        debugPrint('⚠️  클러스터가 생성되지 않았습니다!');
        _isUpdatingMarkers = false;
        return;
      }

      // 새 마커 추가
      debugPrint('➕ [5단계] 마커 추가 중... (${clusters.length}개 클러스터)');
      for (int i = 0; i < clusters.length; i++) {
        final cluster = clusters[i];
        
        if (cluster.length == 1) {
          debugPrint('   - 단일 마커 추가: ${cluster[0].userId}');
          // ✅ 마커 정보 저장
          _userMarkers[cluster[0].userId] = cluster[0];
          await _addLargeSingleMarker(cluster[0], provider);
        } else {
          debugPrint('   - 클러스터 마커 추가: ${cluster.length}명');
          // ✅ 클러스터 정보 저장
          _clusterMarkers['cluster_$i'] = cluster;
          await _addLargeClusterMarker(cluster, i, provider);
        }
      }

      debugPrint('✅ [마커 업데이트 완료]');
      debugPrint('   - 심볼: ${_symbols.length}개');
      debugPrint('   - 원: ${_circles.length}개');
      debugPrint('   - 클러스터: ${_clusterCircles.length}개');
      debugPrint('   - 저장된 유저 마커: ${_userMarkers.length}개');
      debugPrint('   - 저장된 클러스터: ${_clusterMarkers.length}개');
      debugPrint('');
    } catch (e, stackTrace) {
      debugPrint('❌ [마커 업데이트 실패]: $e');
      debugPrint('스택 트레이스: $stackTrace');
      debugPrint('');
    } finally {
      _isUpdatingMarkers = false;
    }
  }

  Future<void> _addLargeClusterMarker(
    List<LocationModel> cluster,
    int index,
    LocationsProvider provider,
  ) async {
    if (_mapLibreController == null || cluster.isEmpty) return;

    try {
      double sumLat = 0, sumLng = 0;
      for (final loc in cluster) {
        sumLat += loc.lat;
        sumLng += loc.lng;
      }
      final centerLat = sumLat / cluster.length;
      final centerLng = sumLng / cluster.length;

      final initials = <String>[];
      for (int i = 0; i < cluster.length && i < 3; i++) {
        final profile = await _fetchUserProfile(cluster[i].userId);
        final nickname = profile?['nickname'] ?? profile?['name'] ?? cluster[i].userId;
        initials.add(_getInitial(nickname));
      }

      // ✅ 클러스터 원 (클릭 가능)
      final clusterCircle = await _mapLibreController!.addCircle(
        CircleOptions(
          geometry: LatLng(centerLat, centerLng),
          circleRadius: 30.0,
          circleColor: '#FF9800',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3.5,
          circleOpacity: 1.0,
          draggable: false,
        ),
      );
      _clusterCircles['cluster_$index'] = clusterCircle;

      String displayText;
      if (cluster.length <= 3) {
        displayText = initials.join(' ');
      } else {
        displayText = '${initials[0]} ${initials[1]}\n${initials[2]} ...';
      }

      // 이니셜 심볼
      await _mapLibreController!.addSymbol(
        SymbolOptions(
          geometry: LatLng(centerLat, centerLng),
          textField: displayText,
          textSize: cluster.length <= 3 ? 14.0 : 11.0,
          textColor: '#FFFFFF',
          textHaloColor: '#FF9800',
          textHaloWidth: 1.0,
          draggable: false,
        ),
      );

      // 인원수 라벨
      final symbol = await _mapLibreController!.addSymbol(
        SymbolOptions(
          geometry: LatLng(centerLat, centerLng),
          textField: '${cluster.length}명',
          textSize: 12.0,
          textColor: '#000000',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 2.0,
          textOffset: const Offset(0, 3.2),
          draggable: false,
        ),
      );
      _symbols['cluster_$index'] = symbol;
    } catch (e) {
      debugPrint('❌ 클러스터 추가 실패: $e');
    }
  }

  // ============================================
  // 수정 3: 마커 추가 시 클릭 가능하도록 설정
  // ============================================
  Future<void> _addLargeSingleMarker(LocationModel loc, LocationsProvider provider) async {
    if (_mapLibreController == null) return;

    try {
      final profile = await _fetchUserProfile(loc.userId);
      final nickname = profile?['nickname'] ?? profile?['name'] ?? loc.userId;
      final initial = _getInitial(nickname);
      
      final stay = _formatDuration(loc.userId, provider);
      final isMe = loc.userId == widget.userId;
      final color = isMe ? '#2196F3' : '#F44336';

      // ✅ 원형 마커 (클릭 가능하도록 draggable: false 설정)
      final circle = await _mapLibreController!.addCircle(
        CircleOptions(
          geometry: LatLng(loc.lat, loc.lng),
          circleRadius: 22.0,
          circleColor: color,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3.5,
          circleOpacity: 1.0,
          draggable: false, // 클릭 가능하도록 설정
        ),
      );
      _circles[loc.userId] = circle;

      // 이니셜 심볼
      await _mapLibreController!.addSymbol(
        SymbolOptions(
          geometry: LatLng(loc.lat, loc.lng),
          textField: initial,
          textSize: 16.0,
          textColor: '#FFFFFF',
          textHaloColor: color,
          textHaloWidth: 1.0,
          draggable: false,
        ),
      );

      // 라벨 심볼
      if (stay.isNotEmpty || !isMe) {
        final label = stay.isNotEmpty ? stay : _short(nickname, 6);
        final symbol = await _mapLibreController!.addSymbol(
          SymbolOptions(
            geometry: LatLng(loc.lat, loc.lng),
            textField: label,
            textSize: 12.0,
            textColor: '#000000',
            textHaloColor: '#FFFFFF',
            textHaloWidth: 2.0,
            textOffset: const Offset(0, 2.5),
            draggable: false,
          ),
        );
        _symbols[loc.userId] = symbol;
      }
    } catch (e) {
      debugPrint('❌ 마커 추가 실패: $e');
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

  // // ✅ 4. 단일 마커 추가 (클릭 포인트 개선 - 중심에 배치)
  // Future<void> _addSingleMarker(LocationModel loc, LocationsProvider provider) async {
  //   if (_mapLibreController == null) return;

  //   final stay = _formatDuration(loc.userId, provider);
  //   final isMe = loc.userId == widget.userId;
  //   final color = isMe ? '#2196F3' : '#F44336';

  //   try {
  //     // ✅ 아주 큰 투명 원 (클릭 영역 확대용)
  //     await _mapLibreController!.addCircle(
  //       CircleOptions(
  //         geometry: LatLng(loc.lat, loc.lng),
  //         circleRadius: 25.0, // 큰 투명 영역
  //         circleColor: color,
  //         circleOpacity: 0.0, // 완전 투명
  //       ),
  //     );

  //     // ✅ 실제 보이는 마커 (중간 크기)
  //     final circle = await _mapLibreController!.addCircle(
  //       CircleOptions(
  //         geometry: LatLng(loc.lat, loc.lng),
  //         circleRadius: 12.0, // 적당한 크기
  //         circleColor: color,
  //         circleStrokeColor: '#FFFFFF',
  //         circleStrokeWidth: 3.0,
  //         circleOpacity: 0.9,
  //       ),
  //     );
  //     _circles[loc.userId] = circle;

  //     // 텍스트 라벨 (마커 아래쪽에 배치)
  //     final label = stay.isNotEmpty ? stay : _short(loc.userId);
  //     final symbol = await _mapLibreController!.addSymbol(
  //       SymbolOptions(
  //         geometry: LatLng(loc.lat, loc.lng),
  //         textField: label,
  //         textSize: 13.0,
  //         textColor: '#000000',
  //         textHaloColor: '#FFFFFF',
  //         textHaloWidth: 2.5,
  //         textOffset: const Offset(0, 1.8), // 마커 아래로 이동
  //       ),
  //     );
  //     _symbols[loc.userId] = symbol;

  //     debugPrint('✅ 마커 추가: ${loc.userId} at (${loc.lat}, ${loc.lng})');

  //   } catch (e) {
  //     debugPrint('❌ 마커 추가 실패 (${loc.userId}): $e');
  //   }
  // }

  // // ✅ 5. 클러스터 마커 추가 (개선된 버전)
  // Future<void> _addClusterMarker(List<LocationModel> cluster, int index) async {
  //   if (_mapLibreController == null || cluster.isEmpty) return;

  //   // 클러스터 중심 계산
  //   double sumLat = 0, sumLng = 0;
  //   for (final loc in cluster) {
  //     sumLat += loc.lat;
  //     sumLng += loc.lng;
  //   }
  //   final centerLat = sumLat / cluster.length;
  //   final centerLng = sumLng / cluster.length;

  //   try {
  //     // ✅ 투명한 큰 클릭 영역
  //     await _mapLibreController!.addCircle(
  //       CircleOptions(
  //         geometry: LatLng(centerLat, centerLng),
  //         circleRadius: 35.0,
  //         circleColor: '#FF9800',
  //         circleOpacity: 0.0, // 투명
  //       ),
  //     );

  //     // 주황색 클러스터 원
  //     final clusterCircle = await _mapLibreController!.addCircle(
  //       CircleOptions(
  //         geometry: LatLng(centerLat, centerLng),
  //         circleRadius: 18.0,
  //         circleColor: '#FF9800', // 주황색
  //         circleStrokeColor: '#FFFFFF',
  //         circleStrokeWidth: 3.0,
  //         circleOpacity: 0.9,
  //       ),
  //     );
  //     _clusterCircles['cluster_$index'] = clusterCircle;

  //     // 클러스터 개수 표시
  //     final symbol = await _mapLibreController!.addSymbol(
  //       SymbolOptions(
  //         geometry: LatLng(centerLat, centerLng),
  //         textField: '${cluster.length}',
  //         textSize: 16.0,
  //         textColor: '#FFFFFF',
  //         textHaloColor: '#FF9800',
  //         textHaloWidth: 1.5,
  //       ),
  //     );
  //     _symbols['cluster_$index'] = symbol;

  //     debugPrint('✅ 클러스터 마커 추가: ${cluster.length}명 at ($centerLat, $centerLng)');

  //   } catch (e) {
  //     debugPrint('❌ 클러스터 마커 추가 실패: $e');
  //   }
  // }

  Future<void> _loadGroupsFromDB() async {
    try {
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

  void _startStopTracking(LocationsProvider provider) {
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      final locs = provider.getDisplayLocations();

      for (final entry in locs.entries) {
        final userId = entry.key;
        final loc = entry.value;
        final currentPos = latlong.LatLng(loc.lat, loc.lng);

        final lastPos = _lastPositions[userId];
        if (lastPos == null) {
          _lastPositions[userId] = currentPos;
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
          if (mounted) setState(() {});
        }
      }

      if (mounted && timer.tick % 6 == 0) setState(() {});
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
    _updateTimer?.cancel();
    _autoMoveTimer?.cancel();
    _durationTimer?.cancel();
    _markerUpdateTimer?.cancel();

    final provider = context.read<LocationsProvider>();
    provider.saveAllStayDurations();

    super.dispose();
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

  // // ✅ 3. 픽셀을 위도/경도로 변환하는 함수
  // double _pixelsToDegreesAtZoom(double pixels, double zoom, double latitude) {
  //   // 줌 레벨에서 1픽셀이 몇 도인지 계산
  //   // 적도 기준: 156543.03392 * cos(latitude) / (2^zoom)
  //   const earthCircumference = 40075017.0; // 미터
  //   final metersPerPixel = earthCircumference * cos(latitude * pi / 180) / pow(2, zoom + 8);
  //   final metersRadius = pixels * metersPerPixel;
    
  //   // 위도 1도 = 약 111,320m
  //   return metersRadius / 111320.0;
  // }

  void _showUserInfo(LocationModel user) async {
    final profile = await _fetchUserProfile(user.userId);
    final provider = context.read<LocationsProvider>();
    
    final nickname = profile?['nickname'] ?? profile?['name'] ?? user.userId;
    final profileImage = profile?['profileImage'];
    final stayInfo = _formatDuration(user.userId, provider);

    // ignore: use_build_context_synchronously
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return Container(
          padding: const EdgeInsets.all(16),
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
            ],
          ),
        );
      },
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

  Future<void> _ensureDefaultGroup() async {
    try {
      final dbId = AppwriteConstants.databaseId;
      final groupsCollectionId = AppwriteConstants.groupsCollectionId;

      final existing = await _db.listDocuments(
        databaseId: dbId,
        collectionId: groupsCollectionId,
        queries: [
          Query.equal('userId', widget.userId),
          Query.equal('groupName', '전체'),
        ],
      );

      if (existing.total == 0) {
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

  // // ✅ 마커 업데이트 함수
  // Future<void> _updateMarkers(LocationsProvider provider) async {
  //   if (_mapLibreController == null) return;

  //   try {
  //     final allLocs = provider.getDisplayLocations();
  //     final locs = await _filterLocationsByGroup(allLocs);

  //     // 기존 심볼 제거
  //     for (final symbol in _symbols.values) {
  //       try {
  //         await _mapLibreController!.removeSymbol(symbol);
  //       } catch (e) {
  //         // 이미 제거된 심볼 무시
  //       }
  //     }
  //     _symbols.clear();

  //     // 기존 원 제거
  //     for (final circle in _circles.values) {
  //       try {
  //         await _mapLibreController!.removeCircle(circle);
  //       } catch (e) {
  //         // 이미 제거된 원 무시
  //       }
  //     }
  //     _circles.clear();

  //     // 새 마커 추가
  //     for (final loc in locs) {
  //       final stay = _formatDuration(loc.userId, provider);
  //       final isMe = loc.userId == widget.userId;
        
  //       // 색상 결정
  //       final color = isMe ? '#2196F3' : '#F44336'; // 파란색 : 빨간색

  //       // 원형 마커 추가
  //       final circle = await _mapLibreController!.addCircle(
  //         CircleOptions(
  //           geometry: LatLng(loc.lat, loc.lng),
  //           circleRadius: 8.0,
  //           circleColor: color,
  //           circleStrokeColor: '#FFFFFF',
  //           circleStrokeWidth: 2.0,
  //         ),
  //       );

  //       _circles[loc.userId] = circle;

  //       // 텍스트 라벨 추가 (stay duration 또는 userId)
  //       if (stay.isNotEmpty || true) {
  //         final symbol = await _mapLibreController!.addSymbol(
  //           SymbolOptions(
  //             geometry: LatLng(loc.lat, loc.lng),
  //             textField: stay.isNotEmpty ? stay : _short(loc.userId),
  //             textSize: 12.0,
  //             textColor: '#000000',
  //             textHaloColor: '#FFFFFF',
  //             textHaloWidth: 2.0,
  //             textOffset: const Offset(0, -1.5),
  //           ),
  //         );

  //         _symbols[loc.userId] = symbol;
  //       }
  //     }
  //   } catch (e) {
  //     debugPrint('❌ 마커 업데이트 실패: $e');
  //   }
  // }

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
    // final localTemplate = 'http://vranks.iptime.org:8080/styles/maptiler-basic/{z}/{x}/{y}.png';
    // final osmTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isDesktop ? '실시간 위치 공유 (Desktop)' : '실시간 위치 공유'),
        actions: [
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
      // body: Consumer<LocationsProvider>(
      //   builder: (context, provider, _) {
      //     return _isDesktop ? _buildFlutterMap(provider) : _buildMapLibreMap(provider);
      //   },
      // ),
    body: Consumer<LocationsProvider>(
      builder: (context, provider, _) {
        final width = MediaQuery.of(context).size.width;
        final isDesktop = width >= 800;

        //debugPrint('ℹ️ 화면 폭: $width, isDesktop: $isDesktop');

        return isDesktop
            ? _buildFlutterMap(provider)   // 데스크탑/웹
            : _buildMapLibreMap(provider); // 모바일
      },
    ),
    );
  }

  // ✅ Desktop용: flutter_map
  Widget _buildFlutterMap(LocationsProvider provider) {
    final allLocs = provider.getDisplayLocations();
    final localTemplate = 'http://vranks.iptime.org:8080/styles/maptiler-basic/{z}/{x}/{y}.png';
    final osmTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    final tileTemplate = _tileSource == 'LOCAL_TILE' ? localTemplate : osmTemplate;

    return FutureBuilder<List<LocationModel>>(
      future: _filterLocationsByGroup(allLocs),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final locs = snapshot.data!;
        final markers = locs.map((l) {
          final stay = _formatDuration(l.userId, provider);
          final isMe = l.userId == widget.userId;
          final displayName = l.userId;
          final initials = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

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
                        child: Text(initials, style: const TextStyle(color: Colors.white)),
                      ),
                      if (stay.isNotEmpty)
                        Positioned(
                          bottom: -25,
                          child: Text(stay, style: const TextStyle(fontSize: 11, color: Colors.black)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Icon(Icons.place, color: isMe ? Colors.blue : Colors.red, size: 30),
                  Text(_short(displayName), style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          );
        }).toList();

        final me = provider.locations[widget.userId];
        final center = me != null ? LatLng(me.lat, me.lng) : const LatLng(37.5665, 126.9780);

        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: latlong.LatLng(center.latitude, center.longitude), initialZoom: 14.0),
              children: [
                TileLayer(
                  urlTemplate: tileTemplate,
                  userAgentPackageName: 'com.example.location_share_app',
                ),
                MarkerClusterLayerWidget(
                  options: MarkerClusterLayerOptions(
                    maxClusterRadius: 45,
                    size: const Size(50, 50),
                    markers: markers,
                    onClusterTap: (cluster) => _showClusterUsers(cluster.markers),
                    builder: (context, clusterMarkers) => Container(
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.orange),
                      child: Text(
                        '${clusterMarkers.length}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
  }

  // ============================================
  // 수정 2: _buildMapLibreMap - onMapClick 구현
  // ============================================
  Widget _buildMapLibreMap(LocationsProvider provider) {
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
          onMapCreated: (controller) {
            _mapLibreController = controller;
            debugPrint("✅ MapLibre controller created");
            
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted && _mapLibreController != null) {
                _lastClusterZoom = _currentZoom;
                debugPrint('🎬 초기 마커 표시');
                _updateMapLibreMarkers(provider);
              }
            });
          },
          onStyleLoadedCallback: () async {
            debugPrint("✅ MapLibre style loaded");
            await Future.delayed(const Duration(milliseconds: 500));
            if (_mapLibreController != null && mounted) {
              _lastClusterZoom = _currentZoom;
              debugPrint('🎬 스타일 로드 후 마커 표시');
              await _updateMapLibreMarkers(provider);
            }
          },
          // ✅ 맵 클릭 이벤트 - queryRenderedFeatures 사용
          onMapClick: (Point<double> point, LatLng coordinates) async {
            debugPrint('');
            debugPrint('🖱️ ========================================');
            debugPrint('🖱️ [맵 클릭 감지!]');
            debugPrint('🖱️ 화면 좌표: (${point.x}, ${point.y})');
            debugPrint('🖱️ 지도 좌표: (${coordinates.latitude}, ${coordinates.longitude})');
            
            if (_mapLibreController == null) return;
            
            try {
              // 클릭한 지점 주변 20픽셀 범위의 피처 조회
              final clickRect = Rect.fromCenter(
                center: Offset(point.x, point.y),
                width: 40,
                height: 40,
              );
              
              debugPrint('🔍 클릭 범위: $clickRect');
              
              final features = await _mapLibreController!.queryRenderedFeaturesInRect(
                clickRect,
                [], // 모든 레이어 조회
                null, // 필터 없음
              );
              
              debugPrint('📍 발견된 피처: ${features.length}개');
              
              if (features.isEmpty) {
                debugPrint('ℹ️  빈 공간 클릭');
                debugPrint('🖱️ ========================================');
                debugPrint('');
                return;
              }
              
              // 피처 정보 출력
              for (var feature in features) {
                debugPrint('   - 레이어: ${feature['layer']}');
                debugPrint('   - 타입: ${feature['type']}');
                debugPrint('   - 좌표: ${feature['geometry']}');
              }
              
              // 가장 가까운 마커 찾기
              await _handleMarkerClickByCoordinates(coordinates, provider);
              
            } catch (e) {
              debugPrint('❌ queryRenderedFeatures 실패: $e');
            }
            
            debugPrint('🖱️ ========================================');
            debugPrint('');
          },
          onCameraMove: (CameraPosition position) {
            final oldZoom = _currentZoom;
            _currentZoom = position.zoom;
            
            if ((oldZoom - _currentZoom).abs() > 0.01) {
              debugPrint('📷 [onCameraMove] 줌: ${oldZoom.toStringAsFixed(2)} → ${_currentZoom.toStringAsFixed(2)}');
            }
          },
          onCameraIdle: () async {
            final zoomDiff = (_currentZoom - _lastClusterZoom).abs();
            
            debugPrint('');
            debugPrint('📷 ==================== [카메라 정지] ====================');
            debugPrint('📷 현재 줌: ${_currentZoom.toStringAsFixed(3)}');
            debugPrint('📷 이전 줌: ${_lastClusterZoom.toStringAsFixed(3)}');
            debugPrint('📷 줌 변화: ${zoomDiff.toStringAsFixed(3)}');
            
            if (zoomDiff > 0.5) {
              debugPrint('📷 ✅ 줌 변경 감지! 클러스터 재계산');
              _lastClusterZoom = _currentZoom;
              
              if (mounted) {
                await Future.delayed(const Duration(milliseconds: 100));
                await _updateMapLibreMarkers(provider);
              }
            } else {
              debugPrint('📷 ℹ️  줌 변경 미미');
            }
            debugPrint('📷 ========================================================');
            debugPrint('');
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: (_is3DMode ? Colors.purple : Colors.blue).withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_is3DMode ? Icons.view_in_ar : Icons.map, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  _getTileSourceName(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        
        _buildFloatingButtons(provider, isDesktop: false),
      ],
    );
  }

  // ============================================
  // 수정 3: 좌표 기반 마커 클릭 핸들러
  // ============================================
  Future<void> _handleMarkerClickByCoordinates(
    LatLng clickedLatLng, 
    LocationsProvider provider
  ) async {
    debugPrint('🎯 [마커 클릭 처리]');
    
    // 줌 레벨별 클릭 허용 반경 (미터)
    double searchRadius;
    if (_currentZoom >= 17) {
      searchRadius = 25;
    } else if (_currentZoom >= 16) {
      searchRadius = 35;
    } else if (_currentZoom >= 15) {
      searchRadius = 50;
    } else if (_currentZoom >= 14) {
      searchRadius = 75;
    } else {
      searchRadius = 100;
    }
    
    debugPrint('📏 검색 반경: ${searchRadius}m');
    
    // 1단계: 클러스터 확인
    LocationModel? closestUser;
    List<LocationModel>? clickedCluster;
    double minDistance = double.infinity;
    
    for (var entry in _clusterMarkers.entries) {
      final cluster = entry.value;
      
      // 클러스터 중심 계산
      double sumLat = 0, sumLng = 0;
      for (final loc in cluster) {
        sumLat += loc.lat;
        sumLng += loc.lng;
      }
      final centerLat = sumLat / cluster.length;
      final centerLng = sumLng / cluster.length;
      
      final distanceDegrees = sqrt(
        pow(centerLat - clickedLatLng.latitude, 2) + 
        pow(centerLng - clickedLatLng.longitude, 2)
      );
      final distanceMeters = distanceDegrees * 111320.0;
      
      debugPrint('   클러스터 ${entry.key}: ${distanceMeters.toStringAsFixed(1)}m');
      
      if (distanceMeters <= searchRadius && distanceMeters < minDistance) {
        minDistance = distanceMeters;
        clickedCluster = cluster;
        closestUser = null; // 클러스터가 더 가까우면 단일 유저 무시
      }
    }
    
    // 2단계: 단일 유저 확인 (클러스터가 없는 경우)
    if (clickedCluster == null) {
      for (var entry in _userMarkers.entries) {
        final loc = entry.value;
        
        final distanceDegrees = sqrt(
          pow(loc.lat - clickedLatLng.latitude, 2) + 
          pow(loc.lng - clickedLatLng.longitude, 2)
        );
        final distanceMeters = distanceDegrees * 111320.0;
        
        debugPrint('   유저 ${entry.key.substring(0, 8)}: ${distanceMeters.toStringAsFixed(1)}m');
        
        if (distanceMeters <= searchRadius && distanceMeters < minDistance) {
          minDistance = distanceMeters;
          closestUser = loc;
        }
      }
    }
    
    // 3단계: 결과 처리
    if (clickedCluster != null) {
      debugPrint('🎯 클러스터 클릭! (${clickedCluster.length}명, ${minDistance.toStringAsFixed(1)}m)');
      _showClusterUsersBottomSheet(clickedCluster, provider);
    } else if (closestUser != null) {
      debugPrint('🎯 유저 클릭! (${closestUser.userId.substring(0, 8)}, ${minDistance.toStringAsFixed(1)}m)');
      _showUserInfo(closestUser);
    } else {
      debugPrint('ℹ️  매칭되는 마커 없음');
    }
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
}