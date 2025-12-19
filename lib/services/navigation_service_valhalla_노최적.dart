import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // ✅ IconData를 위해 추가
import 'package:latlong2/latlong.dart';
import 'dart:math';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';

enum TransportMode {
  driving,
  walking,
  cycling,
}

// ✅ 언어 Enum
enum NavigationLanguage {
  korean,
  english,
}

class NavigationService {
  static const String _valhallaBaseUrl = 'http://vranks.iptime.org:8080/valhalla';
  static const String _nominatimBaseUrl = 'http://vranks.iptime.org:8080/nominatim';

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

      debugPrint('🗺️ Shape: ${shape.substring(0, min(50, shape.length))}...');

      final coordinates = _decodePolylineWithLibrary(shape);

      if (coordinates.isEmpty) {
        debugPrint('❌ 디코딩된 좌표 없음');
        return null;
      }

      final summary = leg['summary'] ?? {};
      final distance = ((summary['length'] ?? 0) as num).toDouble() * 1000;
      final duration = ((summary['time'] ?? 0) as num).toDouble();

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
          valhallaType: typeInt, // ✅ valhallaType 사용
          roadName: street,
        ));
      }

      debugPrint('✅ 경로 OK');
      debugPrint('📏 거리: ${distance.toStringAsFixed(1)} m');
      debugPrint('⏱️ 시간: ${(duration / 60).toStringAsFixed(1)} 분');
      debugPrint('🧭 스텝 수: ${stepsList.length}');
      debugPrint('🗺️ 좌표: ${coordinates.length}개');

      debugPrint('');
      debugPrint('📍 ════════════════ 전체 경로 스텝 ════════════════');
      for (int i = 0; i < stepsList.length; i++) {
        final step = stepsList[i];
        debugPrint('');
        debugPrint('🔹 Step ${i + 1}/${stepsList.length}:');
        debugPrint('   Instruction: ${step.instruction}');
        debugPrint('   Distance: ${step.formattedDistance}');
        debugPrint('   Duration: ${(step.duration / 60).toStringAsFixed(1)}분');
        debugPrint('   Location: (${step.location.latitude.toStringAsFixed(6)}, ${step.location.longitude.toStringAsFixed(6)})');
        debugPrint('   Valhalla Type: ${step.valhallaType}');
        debugPrint('   Road Name: ${step.roadName}');
      }
      debugPrint('');
      debugPrint('📍 ══════════════════════════════════════════════');

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

  List<LatLng> _decodePolylineWithLibrary(String encoded) {
    try {
      debugPrint('🔧 Polyline 디코딩 (라이브러리)');
      
      final decoded = decodePolyline(encoded, accuracyExponent: 6);
      
      final coordinates = decoded
          .map((point) => LatLng(
                point[0].toDouble(),
                point[1].toDouble(),
              ))
          .toList();
      
      debugPrint('✅ 디코딩 완료: ${coordinates.length}개');
      
      if (coordinates.isNotEmpty) {
        debugPrint('   첫: ${coordinates.first.latitude.toStringAsFixed(6)}, ${coordinates.first.longitude.toStringAsFixed(6)}');
        debugPrint('   끝: ${coordinates.last.latitude.toStringAsFixed(6)}, ${coordinates.last.longitude.toStringAsFixed(6)}');
      }
      
      return coordinates;
    } catch (e) {
      debugPrint('❌ precision 6 실패: $e');
      
      try {
        debugPrint('🔄 precision 5 재시도...');
        final decoded = decodePolyline(encoded, accuracyExponent: 5);
        final coordinates = decoded
            .map((point) => LatLng(point[0].toDouble(), point[1].toDouble()))
            .toList();
        
        debugPrint('✅ precision 5 성공: ${coordinates.length}개');
        return coordinates;
      } catch (e2) {
        debugPrint('❌ precision 5도 실패: $e2');
        return [];
      }
    }
  }

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

  Future<List<LocationSearchResult>> searchLocation(String query) async {
    try {
      final encoded = Uri.encodeComponent(query);
      final url = Uri.parse('$_nominatimBaseUrl/search?q=$encoded&format=json&limit=5');

      final response = await http.get(url).timeout(const Duration(seconds: 10));

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

// ✅ NavigationStep 클래스
class NavigationStep {
  final String instruction;
  final double distance;
  final double duration;
  final LatLng location;
  final int valhallaType;
  final String roadName;

  NavigationStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.location,
    required this.valhallaType,
    required this.roadName,
  });

  String get formattedDistance {
    if (distance >= 1000) {
      return '${(distance / 1000).toStringAsFixed(1)}km';
    } else {
      return '${distance.toStringAsFixed(0)}m';
    }
  }

  String getDirection(NavigationLanguage language) {
    return language == NavigationLanguage.korean
        ? _getKoreanDirection()
        : _getEnglishDirection();
  }

  String _getKoreanDirection() {
    switch (valhallaType) {
      case 1: return '출발하세요';
      case 2: return '오른쪽으로 출발하세요';
      case 3: return '왼쪽으로 출발하세요';
      case 4: return '목적지에 도착했습니다';
      case 5: return '오른쪽에 목적지가 있습니다';
      case 6: return '왼쪽에 목적지가 있습니다';
      case 7: return '계속 가세요';
      case 8: return '직진하세요';
      case 9: return '오른쪽으로 살짝 꺾으세요';
      case 10: return '우회전하세요';
      case 11: return '오른쪽으로 급하게 꺾으세요';
      case 12: return 'U턴하세요';
      case 13: return '왼쪽으로 급하게 꺾으세요';
      case 14: return '좌회전하세요';
      case 15: return '왼쪽으로 살짝 꺾으세요';
      case 16: return '진입로로 직진하세요';
      case 17: return '오른쪽 진입로로 진입하세요';
      case 18: return '왼쪽 진입로로 진입하세요';
      case 19: return '오른쪽 진출로로 나가세요';
      case 20: return '왼쪽 진출로로 나가세요';
      case 21: return '직진 방향을 유지하세요';
      case 22: return '오른쪽 차로를 유지하세요';
      case 23: return '왼쪽 차로를 유지하세요';
      case 24: return '차로에 합류하세요';
      case 25: return '로터리에 진입하세요';
      case 26: return '로터리에서 나가세요';
      case 27: return '페리에 탑승하세요';
      case 28: return '페리에서 내리세요';
      default: return instruction.isNotEmpty ? instruction : '계속 진행하세요';
    }
  }

  String _getEnglishDirection() {
    switch (valhallaType) {
      case 1: return 'Start';
      case 2: return 'Start right';
      case 3: return 'Start left';
      case 4: return 'You have arrived';
      case 5: return 'Destination on the right';
      case 6: return 'Destination on the left';
      case 7: return 'Continue';
      case 8: return 'Continue straight';
      case 9: return 'Turn slight right';
      case 10: return 'Turn right';
      case 11: return 'Turn sharp right';
      case 12: return 'Make a U-turn';
      case 13: return 'Turn sharp left';
      case 14: return 'Turn left';
      case 15: return 'Turn slight left';
      case 16: return 'Take the ramp straight';
      case 17: return 'Take the ramp right';
      case 18: return 'Take the ramp left';
      case 19: return 'Exit right';
      case 20: return 'Exit left';
      case 21: return 'Stay straight';
      case 22: return 'Stay right';
      case 23: return 'Stay left';
      case 24: return 'Merge';
      case 25: return 'Enter roundabout';
      case 26: return 'Exit roundabout';
      case 27: return 'Enter ferry';
      case 28: return 'Exit ferry';
      default: return instruction.isNotEmpty ? instruction : 'Continue';
    }
  }

  String getFullDescription(NavigationLanguage language) {
    String result = '';
    
    if (distance > 0 && formattedDistance != '0m') {
      result = language == NavigationLanguage.korean
          ? '$formattedDistance 전방에서 '
          : 'In $formattedDistance, ';
    }
    
    result += getDirection(language);
    return result;
  }

  IconData getDirectionIcon() {
    switch (valhallaType) {
      case 1: case 2: case 3: return Icons.play_arrow;
      case 4: case 5: case 6: return Icons.flag;
      case 8: case 21: return Icons.arrow_upward;
      case 9: case 10: case 11: return Icons.turn_right;
      case 13: case 14: case 15: return Icons.turn_left;
      case 12: return Icons.u_turn_left;
      case 17: case 19: return Icons.turn_slight_right;
      case 18: case 20: return Icons.turn_slight_left;
      case 22: case 23: return Icons.trending_flat;
      case 24: return Icons.merge;
      case 25: case 26: return Icons.roundabout_right;
      default: return Icons.navigation;
    }
  }
}

class RouteResult {
  final List<LatLng> coordinates;
  final double distance;
  final double duration;
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
      case TransportMode.driving: return '자동차';
      case TransportMode.walking: return '도보';
      case TransportMode.cycling: return '자전거';
    }
  }
}

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