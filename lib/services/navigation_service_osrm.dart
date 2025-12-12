import 'dart:convert';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';

enum TransportMode {
  driving,   // 자동차
  walking,   // 도보
  cycling,   // 자전거
}

class NavigationService {
  // ✅ 개인 OSRM 서버 URL
  static const String _osrmBaseUrl = 'http://vranks.iptime.org:8080';
  static const String _nominatimBaseUrl = 'http://vranks.iptime.org:8080/nominatim';
  
  // ✅ 경로 가져오기 (개선된 버전)
  Future<RouteResult?> getRoute({
    required LatLng start,
    required LatLng end,
    TransportMode mode = TransportMode.driving,
    bool alternatives = false,
    bool steps = true,
  }) async {
    try {
      final routeType = _getRouteType(mode);
      
      final url = Uri.parse(
        '$_osrmBaseUrl/$routeType/route/v1/${_getModeString(mode)}/'
        '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
        '?alternatives=$alternatives&steps=$steps&geometries=geojson&overview=full',
      );
      
      debugPrint('');
      debugPrint('🗺️ ═══════════════════════════════════════');
      debugPrint('🗺️ OSRM 경로 요청');
      debugPrint('🗺️ ═══════════════════════════════════════');
      debugPrint('📍 출발: (${start.latitude}, ${start.longitude})');
      debugPrint('📍 도착: (${end.latitude}, ${end.longitude})');
      debugPrint('🚗 이동수단: ${_getModeString(mode)}');
      debugPrint('🔗 URL: $url');
      
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('❌ 요청 시간 초과');
          throw Exception('Request timeout');
        },
      );
      
      if (response.statusCode != 200) {
        debugPrint('❌ OSRM 에러: ${response.statusCode}');
        debugPrint('응답: ${response.body}');
        debugPrint('🗺️ ═══════════════════════════════════════');
        debugPrint('');
        return null;
      }
      
      final data = json.decode(response.body);
      
      if (data['code'] != 'Ok') {
        debugPrint('❌ OSRM 응답 에러: ${data['code']}');
        debugPrint('🗺️ ═══════════════════════════════════════');
        debugPrint('');
        return null;
      }
      
      if ((data['routes'] as List).isEmpty) {
        debugPrint('❌ 경로가 없습니다');
        debugPrint('🗺️ ═══════════════════════════════════════');
        debugPrint('');
        return null;
      }
      
      final route = data['routes'][0];
      final geometry = route['geometry']['coordinates'] as List;
      
      // 좌표 변환 (OSRM은 [lng, lat] 순서)
      final coordinates = geometry
          .map((coord) => LatLng(
                coord[1] as double,
                coord[0] as double,
              ))
          .toList();
      
      final distance = (route['distance'] as num).toDouble(); // 미터
      final duration = (route['duration'] as num).toDouble(); // 초
      
      debugPrint('');
      debugPrint('📊 경로 정보:');
      debugPrint('   거리: ${distance.toStringAsFixed(0)}m');
      debugPrint('   시간: ${(duration / 60).toStringAsFixed(0)}분');
      debugPrint('   좌표 개수: ${coordinates.length}개');
      
      // ✅ 턴 바이 턴 네비게이션 정보
      final instructions = <NavigationStep>[];
      
      if (steps && route['legs'] != null && route['legs'].isNotEmpty) {
        debugPrint('');
        debugPrint('🧭 턴 바이 턴 안내:');
        debugPrint('   ─────────────────────────────────────');
        
        final leg = route['legs'][0];
        final stepsList = leg['steps'] as List;
        
        int stepIndex = 1;
        for (final step in stepsList) {
          final maneuver = step['maneuver'];
          final stepDistance = (step['distance'] as num).toDouble();
          final stepDuration = (step['duration'] as num).toDouble();
          
          final type = maneuver['type'] ?? 'turn';
          final modifier = maneuver['modifier'] ?? '';
          final instruction = maneuver['instruction'] ?? '';
          final roadName = step['name'] ?? '';
          
          debugPrint('   Step $stepIndex:');
          debugPrint('      타입: $type');
          debugPrint('      방향: $modifier');
          debugPrint('      설명: $instruction');
          debugPrint('      도로명: $roadName');
          debugPrint('      거리: ${stepDistance.toStringAsFixed(0)}m');
          debugPrint('      시간: ${(stepDuration / 60).toStringAsFixed(1)}분');
          debugPrint('   ─────────────────────────────────────');
          
          instructions.add(NavigationStep(
            instruction: instruction,
            distance: stepDistance,
            duration: stepDuration,
            location: LatLng(
              maneuver['location'][1],
              maneuver['location'][0],
            ),
            type: type,
            modifier: modifier,
            roadName: roadName,
          ));
          
          stepIndex++;
        }
        
        debugPrint('✅ 총 ${instructions.length}개 스텝');
      }
      
