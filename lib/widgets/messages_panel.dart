import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_message_provider.dart';
import '../providers/locations_provider.dart';
import '../models/shop_models.dart';

class MessagesPanel extends StatelessWidget {
  final String userId;
  final Function(ShopModel, ShopMessageModel) onNavigateToShop;
  
  const MessagesPanel({
    super.key,
    required this.userId,
    required this.onNavigateToShop,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<UserMessageProvider>(
      builder: (context, provider, _) {
        if (provider.activeMessages.isEmpty) {
          return const SizedBox.shrink();
        }
        
        return Positioned(
          top: 16,
          right: 16,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 350),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 메시지 개수 표시
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.notifications_active,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '새 메시지 ${provider.activeMessages.length}개',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                
                // 메시지 카드들
                ...provider.activeMessages.take(3).map((msg) {
                  return _MessageCard(
                    message: msg,
                    userId: userId,
                    onNavigate: (shop) => onNavigateToShop(shop, msg),
                  );
                }),
                
                // 더보기 버튼
                if (provider.activeMessages.length > 3)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    child: TextButton.icon(
                      onPressed: () => _showAllMessages(context, provider),
                      icon: const Icon(Icons.expand_more),
                      label: Text(
                        '+${provider.activeMessages.length - 3}개 더보기',
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.deepPurple,
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
  
  void _showAllMessages(BuildContext context, UserMessageProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.deepPurple,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '받은 메시지',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: provider.activeMessages.length,
                  itemBuilder: (context, index) {
                    final msg = provider.activeMessages[index];
                    return _MessageCard(
                      message: msg,
                      userId: userId,
                      onNavigate: (shop) {
                        Navigator.pop(context);
                        onNavigateToShop(shop, msg);
                      },
                      expanded: true,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final ShopMessageModel message;
  final String userId;
  final Function(ShopModel) onNavigate;
  final bool expanded;
  
  const _MessageCard({
    required this.message,
    required this.userId,
    required this.onNavigate,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ShopModel?>(
      future: context.read<UserMessageProvider>().getShop(message.shopId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        
        final shop = snapshot.data!;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 4,
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
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () {
                        context
                            .read<UserMessageProvider>()
                            .dismissMessage(message.messageId);
                      },
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
                
                // ✅ 액션 버튼 (길찾기 버튼으로 자동 수락)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          context
                              .read<UserMessageProvider>()
                              .dismissMessage(message.messageId);
                        },
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
                        onPressed: () async { // ✅ async 추가
                          debugPrint('🚀 메시지 패널 길찾기 클릭');
                          
                          try {
                            final msgProvider = context.read<UserMessageProvider>();
                            final locProvider = context.read<LocationsProvider>();
                            
                            final myLocation = locProvider.locations[userId];
                            if (myLocation == null) {
                              debugPrint('❌ 현재 위치 없음');
                              return;
                            }
                            
                            // ✅ 메시지 수락
                            await msgProvider.acceptMessage(
                              message,
                              myLocation.lat,
                              myLocation.lng,
                            );
                            
                            debugPrint('✅ 메시지 수락 완료');
                            
                            // ✅ await 추가
                            await onNavigate(shop);
                            
                            debugPrint('✅ 길찾기 완료');
                            
                          } catch (e) {
                            debugPrint('❌ 오류: $e');
                          }
                        },
                        icon: const Icon(Icons.navigation, size: 18),
                        label: const Text('길찾기'),
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