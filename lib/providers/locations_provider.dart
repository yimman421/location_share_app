import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../appwriteClient.dart';
import '../constants/appwrite_config.dart';
import '../models/location_model.dart';
import 'package:appwrite/appwrite.dart';
import 'package:latlong2/latlong.dart';

class LocationsProvider with ChangeNotifier {
  // Appwrite 객체 (전역으로 제공되는 appwriteClient의 인스턴스 사용)
  late Databases _db;
  late Account _account;
  late Realtime _realtime;

  final Map<String, LocationModel> _locations = {};
  final Map<String, DateTime> _stayStartTimes = {};
  final Map<String, bool> _isStaying = {};
  final Map<String, Duration> _stayDurations = {};

  final Set<String> _justMovedUsers = {}; // 이동 직후 1회 제외용

  StreamSubscription? _positionSub;
  StreamSubscription? _realtimeSub;
  Timer? _stayTimer;
  Timer? _autoSaveTimer; // ✅ 자동 저장 타이머 추가

  String? _currentGroupId; // ✅ 현재 선택된 그룹 ID

  Map<String, LocationModel> get locations => Map.unmodifiable(_locations);

  Map<String, LocationModel> get stayingUsers {
    final staying = <String, LocationModel>{};
    _isStaying.forEach((userId, stay) {
      if (stay == true && _locations.containsKey(userId)) {
        staying[userId] = _locations[userId]!;
      }
    });
    return staying;
  }

  LocationsProvider() {
    _initAppwrite(); // appwrite 인스턴스 참조 설정
    _startAutoSave(); // ✅ 자동 저장 타이머 시작
  }

  // ✅✅✅ 지도 이동 트리거 필드 추가
  LatLng? _targetMapLocation;
  LatLng? get targetMapLocation => _targetMapLocation;
  
  // ✅✅✅ 지도 이동 트리거 메서드 추가
  void triggerMapMove(double lat, double lng) {
    debugPrint('');
    debugPrint('🎯 ════════════════════ triggerMapMove 호출 ════════════════════');
    debugPrint('📍 목표 위치: ($lat, $lng)');
    
    _targetMapLocation = LatLng(lat, lng);
    
    debugPrint('📢 notifyListeners() 호출');
    notifyListeners();
    
    debugPrint('⏰ 500ms 후 타겟 초기화 예약');
    // 이동 후 타겟 초기화 (한 번만 트리거)
    Future.delayed(const Duration(milliseconds: 500), () {
      _targetMapLocation = null;
      debugPrint('🗑️ 타겟 초기화 완료');
      debugPrint('🎯 ═══════════════════════════════════════════════');
      debugPrint('');
    });
  }

  // ---------- Appwrite 초기화 (login/logout 후 전역 인스턴스가 바뀌면 호출) ----------
  void _initAppwrite() {
    _db = appwriteDB;
    _account = appwriteAccount;
    _realtime = appwriteRealtime;
  }

