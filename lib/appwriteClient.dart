// ignore: file_names
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import '../constants/appwrite_config.dart';

/// 🔹 Appwrite Client 초기화
final Client appwriteClient = Client()
  ..setEndpoint(AppwriteConstants.endpoint)
  ..setProject(AppwriteConstants.projectId)
  ..setSelfSigned(status: true); // 로컬 개발환경에서는 true로 설정

/// 🔹 주요 Appwrite 서비스 객체
final Databases appwriteDB = Databases(appwriteClient);
final Account appwriteAccount = Account(appwriteClient);
final Storage appwriteStorage = Storage(appwriteClient);
final Realtime appwriteRealtime = Realtime(appwriteClient);
final Functions appwriteFunctions = Functions(appwriteClient);

/// 🔹 로그인 상태 / 닉네임 전역 관리용 Notifier
final ValueNotifier<bool> isLoggedInNotifier = ValueNotifier(false);
final ValueNotifier<String?> nicknameNotifier = ValueNotifier(null);

/// ✅ Appwrite 환경이 잘 초기화되었는지 확인용 (디버깅에 유용)
void debugAppwriteSetup() {
  if (kDebugMode) {
    print('🟢 Appwrite Client initialized');
    print('Endpoint: ${AppwriteConstants.endpoint}');
    print('Project: ${AppwriteConstants.projectId}');
  }
}
