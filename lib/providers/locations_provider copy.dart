// // lib/providers/locations_provider.dart
// import 'dart:async';
// import 'dart:math';
// import 'package:flutter/material.dart';
// import 'package:geolocator/geolocator.dart';
// import '../appwriteClient.dart';
// import '../constants/appwrite_config.dart';
// import '../models/location_model.dart';
// import 'package:appwrite/appwrite.dart';
// import 'package:latlong2/latlong.dart';

// class LocationsProvider with ChangeNotifier {
//   // Appwrite 객체 (전역으로 제공되는 appwriteClient의 인스턴스 사용)
//   late Databases _db;
//   late Account _account;
//   late Realtime _realtime;

//   final Map<String, LocationModel> _locations = {};
//   final Map<String, DateTime> _stayStartTimes = {};
//   final Map<String, bool> _isStaying = {};
//   final Map<String, Duration> _stayDurations = {};

//   final Set<String> _justMovedUsers = {}; // 이동 직후 1회 제외용

//   StreamSubscription? _positionSub;
//   StreamSubscription? _realtimeSub;
//   Timer? _stayTimer;

//   Map<String, LocationModel> get locations => Map.unmodifiable(_locations);

//   Map<String, LocationModel> get stayingUsers {
//     final staying = <String, LocationModel>{};
//     _isStaying.forEach((userId, stay) {
//       if (stay == true && _locations.containsKey(userId)) {
//         staying[userId] = _locations[userId]!;
//       }
//     });
//     return staying;
//   }

//   LocationsProvider() {
//     _initAppwrite(); // appwrite 인스턴스 참조 설정
//     _startStayTimer();
//   }

//   // ---------- Appwrite 초기화 (login/logout 후 전역 인스턴스가 바뀌면 호출) ----------
//   void _initAppwrite() {
//     _db = appwriteDB;
//     _account = appwriteAccount;
//     _realtime = appwriteRealtime;
//   }

//   /// 로그인 성공 후 또는 재로그인 시 반드시 호출해서
//   /// fetch / realtime 구독 / 타이머 등을 정상 상태로 만든다.
//   Future<void> startAll({bool startLocationStream = false}) async {
//     // cancel existing realtime subscription so we don't double-subscribe
//     _realtimeSub?.cancel();
//     _realtimeSub = null;

//     // re-init references (in case appwrite client was re-created)
//     _initAppwrite();

//     // fetch existing docs from DB and initialize timers from stored stayDuration
//     await fetchAllLocations();

//     // start realtime subscription
//     startRealtime();

//     // restart timer if stopped
//     _startStayTimer();

//     // optionally restart device location stream if needed (called from MapPage if used)
//     if (startLocationStream) {
//       await startLocationUpdates();
//     }
//   }

//   /// 간단한 이름: 실행중인지 확인, 아니면 다시 시작
//   void ensureRunning() {
//     if (_stayTimer == null || !_stayTimer!.isActive) _startStayTimer();
//     if (_realtimeSub == null) startRealtime();
//   }

//   // -------------------
//   // 위치 오프셋 계산 (UI 표시용)
//   // -------------------
//   LocationModel _withOffset(LocationModel loc) {
//     final hash = loc.userId.hashCode;
//     final offsetMeters = (hash % 5).toDouble(); // 0~4m
//     final angle = (hash % 360) * pi / 180.0;

//     final dLat = (offsetMeters * cos(angle)) / 111111.0;
//     final dLng =
//         (offsetMeters * sin(angle)) / (111111.0 * cos(loc.lat * pi / 180));

//     return loc.copyWith(
//       lat: loc.lat + dLat,
//       lng: loc.lng + dLng,
//     );
//   }

//   Map<String, LocationModel> getDisplayLocations() {
//     final adjusted = <String, LocationModel>{};
//     for (final entry in _locations.entries) {
//       adjusted[entry.key] = _withOffset(entry.value);
//     }
//     return adjusted;
//   }

//   // -------------------
//   // 머무름 감지
//   // -------------------
//   void _checkStayDuration(LocationModel loc) {
//     final userId = loc.userId;
//     final prev = _locations[userId];

//     if (prev == null) {
//       // 처음 들어온 사용자: start now (또는 DB에서 복원된 경우 start already 세팅되어 있을 수 있음)
//       _stayStartTimes[userId] ??= DateTime.now();
//       _isStaying[userId] = false;
//       _stayDurations[userId] = Duration.zero;
//       return;
//     }

//     final distance = Geolocator.distanceBetween(
//       prev.lat,
//       prev.lng,
//       loc.lat,
//       loc.lng,
//     );

//     const stayThresholdMeters = 10.0;
//     const stayTimeMinutes = 5;

