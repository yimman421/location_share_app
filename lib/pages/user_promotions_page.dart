import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_message_provider.dart';
import '../providers/locations_provider.dart';
import '../models/shop_models.dart';

class UserPromotionsPage extends StatefulWidget {
  final String userId;
  final Function(ShopModel, ShopMessageModel?) onNavigateToShop;
  
  const UserPromotionsPage({
    super.key,
    required this.userId,
    required this.onNavigateToShop,
  });

  @override
  State<UserPromotionsPage> createState() => _UserPromotionsPageState();
}

class _UserPromotionsPageState extends State<UserPromotionsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    // ✅ 초기값은 0 (활성 메시지 탭)
    _tabController = TabController(length: 3, vsync: this, initialIndex: 0);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ✅ 수락됨 탭으로 이동
  void _switchToAcceptedTab() {
    debugPrint('🔄 수락됨 탭으로 이동');
    _tabController.animateTo(1, duration: const Duration(milliseconds: 300));
  }

  // ✅ 최신순으로 정렬 (DESC)
  List<ShopMessageModel> _sortByLatest(List<ShopMessageModel> messages) {
    final sorted = List<ShopMessageModel>.from(messages);
    sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('홍보 메시지'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.mail), text: '활성'),
            Tab(icon: Icon(Icons.check_circle), text: '수락됨'),
            Tab(icon: Icon(Icons.block), text: '무시됨'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ✅ 탭 1: 활성 메시지
          _buildActiveMessagesTab(),
          
          // ✅ 탭 2: 수락된 메시지
          _buildAcceptedMessagesTab(),
          
          // ✅ 탭 3: 무시된 메시지
          _buildDismissedMessagesTab(),
        ],
      ),
    );
  }

  // ✅ 활성 메시지 탭 (최신순)
  Widget _buildActiveMessagesTab() {
    return Consumer<UserMessageProvider>(
      builder: (context, provider, _) {
        final sortedMessages = _sortByLatest(provider.activeMessages);
        
        if (sortedMessages.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mail_outline, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  '활성 메시지가 없습니다',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: sortedMessages.length,
          itemBuilder: (context, index) {
            final message = sortedMessages[index];
            return _buildMessageCard(
              message: message,
              onAccept: (shop) async {
                final locProvider = context.read<LocationsProvider>();
                final myLocation = locProvider.locations[widget.userId];
                
                if (myLocation != null) {
                  await provider.acceptMessage(
                    message,
                    myLocation.lat,
                    myLocation.lng,
                  );
                  _switchToAcceptedTab();
                }
              },
              onDismiss: () {
                provider.dismissMessage(message.messageId);
              },
            );
          },
        );
      },
    );
  }

  // ✅ 수락된 메시지 탭 (최신순, 새로고침 없음)
  Widget _buildAcceptedMessagesTab() {
    return Consumer<UserMessageProvider>(
      builder: (context, provider, _) {
        debugPrint('📊 수락된 메시지 탭 빌드: ${provider.acceptedMessages.length}개');
        
        if (provider.acceptedMessages.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  '수락된 메시지가 없습니다',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),
          );
        }
        
        // ✅ 최신순 정렬
        final sortedMessages = _sortByLatest(provider.acceptedMessages);
        
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: sortedMessages.length,
          itemBuilder: (context, index) {
            final message = sortedMessages[index];
            return _buildAcceptedMessageCard(
              message: message,
              onNavigate: (shop) {
                widget.onNavigateToShop(shop, message);
                Navigator.pop(context);
              },
              onDismiss: () {
                provider.dismissMessage(message.messageId);
              },
            );
          },
        );
      },
    );
  }

  // ✅ 무시된 메시지 탭 (최신순)
  Widget _buildDismissedMessagesTab() {
    return Consumer<UserMessageProvider>(
      builder: (context, provider, _) {
        // ✅ provider.dismissedMessageIds가 있으면 fetchDismissedMessagesForUI() 호출
        if (provider.dismissedMessageIds.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  '무시된 메시지가 없습니다',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),
          );
        }
        
        // ✅ FutureBuilder로 메시지 정보 동적 로드
        return FutureBuilder<List<ShopMessageModel>>(
          future: provider.fetchDismissedMessagesForUI(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(
                child: Text(
                  '무시된 메시지가 없습니다',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }
            
            final dismissedMessages = _sortByLatest(snapshot.data!);
            
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: dismissedMessages.length,
              itemBuilder: (context, index) {
                final message = dismissedMessages[index];
                return _buildDismissedMessageCard(
                  message: message,
                  onRestore: () {
                    final locProvider = context.read<LocationsProvider>();
                    final myLocation = locProvider.locations[widget.userId];
                    
                    if (myLocation != null) {
                      provider.acceptMessage(
                        message,
                        myLocation.lat,
                        myLocation.lng,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${message.message} 메시지를 수락했습니다'),
                        ),
                      );
                      
                      // ✅ 수락됨 탭으로 자동 이동
                      _switchToAcceptedTab();
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // ✅ 활성 메시지 카드
  Widget _buildMessageCard({
    required ShopMessageModel message,
    required Function(ShopModel) onAccept,
    required VoidCallback onDismiss,
  }) {
    return FutureBuilder<ShopModel?>(
      future: context.read<UserMessageProvider>().getShop(message.shopId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        
        final shop = snapshot.data!;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.deepPurple.shade100, width: 2),
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
                      backgroundColor: Colors.deepPurple,
                      child: Icon(
                        _getCategoryIcon(shop.category),
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
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
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                
                // 메시지 내용
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    message.message,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // 정보
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      _formatRemainingTime(message.remainingTime),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.place, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '${message.radius}m 이내',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // 액션 버튼
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onDismiss,
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('무시'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () => onAccept(shop),
                        icon: const Icon(Icons.check_circle, size: 18),
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
          ),
        );
      },
    );
  }

  // ✅ 수락된 메시지 카드 (이동 수단 선택 기능 포함)
  Widget _buildAcceptedMessageCard({
    required ShopMessageModel message,
    required Function(ShopModel) onNavigate,
    required VoidCallback onDismiss,
  }) {
    return FutureBuilder<ShopModel?>(
      future: context.read<UserMessageProvider>().getShop(message.shopId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        
        final shop = snapshot.data!;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.green, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 24),
                    const SizedBox(width: 8),
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
                            '수락됨 • ${shop.category}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                
                // 메시지 내용
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    message.message,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // ✅ 길찾기 버튼만 유지 (이동수단 선택 제거)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => onNavigate(shop),
                        icon: const Icon(Icons.navigation, size: 18),
                        label: const Text('길찾기'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 무시 버튼
                    SizedBox(
                      width: 50,
                      child: OutlinedButton.icon(
                        onPressed: onDismiss,
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text(''),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ✅ 무시된 메시지 카드
  Widget _buildDismissedMessageCard({
    required ShopMessageModel message,
    required VoidCallback onRestore,
  }) {
    return FutureBuilder<ShopModel?>(
      future: context.read<UserMessageProvider>().getShop(message.shopId),
      builder: (context, snapshot) {
        final shop = snapshot.data;
        //final provider = context.read<UserMessageProvider>();
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.grey, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더
                Row(
                  children: [
                    const Icon(Icons.block, color: Colors.grey, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shop?.shopName ?? message.shopName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '무시됨 ${shop != null ? '• ${shop.category}' : ''}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                
                // 메시지 내용
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    message.message,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // ✅ 복구 버튼 (수정됨)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      debugPrint('');
                      debugPrint('🔄 ════════════════════ 메시지 복구 시작 ════════════════════');
                      debugPrint('📌 메시지 ID: ${message.messageId}');
                      debugPrint('📌 메시지: ${message.message}');
                      
                      // ✅ Step 1: 현재 위치 가져오기
                      final locProvider = context.read<LocationsProvider>();
                      final myLocation = locProvider.locations[widget.userId];
                      
                      if (myLocation == null) {
                        debugPrint('❌ 현재 위치를 확인할 수 없습니다');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('현재 위치를 확인할 수 없습니다')),
                          );
                        }
                        return;
                      }
                      
                      debugPrint('✅ 현재 위치: (${myLocation.lat}, ${myLocation.lng})');
                      
                      // ✅ Step 2: 무시된 상태 제거 (dismissedMessageIds에서 제거)
                      final msgProvider = context.read<UserMessageProvider>();
                      
                      // dismissedMessageIds에서 제거
                      msgProvider.dismissedMessageIds.remove(message.messageId);
                      debugPrint('✅ dismissedMessageIds에서 제거');
                      
                      // ✅ Step 3: 메시지 수락 (acceptedMessages에 추가)
                      await msgProvider.acceptMessage(
                        message,
                        myLocation.lat,
                        myLocation.lng,
                      );
                      
                      debugPrint('✅ 메시지 수락 완료');
                      debugPrint('🔄 ════════════════════ 메시지 복구 완료 ════════════════════');
                      debugPrint('');
                      
                      if (mounted) {
                        // ✅ Step 4: 수락됨 탭으로 자동 이동
                        _switchToAcceptedTab();
                        
                        // ignore: use_build_context_synchronously
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✅ ${message.message} 메시지를 수락했습니다'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('수락으로 복구'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
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

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case '음식점': return Icons.restaurant;
      case '카페': return Icons.local_cafe;
      case '의류': return Icons.checkroom;
      case '편의점': return Icons.store;
      case '미용': return Icons.content_cut;
      case '문화/공연': return Icons.theater_comedy;
      default: return Icons.store;
    }
  }
  
  String _formatRemainingTime(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    
    if (hours > 0) {
      return '$hours시간 $minutes분 남음';
    } else if (minutes > 0) {
      return '$minutes분 남음';
    } else {
      return '곧 만료';
    }
  }
}