class AppwriteConstants {
  // Appwrite 설정
  //static const String ipaddress = 'http://172.20.64.126';
  static const String ipaddress = 'http://vranks.iptime.org:8888';
  static const String endpoint = '$ipaddress/v1';
  static const String register = '$ipaddress/register';
  static const String emailverification = '$ipaddress/email_verification.html';
  static const String sendverification = '$ipaddress/send-verification';
  static const String projectId = '684a32e40002f3045e7f';
  //static const String apiKey ='standard_adf773effb8e139e497bd4a79268e3dcbf472b92d152ef03329aeed9bfa8fe09cfd6df5fcfe3a4a62144f883439a4b9dc628ee1d46b1bdb6232d789c1620a79bbb565c57a92b045c1f5359bff0e34ead86f2cbab3b34bc1496a460506a17ca451a806563528bcc0b0771616a632cccbd8632ef463312777eca924548647151e8'; // only for backend-safe ops

  // 데이터베이스 ID들
  static const String databaseId = '684bb9e1002e1351c440';
  static const String usersCollectionId = '685e5b8400138283e473';
  static const String messagesCollectionId = '684bb9f8000aaa8881b7';
  static const String acceptedUsersCollectionId = '684f77a00022a737afe8';
  static const String locationsCollectionId = 'locations';
  static const String groupsCollectionId = 'groups';
  static const String peoplesCollectionId = 'peoples';

  // ✅ 샵 관련 컬렉션들
  static const String shopsCollectionId = 'shops';
  static const String shopMessagesCollectionId = 'shop_messages';
  static const String messageAcceptancesCollectionId = 'message_acceptances';
  static const String meetingGroupsCollectionId = 'meeting_groups';

  // ✅ 개인 장소 컬렉션 (새로 추가)
  static const String personalPlacesCollectionId = 'personal_places';

  // ✅ Appwrite Function IDs
  static const String addressFunctionId = '6930eee1001f0ef3c9ed'; // ✅ Function ID 설정 필요

  // ✅ 시간 제한 그룹 컬렉션
  static const String tempGroupsCollectionId = 'temp_groups';
  static const String tempGroupMembersCollectionId = 'temp_group_members';
  static const String tempGroupInvitesCollectionId = 'temp_group_invites';
  
  // 나중에 추가될 컬렉션 (Phase 2, 3)
  static const String tempGroupMessagesCollectionId = 'temp_group_messages';
  static const String tempGroupExtensionsCollectionId = 'temp_group_extensions';
}

// 라우트 이름들
class AppRoutes {
  static const String main = '/';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String user = '/user';
  static const String ownerMessages = '/owner-messages';
}
/*
shop_owner_screen.dart
owner_message_detail_screen.dart
user_screen.dart
map_view.dart
*/