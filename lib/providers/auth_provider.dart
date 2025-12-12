import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
import '../constants/appwrite_config.dart';
import 'package:provider/provider.dart';
import 'locations_provider.dart';

class AuthProvider {
  final Client client = Client();
  late Account account;
  late Databases databases;

  AuthProvider() {
    client
      .setEndpoint(AppwriteConstants.endpoint)
      .setProject(AppwriteConstants.projectId);
    account = Account(client);
    databases = Databases(client);
  }

  /// 서버 기반 회원가입
  Future<bool> register(
      BuildContext context, String email, String password, String name) async {
    try {
      final response = await http.post(
        Uri.parse(AppwriteConstants.register),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'name': name,
        }),
      );

      if (response.statusCode == 200) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('회원가입 성공. 이메일 확인')));

        return true;
      } else {
        final data = jsonDecode(response.body);
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['error'] ?? '회원가입 실패')));
        return false;
      }
    } catch (e) {
      debugPrint('[ERROR] register request: $e');
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('회원가입 중 오류가 발생했습니다.')));
      return false;
    }
  }

  /// 서버 기반 인증메일 전송
  Future<bool> sendVerificationEmail(String email) async {
    try {
      final response = await http.post(
        Uri.parse(AppwriteConstants.sendverification),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[ERROR] sendVerificationEmail: $e');
      return false;
    }
  }

  /// 이메일 인증 확인
  Future<bool> checkEmailVerification() async {
    try {
      final user = await account.get();
      final map = user.toMap();
      return map['emailVerification'] ?? false;
    } catch (e) {
      debugPrint('[ERROR] checkEmailVerification: $e');
      return false;
    }
  }

  /// 로그인
  Future<Map<String, dynamic>?> login(
      BuildContext context, String email, String password) async {
    try {
      // 🔹 기존 세션 완전 정리
      try {
        await account.deleteSessions(); // 모든 세션 삭제
      } catch (_) {}

      // 🔹 새 세션 생성
      await account.createEmailPasswordSession(email: email, password: password);
      final user = await account.get();

      if (!user.emailVerification) {
        await account.deleteSession(sessionId: 'current');
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이메일 인증이 완료되지 않았습니다. 이메일을 확인해주세요.')),
        );
        return null;
      }

      await ensureUserProfile(user.toMap());
      return user.toMap();
    } on AppwriteException catch (e) {
      debugPrint('[AppwriteException] login: ${e.message}');
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message ?? '로그인 실패')));
      return null;
    } catch (e) {
      debugPrint('[ERROR] login: $e');
      return null;
    }
  }

  /// ✅ users 컬렉션 존재 확인 및 자동 생성
  Future<void> ensureUserProfile(Map<String, dynamic> user) async {
    try {
      final databases = Databases(client);
      final dbId = AppwriteConstants.databaseId;
      final usersCollectionId = AppwriteConstants.usersCollectionId;

      final userId = user[r'$id'];
      final email = user['email'];
      final nickname = user['name'] ?? email.split('@').first;

      // ignore: deprecated_member_use
      final existing = await databases.listDocuments(
        databaseId: dbId,
        collectionId: usersCollectionId,
        queries: [Query.equal('userId', userId)],
      );

      if (existing.total == 0) {
        // ignore: deprecated_member_use
        await databases.createDocument(
          databaseId: dbId,
          collectionId: usersCollectionId,
          documentId: userId,
          data: {
            'userId': userId,
            'email': email,
            'nickname': nickname,
            'createdAt': DateTime.now().toIso8601String(),
          },
        );
        debugPrint('✅ users 컬렉션에 새 유저 생성됨: $email');
      }
    } catch (e) {
      debugPrint('[WARN] ensureUserProfile error: $e');
    }
  }

  /// 자동 로그인
  Future<Map<String, dynamic>?> autoLogin() async {
    try {
      final user = await account.get();

      if (user.emailVerification == false) {
        debugPrint('[INFO] autoLogin 차단: 미인증 사용자');
        return null;
      }

      await ensureUserProfile(user.toMap());
      return user.toMap();
    } catch (e) {
      debugPrint('[ERROR] autoLogin: $e');
      return null;
    }
  }

  /// 로그아웃
  Future<void> logout(BuildContext context) async {
    try {
      await account.deleteSession(sessionId: 'current');
      debugPrint('[INFO] logout: session deleted');
    } on AppwriteException catch (e) {
      final msg = e.message ?? e.toString();
      if (e.code == 401 || e.code == 403 || msg.contains('general_unauthorized_scope') || msg.contains('user_unauthorized')) {
        debugPrint('[INFO] logout: session expired - ignore: $msg');
      } else {
        debugPrint('[WARN] logout AppwriteException: $e');
      }
    } catch (e) {
      debugPrint('[WARN] logout other error: $e');
    }

    // ✅ LocationsProvider 정리
    try {
      if (context.mounted) {
        final locProv = Provider.of<LocationsProvider>(context, listen: false);
        locProv.disposeProvider();
      }
    } catch (e) {
      debugPrint('[WARN] logout disposeProvider error: $e');
    }

    // ✅ 완전 초기화
    try {
      client
        .setEndpoint(AppwriteConstants.endpoint)
        .setProject(AppwriteConstants.projectId);

      // ⚠️ SDK 내부 세션 캐시를 강제로 초기화하려면 새 Client 객체를 생성해야 함
      final newClient = Client()
        ..setEndpoint(AppwriteConstants.endpoint)
        ..setProject(AppwriteConstants.projectId);

      account = Account(newClient);
      databases = Databases(newClient);

      debugPrint('[INFO] AuthProvider fully reinitialized');
    } catch (e) {
      debugPrint('[ERROR] failed to reinitialize client/account: $e');
    }
  }
}
