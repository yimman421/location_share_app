// lib/pages/simple_location_picker.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:latlong2/latlong.dart' as latlong;

class SimpleLocationPicker extends StatefulWidget {
  final String userId;
  final double initialLat;
  final double initialLng;
  final String initialAddress;

  const SimpleLocationPicker({
    super.key,
    required this.userId,
    required this.initialLat,
    required this.initialLng,
    required this.initialAddress,
  });

  @override
  State<SimpleLocationPicker> createState() => _SimpleLocationPickerState();
}

class _SimpleLocationPickerState extends State<SimpleLocationPicker> {
  final flutter_map.MapController _mapController = flutter_map.MapController();
  late latlong.LatLng _currentCenter;

  @override
  void initState() {
    super.initState();
    _currentCenter = latlong.LatLng(widget.initialLat, widget.initialLng);
    
    debugPrint('');
    debugPrint('📍 ═══════════════ SimpleLocationPicker 시작 ═══════════════');
    debugPrint('📍 초기 위치: (${widget.initialLat}, ${widget.initialLng})');
    debugPrint('📫 초기 주소: ${widget.initialAddress}');
    debugPrint('🌐 플랫폼: ${kIsWeb ? "Web" : "Mobile"}');
    debugPrint('📍 ════════════════════════════════════════════════════════');
    debugPrint('');

    // 지도 초기 위치로 이동
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(_currentCenter, 16.0);
      debugPrint('✅ 지도 초기 위치 설정 완료');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('샵 위치 선택'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Stack(
        children: [
          // ✅ FlutterMap 사용 (Web 호환)
          flutter_map.FlutterMap(
            mapController: _mapController,
            options: flutter_map.MapOptions(
              initialCenter: _currentCenter,
              initialZoom: 16.0,
              onPositionChanged: (position, hasGesture) {
                if (hasGesture && position.center != null) {
                  setState(() {
                    _currentCenter = position.center!;
                  });
                }
              },
            ),
            children: [
              // 타일 레이어
              flutter_map.TileLayer(
                urlTemplate: 'http://vranks.iptime.org:8080/styles/maptiler-basic/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.location_share_app',
              ),
            ],
          ),
          
          // 중앙 고정 빨간 핀
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
                const SizedBox(height: 50), // 핀의 끝부분이 중앙이 되도록
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
          
          // 현재 좌표 표시
          Positioned(
            top: 100,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '현재 선택된 위치:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '위도: ${_currentCenter.latitude.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  Text(
                    '경도: ${_currentCenter.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          
          // 하단 버튼
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      debugPrint('❌ 취소 버튼 클릭');
                      Navigator.pop(context);
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
                    onPressed: () {
                      debugPrint('');
                      debugPrint('✅ ═══════════════ 위치 확정 ═══════════════');
                      debugPrint('📍 선택된 위치: (${_currentCenter.latitude}, ${_currentCenter.longitude})');
                      debugPrint('✅ ═══════════════════════════════════════');
                      debugPrint('');
                      
                      Navigator.pop(context, {
                        'lat': _currentCenter.latitude,
                        'lng': _currentCenter.longitude,
                        'address': '선택된 위치 (위도: ${_currentCenter.latitude.toStringAsFixed(4)}, 경도: ${_currentCenter.longitude.toStringAsFixed(4)})',
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.check_circle),
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
      ),
    );
  }
}