      debugPrint('🗺️ ═══════════════════════════════════════');
      debugPrint('');
      
      return RouteResult(
        coordinates: coordinates,
        distance: distance,
        duration: duration,
        instructions: instructions,
        transportMode: mode,
      );
      
    } catch (e) {
      debugPrint('❌ 경로 생성 실패: $e');
      debugPrint('🗺️ ═══════════════════════════════════════');
      debugPrint('');
      return null;
    }
  }
  
  // ✅ 거리 및 시간 예측
  Future<RouteInfo?> getRouteInfo({
    required LatLng start,
    required LatLng end,
    TransportMode mode = TransportMode.driving,
  }) async {
    try {
      final routeType = _getRouteType(mode);
      
      final url = Uri.parse(
        '$_osrmBaseUrl/$routeType/route/v1/${_getModeString(mode)}/'
        '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
        '?overview=false',
      );
      
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );
      
      if (response.statusCode != 200) return null;
      
      final data = json.decode(response.body);
      
      if (data['code'] != 'Ok' || (data['routes'] as List).isEmpty) {
        return null;
      }
      
      final route = data['routes'][0];
      
      return RouteInfo(
        distance: (route['distance'] as num).toDouble(),
        duration: (route['duration'] as num).toDouble(),
        transportMode: mode,
      );
      
    } catch (e) {
      debugPrint('❌ 경로 정보 실패: $e');
      return null;
    }
  }
  
  // ✅ 주소 검색 (Nominatim)
  Future<List<LocationSearchResult>> searchLocation(String query) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      
      final url = Uri.parse(
        '$_nominatimBaseUrl/search?q=$encodedQuery&format=json&limit=5',
      );
      
      debugPrint('🔍 주소 검색: $query');
      
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );
      
      if (response.statusCode != 200) {
        debugPrint('❌ Nominatim 에러: ${response.statusCode}');
        return [];
      }
      
      final data = json.decode(response.body) as List;
      
      final results = data
          .map((item) => LocationSearchResult(
                name: item['display_name'] ?? '',
                lat: double.parse(item['lat']),
                lng: double.parse(item['lon']),
                type: item['type'] ?? 'location',
              ))
          .toList();
      
      debugPrint('✅ 검색 결과: ${results.length}개');
      
      return results;
      
    } catch (e) {
      debugPrint('❌ 주소 검색 실패: $e');
      return [];
    }
  }
  
  // ✅ 라우트 타입 결정
  String _getRouteType(TransportMode mode) {
    switch (mode) {
      case TransportMode.driving:
        return 'osrm-car';
      case TransportMode.walking:
        return 'osrm-foot';
      case TransportMode.cycling:
        return 'osrm-bicycle';
    }
  }
  
  // ✅ 모드 문자열
  String _getModeString(TransportMode mode) {
    switch (mode) {
      case TransportMode.driving:
        return 'driving';
      case TransportMode.walking:
        return 'walking';
      case TransportMode.cycling:
        return 'cycling';
    }
  }
  
  // ✅ 직선 거리 계산
  double calculateStraightDistance(LatLng start, LatLng end) {
    const earthRadius = 6371000; // 미터
    
    final dLat = _toRadians(end.latitude - start.latitude);
    final dLng = _toRadians(end.longitude - start.longitude);
    
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(start.latitude)) *
            cos(_toRadians(end.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }
  
  double _toRadians(double degree) {
    return degree * 3.14159265359 / 180;
  }
}

// ✅ 경로 결과 모델
class RouteResult {
  final List<LatLng> coordinates;
  final double distance; // 미터
  final double duration; // 초
  final List<NavigationStep> instructions;
  final TransportMode transportMode;
  
  RouteResult({
    required this.coordinates,
    required this.distance,
    required this.duration,
    required this.instructions,
    required this.transportMode,
  });
  