//     if (distance <= stayThresholdMeters) {
//       // 움직이지 않음 → start가 없으면 현재로 세팅
//       _stayStartTimes[userId] ??= DateTime.now();
//       final stayDuration = DateTime.now().difference(_stayStartTimes[userId]!);
//       _stayDurations[userId] = stayDuration;

//       final currentlyStaying = _isStaying[userId] ?? false;
//       if (stayDuration.inMinutes >= stayTimeMinutes && !currentlyStaying) {
//         _isStaying[userId] = true;
//         print('[Stay] $userId has stayed for ${stayDuration.inMinutes} min');
//       }
//     } else {
//       // 움직였으면 즉시 리셋
//       _stayStartTimes[userId] = DateTime.now();
//       _stayDurations[userId] = Duration.zero;
//       _isStaying[userId] = false;
//       _justMovedUsers.add(userId); // 타이머 루프에서 1회 제외
//       notifyListeners();
//       print('[resetStayDuration] $userId stay reset by move');
//     }
//   }

//   Duration? getStayDuration(String userId) => _stayDurations[userId];

//   void resetStayDuration(String userId) {
//     _stayStartTimes[userId] = DateTime.now();
//     _stayDurations[userId] = Duration.zero;
//     _isStaying[userId] = false;
//     notifyListeners();
//     print('[resetStayDuration] $userId stay reset');
//   }

//   // -------------------
//   // 사용자가 "이동" 버튼을 눌렀을 때 (UI에서 호출)
//   // -------------------
//   Future<void> onUserMove(String userId, LatLng newPos) async {
//     // 1) UI 즉시 초기화
//     _stayStartTimes[userId] = DateTime.now();
//     _stayDurations[userId] = Duration.zero;
//     _isStaying[userId] = false;
//     _justMovedUsers.add(userId);
//     notifyListeners();

//     // 2) DB에 마지막 머무름 저장 (있다면)
//     await saveLastStay(userId);

//     // 3) 로컬 위치 업데이트
//     final current = _locations[userId];
//     if (current != null) {
//       _locations[userId] = current.copyWith(
//         lat: newPos.latitude,
//         lng: newPos.longitude,
//         timestamp: DateTime.now(),
//       );
//     }

//     print('[onUserMove] $userId moved -> stay reset');
//   }

//   // -------------------
//   // DB에 마지막 머무름 기록 (Appwrite)
//   // -------------------
//   Future<void> saveLastStay(String userId) async {
//     final dur = _stayDurations[userId] ?? Duration.zero;
//     if (dur.inSeconds == 0) return;
//     try {
//       await _db.updateDocument(
//         databaseId: AppwriteConstants.databaseId,
//         collectionId: AppwriteConstants.locationsCollectionId,
//         documentId: userId,
//         data: {'stayDuration': dur.inSeconds},
//       );
//       print('[saveLastStay] $userId stayed ${dur.inSeconds}s');
//     } catch (e) {
//       print('[saveLastStay] error: $e');
//     }
//   }

//   Future<void> saveAllStayDurations() async {
//     try {
//       final futures = _locations.keys.map((userId) => saveLastStay(userId));
//       await Future.wait(futures);
//       print('[saveAllStayDurations] all saved');
//     } catch (e) {
//       print('[saveAllStayDurations] error: $e');
//     }
//   }

//   // -------------------
//   // 타이머: 1초마다 UI용 duration 갱신 (notifyListeners)
//   // -------------------
//   void _startStayTimer() {
//     _stayTimer?.cancel();
//     _stayTimer = Timer.periodic(const Duration(seconds: 1), (_) {
//       bool changed = false;
//       _locations.forEach((userId, loc) {
//         if (_justMovedUsers.contains(userId)) {
//           // 이동 직후 1회 무시 (이미 초기화되었음)
//           _justMovedUsers.remove(userId);
//           return;
//         }
//         final start = _stayStartTimes[userId];
//         if (start != null) {
//           final diff = DateTime.now().difference(start);
//           if ((_stayDurations[userId]?.inSeconds ?? -1) != diff.inSeconds) {
//             _stayDurations[userId] = diff;
//             changed = true;
//           }
//         }
//       });
//       if (changed) notifyListeners();
//     });
//   }

//   // -------------------
//   // Realtime 구독 (Appwrite)
//   // -------------------
//   void startRealtime() {
//     // cancel 기존
//     _realtimeSub?.cancel();
//     _realtimeSub = null;

//     final channel =
//         'databases.${AppwriteConstants.databaseId}.collections.${AppwriteConstants.locationsCollectionId}.documents';

