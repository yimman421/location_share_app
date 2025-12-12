import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/shop_provider.dart';
import '../constants/shop_constants.dart';
import 'package:intl/intl.dart';

class ShopOwnerPage extends StatefulWidget {
  final String userId;
  
  const ShopOwnerPage({
    super.key,
    required this.userId,
  });

  @override
  State<ShopOwnerPage> createState() => _ShopOwnerPageState();
}

class _ShopOwnerPageState extends State<ShopOwnerPage> {
  int _selectedIndex = 0;
  
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final provider = context.read<ShopProvider>();
      
      await provider.fetchMyShop(widget.userId);
      if (provider.myShop != null) {
        await provider.fetchMyMessages(provider.myShop!.shopId);
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('샵 관리'),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: Consumer<ShopProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (provider.myShop == null) {
            return _buildNoShopView(context);
          }
          
          return IndexedStack(
            index: _selectedIndex,
            children: [
              _buildDashboard(provider),
              _buildMessageHistory(provider),
              _buildShopSettings(provider),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: Colors.deepPurple,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: '대시보드',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.message),
            label: '메시지 내역',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.store),
            label: '샵 설정',
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => _showSendMessageDialog(context),
              backgroundColor: Colors.deepPurple,
              icon: const Icon(Icons.send),
              label: const Text('홍보 메시지 보내기'),
            )
          : null,
    );
  }

  // ================= 샵이 없을 때 =================
  Widget _buildNoShopView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.store, size: 80, color: Colors.grey),
          const SizedBox(height: 20),
          const Text(
            '등록된 샵이 없습니다',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            '새로운 샵을 등록해주세요',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: () => _showCreateShopDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('샵 등록하기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            ),
          ),
        ],
      ),
    );
  }

  // ================= 대시보드 =================
  Widget _buildDashboard(ShopProvider provider) {
    final shop = provider.myShop!;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 샵 정보 카드
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.deepPurple,
                        child: Icon(
                          _getCategoryIcon(shop.category),
                          size: 30,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shop.shopName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              shop.category,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow(Icons.location_on, shop.address),
                  _buildInfoRow(Icons.phone, shop.phone),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // 배너 메시지
          if (shop.bannerMessage.isNotEmpty)
            Card(
              color: Colors.amber[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.campaign, color: Colors.amber),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        shop.bannerMessage,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 20),

          // 통계
          const Text(
            '최근 활동',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  '전송 메시지',
                  provider.myMessages.length.toString(),
                  Colors.blue,
                  Icons.send,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  '총 수락자',
                  _getTotalAcceptCount(provider).toString(),
                  Colors.green,
                  Icons.check_circle,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 최근 메시지 - 클릭 시 확장 기능 제공
          const Text(
            '최근 메시지',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          provider.myMessages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      '전송한 메시지가 없습니다',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ),
                )
              : Column(
                  children: provider.myMessages.map((msg) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: msg.isExpired ? Colors.grey : Colors.deepPurple,
                          child: Icon(
                            msg.isExpired ? Icons.schedule : Icons.message,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(msg.message),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text('전송: ${_formatTime(msg.createdAt)}'),
                            Text(
                              msg.isExpired
                                  ? '만료됨'
                                  : '남은 시간: ${_formatDuration(msg.remainingTime)}',
                              style: TextStyle(
                                color: msg.isExpired ? Colors.grey : Colors.orange,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${msg.acceptCount}명',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const Text('수락', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildDetailItem(
                                        '반경',
                                        '${msg.radius}m',
                                      ),
                                    ),
                                    Expanded(
                                      child: _buildDetailItem(
                                        '유효시간',
                                        '${msg.validityHours}시간',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: () => _showAcceptanceList(provider, msg),
                                  icon: const Icon(Icons.people),
                                  label: const Text('수락자 목록 보기'),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(double.infinity, 45),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ],
      ),
    );
  }

  // ================= 메시지 내역 =================
  Widget _buildMessageHistory(ShopProvider provider) {
    if (provider.myMessages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.message_outlined, size: 80, color: Colors.grey),
            SizedBox(height: 20),
            Text(
              '전송한 메시지가 없습니다',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: provider.myMessages.length,
            itemBuilder: (context, index) {
              final msg = provider.myMessages[index];

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: msg.isExpired ? Colors.grey : Colors.deepPurple,
                    child: Icon(
                      msg.isExpired ? Icons.schedule : Icons.message,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(msg.message),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text('전송: ${_formatTime(msg.createdAt)}'),
                      Text(
                        msg.isExpired
                            ? '만료됨'
                            : '남은 시간: ${_formatDuration(msg.remainingTime)}',
                        style: TextStyle(
                          color: msg.isExpired ? Colors.grey : Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${msg.acceptCount}명',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Text('수락', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildDetailItem(
                                  '반경',
                                  '${msg.radius}m',
                                ),
                              ),
                              Expanded(
                                child: _buildDetailItem(
                                  '유효시간',
                                  '${msg.validityHours}시간',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () => _showAcceptanceList(provider, msg),
                            icon: const Icon(Icons.people),
                            label: const Text('수락자 목록 보기'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ================= 샵 설정 =================
  Widget _buildShopSettings(ShopProvider provider) {
    final shop = provider.myShop!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('샵 정보', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildSettingTile(
          icon: Icons.store,
          title: '샵 이름',
          subtitle: shop.shopName,
          onTap: () => _editShopInfo(context, 'shopName', '샵 이름', shop.shopName),
        ),
        _buildSettingTile(
          icon: Icons.category,
          title: '카테고리',
          subtitle: shop.category,
          onTap: () => _editShopCategory(context),
        ),
        _buildSettingTile(
          icon: Icons.location_on,
          title: '주소',
          subtitle: shop.address,
          onTap: () => _editShopInfo(context, 'address', '주소', shop.address),
        ),
        _buildSettingTile(
          icon: Icons.phone,
          title: '전화번호',
          subtitle: shop.phone,
          onTap: () => _editShopInfo(context, 'phone', '전화번호', shop.phone),
        ),
        _buildSettingTile(
          icon: Icons.description,
          title: '설명',
          subtitle: shop.description.isEmpty ? '설명 없음' : shop.description,
          onTap: () => _editShopInfo(context, 'description', '설명', shop.description),
        ),
        const Divider(height: 32),
        const Text('베너 메시지', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('지도에 표시될 샵의 홍보 메시지를 설정하세요', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        _buildSettingTile(
          icon: Icons.campaign,
          title: '베너 메시지',
          subtitle: shop.bannerMessage.isEmpty ? '설정되지 않음' : shop.bannerMessage,
          onTap: () => _editShopInfo(context, 'bannerMessage', '베너 메시지', shop.bannerMessage),
        ),
      ],
    );
  }

  // ================= 유틸리티 =================
  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: Colors.grey[700])),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 30, color: color),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: Colors.deepPurple),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.edit),
        onTap: onTap,
      ),
    );
  }
  
  // ✅ 1. 샵 등록 다이얼로그 - mounted 체크 추가
  Future<void> _showCreateShopDialog(BuildContext context) async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final phoneController = TextEditingController();
    final descController = TextEditingController();
    String selectedCategory = ShopConstants.shopCategories.first;
    
    if (!mounted) return;
    
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('샵 등록하기'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '샵 이름',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: '카테고리',
                    border: OutlineInputBorder(),
                  ),
                  items: ShopConstants.shopCategories.map((cat) {
                    return DropdownMenuItem(value: cat, child: Text(cat));
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedCategory = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: '주소',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: '전화번호',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: '설명',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty ||
                    addressController.text.isEmpty ||
                    phoneController.text.isEmpty) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('필수 항목을 입력해주세요')),
                  );
                  return;
                }
                
                Navigator.pop(dialogContext);
                
                final provider = context.read<ShopProvider>();
                final success = await provider.createShop(
                  ownerId: widget.userId,
                  shopName: nameController.text,
                  category: selectedCategory,
                  lat: 37.408915,
                  lng: 127.148245,
                  address: addressController.text,
                  phone: phoneController.text,
                  description: descController.text,
                );
                
                // ✅ mounted 체크 추가
                if (success && mounted) {
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ 샵 등록 완료')),
                  );
                  
                  await provider.fetchMyMessages(provider.myShop!.shopId);
                }
              },
              child: const Text('등록'),
            ),
          ],
        ),
      ),
    );
    
    // ✅ dispose 시 컨트롤러 정리
    nameController.dispose();
    addressController.dispose();
    phoneController.dispose();
    descController.dispose();
  }

  // ✅ 2. 메시지 전송 다이얼로그 - mounted 체크 추가
  Future<void> _showSendMessageDialog(BuildContext context) async {
    final messageController = TextEditingController();
    int selectedRadius = ShopConstants.radiusOptions[2];
    int selectedValidity = ShopConstants.validityOptions[1];
    
    if (!mounted) return;
    
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('홍보 메시지 보내기'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: messageController,
                  decoration: const InputDecoration(
                    labelText: '메시지',
                    hintText: '예: 선착순 30명 아메리카노 무료!',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                const Text('반경 설정', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<int>(
                  value: selectedRadius,
                  isExpanded: true,
                  items: ShopConstants.radiusOptions.map((r) {
                    return DropdownMenuItem(
                      value: r,
                      child: Text('$r미터'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedRadius = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                const Text('유효시간', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<int>(
                  value: selectedValidity,
                  isExpanded: true,
                  items: ShopConstants.validityOptions.map((h) {
                    return DropdownMenuItem(
                      value: h,
                      child: Text('$h시간'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedValidity = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (messageController.text.isEmpty) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('메시지를 입력해주세요')),
                  );
                  return;
                }
                
                Navigator.pop(dialogContext);
                
                final provider = context.read<ShopProvider>();
                final shop = provider.myShop!;
                
                final result = await provider.sendMessage(
                  shopId: shop.shopId,
                  ownerId: widget.userId,
                  message: messageController.text,
                  radius: selectedRadius,
                  validityHours: selectedValidity,
                );
                
                // ✅ mounted 체크 추가
                if (result != null && mounted) {
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ 메시지 전송 완료')),
                  );
                  
                  await provider.fetchMyMessages(shop.shopId);
                }
              },
              child: const Text('전송'),
            ),
          ],
        ),
      ),
    );
    
    // ✅ dispose 시 컨트롤러 정리
    messageController.dispose();
  }
  
  Future<void> _showAcceptanceList(
    ShopProvider provider,
    dynamic msg,
  ) async {
    await provider.fetchAcceptances(msg.messageId);
    
    if (!mounted) return;
    
    final acceptances = provider.acceptances[msg.messageId] ?? [];
    
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '수락자 목록',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${acceptances.length}명',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: acceptances.isEmpty
                ? const Center(
                    child: Text(
                      '아직 수락한 사람이 없습니다',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: acceptances.length,
                    itemBuilder: (context, index) {
                      final acceptance = acceptances[index];
                      
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person),
                        ),
                        title: Text('사용자 ${acceptance.userId.substring(0, 8)}...'),
                        subtitle: Text(
                          '수락 시간: ${_formatTime(acceptance.acceptedAt)}',
                        ),
                        trailing: Text(
                          '(${acceptance.userLat.toStringAsFixed(4)}, ${acceptance.userLng.toStringAsFixed(4)})',
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
  
  // ✅ 3. 샵 정보 수정 - mounted 체크 추가
  Future<void> _editShopInfo(
    BuildContext context,
    String field,
    String label,
    String currentValue,
  ) async {
    final controller = TextEditingController(text: currentValue);
    
    if (!mounted) return;
    
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$label 수정'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          maxLines: field == 'description' || field == 'bannerMessage' ? 3 : 1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              
              final provider = context.read<ShopProvider>();
              final success = await provider.updateShop(
                shopId: provider.myShop!.shopId,
                shopName: field == 'shopName' ? controller.text : null,
                address: field == 'address' ? controller.text : null,
                phone: field == 'phone' ? controller.text : null,
                description: field == 'description' ? controller.text : null,
                bannerMessage: field == 'bannerMessage' ? controller.text : null,
              );
              
              // ✅ mounted 체크 추가
              if (success && mounted) {
                // ignore: use_build_context_synchronously
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ 수정 완료')),
                );
              }
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    
    // ✅ dispose 시 컨트롤러 정리
    controller.dispose();
  }
  
  // ✅ 4. 카테고리 변경 - mounted 체크 추가
  Future<void> _editShopCategory(BuildContext context) async {
    final provider = context.read<ShopProvider>();
    String selectedCategory = provider.myShop!.category;
    
    if (!mounted) return;
    
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('카테고리 변경'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: ShopConstants.shopCategories.map((cat) {
              return RadioListTile<String>(
                value: cat,
                // ignore: deprecated_member_use
                groupValue: selectedCategory,
                title: Text(cat),
                // ignore: deprecated_member_use
                onChanged: (value) {
                  if (value != null) {
                    setState(() => selectedCategory = value);
                  }
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                
                final updateProvider = context.read<ShopProvider>();
                final success = await updateProvider.updateShop(
                  shopId: updateProvider.myShop!.shopId,
                  category: selectedCategory,
                );
                
                // ✅ mounted 체크 추가
                if (success && mounted) {
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ 카테고리 변경 완료')),
                  );
                }
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
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

  String _formatTime(DateTime dt) => DateFormat('MM/dd HH:mm').format(dt);

  String _formatDuration(Duration d) {
    if (d.isNegative || d == Duration.zero) return '0분';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '$h시간 $m분' : '$m분';
  }

  int _getTotalAcceptCount(ShopProvider provider) {
    return provider.myMessages.fold<int>(0, (sum, msg) => sum + msg.acceptCount);
  }
}
