class ShopConstants {
  // ✅ 새로운 컬렉션 ID들
  static const String shopsCollectionId = 'shops'; // 샵 정보
  static const String shopMessagesCollectionId = 'shop_messages'; // 샵 메시지
  static const String messageAcceptancesCollectionId = 'message_acceptances'; // 수락 기록
  static const String meetingGroupsCollectionId = 'meeting_groups'; // 모임 그룹
  
  // ✅ 반경 옵션 (미터)
  static const List<int> radiusOptions = [100, 200, 300, 500, 1000, 30000];
  
  // ✅ 유효시간 옵션 (시간)
  static const List<int> validityOptions = [1, 3, 6, 12, 24, 72];
  
  // ✅ 샵 카테고리
  static const List<String> shopCategories = [
    '음식점',
    '카페',
    '의류',
    '편의점',
    '미용',
    '문화/공연',
    '기타',
  ];
  
  // ✅ 메시지 타입
  static const String messageTypePromotion = 'promotion'; // 일반 홍보
  static const String messageTypeMeeting = 'meeting'; // 모임 대상
}
