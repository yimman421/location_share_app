// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:latlong2/latlong.dart' as latlong;
import 'package:provider/provider.dart';
//import 'package:intl/intl.dart';

import '../providers/locations_provider.dart';
import '../providers/auth_provider.dart';
import '../models/location_model.dart';
import 'login_page.dart';
import '../constants/appwrite_config.dart';
import '../appwriteClient.dart';
import 'package:appwrite/appwrite.dart';

class MapPage extends StatefulWidget {
  final String userId;
  const MapPage({super.key, required this.userId});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  MapLibreMapController? _mapController;
  final latlong.Distance _distance = latlong.Distance();
  final Databases _db = appwriteDB;

  Timer? _updateTimer;
  Timer? _autoMoveTimer;
  Timer? _markerUpdateTimer;
  bool _autoMovingSon = false;

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
    _startMarkerUpdateTimer(provider);
  }

  // ✅ 마커 주기적 업데이트
  void _startMarkerUpdateTimer(LocationsProvider provider) {
    _markerUpdateTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_mapController != null && mounted) {
        _updateMarkers(provider);
      }
    });
  }

  // ✅ 3D 모드 토글
  Future<void> _toggle3DMode() async {
    if (_mapController == null) return;

    setState(() => _is3DMode = !_is3DMode);

    if (_is3DMode) {
      await _mapController!.animateCamera(
        CameraUpdate.tiltTo(60.0),
        duration: const Duration(milliseconds: 1000),
      );
    } else {
      await _mapController!.animateCamera(
        CameraUpdate.tiltTo(0.0),
        duration: const Duration(milliseconds: 1000),
      );
      await _mapController!.animateCamera(
        CameraUpdate.bearingTo(0.0),
        duration: const Duration(milliseconds: 500),
      );
    }
  }

  // ✅ 타일 소스 순환 변경
  void _toggleTileSource() {
    setState(() {
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
    });
  }

  // ✅ 타일 소스 URL 가져오기
  String _getStyleUrl() {
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

  void _moveToMyLocation(LocationsProvider provider) async {
    final me = provider.locations[widget.userId];
    if (me == null || _mapController == null) return;

    await _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(me.lat, me.lng),
        15.0,
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
                        const Text(
                          '그룹 관리',
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
                    const Divider(),
                    const SizedBox(height: 16),

                    const Text(
                      '유저 추가',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
                                  const SnackBar(
                                    content: Text('해당 이메일로 가입된 사용자가 없습니다.'),
                                  ),
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
                                const SnackBar(
                                  content: Text('해당 이메일로 가입된 사용자가 없습니다.'),
                                ),
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
                          leading: const CircleAvatar(
                            child: Icon(Icons.person),
                          ),
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
                                  SnackBar(
                                    content: Text('$email 님이 전체 그룹에 추가되었습니다.'),
                                  ),
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
                                  const SnackBar(
                                    content: Text('이미 추가된 유저입니다.'),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),

                    const Text(
                      '등록된 유저',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.person),
                                  ),
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
                                  onTap: () => _showChangeUserGroupDialog(item, setDialogState),
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

      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$email 님이 삭제되었습니다.')),
      );

      setDialogState(() {});
    } catch (e) {
      debugPrint('❌ 유저 삭제 실패: $e');
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('삭제에 실패했습니다.')),
      );
    }
  }

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

  // ✅ 마커 업데이트 함수
  Future<void> _updateMarkers(LocationsProvider provider) async {
    if (_mapController == null) return;

    try {
      final allLocs = provider.getDisplayLocations();
      final locs = await _filterLocationsByGroup(allLocs);

      // 기존 심볼 제거
      for (final symbol in _symbols.values) {
        try {
          await _mapController!.removeSymbol(symbol);
        } catch (e) {
          // 이미 제거된 심볼 무시
        }
      }
      _symbols.clear();

      // 기존 원 제거
      for (final circle in _circles.values) {
        try {
          await _mapController!.removeCircle(circle);
        } catch (e) {
          // 이미 제거된 원 무시
        }
      }
      _circles.clear();

      // 새 마커 추가
      for (final loc in locs) {
        final stay = _formatDuration(loc.userId, provider);
        final isMe = loc.userId == widget.userId;
        
        // 색상 결정
        final color = isMe ? '#2196F3' : '#F44336'; // 파란색 : 빨간색

        // 원형 마커 추가
        final circle = await _mapController!.addCircle(
          CircleOptions(
            geometry: LatLng(loc.lat, loc.lng),
            circleRadius: 8.0,
            circleColor: color,
            circleStrokeColor: '#FFFFFF',
            circleStrokeWidth: 2.0,
          ),
        );

        _circles[loc.userId] = circle;

        // 텍스트 라벨 추가 (stay duration 또는 userId)
        if (stay.isNotEmpty || true) {
          final symbol = await _mapController!.addSymbol(
            SymbolOptions(
              geometry: LatLng(loc.lat, loc.lng),
              textField: stay.isNotEmpty ? stay : _short(loc.userId),
              textSize: 12.0,
              textColor: '#000000',
              textHaloColor: '#FFFFFF',
              textHaloWidth: 2.0,
              textOffset: const Offset(0, -1.5),
            ),
          );

          _symbols[loc.userId] = symbol;
        }
      }
    } catch (e) {
      debugPrint('❌ 마커 업데이트 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('실시간 위치 공유'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: '그룹 관리',
            onPressed: _showGroupManagementDialog,
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: ValueKey(_dropdownKey),
              value: _selectedGroupName?.trim().isEmpty ?? true
                  ? '전체'
                  : _selectedGroupName,
              icon: const Icon(Icons.group, color: Colors.white),
              dropdownColor: Colors.blueGrey[50],
              items: [
                const DropdownMenuItem<String>(
                  value: '전체',
                  child: Text('전체'),
                ),
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
                  final selected =
                      _groups.firstWhere((g) => g['name'] == value, orElse: () => {'id': 'all', 'name': '전체'});
                  setState(() {
                    _selectedGroupName = selected['name'];
                    _selectedGroupId = selected['id'];
                  });
                }
              },
            ),
          ),
          IconButton(
            icon: Icon(
              _mapMode == 'REALTIME' ? Icons.public : Icons.map_outlined,
            ),
            tooltip: _mapMode == 'REALTIME'
                ? 'Local 더미모드로 전환'
                : '실시간 모드로 전환',
            onPressed: _toggleMapMode,
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Consumer<LocationsProvider>(
        builder: (context, provider, _) {
          return Stack(
            children: [
              // ✅ MapLibre GL 지도
              MapLibreMap(
                key: ValueKey('map_${_tileSource}_${_is3DMode}'),
                styleString: _getStyleUrl(),
                initialCameraPosition: CameraPosition(
                  target: const LatLng(37.408915, 127.148245),
                  zoom: 15.0,
                  tilt: _is3DMode ? 60.0 : 0.0,
                ),
                onMapCreated: (MapLibreMapController controller) async {
                  _mapController = controller;
                  
                  // 지도 로드 대기
                  await Future.delayed(const Duration(milliseconds: 500));
                  
                  if (mounted) {
                    _updateMarkers(provider);
                  }
                },
                onStyleLoadedCallback: () {
                  if (mounted) {
                    _updateMarkers(provider);
                  }
                },
                myLocationEnabled: true,
                myLocationTrackingMode: MyLocationTrackingMode.none,
                compassEnabled: true,
                rotateGesturesEnabled: true,
                tiltGesturesEnabled: true,
              ),

              // ✅ 타일 소스 표시 배너
              Positioned(
                top: 16,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _is3DMode 
                        ? Colors.purple.withOpacity(0.9)
                        : Colors.blue.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
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

              // ✅ 우측 하단 버튼들
              Positioned(
                bottom: 18,
                right: 18,
                child: Column(
                  children: [
                    // 내 위치로 이동
                    FloatingActionButton(
                      heroTag: "move_my_location",
                      mini: true,
                      backgroundColor: Colors.blue,
                      onPressed: () => _moveToMyLocation(provider),
                      child: const Icon(Icons.my_location),
                    ),
                    const SizedBox(height: 12),

                    // ✅ 3D 모드 토글
                    if (_tileSource.contains('3D'))
                      FloatingActionButton(
                        heroTag: "toggle_3d",
                        mini: true,
                        backgroundColor: _is3DMode
                            ? Colors.purple
                            : Colors.grey[600],
                        onPressed: _toggle3DMode,
                        child: Icon(
                          _is3DMode ? Icons.view_in_ar : Icons.view_in_ar_outlined,
                        ),
                      ),
                    if (_tileSource.contains('3D')) const SizedBox(height: 12),

                    // ✅ 북쪽으로 회전 (3D 모드일 때만)
                    if (_is3DMode && _tileSource.contains('3D'))
                      FloatingActionButton(
                        heroTag: "reset_bearing",
                        mini: true,
                        backgroundColor: Colors.indigo,
                        onPressed: () async {
                          if (_mapController != null) {
                            await _mapController!.animateCamera(
                              CameraUpdate.bearingTo(0.0),
                              duration: const Duration(milliseconds: 500),
                            );
                          }
                        },
                        child: const Icon(Icons.navigation),
                      ),
                    if (_is3DMode && _tileSource.contains('3D')) const SizedBox(height: 12),

                    // 자동 이동 (테스트용)
                    FloatingActionButton(
                      heroTag: "auto_move_son",
                      mini: true,
                      backgroundColor: _autoMovingSon
                          ? Colors.redAccent
                          : Colors.green,
                      onPressed: () => _toggleAutoMove(provider),
                      child: Icon(_autoMovingSon ? Icons.pause : Icons.play_arrow),
                    ),
                    const SizedBox(height: 12),

                    // ✅ 타일 소스 변경 (4가지 순환)
                    FloatingActionButton(
                      heroTag: "toggle_tile_source",
                      mini: true,
                      backgroundColor: Colors.orange,
                      onPressed: _toggleTileSource,
                      child: const Icon(Icons.layers),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}