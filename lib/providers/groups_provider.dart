import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import '../appwriteClient.dart';
import '../constants/appwrite_config.dart';

class GroupsProvider with ChangeNotifier {
  late Databases _db;
  late Account _account;
  late Realtime _realtime;

  final List<String> _groups = [];
  RealtimeSubscription? _realtimeSub;

  List<String> get groups => List.unmodifiable(_groups);

  GroupsProvider() {
    _initAppwrite();
    fetchGroups();
    _subscribeRealtime();
  }

  void _initAppwrite() {
    _db = appwriteDB;
    _account = appwriteAccount;
    _realtime = appwriteRealtime;
  }

  /// Appwrite에서 groups 컬렉션 불러오기
  Future<void> fetchGroups() async {
    try {
      // ignore: deprecated_member_use
      final res = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.groupsCollectionId,
      );

      _groups
        ..clear()
        ..addAll(res.documents.map((d) => d.data['name']?.toString() ?? ''));
      notifyListeners();

      debugPrint('[fetchGroups] Loaded ${_groups.length} groups');
    } catch (e) {
      debugPrint('[fetchGroups] error: $e');
    }
  }

  /// 새 그룹 추가
  Future<void> addGroup(String name) async {
    if (name.trim().isEmpty) return;
    try {
      final user = await _account.get();

      // ignore: deprecated_member_use
      await _db.createDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: AppwriteConstants.groupsCollectionId,
        documentId: ID.unique(),
        data: {
          'name': name,
          'createdBy': user.$id,
          'createdAt': DateTime.now().toIso8601String(),
        },
        permissions: [
          Permission.read(Role.any()),
          Permission.update(Role.user(user.$id)),
          Permission.delete(Role.user(user.$id)),
        ],
      );

      _groups.add(name);
      notifyListeners();
      debugPrint('[addGroup] Added "$name"');
    } catch (e) {
      debugPrint('[addGroup] error: $e');
    }
  }

  /// 실시간 반영 (다른 기기에서도 반영되게)
  void _subscribeRealtime() {
    final channel =
        'databases.${AppwriteConstants.databaseId}.collections.${AppwriteConstants.groupsCollectionId}.documents';

    _realtimeSub = _realtime.subscribe([channel]);
    _realtimeSub!.stream.listen((event) {
      try {
        final type = event.events.firstOrNull ?? '';
        final payload = Map<String, dynamic>.from(event.payload);
        final name = payload['name']?.toString() ?? '';

        if (type.contains('.create') && !_groups.contains(name)) {
          _groups.add(name);
          notifyListeners();
          debugPrint('[Realtime] New group added: $name');
        } else if (type.contains('.delete')) {
          _groups.remove(name);
          notifyListeners();
          debugPrint('[Realtime] Group deleted: $name');
        }
      } catch (e) {
        debugPrint('[Realtime] error: $e');
      }
    });

    debugPrint('[Realtime] Subscribed to groups updates');
  }

  @override
  void dispose() {
    _realtimeSub?.close();
    super.dispose();
  }
}
