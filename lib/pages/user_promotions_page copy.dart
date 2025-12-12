// lib/pages/user_promotions_page.dart - 완전 수정 버전

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart' as latlong;
import '../providers/user_message_provider.dart';
import '../providers/locations_provider.dart';
import '../providers/shops_map_provider.dart';
import '../models/shop_models.dart';
import '../models/location_model.dart';
import '../appwriteClient.dart';
import '../constants/appwrite_config.dart';
import '../constants/shop_constants.dart';
import '../services/navigation_service.dart';
import 'package:appwrite/appwrite.dart';

class UserPromotionsPage extends StatefulWidget {
  final String userId;
  final Function(ShopModel, ShopMessageModel?)? onNavigateToShop;
  
  const UserPromotionsPage({
    super.key,
    required this.userId,
    this.onNavigateToShop,
  });

  @override
  State<UserPromotionsPage> createState() => _UserPromotionsPageState();
}

class _UserPromotionsPageState extends State<UserPromotionsPage> {
  int _selectedTab = 0; // 0: 활성, 1: 수락됨
  final Databases _db = appwriteDB;
  
  // ✅ 각 메시지별 선택된 이동 수단
  final Map<String, TransportMode> _selectedModes = {};
  
  // ✅ 각 메시지별 계산된 경로
  final Map<String, RouteResult?> _calculatedRoutes = {};
  
