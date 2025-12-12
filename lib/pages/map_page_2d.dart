// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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

class MapPage extends StatefulWidget {
  final String userId;
  const MapPage({super.key, required this.userId});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  final _distance = Distance();
  final Databases _db = appwriteDB; // appwriteClient.dart에서 불러온 객체

  Timer? _updateTimer;
  Timer? _autoMoveTimer;
  bool _autoMovingSon = false;

  // 모드: LOCAL(더미데이터) / REALTIME(Appwrite)
  String _mapMode = 'REALTIME';
  // 지도 소스: LOCAL_TILE or OSM_TILE
  String _tileSource = 'LOCAL_TILE';

  // 그룹 필터: id/name 쌍으로 관리 ('' id 는 기본 '전체'를 의미)
  String? _selectedGroupId = '';
  String? _selectedGroupName = '전체';
  List<Map<String, String>> _groups = [
    {'id': 'all', 'name': '전체'}
  ]; // DB에서 불러올 예정

  int _dropdownKey = 0; // ✅ 드롭다운 강제 리빌드용

  final Map<String, LatLng> _lastPositions = {};
  final Map<String, DateTime?> _stopStartTimes = {};

  // ✅ Duration 증가 계산용 (MapPage 로컬 캐시)
  final Map<String, Duration> _elapsedDurations = {};
  Timer? _durationTimer;

  @override
  void initState() {
    super.initState();
    final provider = context.read<LocationsProvider>();

    // DB 로드는 빌드가 끝난 후 실행하여 setState during build 오류 방지
    WidgetsBinding.instance.addPostFrameCallback((_) {
    // 🔹 기본 그룹(전체) 보장
      _ensureDefaultGroup();
      _loadGroupsFromDB();
    });

    // ✅ 재로그인 후 진입 시 반드시 Realtime 초기화
    provider.resetRealtimeConnection();

    // ✅ 다시 시작
    provider.startAll(startLocationStream: true);

    if (_mapMode == 'LOCAL') {
      _activateLocalMode(provider);
    } else {
      _activateRealtimeMode(provider);
    }

    _startStopTracking(provider);
    _startElapsedTimer(provider);
  }

  /// ✅ Appwrite DB에서 그룹 목록 불러오기
  Future<void> _loadGroupsFromDB() async {
    try {
      // ignore: duplicate_ignore
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
        } catch (_) {
          // ignore single document parse errors
        }
      }

      // ✅ 중복 제거 (그룹 이름 기준)
      final uniqueByName = <String, Map<String, String>>{};
      for (final g in fetched) {
        uniqueByName[g['name']!] = g;
      }

      setState(() {
        _groups = [
          {'id': 'all', 'name': '전체'},
          ...uniqueByName.values,
        ];

        // ✅ 현재 선택된 그룹이 목록에 없으면 '전체'로 복귀
        final validIds = _groups.map((e) => e['id']).toSet();
        if (!validIds.contains(_selectedGroupId)) {
          _selectedGroupId = 'all';
          _selectedGroupName = '전체';
        }

        _dropdownKey++; // ✅ 드롭다운 강제 갱신
      });