  String get formattedDistance {
    if (distance >= 1000) {
      return '${(distance / 1000).toStringAsFixed(1)}km';
    } else {
      return '${distance.toStringAsFixed(0)}m';
    }
  }
  
  String get formattedDuration {
    final minutes = (duration / 60).round();
    
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return '$hours시간 $mins분';
    } else {
      return '$minutes분';
    }
  }
  
  String get transportModeString {
    switch (transportMode) {
      case TransportMode.driving:
        return '자동차';
      case TransportMode.walking:
        return '도보';
      case TransportMode.cycling:
        return '자전거';
    }
  }
}

// ✅ 네비게이션 스텝 모델 (고도화 완료)
class NavigationStep {
  final String instruction;
  final double distance;
  final double duration;
  final LatLng location;
  final String type;
  final String modifier;
  final String roadName;
  
  NavigationStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.location,
    required this.type,
    this.modifier = '',
    this.roadName = '',
  });
  
  String get formattedDistance {
    if (distance >= 1000) {
      return '${(distance / 1000).toStringAsFixed(1)}km';
    } else {
      return '${distance.toStringAsFixed(0)}m';
    }
  }
  
  // ✅ 한글 방향 설명 (고도화 완료 - map_page.dart와 동일)
  String get koreanDirection {
    switch (type) {
      case 'turn':
        if (modifier == 'left') return '좌회전하세요';
        if (modifier == 'right') return '우회전하세요';
        if (modifier == 'slight left') return '왼쪽으로 살짝 꺾으세요';
        if (modifier == 'slight right') return '오른쪽으로 살짝 꺾으세요';
        if (modifier == 'sharp left') return '왼쪽으로 급하게 꺾으세요';
        if (modifier == 'sharp right') return '오른쪽으로 급하게 꺾으세요';
        if (modifier == 'uturn') return 'U턴하세요';
        return '회전하세요';
        
      case 'new name':
        // 도로명이 바뀌는 경우
        if (roadName.isNotEmpty && roadName != 'null') {
          if (modifier == 'straight') return '$roadName(으)로 직진하세요';
          if (modifier == 'slight left') return '$roadName(으)로 왼쪽 방향으로 가세요';
          if (modifier == 'slight right') return '$roadName(으)로 오른쪽 방향으로 가세요';
          if (modifier == 'left') return '$roadName(으)로 좌회전하세요';
          if (modifier == 'right') return '$roadName(으)로 우회전하세요';
          return '$roadName(으)로 계속 가세요';
        } else {
          if (modifier == 'straight') return '직진하세요';
          if (modifier == 'slight left') return '왼쪽 방향으로 계속 가세요';
          if (modifier == 'slight right') return '오른쪽 방향으로 계속 가세요';
          if (modifier == 'left') return '왼쪽으로 계속 가세요';
          if (modifier == 'right') return '오른쪽으로 계속 가세요';
          return '계속 가세요';
        }
        
      case 'continue':
        // ✅ 핵심 수정: modifier를 명확하게 반영
        if (modifier == 'straight') return '직진하세요';
        if (modifier == 'left') return '왼쪽 방향으로 계속 가세요';
        if (modifier == 'right') return '오른쪽 방향으로 계속 가세요';
        if (modifier == 'slight left') return '왼쪽으로 조금 치우쳐 계속 가세요';
        if (modifier == 'slight right') return '오른쪽으로 조금 치우쳐 계속 가세요';
        if (modifier == 'sharp left') return '왼쪽으로 크게 꺾어 계속 가세요';
        if (modifier == 'sharp right') return '오른쪽으로 크게 꺾어 계속 가세요';
        if (modifier.isEmpty) return '현재 도로를 따라 계속 가세요';
        return '계속 가세요';
        
      case 'depart':
        if (modifier == 'left') return '왼쪽으로 출발하세요';
        if (modifier == 'right') return '오른쪽으로 출발하세요';
        if (modifier == 'straight') return '직진으로 출발하세요';
        return '출발하세요';
        
      case 'arrive':
        if (modifier == 'left') return '왼쪽에 목적지가 있습니다';
        if (modifier == 'right') return '오른쪽에 목적지가 있습니다';
        if (modifier == 'straight') return '앞에 목적지가 있습니다';
        return '목적지에 도착했습니다';
        
      case 'merge':
        if (modifier == 'left') return '왼쪽 차로로 합류하세요';
        if (modifier == 'right') return '오른쪽 차로로 합류하세요';
        if (modifier == 'slight left') return '왼쪽으로 합류하세요';
        if (modifier == 'slight right') return '오른쪽으로 합류하세요';
        return '합류하세요';
        
      case 'on ramp':
        if (modifier == 'left') return '왼쪽 진입로로 진입하세요';
        if (modifier == 'right') return '오른쪽 진입로로 진입하세요';
        if (modifier == 'slight left') return '왼쪽 진입로 방향으로 가세요';
        if (modifier == 'slight right') return '오른쪽 진입로 방향으로 가세요';
        return '진입로로 진입하세요';
        
      case 'off ramp':
        if (modifier == 'left') return '왼쪽 진출로로 나가세요';
        if (modifier == 'right') return '오른쪽 진출로로 나가세요';
        if (modifier == 'slight left') return '왼쪽 진출로 방향으로 가세요';
        if (modifier == 'slight right') return '오른쪽 진출로 방향으로 가세요';
        return '진출로로 나가세요';
        
      case 'fork':
        if (modifier == 'left') return '왼쪽 길로 가세요';
        if (modifier == 'right') return '오른쪽 길로 가세요';
        if (modifier == 'slight left') return '왼쪽 방향 길로 가세요';
        if (modifier == 'slight right') return '오른쪽 방향 길로 가세요';
        return '분기점에서 길을 선택하세요';
        
      case 'end of road':
        if (modifier == 'left') return '도로 끝에서 좌회전하세요';
        if (modifier == 'right') return '도로 끝에서 우회전하세요';
        return '도로가 끝납니다';
        
      case 'use lane':
        if (modifier.contains('left')) return '왼쪽 차로를 이용하세요';
        if (modifier.contains('right')) return '오른쪽 차로를 이용하세요';
        return '차로를 유지하세요';
        
      case 'roundabout':
      case 'rotary':
        if (modifier.contains('1')) return '로터리에서 첫 번째 출구로 나가세요';
        if (modifier.contains('2')) return '로터리에서 두 번째 출구로 나가세요';
        if (modifier.contains('3')) return '로터리에서 세 번째 출구로 나가세요';
        if (modifier.contains('4')) return '로터리에서 네 번째 출구로 나가세요';
        if (modifier == 'left') return '로터리에서 왼쪽으로 나가세요';
        if (modifier == 'right') return '로터리에서 오른쪽으로 나가세요';
        if (modifier == 'straight') return '로터리에서 직진으로 나가세요';
        return '로터리에 진입하세요';
        
      case 'roundabout turn':
        if (modifier == 'left') return '로터리에서 좌회전하세요';
        if (modifier == 'right') return '로터리에서 우회전하세요';
        return '로터리에서 회전하세요';
        
      case 'notification':
        if (modifier.contains('straight')) return '직진 방향을 유지하세요';
        if (modifier == 'left') return '왼쪽 방향을 유지하세요';
        if (modifier == 'right') return '오른쪽 방향을 유지하세요';
        return '경로를 따라 가세요';
        
      default:
        return '계속 진행하세요';
    }
  }
  
  // ✅ 완전한 설명 (거리 + 방향 + 도로명)
  String get fullDescription {
    String result = '';
    
    // 거리 정보
    if (distance > 0 && formattedDistance != '0m') {
      result = '$formattedDistance 전방에서 ';
    }
    
    // 방향 안내
    result += koreanDirection;
    
    return result;
  }
  
  // ✅ 도로명 포함 설명
  String get fullDescriptionWithRoad {
    String result = fullDescription;
    
    // 도로명이 이미 포함되어 있지 않으면 추가
    if (roadName.isNotEmpty && roadName != 'null' && !result.contains(roadName)) {
      result += ' ($roadName)';
    }
    
    return result;
  }
}

// ✅ 간단한 경로 정보
class RouteInfo {
  final double distance;
  final double duration;
  final TransportMode transportMode;
  
  RouteInfo({
    required this.distance,
    required this.duration,
    required this.transportMode,
  });
}

// ✅ 주소 검색 결과
class LocationSearchResult {
  final String name;
  final double lat;
  final double lng;
  final String type;
  
  LocationSearchResult({
    required this.name,
    required this.lat,
    required this.lng,
    required this.type,
  });
}