//     _realtimeSub = _realtime.subscribe([channel]).stream.listen((event) {
//       try {
//         final eventType = event.events.isNotEmpty ? event.events.first : '';
//         if (eventType.contains('.delete')) {
//           final payload = Map<String, dynamic>.from(event.payload);
//           final deletedId = payload['\$id'] ?? payload['id'] ?? payload['userId'];
//           if (deletedId is String && _locations.containsKey(deletedId)) {
//             _locations.remove(deletedId);
//             _stayStartTimes.remove(deletedId);
//             _isStaying.remove(deletedId);
//             _stayDurations.remove(deletedId);
//             notifyListeners();
//             print('[Realtime] User $deletedId removed');
//           }
//           return;
//         }

//         final Map<String, dynamic> map = Map<String, dynamic>.from(event.payload);
//         final doc = map['\$data'] ?? map;
//         if (doc is! Map<String, dynamic>) return;

//         final userId = doc['userId'] ?? doc['\$id'] ?? doc['id'];
//         if (userId == null) return;

//         final loc = LocationModel.fromMap({...doc, 'userId': userId});
//         _locations[loc.userId] = loc;

//         // Realtime에서 stayDuration이 있으면 startTime을 복원해 타이머가 계속 증가하게 함
//         if (doc.containsKey('stayDuration')) {
//           try {
//             final s = doc['stayDuration'];
//             final dur = s is int ? Duration(seconds: s) : Duration(seconds: int.tryParse(s.toString()) ?? 0);
//             _stayDurations[loc.userId] = dur;
//             // 복원: startTime = now - dur
//             _stayStartTimes[loc.userId] = DateTime.now().subtract(dur);
//           } catch (_) {}
//         } else {
//           // stayDuration 없으면 기존 로직으로 체크
//           _checkStayDuration(loc);
//         }

//         // 항상 check 해주고 notify
//         _checkStayDuration(loc);
//         notifyListeners();
//         print('[Realtime] Updated location for ${loc.userId}');
//       } catch (e, st) {
//         print('[Realtime parse error] $e\n$st');
//       }
//     }, onError: (err) {
//       print('[Realtime error] $err');
//     });

//     print('[Realtime] Subscribed to location updates');
//   }

//   // -------------------
//   // 위치 저장 / 업데이트 (Appwrite)
//   // -------------------
//   Future<void> saveLocation(LocationModel loc) async {
//     final userId = loc.userId;
//     final staySec = _stayDurations[userId]?.inSeconds ?? 0;

//     final safeData = Map<String, dynamic>.from(loc.toMap())
//       ..removeWhere((key, value) => value == null)
//       ..addAll({'stayDuration': staySec});

//     try {
//       try {
//         await _db.getDocument(
//           databaseId: AppwriteConstants.databaseId,
//           collectionId: AppwriteConstants.locationsCollectionId,
//           documentId: userId,
//         );
//         await _db.updateDocument(
//           databaseId: AppwriteConstants.databaseId,
//           collectionId: AppwriteConstants.locationsCollectionId,
//           documentId: userId,
//           data: safeData,
//         );
//       } catch (_) {
//         await _db.createDocument(
//           databaseId: AppwriteConstants.databaseId,
//           collectionId: AppwriteConstants.locationsCollectionId,
//           documentId: userId,
//           data: safeData,
//           permissions: [
//             Permission.read(Role.any()),
//             Permission.update(Role.user(userId)),
//             Permission.delete(Role.user(userId)),
//           ],
//         );
//       }

//       _locations[userId] = loc;
//       _checkStayDuration(loc);
//       notifyListeners();
//       print('[saveLocation] Saved for $userId (staySec=$staySec)');
//     } catch (e) {
//       print('[saveLocation] error: $e');
//     }
//   }

//   // -------------------
//   // 전체 로드 (fetch) — 여기서 DB에 있던 stayDuration 복원 처리 추가
//   // -------------------
//   Future<void> fetchAllLocations() async {
//     try {
//       final res = await _db.listDocuments(
//         databaseId: AppwriteConstants.databaseId,
//         collectionId: AppwriteConstants.locationsCollectionId,
//       );
//       for (final d in res.documents) {
//         final map = d.data;
//         final userId = map['userId'] ?? d.$id ?? map['\$id'];
//         if (userId == null) continue;
//         final loc = LocationModel.fromMap({...map, 'userId': userId});
//         _locations[userId] = loc;

//         // 복원: DB에 stayDuration이 저장되어 있다면 startTime을 복원 => 타이머가 계속 증가하도록 함
//         if (map.containsKey('stayDuration')) {
//           try {
//             final s = map['stayDuration'];
//             final dur = s is int ? Duration(seconds: s) : Duration(seconds: int.tryParse(s.toString()) ?? 0);
//             _stayDurations[userId] = dur;
//             _stayStartTimes[userId] = DateTime.now().subtract(dur);
//           } catch (_) {
//             _stayDurations[userId] = Duration.zero;
//             _stayStartTimes[userId] = DateTime.now();
//           }
//         } else {
//           // 없으면 초기값 세팅
//           _stayDurations[userId] ??= Duration.zero;
//           _stayStartTimes[userId] ??= DateTime.now();
//         }
//       }
//       notifyListeners();
//       print('[fetchAllLocations] Loaded ${_locations.length} docs');
//     } catch (e) {
//       print('[fetchAllLocations] error: $e');
//     }
//   }

