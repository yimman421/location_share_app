import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart'; // ✅ 추가

enum TransportMode {
  driving,   // 자동차
  walking,   // 도보
  cycling,   // 자전거
}

class NavigationService {
  static const String _valhallaBaseUrl = 'http://vranks.iptime.org:8080/valhalla';
  static const String _nominatimBaseUrl = 'http://vranks.iptime.org:8080/nominatim';

  // ================================
  // 🔥 Valhalla 경로 요청
  // ================================
  Future<RouteResult?> getRoute({
    required LatLng start,
    required LatLng end,
    TransportMode mode = TransportMode.driving,
    bool steps = true,
  }) async {
    final requestBody = {
      'locations': [
        {'lat': start.latitude, 'lon': start.longitude},
        {'lat': end.latitude, 'lon': end.longitude},
      ],
      'costing': _getCostingString(mode),
      'directions_options': {
        'units': 'kilometers',
        'language': 'ko-KR',
      },
      'costing_options': _getCostingOptions(mode),
    };

    debugPrint('');
    debugPrint('🗺️ ═══════════════════════════════════════');
    debugPrint('🗺️ Valhalla 경로 요청 시작');
    debugPrint('📍 출발: ${start.latitude}, ${start.longitude}');
    debugPrint('📍 도착: ${end.latitude}, ${end.longitude}');
    debugPrint('🚗 mode: ${_getCostingString(mode)}');

    try {
      final url = Uri.parse('$_valhallaBaseUrl/route');
      debugPrint('🔗 요청 URL: $url');

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Connection': 'keep-alive',
            },
            body: json.encode(requestBody),
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('📡 상태 코드: ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('❌ HTTP 에러: ${response.statusCode}');
        debugPrint('📡 응답: ${response.body}');
        return null;
      }

      final data = json.decode(response.body);

      if (data is! Map || !data.containsKey('trip')) {
        debugPrint('❌ 잘못된 응답 형식');
        return null;
      }

      final trip = data['trip'];
      final legs = trip['legs'] as List?;
      if (legs == null || legs.isEmpty) {
        debugPrint('❌ legs 데이터 없음');
        return null;
      }

      final leg = legs.first;
      final shape = leg['shape'] as String?;

      if (shape == null || shape.isEmpty) {
        debugPrint('❌ shape 데이터 없음');
        return null;
      }

      debugPrint('🗺️ Shape 문자열: ${shape.substring(0, min(50, shape.length))}...');

      // ✅ google_polyline_algorithm 라이브러리 사용!
      final coordinates = _decodePolylineWithLibrary(shape);

      if (coordinates.isEmpty) {
        debugPrint('❌ 디코딩된 좌표 없음');
        return null;
      }

      // summary
      final summary = leg['summary'] ?? {};
      final distance = ((summary['length'] ?? 0) as num).toDouble() * 1000;
      final duration = ((summary['time'] ?? 0) as num).toDouble();

      // maneuvers → steps
      final stepsList = <NavigationStep>[];
      final maneuvers = (leg['maneuvers'] as List?) ?? [];

      for (final mRaw in maneuvers) {
        final m = (mRaw as Map<String, dynamic>);

        final length = ((m['length'] ?? 0) as num).toDouble() * 1000;
        final time = ((m['time'] ?? 0) as num).toDouble();
        final typeInt = m['type'] is int ? m['type'] : int.tryParse('${m['type']}') ?? 0;

        final instr = m['instruction']?.toString() ?? '';
        final street = (m['street_names'] as List?)
                ?.map((e) => e.toString())
                .join(', ') ??
            '';

        final idx = m['begin_shape_index'] is int
            ? m['begin_shape_index']
            : int.tryParse('${m['begin_shape_index']}') ?? 0;

        final pos = (idx >= 0 && idx < coordinates.length)
            ? coordinates[idx]
            : coordinates.first;

        stepsList.add(NavigationStep(
          instruction: instr,
          distance: length,
          duration: time,
          location: pos,
          type: _getManeuverType(typeInt),
          modifier: '',
          roadName: street,
        ));
      }

      debugPrint('✅ 경로 OK → 결과 반환');
      debugPrint('📏 거리: ${distance.toStringAsFixed(1)} m');
      debugPrint('⏱️ 시간: ${(duration / 60).toStringAsFixed(1)} 분');
      debugPrint('🧭 스텝 수: ${stepsList.length}');
      debugPrint('🗺️ 좌표 개수: ${coordinates.length}');
      debugPrint('🗺️ ═══════════════════════════════════════');

      return RouteResult(
        coordinates: coordinates,
        distance: distance,
        duration: duration,
        instructions: stepsList,
        transportMode: mode,
      );
    } catch (e, st) {
      debugPrint('❌ 예외 발생: $e');
      debugPrint(st.toString());
      return null;
    }
  }

  // ================================
  // ✅ google_polyline_algorithm 라이브러리 사용
  // ================================
  List<LatLng> _decodePolylineWithLibrary(String encoded) {
    try {
      debugPrint('🔧 Polyline 디코딩 시작 (라이브러리 사용)');
      debugPrint('   입력 길이: ${encoded.length}');
      
      // ✅ precision 6으로 디코딩 (Valhalla polyline6 형식)
      final decoded = decodePolyline(encoded, accuracyExponent: 6);
      
      final coordinates = decoded
          .map((point) => LatLng(
                point[0].toDouble(),  // latitude
                point[1].toDouble(),  // longitude
              ))
          .toList();
      
      debugPrint('✅ 디코딩 완료: ${coordinates.length}개 좌표');
      
      if (coordinates.isNotEmpty) {
        debugPrint('   첫 좌표: ${coordinates.first.latitude.toStringAsFixed(6)}, ${coordinates.first.longitude.toStringAsFixed(6)}');
        if (coordinates.length > 1) {
          debugPrint('   마지막 좌표: ${coordinates.last.latitude.toStringAsFixed(6)}, ${coordinates.last.longitude.toStringAsFixed(6)}');
        }
      }
      
      return coordinates;
    } catch (e, stack) {
      debugPrint('❌ Polyline 디코딩 실패: $e');
      debugPrint('Stack: $stack');
      
      // ✅ precision 5로 재시도
      try {
        debugPrint('🔄 precision 5로 재시도...');
        final decoded = decodePolyline(encoded, accuracyExponent: 5);
        final coordinates = decoded
            .map((point) => LatLng(point[0].toDouble(), point[1].toDouble()))
            .toList();
        
        debugPrint('✅ precision 5로 성공: ${coordinates.length}개 좌표');
        return coordinates;
      } catch (e2) {
        debugPrint('❌ precision 5도 실패: $e2');
        return [];
      }
    }
  }

  // ================================
  // 🔹 요약 버전 (거리/시간만 필요할 때)
  // ================================
  Future<RouteInfo?> getRouteInfo({
    required LatLng start,
    required LatLng end,
    TransportMode mode = TransportMode.driving,
  }) async {
    final result = await getRoute(start: start, end: end, mode: mode);
    if (result == null) return null;

    return RouteInfo(
      distance: result.distance,
      duration: result.duration,
      transportMode: mode,
    );
  }

  /// ===============================
  /// 🔍 Nominatim 주소 검색
  /// ===============================
  Future<List<LocationSearchResult>> searchLocation(String query) async {
    try {
      final encoded = Uri.encodeComponent(query);
      final url = Uri.parse('$_nominatimBaseUrl/search?q=$encoded&format=json&limit=5');

      debugPrint('🔍 Nominatim 검색 요청: $url');

      final response =
          await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return [];

      final data = json.decode(response.body) as List;

      return data
          .map((item) => LocationSearchResult(
                name: item['display_name'] ?? '',
                lat: double.parse(item['lat']),
                lng: double.parse(item['lon']),
                type: item['type'] ?? 'location',
              ))
          .toList();
    } catch (e) {
      debugPrint('❌ 검색 실패: $e');
      return [];
    }
  }

  // ✅ Valhalla costing 문자열
  String _getCostingString(TransportMode mode) {
    switch (mode) {
      case TransportMode.driving:
        return 'auto';
      case TransportMode.walking:
        return 'pedestrian';
      case TransportMode.cycling:
        return 'bicycle';
    }
  }

  // ✅ Costing 옵션
  Map<String, dynamic> _getCostingOptions(TransportMode mode) {
    switch (mode) {
      case TransportMode.driving:
        return {
          'auto': {
            'use_highways': 1.0,
            'use_tolls': 1.0,
            'use_ferry': 1.0,
          }
        };
      case TransportMode.walking:
        return {
          'pedestrian': {
            'walking_speed': 5.1,
            'max_hiking_difficulty': 1,
          }
        };
      case TransportMode.cycling:
        return {
          'bicycle': {
            'bicycle_type': 'Road',
            'cycling_speed': 20.0,
            'use_roads': 0.5,
          }
        };
    }
  }

  // ✅ Valhalla maneuver type을 OSRM 스타일로 변환
  String _getManeuverType(int type) {
    switch (type) {
      case 0:
        return 'none';
      case 1:
        return 'depart';
      case 2:
        return 'depart-right';
      case 3:
        return 'depart-left';
      case 4:
        return 'arrive';
      case 5:
        return 'arrive-right';
      case 6:
        return 'arrive-left';
      case 7:
        return 'continue';
      case 8:
        return 'continue-straight';
      case 9:
        return 'turn-slight-right';
      case 10:
        return 'turn-right';
      case 11:
        return 'turn-sharp-right';
      case 12:
        return 'turn-uturn';
      case 13:
        return 'turn-sharp-left';
      case 14:
        return 'turn-left';
      case 15:
        return 'turn-slight-left';
      case 16:
        return 'ramp-straight';
      case 17:
        return 'ramp-right';
      case 18:
        return 'ramp-left';
      case 19:
        return 'exit-right';
      case 20:
        return 'exit-left';
      case 21:
        return 'stay-straight';
      case 22:
        return 'stay-right';
      case 23:
        return 'stay-left';
      case 24:
        return 'merge';
      case 25:
        return 'roundabout-enter';
      case 26:
        return 'roundabout-exit';
      case 27:
        return 'ferry-enter';
      case 28:
        return 'ferry-exit';
      default:
        return 'continue';
    }
  }

  double calculateStraightDistance(LatLng start, LatLng end) {
    const earth = 6371000.0;
    final dLat = _toRadians(end.latitude - start.latitude);
    final dLon = _toRadians(end.longitude - start.longitude);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(start.latitude)) *
            cos(_toRadians(end.latitude)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    return earth * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _toRadians(double deg) => deg * pi / 180.0;
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

// ✅ 네비게이션 스텝 모델
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
    required this.modifier,
    required this.roadName,
  });

  String get formattedDistance {
    if (distance >= 1000) {
      return '${(distance / 1000).toStringAsFixed(1)}km';
    } else {
      return '${distance.toStringAsFixed(0)}m';
    }
  }

  // ✅ 한글 방향 설명
  String get koreanDirection {
    switch (type) {
      case 'depart':
      case 'depart-right':
      case 'depart-left':
        if (type == 'depart-left') return '왼쪽으로 출발하세요';
        if (type == 'depart-right') return '오른쪽으로 출발하세요';
        return '출발하세요';

      case 'arrive':
      case 'arrive-right':
      case 'arrive-left':
        if (type == 'arrive-left') return '왼쪽에 목적지가 있습니다';
        if (type == 'arrive-right') return '오른쪽에 목적지가 있습니다';
        return '목적지에 도착했습니다';

      case 'turn-slight-right':
        return '오른쪽으로 살짝 꺾으세요';
      case 'turn-right':
        return '우회전하세요';
      case 'turn-sharp-right':
        return '오른쪽으로 급하게 꺾으세요';
      case 'turn-slight-left':
        return '왼쪽으로 살짝 꺾으세요';
      case 'turn-left':
        return '좌회전하세요';
      case 'turn-sharp-left':
        return '왼쪽으로 급하게 꺾으세요';
      case 'turn-uturn':
        return 'U턴하세요';

      case 'continue':
      case 'continue-straight':
        if (type == 'continue-straight') return '직진하세요';
        return '계속 가세요';

      case 'ramp-straight':
        return '진입로로 직진하세요';
      case 'ramp-right':
        return '오른쪽 진입로로 진입하세요';
      case 'ramp-left':
        return '왼쪽 진입로로 진입하세요';

      case 'exit-right':
        return '오른쪽 진출로로 나가세요';
      case 'exit-left':
        return '왼쪽 진출로로 나가세요';

      case 'stay-straight':
        return '직진 방향을 유지하세요';
      case 'stay-right':
        return '오른쪽 차로를 유지하세요';
      case 'stay-left':
        return '왼쪽 차로를 유지하세요';

      case 'merge':
        return '차로에 합류하세요';

      case 'roundabout-enter':
        return '로터리에 진입하세요';
      case 'roundabout-exit':
        return '로터리에서 나가세요';

      case 'ferry-enter':
        return '페리에 탑승하세요';
      case 'ferry-exit':
        return '페리에서 내리세요';

      default:
        if (instruction.isNotEmpty) return instruction;
        return '계속 진행하세요';
    }
  }

  // ✅ 완전한 설명 (거리 + 방향)
  String get fullDescription {
    String result = '';

    // 거리 정보
    if (distance > 0 && formattedDistance != '0m') {
      result = '$formattedDistance 전방에서 ';
    }

    // 방향 안내
    if (instruction.isNotEmpty && !instruction.contains('Instruction')) {
      result += instruction;
    } else {
      result += koreanDirection;
    }

    return result;
  }

  // ✅ 도로명 포함 설명
  String get fullDescriptionWithRoad {
    String result = fullDescription;

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