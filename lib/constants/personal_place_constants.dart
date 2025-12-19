class PersonalPlaceConstants {
  // ✅ 컬렉션 ID
  static const String personalPlacesCollectionId = 'personal_places';
  
  // ✅ 사전 정의된 카테고리
  static const List<String> predefinedCategories = [
    '집',
    '회사',
    '학교',
    '맛집',
    '카페',
    '병원',
    '자주 가는 곳',
    '기타',
  ];
  
  // ✅ 카테고리 아이콘 매핑
  static const Map<String, String> categoryIcons = {
    '집': '🏠',
    '회사': '🏢',
    '학교': '🏫',
    '맛집': '🍽️',
    '카페': '☕',
    '병원': '🏥',
    '자주 가는 곳': '⭐',
    '기타': '📍',
  };
  
  // ✅ 커스텀 카테고리 표시
  static const String customCategoryLabel = '직접 입력';
}