//   Future<void> startLocationUpdates({int distanceFilterMeters = 10}) async {
//     LocationPermission perm = await Geolocator.checkPermission();
//     if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
//     if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
//       print('[Location] permission denied');
//       return;
//     }

//     _positionSub?.cancel();

//     _positionSub = Geolocator.getPositionStream(
//       locationSettings: LocationSettings(
//         accuracy: LocationAccuracy.bestForNavigation,
//         distanceFilter: distanceFilterMeters,
//       ),
//     ).listen((Position p) async {
//       try {
//         final awUser = await _account.get();
//         final userId = awUser.$id;
//         final loc = LocationModel(
//           userId: userId,
//           lat: p.latitude,
//           lng: p.longitude,
//           speed: p.speed,
//           heading: p.heading,
//           accuracy: p.accuracy,
//           timestamp: DateTime.now(),
//         );
//         await saveLocation(loc);
//       } catch (e) {
//         print('[Location stream] error: $e');
//       }
//     });

//     print('[startLocationUpdates] started');
//   }

//   Future<void> stopLocationUpdates() async {
//     await _positionSub?.cancel();
//     _positionSub = null;
//     print('[stopLocationUpdates] stopped');
//   }

//   Future<void> updateOnce() async {
//     try {
//       final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
//       final awUser = await _account.get();
//       final userId = awUser.$id;
//       final loc = LocationModel(
//         userId: userId,
//         lat: pos.latitude,
//         lng: pos.longitude,
//         speed: pos.speed,
//         heading: pos.heading,
//         accuracy: pos.accuracy,
//         timestamp: DateTime.now(),
//       );
//       await saveLocation(loc);
//     } catch (e) {
//       print('[updateOnce] error: $e');
//     }
//   }

//   // -------------------
//   // 정리/종료
//   // -------------------
//   void disposeProvider() {
//     print('[LocationsProvider] disposeProvider() called');

//     _positionSub?.cancel();
//     _positionSub = null;

//     _realtimeSub?.cancel();
//     _realtimeSub = null;

//     _stayTimer?.cancel();
//     _stayTimer = null;

//     _locations.clear();
//     _stayStartTimes.clear();
//     _isStaying.clear();
//     _stayDurations.clear();
//     _justMovedUsers.clear();

//     notifyListeners();
//     print('[LocationsProvider] disposed completely');
//   }

//   void addDummyLocations(List<LocationModel> dummyLocations) {
//     _locations.addAll({for (final l in dummyLocations) l.userId: l});
//     for (final l in dummyLocations) {
//       _stayDurations[l.userId] = Duration.zero;
//       _stayStartTimes[l.userId] = DateTime.now();
//     }
//     notifyListeners();
//   }

//   void updateLocation(String userId, double newLat, double newLng) {
//     final current = _locations[userId];
//     if (current == null) return;
//     final updated = current.copyWith(lat: newLat, lng: newLng, timestamp: DateTime.now());
//     _locations[userId] = updated;
//     _checkStayDuration(updated);
//     notifyListeners();
//     print('[updateLocation] $userId → (${newLat.toStringAsFixed(5)}, ${newLng.toStringAsFixed(5)})');
//   }

//   void resetState() {
//     print('[LocationsProvider] Resetting state...');
//     _locations.clear();
//     _stayDurations.clear();
//     _stayStartTimes.clear();
//     _isStaying.clear();
//     _justMovedUsers.clear();
//     notifyListeners();
//   }

//   void resetRealtimeConnection() {
//     print('[LocationsProvider] resetRealtimeConnection() called');

//     // 1️⃣ 실시간 스트림 및 타이머 종료
//     _realtimeSub?.cancel();
//     _realtimeSub = null;

//     _stayTimer?.cancel();
//     _stayTimer = null;

//     // 2️⃣ 로컬 데이터 초기화
//     _locations.clear();
//     _stayDurations.clear();
//     _stayStartTimes.clear();
//     _isStaying.clear();
//     _justMovedUsers.clear();

//     // 3️⃣ Appwrite 객체 재초기화 (재로그인 시 새 client를 쓰도록)
//     _initAppwrite();

//     notifyListeners();
//     print('[LocationsProvider] Realtime & stay timer fully reset');
//   }
// }