      debugPrint('✅ 그룹 불러오기 성공: ${_groups.length}개');
    } catch (e) {
      debugPrint('❌ 그룹 불러오기 실패: $e');
    }
  }

  // _MapPageState 내부에 추가
  Future<String?> _addGroupToDB(String name) async {
    try {
      // 🔹 먼저 중복 여부 확인
      final check = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.groupsCollectionId,
        queries: [
          Query.equal('userId', widget.userId),
          Query.equal('groupName', name),
        ],
      );

      if (check.documents.isNotEmpty) {
        // 이미 동일 이름 존재 시
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미 같은 이름의 그룹 [$name] 이(가) 존재합니다.')),
        );
        return null;
      }

      // 🔹 새로운 그룹 생성
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

                // ✅ 메모리(UI) 중복 방지 (DB 저장 전)
                final existsInUI = _groups.any((g) => g['name'] == name);
                if (existsInUI) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('이미 같은 이름의 그룹 [$name] 이(가) 존재합니다.')),
                  );
                  Navigator.pop(context);
                  return;
                }

                Navigator.pop(context); // 입력창 닫기

                // ✅ DB 저장 시도
                final id = await _addGroupToDB(name);

                // 🔹 DB 저장 성공시에만 UI 반영
                if (id != null) {
                  setState(() {
                    _groups.add({'id': id, 'name': name});
                    _dropdownKey++; // ✅ 추가 후 드롭다운 즉시 갱신
                  });
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('✅ 그룹 [$name] 추가 완료')),
                  );
                } else {
                  // 🔹 DB 저장 실패 — UI 추가 안 함
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

  /// ✅ Appwrite DB에서 그룹 문서 삭제
  Future<bool> _deleteGroupFromDB(String docId) async {
    //if (docId.isEmpty) return false;
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
        //nickname: '나',
        //avatarUrl:
            //'https://api.dicebear.com/8.x/pixel-art/png?seed=${Uri.encodeComponent(widget.userId)}',
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
        //nickname: '아들',
        //avatarUrl: 'https://api.dicebear.com/8.x/pixel-art/png?seed=son',
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
        //nickname: '형',
        //avatarUrl: 'https://api.dicebear.com/8.x/pixel-art/png?seed=brother',
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
        final currentPos = LatLng(loc.lat, loc.lng);

        final lastPos = _lastPositions[userId];
        if (lastPos == null) {
          _lastPositions[userId] = currentPos;
          continue;
        }

        final moved = _distance(lastPos, currentPos);
        if (moved < 2) {
          _stopStartTimes[userId] ??= DateTime.now();
        } else {
          // 이동 감지 시: provider의 stay 초기화 + MapPage 로컬 elapsed 초기화
          _stopStartTimes[userId] = null;
          _lastPositions[userId] = currentPos;

          // provider 내부에서 초기화
          provider.resetStayDuration(userId);

          // MapPage 쪽 캐시도 초기화 (중요)
          _elapsedDurations[userId] = Duration.zero;

          // UI 갱신
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

  // ✅ 사용자 정보 조회 함수
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

  // ✅ 개별 사용자 바텀시트 (실시간 반영)
  void _showUserInfo(LocationModel user) {
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
            final provider = context.read<LocationsProvider>();
            final stayInfo = _formatDuration(user.userId, provider);

            return FutureBuilder<Map<String, dynamic>?>(
              future: _fetchUserProfile(user.userId),
              builder: (context, snapshot) {
                final profile = snapshot.data;
                final nickname =
                    profile?['nickname'] ?? profile?['name'] ?? user.userId;
                final profileImage = profile?['profileImage'];

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
          },
        );
      },
    ).whenComplete(() => ticker.dispose());
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

  void _moveToMyLocation(LocationsProvider provider) {
    final me = provider.locations[widget.userId];
    if (me == null) return;
    _mapController.move(LatLng(me.lat, me.lng), 15);
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

      provider.onUserMove('son', LatLng(newLat, newLng));

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

  void _toggleTileSource() {
    setState(() {
      _tileSource =
          _tileSource == 'LOCAL_TILE' ? 'OSM_TILE' : 'LOCAL_TILE';
    });
  }

  // 그룹 항목 길게 누르면 삭제 확인 후 삭제
  Future<void> _onLongPressGroupItem(Map<String, String> group) async {
    final name = group['name'] ?? '';
    final id = group['id'] ?? '';

    // '전체' 그룹은 삭제 불가
    if (name == '전체') return;

    // 삭제 확인 다이얼로그
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

    // Appwrite DB에서 삭제
    final ok = await _deleteGroupFromDB(id);

    if (ok) {
      setState(() {
        _groups.removeWhere((g) => g['id'] == id);

        // ✅ 만약 현재 선택된 그룹이 삭제된 그룹이라면 '전체'로 복귀
        if (_selectedGroupId == id) {
          final allGroup = _groups.firstWhere(
            (g) => g['name'] == '전체',
            orElse: () => {'id': 'all', 'name': '전체'},
          );
          _selectedGroupId = allGroup['id'];
          _selectedGroupName = allGroup['name'];
        }

        _dropdownKey++; // ✅ 드롭다운 강제 리빌드
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

  /// ✅ 통합된 그룹 관리 다이얼로그
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
                    // 🔹 헤더
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

                    // 🔹 유저 검색 섹션
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

                    // 🔹 검색 결과 표시
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
                                // ✅ 추가 후 목록 새로고침
                                setDialogState(() {
                                  foundUser = null;
                                  searchController.clear();
                                });
                                // 하단 목록도 갱신하기 위해 재빌드
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

                    // 🔹 등록된 유저 목록 섹션
                    const Text(
                      '등록된 유저',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 🔹 유저 목록
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

  /// ✅ peoples 리스트 가져오기 (Future로 변경)
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

        // 내 자신은 제외
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

  /// ✅ peoples에서 유저 삭제
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

      // ✅ UI 갱신
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

  /// 🔹 peoples 컬렉션에 특정 유저 추가 (기본 그룹: '전체')
  Future<bool> _addPersonToPeoples({
    required String peopleUserId,
    required List<String> groups,
  }) async {
    try {
      // 🔹 중복 확인
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

      // 🔹 peoples 컬렉션에 추가
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

  /// 🔹 로그인 후, 기본 '전체' 그룹이 없을 경우 자동 생성
  Future<void> _ensureDefaultGroup() async {
    try {
      final dbId = AppwriteConstants.databaseId;
      final groupsCollectionId = AppwriteConstants.groupsCollectionId;

      // 🔹 기본 그룹 존재 확인
      final existing = await _db.listDocuments(
        databaseId: dbId,
        collectionId: groupsCollectionId,
        queries: [
          Query.equal('userId', widget.userId),
          Query.equal('groupName', '전체'),
        ],
      );

      if (existing.total == 0) {
        // 🔹 없으면 생성
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

  // 그룹 변경 다이얼로그
  Future<void> _showChangeUserGroupDialog(
    Map<String, dynamic> userItem,
    StateSetter setDialogState, // ✅ 부모 Dialog의 setState 전달받음
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
      // 1️⃣ userItem 바로 변경
      userItem['groups'] = [result];

      // 2️⃣ peoplesCollection DB 업데이트
      await _updatePersonGroups(
        userDocId: userItem['peopleDocId'],
        newGroups: [result],
      );

      // 3️⃣ ✅ 부모 Dialog UI 즉시 갱신
      setDialogState(() {});

      // 4️⃣ MapPage 전체 UI도 갱신 (필요시)
      if (mounted) setState(() {});
    }
  }

  // peoples 컬렉션 그룹 업데이트
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

  /// 🔹 그룹별로 위치 데이터 필터링 (peoples 컬렉션 기준)
  Future<List<LocationModel>> _filterLocationsByGroup(
    Map<String, LocationModel> allLocs,
  ) async {
    // '전체' 선택 시 모든 위치 반환
    if (_selectedGroupName == '전체') {
      return allLocs.values.toList();
    }

    try {
      // peoples 컬렉션에서 현재 선택된 그룹에 속한 사용자 조회
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.peoplesCollectionId,
        queries: [
          Query.equal('userId', widget.userId),
        ],
      );

      // 선택된 그룹에 속한 peopleUserId 목록 추출
      final filteredUserIds = <String>{};
      for (var doc in result.documents) {
        final groups = List<String>.from(doc.data['groups'] ?? []);
        if (groups.contains(_selectedGroupName)) {
          filteredUserIds.add(doc.data['peopleUserId']);
        }
      }

      // 내 위치는 항상 포함
      filteredUserIds.add(widget.userId);

      // 필터링된 사용자의 위치만 반환
      return allLocs.entries
          .where((entry) => filteredUserIds.contains(entry.key))
          .map((entry) => entry.value)
          .toList();
    } catch (e) {
      debugPrint('❌ 그룹 필터링 실패: $e');
      return allLocs.values.toList(); // 오류 시 전체 반환
    }
  }

  @override
  Widget build(BuildContext context) {
    //print("현재 그룹 목록: ${_groups.map((g) => g['name']).toList()}");
    //print("현재 선택된 그룹: $_selectedGroupName / $_selectedGroupId");
    final localTemplate =
        'http://vranks.iptime.org:8080/styles/maptiler-basic/{z}/{x}/{y}.png';
    final osmTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    final tileTemplate =
        _tileSource == 'LOCAL_TILE' ? localTemplate : osmTemplate;

    return Scaffold(
      appBar: AppBar(
        title: const Text('실시간 위치 공유'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: '그룹 관리',
            onPressed: _showGroupManagementDialog, // ✅ 통합 함수로 변경
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: ValueKey(_dropdownKey),
              value: _selectedGroupName?.trim().isEmpty ?? true
                  ? '전체'
                  : _selectedGroupName, // ✅ 항상 유효한 기본값 보장
              icon: const Icon(Icons.group, color: Colors.white),
              dropdownColor: Colors.blueGrey[50],
              items: [
                // ✅ 항상 '전체' 추가
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
        final allLocs = provider.getDisplayLocations();

        // 🔹 그룹 필터링 (비동기 처리)
        return FutureBuilder<List<LocationModel>>(
          future: _filterLocationsByGroup(allLocs),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final locs = snapshot.data!;

            // 🔹 필터링된 locs로 마커 생성
            final markers = locs.map((l) {
              final stay = _formatDuration(l.userId, provider);
              final isMe = l.userId == widget.userId;
              final isSon = l.userId == 'son';

              // nickname/avatarUrl이 locations에 없다면 기본/대체 UI로 처리
              final displayName = l.userId; // 닉네임은 프로필에서 따로 조회 가능
              final initials = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

              return Marker(
                key: ValueKey(l.userId),
                point: LatLng(l.lat, l.lng),
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
                            backgroundColor: isMe ? Colors.blue : (isSon ? Colors.orange : Colors.grey),
                            // locations에 avatarUrl이 없으므로 기본 표시: 이니셜로 대체
                            child: Text(initials, style: const TextStyle(color: Colors.white)),
                          ),
                          if (stay.isNotEmpty)
                            Positioned(
                              bottom: -25,
                              child: Text(
                                stay,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.black),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Icon(
                        Icons.place,
                        color: isMe
                            ? Colors.blue
                            : isSon
                                ? Colors.orange
                                : Colors.red,
                        size: 30,
                      ),
                      Text(_short(displayName), style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              );
            }).toList();

            final me = provider.locations[widget.userId];
            final center = me != null
                ? LatLng(me.lat, me.lng)
                : const LatLng(37.5665, 126.9780);

            return Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(initialCenter: center, initialZoom: 14.0),
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
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  bottom: 18,
                  right: 18,
                  child: Column(
                    children: [
                      FloatingActionButton(
                        heroTag: "move_my_location",
                        mini: true,
                        backgroundColor: Colors.blue,
                        onPressed: () => _moveToMyLocation(provider),
                        child: const Icon(Icons.my_location),
                      ),
                      const SizedBox(height: 12),
                      FloatingActionButton(
                        heroTag: "auto_move_son",
                        mini: true,
                        backgroundColor: _autoMovingSon
                            ? Colors.redAccent
                            : Colors.green,
                        onPressed: () => _toggleAutoMove(provider),
                        child: Icon(_autoMovingSon
                            ? Icons.pause
                            : Icons.play_arrow),
                      ),
                      const SizedBox(height: 12),
                      FloatingActionButton(
                        heroTag: "toggle_tile_source",
                        mini: true,
                        backgroundColor: _tileSource == 'LOCAL_TILE'
                            ? Colors.orange
                            : Colors.grey,
                        onPressed: _toggleTileSource,
                        child: const Icon(Icons.layers),
                      ),
                    ],
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
}
