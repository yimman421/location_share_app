import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import '../constants/appwrite_config.dart';

class AppwriteService {
  static final AppwriteService _instance = AppwriteService._internal();
  factory AppwriteService() => _instance;
  AppwriteService._internal();

  late final Client client;
  late final Account account;
  late final Databases databases;
  late final Realtime realtime;

  static const String endpoint = AppwriteConstants.endpoint;
  static const String projectId = AppwriteConstants.projectId;
  static const String databaseId = AppwriteConstants.databaseId;

  final String usersCollectionId = AppwriteConstants.usersCollectionId;
  final String locationsCollectionId = AppwriteConstants.locationsCollectionId;
  final String groupsCollectionId = AppwriteConstants.groupsCollectionId;
  final String messagesCollectionId = AppwriteConstants.messagesCollectionId;

  void init() {
    client = Client()
      ..setEndpoint(endpoint)
      ..setProject(projectId)
      ..setSelfSigned(status: true);
    account = Account(client);
    databases = Databases(client);
    realtime = Realtime(client);
  }

  // -------- 기존 회원가입 / 로그인 --------------
  Future<User> registerAccount(String email, String password, String name) async {
    final user = await account.create(userId: ID.unique(), email: email, password: password, name: name);
    final data = {
      'userId': user.$id,
      'email': user.email,
      'name': user.name,
      'nickname': user.name,
      'profileImage': '',
      'lastSeen': DateTime.now().toIso8601String(),
    };
    // ignore: deprecated_member_use
    await databases.createDocument(
      databaseId: databaseId,
      collectionId: usersCollectionId,
      documentId: user.$id,
      data: data,
    );
    await account.createEmailVerification(url: 'https://yourappdomain.com/verify');
    return user;
  }

  Future<Map<String, dynamic>> loginAccount(String email, String password) async {
    try {
      await account.deleteSession(sessionId: 'current');
    } catch (e) {
      // 세션이 없으면 무시
    }
    await account.createEmailPasswordSession(email: email, password: password);
    final user = await account.get();
    try {
      // ignore: deprecated_member_use
      final doc = await databases.getDocument(
          databaseId: databaseId, collectionId: usersCollectionId, documentId: user.$id);
      return {'account': user, 'profile': doc.data};
    } catch (_) {
      final data = {
        'userId': user.$id,
        'email': user.email,
        'name': user.name,
        'nickname': user.name,
        'profileImage': '',
        'lastSeen': DateTime.now().toIso8601String(),
      };
      // ignore: deprecated_member_use
      await databases.createDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: user.$id,
        data: data,
      );
      return {'account': user, 'profile': data};
    }
  }

  Future<User> getCurrentAccount() async => await account.get();

  // -------- 위치 관련 기능 ----------------
  Future<void> saveLocation(String userId, double lat, double lng) async {
    // ignore: deprecated_member_use
    await databases.createDocument(
      databaseId: databaseId,
      collectionId: locationsCollectionId,
      documentId: ID.unique(),
      data: {
        'userId': userId,
        'latitude': lat,
        'longitude': lng,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  RealtimeSubscription subscribeToLocations(Function(Map<String, dynamic>) onChange) {
    final subscription = realtime.subscribe([
      'databases.$databaseId.collections.$locationsCollectionId.documents',
    ]);
    subscription.stream.listen((event) {
      if (event.payload.isNotEmpty) {
        onChange(event.payload);
      }
    });
    return subscription;
  }

  // -------- 그룹 관련 기능 ----------------
  Future<List<Document>> getGroupsForUser(String userId) async {
    // ignore: deprecated_member_use
    final result = await databases.listDocuments(
      databaseId: databaseId,
      collectionId: groupsCollectionId,
      queries: [Query.equal('members', userId)],
    );
    return result.documents;
  }

  // -------- 채팅 관련 기능 ----------------
  Future<void> sendMessage(String groupId, String userId, String text) async {
    // ignore: deprecated_member_use
    await databases.createDocument(
      databaseId: databaseId,
      collectionId: messagesCollectionId,
      documentId: ID.unique(),
      data: {
        'groupId': groupId,
        'userId': userId,
        'text': text,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
  }

  RealtimeSubscription subscribeToMessages(String groupId, Function(Map<String, dynamic>) onMessage) {
    final subscription = realtime.subscribe([
      'databases.$databaseId.collections.$messagesCollectionId.documents',
    ]);
    subscription.stream.listen((event) {
      if (event.payload.isNotEmpty && event.payload['groupId'] == groupId) {
        onMessage(event.payload);
      }
    });
    return subscription;
  }
}