  /// ✅ 30초마다 자동으로 duration 저장
  void _startAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      saveAllStayDurations();
    });
    debugPrint('[AutoSave] Timer started - saving every 30 seconds');
  }

  /// -------------------
  /// ✅ 사용자 그룹 변경
  /// -------------------
  Future<void> updateUserGroup(String userId, String newGroupId) async {
    final loc = _locations[userId];
    if (loc == null) return;

    // 1️⃣ 로컬 업데이트
    final updatedLoc = loc.copyWith(groupId: newGroupId);
    _locations[userId] = updatedLoc;

    try {
      // 2️⃣ DB 업데이트
      // ignore: deprecated_member_use
      await _db.updateDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.locationsCollectionId,
        documentId: loc.id,
        data: {'groupId': newGroupId},
      );
      debugPrint('[updateUserGroup] $userId group updated to $newGroupId');
    } catch (e) {
      debugPrint('[updateUserGroup] error: $e');
    }

    // 3️⃣ UI 갱신: 무조건 호출
    notifyListeners();
  }

  /// ✅ 그룹 필터 설정
  void setCurrentGroup(String? groupId) {
    _currentGroupId = groupId;
    fetchAllLocations(); // 그룹 변경 시 DB 재조회
  }

  /// 로그인 성공 후 또는 재로그인 시 반드시 호출해서
  /// fetch / realtime 구독 / 타이머 등을 정상 상태로 만든다.
  Future<void> startAll({bool startLocationStream = false}) async {
    // cancel existing realtime subscription so we don't double-subscribe
    _realtimeSub?.cancel();
    _realtimeSub = null;

    // re-init references (in case appwrite client was re-created)
    _initAppwrite();

    // fetch existing docs from DB and initialize timers from stored stayDuration
    await fetchAllLocations();

    // start realtime subscription
    startRealtime();

    // restart timer if stopped
    _startStayTimer();
    
    // ✅ 자동 저장 타이머 재시작
    _startAutoSave();

    // optionally restart device location stream if needed (called from MapPage if used)
    if (startLocationStream) {
      await startLocationUpdates();
    }
  }

  /// 간단한 이름: 실행중인지 확인, 아니면 다시 시작
  void ensureRunning() {
    if (_stayTimer == null || !_stayTimer!.isActive) _startStayTimer();
    if (_realtimeSub == null) startRealtime();
    if (_autoSaveTimer == null || !_autoSaveTimer!.isActive) _startAutoSave();
  }

  // -------------------
  // 위치 오프셋 계산 (UI 표시용)
  // -------------------
  LocationModel _withOffset(LocationModel loc) {
    final hash = loc.userId.hashCode;
    final offsetMeters = (hash % 5).toDouble(); // 0~4m
    final angle = (hash % 360) * pi / 180.0;

    final dLat = (offsetMeters * cos(angle)) / 111111.0;
    final dLng =
        (offsetMeters * sin(angle)) / (111111.0 * cos(loc.lat * pi / 180));

    return loc.copyWith(
      lat: loc.lat + dLat,
      lng: loc.lng + dLng,
    );
  }

  Map<String, LocationModel> getDisplayLocations() {
    final adjusted = <String, LocationModel>{};
    for (final entry in _locations.entries) {
      adjusted[entry.key] = _withOffset(entry.value);
    }
    return adjusted;
  }

  // -------------------
  // 머무름 감지
  // -------------------
  void _checkStayDuration(LocationModel loc) {
    final userId = loc.userId;
    final prev = _locations[userId];

    if (prev == null) {
      // 처음 들어온 사용자: start now (또는 DB에서 복원된 경우 start already 세팅되어 있을 수 있음)
      _stayStartTimes[userId] ??= DateTime.now();
      _isStaying[userId] = false;
      _stayDurations[userId] ??= Duration.zero;
      return;
    }

    final distance = Geolocator.distanceBetween(
      prev.lat,
      prev.lng,
      loc.lat,
      loc.lng,
    );

    const stayThresholdMeters = 10.0;
    const stayTimeMinutes = 5;

    if (distance <= stayThresholdMeters) {
      // 움직이지 않음 → start가 없으면 현재로 세팅
      _stayStartTimes[userId] ??= DateTime.now();
      final stayDuration = DateTime.now().difference(_stayStartTimes[userId]!);
      _stayDurations[userId] = stayDuration;

      final currentlyStaying = _isStaying[userId] ?? false;
      if (stayDuration.inMinutes >= stayTimeMinutes && !currentlyStaying) {
        _isStaying[userId] = true;
        debugPrint('[Stay] $userId has stayed for ${stayDuration.inMinutes} min');
      }
    } else {
      // 움직였으면 즉시 리셋
      _stayStartTimes[userId] = DateTime.now();
      _stayDurations[userId] = Duration.zero;
      _isStaying[userId] = false;
      _justMovedUsers.add(userId); // 타이머 루프에서 1회 제외
      notifyListeners();
      debugPrint('[resetStayDuration] $userId stay reset by move');
    }
  }

  Duration getStayDuration(String userId) {
    final start = _stayStartTimes[userId];
    if (start == null) return _stayDurations[userId] ?? Duration.zero;
    
    // ✅ 현재 시각 기준으로 계속 증가하는 duration 반환
    return DateTime.now().difference(start);
  }

  void resetStayDuration(String userId) {
    _stayStartTimes[userId] = DateTime.now();
    _stayDurations[userId] = Duration.zero;
    _isStaying[userId] = false;
    notifyListeners();
    debugPrint('[resetStayDuration] $userId stay reset');
  }

  // -------------------
  // 사용자가 "이동" 버튼을 눌렀을 때 (UI에서 호출)
  // -------------------
  Future<void> onUserMove(String userId, LatLng newPos) async {
    // 1) DB에 마지막 머무름 저장 (있다면)
    await saveLastStay(userId);

    // 2) UI 즉시 초기화
    _stayStartTimes[userId] = DateTime.now();
    _stayDurations[userId] = Duration.zero;
    _isStaying[userId] = false;
    _justMovedUsers.add(userId);
    notifyListeners();

    // 3) 로컬 위치 업데이트
    final current = _locations[userId];
    if (current != null) {
      final updated = current.copyWith(
        lat: newPos.latitude,
        lng: newPos.longitude,
        timestamp: DateTime.now(),
      );
      _locations[userId] = updated;
      // DB에도 반영
      await saveLocation(updated);
      debugPrint('[onUserMove] Updated existing location for $userId');
    } else {
      // 현재 로컬에 없으면 새로 생성 (임시 id)
      final newLoc = LocationModel(
        id: ID.unique(),
        userId: userId,
        groupId: _currentGroupId,
        lat: newPos.latitude,
        lng: newPos.longitude,
        timestamp: DateTime.now(),
      );
      _locations[userId] = newLoc; // 로컬 반영
      await saveLocation(newLoc);
      debugPrint('[onUserMove] Created new location for $userId');
    }
  }

  // -------------------
  // ✅ DB에 마지막 머무름 기록 (수정됨)
  // -------------------
  Future<void> saveLastStay(String userId) async {
    final loc = _locations[userId];
    if (loc == null) {
      debugPrint('[saveLastStay] No location found for $userId');
      return;
    }

    // ✅ 현재 실제 duration 계산
    final dur = getStayDuration(userId);
    
    if (dur.inSeconds == 0) {
      debugPrint('[saveLastStay] $userId has 0 duration, skipping');
      return;
    }

    try {
      // ✅ documentId는 LocationModel의 id를 사용 (userId가 아님!)
      // ignore: deprecated_member_use
      await _db.updateDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.locationsCollectionId,
        documentId: loc.id, // ✅ 수정: userId → loc.id
        data: {'stayDuration': dur.inSeconds},
      );
      //print('[saveLastStay] ✅ $userId stayed ${dur.inSeconds}s (${(dur.inSeconds / 60).toStringAsFixed(1)} min) - saved to doc ${loc.id}');
    } catch (e) {
      debugPrint('[saveLastStay] ❌ error for $userId: $e');
    }
  }

  Future<void> saveAllStayDurations() async {
    try {
      //print('[saveAllStayDurations] Starting to save all durations...');
      final futures = _locations.keys.map((userId) => saveLastStay(userId));
      await Future.wait(futures);
      //print('[saveAllStayDurations] ✅ All saved');
    } catch (e) {
      debugPrint('[saveAllStayDurations] ❌ error: $e');
    }
  }

  // -------------------
  // ✅ 타이머: 1초마다 UI용 duration 갱신 (notifyListeners 활성화)
  // -------------------
  void _startStayTimer() {
    if (_stayTimer != null && _stayTimer!.isActive) return;

    _stayTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      bool needsUpdate = false;
      
      _locations.forEach((userId, loc) {
        if (_justMovedUsers.contains(userId)) {
          _justMovedUsers.remove(userId);
          return;
        }

        final start = _stayStartTimes[userId];
        if (start != null) {
          final newDuration = DateTime.now().difference(start);
          // ✅ duration이 실제로 변경되었을 때만 업데이트
          if (_stayDurations[userId] != newDuration) {
            _stayDurations[userId] = newDuration;
            needsUpdate = true;
          }
        }
      });

      // ✅ 변경사항이 있을 때만 notifyListeners 호출
      if (needsUpdate) {
        notifyListeners();
      }
    });

    debugPrint('[StayTimer] started ✅ (with notifyListeners)');
  }

  // -------------------
  // ✅ Realtime (그룹 기반 구독)
  // -------------------
  void startRealtime() {
    _realtimeSub?.cancel();

    final channel =
        'databases.${AppwriteConstants.databaseId}.collections.${AppwriteConstants.locationsCollectionId}.documents';

    final currentGroup = (_currentGroupId ?? '전체').toString();

    _realtimeSub = _realtime.subscribe([channel]).stream.listen((event) {
      try {
        final eventType = event.events.isNotEmpty ? event.events.first : '';
        final data = Map<String, dynamic>.from(event.payload);

        final docGroup = (data['groupId'] ?? '전체').toString();

        // 그룹 필터링
        if (currentGroup != '전체' && docGroup != currentGroup) {
          return; // 다른 그룹이면 무시
        }

        if (eventType.contains('.delete')) {
          final id = data['\$id'];
          _locations.removeWhere((_, v) => v.id == id);
          notifyListeners();
          debugPrint('[Realtime] Deleted $id');
          return;
        }

        final loc = LocationModel.fromMap(data);
        _locations[loc.userId] = loc;
        _checkStayDuration(loc);
        notifyListeners();
        //print('[Realtime] Updated location for ${loc.userId}');
      } catch (e, st) {
        debugPrint('[Realtime parse error] $e\n$st');
      }
    });

    debugPrint('[Realtime] Subscribed to locations');
  }

  // -------------------
  // ✅ Appwrite: 위치 저장 / 업데이트
  // -------------------
  Future<void> saveLocation(LocationModel loc) async {
    try {
      // ✅ 현재 duration 저장
      final currentDuration = getStayDuration(loc.userId);
      
      // 안전한 Map 데이터 생성
      final safeData = Map<String, dynamic>.from(loc.toMap())
        ..removeWhere((key, value) => value == null)
        ..addAll({'stayDuration': currentDuration.inSeconds});

      // ✅ groupId가 없으면 기본 그룹(null 허용)
      final groupId = loc.groupId ?? _currentGroupId ?? 'default';

      // ✅ 기존 문서 조회
      final queries = [
        Query.equal('userId', loc.userId),
        Query.equal('groupId', groupId),
      ];

      // ignore: deprecated_member_use
      final res = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.locationsCollectionId,
        queries: queries,
      );

      if (res.documents.isNotEmpty) {
        // ✅ 기존 문서가 있을 경우 업데이트
        final existingId = res.documents.first.$id;
        // ignore: deprecated_member_use
        await _db.updateDocument(
          databaseId: AppwriteConstants.databaseId,
          collectionId: AppwriteConstants.locationsCollectionId,
          documentId: existingId,
          data: safeData,
        );
        debugPrint('[saveLocation] Updated existing document: $existingId (duration: ${currentDuration.inSeconds}s)');
        
        // ✅ 로컬 LocationModel의 id도 업데이트
        _locations[loc.userId] = loc.copyWith(id: existingId, timestamp: DateTime.now());
      } else {
        // ✅ 문서가 없을 경우 새로 생성
        // ignore: deprecated_member_use
        final newDoc = await _db.createDocument(
          databaseId: AppwriteConstants.databaseId,
          collectionId: AppwriteConstants.locationsCollectionId,
          documentId: ID.unique(),
          data: {
            ...safeData,
            'groupId': groupId,
          },
          permissions: [
            Permission.read(Role.any()),
            Permission.update(Role.user(loc.userId)),
            Permission.delete(Role.user(loc.userId)),
          ],
        );
        debugPrint('[saveLocation] Created new document ${newDoc.$id} for ${loc.userId}');
        
        // ✅ 로컬 캐시에 실제 document id 저장
        _locations[loc.userId] = loc.copyWith(
          id: newDoc.$id,
          timestamp: DateTime.now(),
        );
      }

      _checkStayDuration(_locations[loc.userId]!);
      notifyListeners();
    } catch (e, st) {
      debugPrint('[saveLocation] error: $e\n$st');
    }
  }

  // -------------------
  // ✅ 전체 로드 (그룹 필터 반영 + duration 복원)
  // -------------------
  Future<void> fetchAllLocations() async {
    try {
      final queries = <String>[];
      final currentGroup = (_currentGroupId ?? '전체').toString();

      if (currentGroup != '전체') {
        // 문자열로 통일해서 DB 쿼리
        queries.add(Query.equal('groupId', currentGroup));
      }

      // ignore: deprecated_member_use
      final res = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.locationsCollectionId,
        queries: queries,
      );

      _locations.clear();

      for (final d in res.documents) {
        final map = d.data;
        final loc = LocationModel.fromMap({'\$id': d.$id, ...map});
        _locations[loc.userId] = loc;

        // ✅ DB에 저장된 stayDuration을 복원
        if (map.containsKey('stayDuration')) {
          final s = map['stayDuration'];
          final savedDuration = s is int 
              ? Duration(seconds: s) 
              : Duration(seconds: int.tryParse(s.toString()) ?? 0);
          
          if (savedDuration.inSeconds > 0) {
            // ✅ 저장된 duration만큼 과거 시점으로 시작 시간 설정
            _stayDurations[loc.userId] = savedDuration;
            _stayStartTimes[loc.userId] = DateTime.now().subtract(savedDuration);
            debugPrint('[fetchAllLocations] ✅ Restored ${loc.userId} duration: ${savedDuration.inSeconds}s');
          } else {
            _stayDurations[loc.userId] = Duration.zero;
            _stayStartTimes[loc.userId] = DateTime.now();
          }
        } else {
          _stayDurations[loc.userId] = Duration.zero;
          _stayStartTimes[loc.userId] = DateTime.now();
        }
      }

      notifyListeners();
      debugPrint('[fetchAllLocations] ✅ Loaded ${_locations.length} locations with durations');
    } catch (e) {
      debugPrint('[fetchAllLocations] ❌ error: $e');
    }
  }

  Future<void> startLocationUpdates({int distanceFilterMeters = 10}) async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
      debugPrint('[Location] permission denied');
      return;
    }

    _positionSub?.cancel();

    _positionSub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: distanceFilterMeters,
      ),
    ).listen((Position p) async {
      try {
        final awUser = await _account.get();
        final userId = awUser.$id;
        // id를 생성해서 넘겨줌 (임시/고유 id)
        final loc = LocationModel(
          id: ID.unique(),             // << 여기 추가
          userId: userId,
          groupId: _currentGroupId,    // 선택된 그룹이 있다면 같이 저장되도록
          lat: p.latitude,
          lng: p.longitude,
          speed: p.speed,
          heading: p.heading,
          accuracy: p.accuracy,
          timestamp: DateTime.now(),
        );
        await saveLocation(loc);
      } catch (e) {
        debugPrint('[Location stream] error: $e');
      }
    });

    debugPrint('[startLocationUpdates] started');
  }

  Future<void> stopLocationUpdates() async {
    await _positionSub?.cancel();
    _positionSub = null;
    debugPrint('[stopLocationUpdates] stopped');
  }

  Future<void> updateOnce() async {
    try {
      // ignore: deprecated_member_use
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      final awUser = await _account.get();
      final userId = awUser.$id;
      final loc = LocationModel(
        id: ID.unique(),            // << 추가
        userId: userId,
        groupId: _currentGroupId,   // 선택 그룹 포함(선택)
        lat: pos.latitude,
        lng: pos.longitude,
        speed: pos.speed,
        heading: pos.heading,
        accuracy: pos.accuracy,
        timestamp: DateTime.now(),
      );
      await saveLocation(loc);
    } catch (e) {
      debugPrint('[updateOnce] error: $e');
    }
  }

  // -------------------
  // 정리/종료
  // -------------------
  void disposeProvider() {
    debugPrint('[LocationsProvider] disposeProvider() called');

    _positionSub?.cancel();
    _positionSub = null;

    _realtimeSub?.cancel();
    _realtimeSub = null;

    _stayTimer?.cancel();
    _stayTimer = null;

    _autoSaveTimer?.cancel(); // ✅ 자동 저장 타이머도 정리
    _autoSaveTimer = null;

    // ✅ 종료 전 마지막 저장
    saveAllStayDurations();

    _locations.clear();
    _stayStartTimes.clear();
    _isStaying.clear();
    _stayDurations.clear();
    _justMovedUsers.clear();

    notifyListeners();
    debugPrint('[LocationsProvider] disposed completely');
  }

  void addDummyLocations(List<LocationModel> dummyLocations) {
    _locations.addAll({for (final l in dummyLocations) l.userId: l});
    for (final l in dummyLocations) {
      _stayDurations[l.userId] = Duration.zero;
      _stayStartTimes[l.userId] = DateTime.now();
    }
    notifyListeners();
  }

  void updateLocation(String userId, double newLat, double newLng) {
    final current = _locations[userId];
    if (current == null) return;
    final updated = current.copyWith(lat: newLat, lng: newLng, timestamp: DateTime.now());
    _locations[userId] = updated;
    _checkStayDuration(updated);
    notifyListeners();
    debugPrint('[updateLocation] $userId → (${newLat.toStringAsFixed(5)}, ${newLng.toStringAsFixed(5)})');
  }

  void resetState() {
    debugPrint('[LocationsProvider] Resetting state...');
    
    // ✅ 초기화 전 저장
    saveAllStayDurations();
    
    _locations.clear();
    _stayDurations.clear();
    _stayStartTimes.clear();
    _isStaying.clear();
    _justMovedUsers.clear();
    notifyListeners();
  }

  void resetRealtimeConnection() {
    debugPrint('[LocationsProvider] resetRealtimeConnection() called');

    // ✅ 재연결 전 저장
    saveAllStayDurations();

    // 1️⃣ 실시간 스트림 및 타이머 종료
    _realtimeSub?.cancel();
    _realtimeSub = null;

    _stayTimer?.cancel();
    _stayTimer = null;

    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;

    // 2️⃣ 로컬 데이터 초기화
    _locations.clear();
    _stayDurations.clear();
    _stayStartTimes.clear();
    _isStaying.clear();
    _justMovedUsers.clear();

    // 3️⃣ Appwrite 객체 재초기화 (재로그인 시 새 client를 쓰도록)
    _initAppwrite();

    notifyListeners();
    debugPrint('[LocationsProvider] Realtime & stay timer fully reset');
  }
}