  @override
  void initState() {
    super.initState();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('홍보 메시지'),
        backgroundColor: Colors.deepPurple,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: () {
              final msgProvider = context.read<UserMessageProvider>();
              msgProvider.forceRefresh();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🔄 메시지 새로고침 중...'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer3<UserMessageProvider, ShopsMapProvider, LocationsProvider>(
        builder: (context, msgProvider, shopsProvider, locProvider, _) {
          return Column(
            children: [
              // ✅ 탭 바 - 활성 메시지 카운트도 추가
              Container(
                color: Colors.deepPurple,
                child: Row(
                  children: [
                    Expanded(
                      child: _buildTab(
                        label: '활성 메시지',
                        count: msgProvider.activeMessages.length,  // ✅ 카운트 추가
                        selected: _selectedTab == 0,
                        onTap: () => setState(() => _selectedTab = 0),
                      ),
                    ),
                    Expanded(
                      child: _buildTab(
                        label: '수락됨',
                        count: msgProvider.acceptedMessageIds.length,  // ✅ 카운트
                        selected: _selectedTab == 1,
                        onTap: () => setState(() => _selectedTab = 1),
                      ),
                    ),
                  ],
                ),
              ),
              
              // ✅ 콘텐츠
              Expanded(
                child: _selectedTab == 0
                    ? _buildActiveMessages(msgProvider, locProvider)
                    : _buildAcceptedMessages(msgProvider, locProvider),
              ),
            ],
          );
        },
      ),
    );
  }
  
  // ✅ 탭 버튼
  Widget _buildTab({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? Colors.white : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
              Text(
                '$count개',
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // ✅ 활성 메시지 목록
  Widget _buildActiveMessages(
    UserMessageProvider msgProvider,
    LocationsProvider locProvider,
  ) {
    if (msgProvider.activeMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_off, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              '활성 메시지가 없습니다',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '반경 내 가게의 홍보 메시지가 표시됩니다',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: msgProvider.activeMessages.length,
      itemBuilder: (context, index) {
        final msg = msgProvider.activeMessages[index];
        
        return _buildActiveMessageCard(
          msg,
          msgProvider,
          locProvider,
        );
      },
    );
  }
  
  // ✅ 활성 메시지 카드
  Widget _buildActiveMessageCard(
    ShopMessageModel msg,
    UserMessageProvider msgProvider,
    LocationsProvider locProvider,
  ) {
    final remainingTime = msg.remainingTime;
    final isExpiringSoon = remainingTime.inMinutes < 30;
    
    return FutureBuilder<ShopModel?>(
      future: msgProvider.getShop(msg.shopId),
      builder: (context, shopSnapshot) {
        if (!shopSnapshot.hasData) {
          return const SizedBox.shrink();
        }
        
        final shop = shopSnapshot.data!;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isExpiringSoon ? Colors.red[100]! : Colors.deepPurple[100]!,
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.deepPurple,
                      child: Text(
                        shop.shopName[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shop.shopName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            shop.category,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // 메시지
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.campaign, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          msg.message,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // 정보
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      _formatRemainingTime(remainingTime),
                      style: TextStyle(
                        fontSize: 12,
                        color: isExpiringSoon ? Colors.red : Colors.grey[600],
                        fontWeight: isExpiringSoon ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '${msg.radius}m 이내',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // ✅ 액션 버튼
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          msgProvider.dismissMessage(msg.messageId);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('메시지가 무시되었습니다')),
                          );
                        },
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('무시'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey,
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _showAcceptedMessageDetail(
                            msg,
                            shop,
                            locProvider,
                            msgProvider,
                          );
                        },
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('수락'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
        );
      },
    );
  }
  
  // ✅ 수락된 메시지 목록
  Widget _buildAcceptedMessages(
    UserMessageProvider msgProvider,
    LocationsProvider locProvider,
  ) {
    return FutureBuilder<List<ShopMessageModel>>(
      future: _getAcceptedMessages(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, size: 80, color: Colors.green[300]),
                const SizedBox(height: 16),
                Text(
                  '수락된 메시지가 없습니다',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }
        
        final acceptedMessages = snapshot.data!;
        
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: acceptedMessages.length,
          itemBuilder: (context, index) {
            final msg = acceptedMessages[index];
            return _buildAcceptedMessageCard(msg, locProvider, msgProvider);
          },
        );
      },
    );
  }

  Widget _buildAcceptedMessageCard(
    ShopMessageModel msg,
    LocationsProvider locProvider,
    UserMessageProvider msgProvider,
  ) {
    final myLocation = locProvider.locations[widget.userId];
    final selectedMode = _selectedModes[msg.messageId] ?? TransportMode.driving;
    
    return FutureBuilder<ShopModel?>(
      future: _getShop(msg.shopId),
      builder: (context, shopSnapshot) {
        if (!shopSnapshot.hasData) {
          return const SizedBox.shrink();
        }
        
        final shop = shopSnapshot.data!;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.green[100]!, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shop.shopName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            msg.message,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 24,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // ✅ 이동 수단 선택 (3개 버튼)
                const Text(
                  '이동 수단 선택',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                
                const SizedBox(height: 12),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildTransportModeButton(
                      icon: Icons.directions_car,
                      label: '자동차',
                      mode: TransportMode.driving,
                      isSelected: selectedMode == TransportMode.driving,
                      onTap: () async {
                        setState(() {
                          _selectedModes[msg.messageId] = TransportMode.driving;
                        });
                        
                        if (myLocation != null) {
                          await _calculateRoute(
                            msg,
                            shop,
                            myLocation,
                            TransportMode.driving,
                          );
                        }
                      },
                    ),
                    _buildTransportModeButton(
                      icon: Icons.directions_walk,
                      label: '도보',
                      mode: TransportMode.walking,
                      isSelected: selectedMode == TransportMode.walking,
                      onTap: () async {
                        setState(() {
                          _selectedModes[msg.messageId] = TransportMode.walking;
                        });
                        
                        if (myLocation != null) {
                          await _calculateRoute(
                            msg,
                            shop,
                            myLocation,
                            TransportMode.walking,
                          );
                        }
                      },
                    ),
                    _buildTransportModeButton(
                      icon: Icons.directions_bike,
                      label: '자전거',
                      mode: TransportMode.cycling,
                      isSelected: selectedMode == TransportMode.cycling,
                      onTap: () async {
                        setState(() {
                          _selectedModes[msg.messageId] = TransportMode.cycling;
                        });
                        
                        if (myLocation != null) {
                          await _calculateRoute(
                            msg,
                            shop,
                            myLocation,
                            TransportMode.cycling,
                          );
                        }
                      },
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // ✅ 경로 정보
                if (_calculatedRoutes[msg.messageId] != null)
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info, color: Colors.blue[700]),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_calculatedRoutes[msg.messageId]!.transportModeString} · ${_calculatedRoutes[msg.messageId]!.formattedDuration}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[700],
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    _calculatedRoutes[msg.messageId]!.formattedDistance,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                
                // ✅ 길찾기 시작 버튼 - UI 자동 종료 추가
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      debugPrint('');
                      debugPrint('🚀 ════════════════════ 길찾기 시작 ════════════════════');
                      debugPrint('📌 메시지: "${msg.message}"');
                      debugPrint('🏪 가게: ${shop.shopName}');
                      
                      try {
                        // ✅ 메시지 수락
                        if (!msgProvider.acceptedMessageIds.contains(msg.messageId)) {
                          await msgProvider.acceptMessage(
                            msg,
                            myLocation!.lat,
                            myLocation.lng,
                          );
                        }
                        
                        // ✅ 길찾기 콜백 실행
                        if (widget.onNavigateToShop != null) {
                          widget.onNavigateToShop!(shop, msg);
                        }
                        
                        // ✅ UI 자동 종료 (현재 홍보 메시지 페이지)
                        if (mounted) {
                          Navigator.pop(context);
                          debugPrint('✅ 길찾기 실행 완료 - UI 자동 종료');
                        }
                        
                        debugPrint('🚀 ════════════════════ 길찾기 완료 ════════════════════');
                        debugPrint('');
                        
                      } catch (e) {
                        debugPrint('❌ 길찾기 오류: $e');
                      }
                    },
                    icon: const Icon(Icons.navigation),
                    label: const Text('길찾기 시작'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ✅ 수락된 메시지 상세 뷰 (BottomSheet)
  void _showAcceptedMessageDetail(
    ShopMessageModel msg,
    ShopModel shop,
    LocationsProvider locProvider,
    UserMessageProvider? msgProvider,
  ) {
    final myLocation = locProvider.locations[widget.userId];
    bool isBottomSheetOpen = true; // ✅ BottomSheet 상태 추적
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          child: Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ... 헤더와 메시지 코드 동일 ...
                
                // ✅ 길찾기 버튼 개선
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      debugPrint('');
                      debugPrint('🚀 ════════════════════ 길찾기 시작 ════════════════════');
                      debugPrint('📌 메시지: "${msg.message}"');
                      debugPrint('🏪 가게: ${shop.shopName}');
                      
                      try {
                        // ✅ Step 1: 메시지 수락 (이미 수락한 경우 스킵)
                        if (msgProvider != null && !msgProvider.acceptedMessageIds.contains(msg.messageId)) {
                          debugPrint('⏳ Step 1: 메시지 수락 중...');
                          await msgProvider.acceptMessage(
                            msg,
                            myLocation!.lat,
                            myLocation.lng,
                          );
                          debugPrint('✅ Step 1: 메시지 수락 완료');
                        }
                        
                        // ✅ Step 2: 길찾기 콜백 실행
                        debugPrint('⏳ Step 2: 길찾기 실행 중...');
                        if (widget.onNavigateToShop != null) {
                          debugPrint('   콜백 함수 호출: widget.onNavigateToShop!()');
                          widget.onNavigateToShop!(shop, msg);
                          debugPrint('✅ Step 2: 길찾기 실행 완료');
                        } else {
                          debugPrint('❌ onNavigateToShop 콜백이 null');
                        }
                        
                        // ✅ Step 3: UI 종료 (BottomSheet 닫기)
                        debugPrint('⏳ Step 3: UI 종료 중...');
                        
                        if (mounted && isBottomSheetOpen) {
                          Navigator.pop(context); // BottomSheet 닫기
                          isBottomSheetOpen = false;
                          
                          // 약간의 딜레이 후 홍보 메시지 페이지도 닫기
                          Future.delayed(const Duration(milliseconds: 300), () {
                            if (mounted) {
                              Navigator.pop(context); // 홍보 메시지 페이지 닫기
                              debugPrint('✅ Step 3: UI 종료 완료');
                            }
                          });
                        }
                        
                        debugPrint('🚀 ════════════════════ 길찾기 완료 ════════════════════');
                        debugPrint('');
                        
                      } catch (e) {
                        debugPrint('❌ 길찾기 실행 오류: $e');
                      }
                    },
                    icon: const Icon(Icons.navigation),
                    label: const Text('길찾기 시작'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      isBottomSheetOpen = false;
    });
  }
  
  // ✅ 이동 수단 선택 버튼
  Widget _buildTransportModeButton({
    required IconData icon,
    required String label,
    required TransportMode mode,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.deepPurple : Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Colors.deepPurple : Colors.grey[300]!,
                width: 2,
              ),
            ),
            child: Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[600],
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.deepPurple : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
  
  // ✅ 경로 계산
  Future<void> _calculateRoute(
    ShopMessageModel msg,
    ShopModel shop,
    LocationModel myLocation,
    TransportMode mode,
  ) async {
    try {
      debugPrint('🚗 경로 계산: ${mode.toString()}');
      
      final navigationService = NavigationService();
      final route = await navigationService.getRoute(
        start: latlong.LatLng(myLocation.lat, myLocation.lng),
        end: latlong.LatLng(shop.lat, shop.lng),
        mode: mode,
      );
      
      // ✅ mounted 체크 (BottomSheet가 닫혀도 setState 호출하지 않기)
      if (!mounted) {
        debugPrint('⚠️  위젯이 마운트되지 않음 (무시)');
        return;
      }
      
      if (route != null) {
        _calculatedRoutes[msg.messageId] = route;
        
        debugPrint('✅ 경로 계산 완료');
        debugPrint('   거리: ${route.formattedDistance}');
        debugPrint('   시간: ${route.formattedDuration}');
      }
    } catch (e) {
      debugPrint('❌ 경로 계산 실패: $e');
    }
  }
  
  // ✅ 수락된 메시지 조회
  Future<List<ShopMessageModel>> _getAcceptedMessages() async {
    try {
      final result = await _db.listDocuments(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.messageAcceptancesCollectionId,
        queries: [
          Query.equal('userId', widget.userId),
          Query.notEqual('dismissed', true),
        ],
      );
      
      final acceptedMessages = <ShopMessageModel>[];
      
      for (final doc in result.documents) {
        final messageId = doc.data['messageId'];
        
        try {
          final msgDoc = await _db.getDocument(
            databaseId: AppwriteConstants.databaseId,
            collectionId: ShopConstants.shopMessagesCollectionId,
            documentId: messageId,
          );
          
          final msg = ShopMessageModel.fromJson(msgDoc.data, msgDoc.$id);
          acceptedMessages.add(msg);
        } catch (e) {
          debugPrint('⚠️  메시지 조회 실패: $messageId');
        }
      }
      
      return acceptedMessages;
    } catch (e) {
      debugPrint('❌ 수락된 메시지 조회 실패: $e');
      return [];
    }
  }
  
  // ✅ 샵 정보 조회
  Future<ShopModel?> _getShop(String shopId) async {
    try {
      final doc = await _db.getDocument(
        databaseId: AppwriteConstants.databaseId,
        collectionId: ShopConstants.shopsCollectionId,
        documentId: shopId,
      );
      
      return ShopModel.fromJson(doc.data, doc.$id);
    } catch (e) {
      debugPrint('❌ 샵 조회 실패: $e');
      return null;
    }
  }
  
  // ✅ 남은 시간 포맷
  String _formatRemainingTime(Duration d) {
    if (d.inSeconds <= 0) return '곧 만료';
    
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    
    if (hours > 0) {
      return '$hours시간 $minutes분 남음';
    } else {
      return '$minutes분 남음';
    }
  }
}