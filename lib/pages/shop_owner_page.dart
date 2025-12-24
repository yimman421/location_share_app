import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/shop_provider.dart';
import '../constants/shop_constants.dart';
import 'package:intl/intl.dart';
import 'simple_location_picker.dart'; // ✅ 간단한 위치 선택기
import '../models/shop_models.dart';

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
        
        // ✅ 모든 메시지의 수락자 목록 미리 로드 (실시간 카운트용)
        for (var msg in provider.myMessages) {
          await provider.fetchAcceptances(msg.messageId);
        }
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

          // 최근 메시지
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
                  children: provider.myMessages.take(3).map((msg) {
                    return _buildMessageCard(msg, provider);
                  }).toList(),
                ),
        ],
      ),
    );
  }

  // ✅ 총 수락자 수 계산 (만료된 메시지 제외)
  int _getTotalAcceptCount(ShopProvider provider) {
    int totalCount = 0;
    
    for (var msg in provider.myMessages) {
      // ✅ 만료되지 않은 메시지만 카운트
      if (!msg.isExpired) {
        final acceptances = provider.acceptances[msg.messageId] ?? [];
        totalCount += acceptances.length;
      }
    }
    
    return totalCount;
  }

  // ✅ 특정 메시지의 수락자 수 (acceptances 기반)
  int _getMessageAcceptCount(ShopProvider provider, String messageId) {
    final acceptances = provider.acceptances[messageId] ?? [];
    return acceptances.length;
  }

  Widget _buildMessageCard(dynamic msg, ShopProvider provider) {
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
              '${_getMessageAcceptCount(provider, msg.messageId)}명',
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
                // ✅ 첫 번째 줄: 반경 + 남은 유효시간
                Row(
                  children: [
                    Expanded(
                      child: _buildDetailItem('반경', '${msg.radius}m'),
                    ),
                    Expanded(
                      child: _buildDetailItem(
                        '남은 시간',
                        _formatRemainingTime(msg),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // ✅ 두 번째 줄: 남은 자리 (중앙)
                _buildDetailItem(
                  '남은 자리',
                  _formatRemainingSlots(msg, provider),
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

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: provider.myMessages.length,
      itemBuilder: (context, index) {
        final msg = provider.myMessages[index];
        return _buildMessageCard(msg, provider);
      },
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
        // ✅ 샵 위치 변경 버튼 추가
        _buildSettingTile(
          icon: Icons.edit_location,
          title: '샵 위치 변경',
          subtitle: '지도에서 정확한 위치 선택',
          onTap: () => _changeShopLocation(context, provider),
          iconColor: Colors.blue,
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
        const Divider(height: 32),
        // ✅ 위험 구역 - 샵 삭제
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red[50],
            border: Border.all(color: Colors.red[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning, color: Colors.red[700]),
                  const SizedBox(width: 8),
                  Text(
                    '위험 구역',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '샵을 삭제하면 모든 홍보 메시지와 데이터가 영구적으로 삭제됩니다.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.red[900],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _confirmDeleteShop(context, provider),
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('샵 삭제'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
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
    Color? iconColor,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: iconColor ?? Colors.deepPurple),
        title: Text(title),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.edit),
        onTap: onTap,
      ),
    );
  }
  
  // ✅ 1. 샵 등록 다이얼로그 - 지도에서 위치 선택 기능 추가
  Future<void> _showCreateShopDialog(
    BuildContext context, {
    String? initialName,
    String? initialCategory,
    double? initialLat,
    double? initialLng,
    String? initialAddress,
    String? initialPhone,
    String? initialDescription,
  }) async {
    // ✅ 기존 값이 있으면 사용, 없으면 기본값
    final nameController = TextEditingController(text: initialName ?? '');
    final phoneController = TextEditingController(text: initialPhone ?? '');
    final descController = TextEditingController(text: initialDescription ?? '');
    String selectedCategory = initialCategory ?? ShopConstants.shopCategories.first;
    double? selectedLat = initialLat;
    double? selectedLng = initialLng;
    String? selectedAddress = initialAddress;
    
    debugPrint('');
    debugPrint('🏪 ═══════════════ 샵 등록 다이얼로그 열기 ═══════════════');
    debugPrint('📝 기존 샵 이름: $initialName');
    debugPrint('📞 기존 전화번호: $initialPhone');
    debugPrint('📍 기존 위치: ${initialLat != null ? "($initialLat, $initialLng)" : "없음"}');
    debugPrint('🏪 ════════════════════════════════════════════════════════');
    debugPrint('');
    
    if (!mounted) return;
    
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('샵 등록하기'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '샵 이름 *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: '카테고리',
                    border: OutlineInputBorder(),
                  ),
                  items: ShopConstants.shopCategories.map((cat) {
                    return DropdownMenuItem(value: cat, child: Text(cat));
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedCategory = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                // ✅ 지도에서 위치 선택 버튼
                Container(
                  decoration: BoxDecoration(
                    color: selectedAddress != null ? Colors.green[50] : Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selectedAddress != null ? Colors.green : Colors.blue,
                      width: 2,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      selectedAddress != null ? Icons.check_circle : Icons.map,
                      color: selectedAddress != null ? Colors.green : Colors.blue,
                    ),
                    title: Text(
                      selectedAddress != null ? '위치 선택 완료' : '지도에서 위치 선택 *',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: selectedAddress != null ? Colors.green[900] : Colors.blue[900],
                      ),
                    ),
                    subtitle: selectedAddress != null
                        ? Text(
                            selectedAddress,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        : const Text('탭하여 지도에서 정확한 위치를 선택하세요'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () async {
                      debugPrint('');
                      debugPrint('🏪 ═══════════════ 지도에서 위치 선택 버튼 클릭 ═══════════════');
                      
                      // ✅ 현재 입력값 저장
                      final currentName = nameController.text;
                      final currentPhone = phoneController.text;
                      final currentDesc = descController.text;
                      
                      debugPrint('💾 현재 입력값 저장:');
                      debugPrint('   이름: $currentName');
                      debugPrint('   전화: $currentPhone');
                      debugPrint('   설명: $currentDesc');
                      
                      // 다이얼로그 닫기
                      Navigator.pop(dialogContext);
                      
                      debugPrint('✅ 다이얼로그 닫힘');
                      debugPrint('📍 SimpleLocationPicker로 이동...');
                      
                      // ✅ 간단한 위치 선택기 사용
                      final result = await Navigator.push<Map<String, dynamic>>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SimpleLocationPicker(
                            userId: widget.userId,
                            initialLat: selectedLat ?? 37.408915,
                            initialLng: selectedLng ?? 127.148245,
                            initialAddress: selectedAddress ?? '',
                          ),
                        ),
                      );
                      
                      debugPrint('🔙 SimpleLocationPicker에서 돌아옴');
                      debugPrint('📦 결과: $result');
                      
                      if (result != null && mounted) {
                        debugPrint('✅ 결과 수신 성공');
                        final newLat = result['lat'] as double;
                        final newLng = result['lng'] as double;
                        final newAddress = result['address'] as String;
                        
                        debugPrint('📍 선택된 위치: ($newLat, $newLng)');
                        debugPrint('📫 선택된 주소: $newAddress');
                        
                        // ✅ 다이얼로그 다시 열기 (모든 입력값 유지)
                        _showCreateShopDialog(
                          context,
                          initialName: currentName,
                          initialCategory: selectedCategory,
                          initialLat: newLat,
                          initialLng: newLng,
                          initialAddress: newAddress,
                          initialPhone: currentPhone,
                          initialDescription: currentDesc,
                        );
                      } else {
                        debugPrint('⚠️ 결과 없음 또는 취소됨');
                        // ✅ 취소된 경우에도 입력값 유지하며 다이얼로그 재오픈
                        if (mounted) {
                          _showCreateShopDialog(
                            context,
                            initialName: currentName,
                            initialCategory: selectedCategory,
                            initialLat: selectedLat,
                            initialLng: selectedLng,
                            initialAddress: selectedAddress,
                            initialPhone: currentPhone,
                            initialDescription: currentDesc,
                          );
                        }
                      }
                      
                      debugPrint('🏪 ═══════════════════════════════════════════════════════');
                      debugPrint('');
                    },
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: '전화번호 *',
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
              onPressed: () {
                debugPrint('❌ 샵 등록 취소');
                Navigator.pop(dialogContext);
              },
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                debugPrint('');
                debugPrint('✅ ═══════════════ 샵 등록 시도 ═══════════════');
                debugPrint('📝 샵 이름: ${nameController.text}');
                debugPrint('📞 전화번호: ${phoneController.text}');
                debugPrint('📍 위치: ${selectedLat != null ? "($selectedLat, $selectedLng)" : "null"}');
                debugPrint('📫 주소: ${selectedAddress ?? "null"}');
                
                if (nameController.text.isEmpty ||
                    selectedLat == null ||
                    selectedLng == null ||
                    phoneController.text.isEmpty) {
                  debugPrint('❌ 필수 항목 누락!');
                  debugPrint('   이름: ${nameController.text.isEmpty ? "비어있음" : "OK"}');
                  debugPrint('   위도: ${selectedLat == null ? "null" : "OK"}');
                  debugPrint('   경도: ${selectedLng == null ? "null" : "OK"}');
                  debugPrint('   전화: ${phoneController.text.isEmpty ? "비어있음" : "OK"}');
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('필수 항목을 입력해주세요'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                Navigator.pop(dialogContext);
                
                final provider = context.read<ShopProvider>();
                final success = await provider.createShop(
                  ownerId: widget.userId,
                  shopName: nameController.text,
                  category: selectedCategory,
                  lat: selectedLat,
                  lng: selectedLng,
                  address: selectedAddress!,
                  phone: phoneController.text,
                  description: descController.text,
                );
                
                if (success && mounted) {
                  debugPrint('✅ 샵 등록 성공!');
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ 샵 등록 완료')),
                  );
                  
                  await provider.fetchMyMessages(provider.myShop!.shopId);
                } else {
                  debugPrint('❌ 샵 등록 실패');
                }
                
                debugPrint('✅ ═══════════════════════════════════════════');
                debugPrint('');
              },
              child: const Text('등록'),
            ),
          ],
        ),
      ),
    );
    
    nameController.dispose();
    phoneController.dispose();
    descController.dispose();
  }

  // ✅ 샵 위치 변경
  Future<void> _changeShopLocation(BuildContext context, ShopProvider provider) async {
    final shop = provider.myShop!;
    
    debugPrint('');
    debugPrint('📍 ═══════════════ 샵 위치 변경 시작 ═══════════════');
    debugPrint('🏪 샵 이름: ${shop.shopName}');
    debugPrint('📍 현재 위치: (${shop.lat}, ${shop.lng})');
    debugPrint('📫 현재 주소: ${shop.address}');
    
    // ✅ 간단한 위치 선택기 사용
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SimpleLocationPicker(
          userId: widget.userId,
          initialLat: shop.lat,
          initialLng: shop.lng,
          initialAddress: shop.address,
        ),
      ),
    );
    
    debugPrint('🔙 SimpleLocationPicker에서 돌아옴');
    debugPrint('📦 결과: $result');
    
    if (result != null && mounted) {
      final lat = result['lat'] as double;
      final lng = result['lng'] as double;
      final address = result['address'] as String;
      
      debugPrint('✅ 새 위치: ($lat, $lng)');
      debugPrint('📫 새 주소: $address');
      
      final success = await provider.updateShopLocation(
        shopId: shop.shopId,
        lat: lat,
        lng: lng,
        address: address,
      );
      
      if (success && mounted) {
        debugPrint('✅ 샵 위치 변경 성공');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 샵 위치가 변경되었습니다'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        debugPrint('❌ 샵 위치 변경 실패');
      }
    } else {
      debugPrint('⚠️ 결과 없음 또는 mounted = false');
    }
    
    debugPrint('📍 ═══════════════════════════════════════════════════');
    debugPrint('');
  }

  // ✅ 2. 메시지 전송 다이얼로그
  Future<void> _showSendMessageDialog(BuildContext context) async {
    final messageController = TextEditingController();
    int selectedRadius = ShopConstants.radiusOptions[2];
    int selectedValidity = ShopConstants.validityOptions[1];
    int? selectedMaxUsers; // ✅ 인원 제한 (null = 무제한)
    
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
                    return DropdownMenuItem(value: r, child: Text('$r미터'));
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
                    return DropdownMenuItem(value: h, child: Text('$h시간'));
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedValidity = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                const Text('인원 제한', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<bool>(
                        title: const Text('무제한', style: TextStyle(fontSize: 14)),
                        value: true,
                        groupValue: selectedMaxUsers == null,
                        onChanged: (value) {
                          setState(() => selectedMaxUsers = null);
                        },
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<bool>(
                        title: const Text('제한', style: TextStyle(fontSize: 14)),
                        value: false,
                        groupValue: selectedMaxUsers == null,
                        onChanged: (value) {
                          setState(() => selectedMaxUsers = 10); // 기본값 10명
                        },
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                if (selectedMaxUsers != null) ...[
                  const SizedBox(height: 8),
                  DropdownButton<int>(
                    value: selectedMaxUsers,
                    isExpanded: true,
                    items: [5, 10, 20, 30, 50, 100].map((count) {
                      return DropdownMenuItem(
                        value: count,
                        child: Text('최대 $count명'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedMaxUsers = value);
                      }
                    },
                  ),
                ],
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
                  maxUsers: selectedMaxUsers, // ✅ 인원 제한 전달
                );
                
                if (result != null && mounted) {
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
    
    messageController.dispose();
  }
  
  Future<void> _showAcceptanceList(ShopProvider provider, dynamic msg) async {
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text('사용자 ${acceptance.userId.substring(0, 8)}...'),
                        subtitle: Text('수락 시간: ${_formatTime(acceptance.acceptedAt)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '(${acceptance.userLat.toStringAsFixed(4)}, ${acceptance.userLng.toStringAsFixed(4)})',
                              style: const TextStyle(fontSize: 11),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.visibility, size: 16, color: Colors.blue),
                          ],
                        ),
                        // ✅ 클릭 시 해당 위치만 보기 (길찾기 없음)
                        onTap: () {
                          debugPrint('');
                          debugPrint('👁️ ═══════════════ 수락자 위치 보기 ═══════════════');
                          debugPrint('👤 사용자: ${acceptance.userId}');
                          debugPrint('📍 위치: (${acceptance.userLat}, ${acceptance.userLng})');
                          
                          // BottomSheet 닫기
                          Navigator.pop(context);
                          
                          // ✅ 지도로 돌아가서 해당 위치로 이동만
                          Navigator.pop(context, {
                            'action': 'view_location',
                            'lat': acceptance.userLat,
                            'lng': acceptance.userLng,
                            'userId': acceptance.userId,
                          });
                          
                          debugPrint('👁️ ═══════════════════════════════════════════════');
                          debugPrint('');
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ✅ 3. 샵 정보 수정
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
              
              if (success && mounted) {
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
    
    controller.dispose();
  }
  
  // ✅ 4. 카테고리 변경
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
                groupValue: selectedCategory,
                title: Text(cat),
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
                
                if (success && mounted) {
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

  // ✅ 샵 삭제 확인
  Future<void> _confirmDeleteShop(BuildContext context, ShopProvider provider) async {
    final shop = provider.myShop!;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('샵 삭제 확인'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '정말로 "${shop.shopName}"을(를) 삭제하시겠습니까?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('다음 항목이 모두 삭제됩니다:', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            const Text('• 샵 정보', style: TextStyle(fontSize: 13)),
            const Text('• 모든 홍보 메시지', style: TextStyle(fontSize: 13)),
            const Text('• 메시지 수락 기록', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red[300]!),
              ),
              child: const Text(
                '⚠️ 이 작업은 되돌릴 수 없습니다!',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final success = await provider.deleteShop(shop.shopId);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 샵이 삭제되었습니다')),
        );
        Navigator.pop(context);
      }
    }
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

  // ✅ 남은 시간 표시 (22시간/48시간)
  String _formatRemainingTime(ShopMessageModel msg) {
    if (msg.isExpired) {
      return '만료됨';
    }
    
    final remaining = msg.remainingTime;
    final total = Duration(hours: msg.validityHours);
    
    final remainingHours = remaining.inHours;
    final totalHours = total.inHours;
    
    return '$remainingHours시간/$totalHours시간';
  }

  // ✅ 남은 자리 표시 (21명/50명)
  String _formatRemainingSlots(ShopMessageModel msg, ShopProvider provider) {
    if (msg.maxUsers == null) {
      return '무제한';
    }
    
    // ✅ 실시간 수락자 수 가져오기
    final acceptances = provider.acceptances[msg.messageId] ?? [];
    final currentCount = acceptances.length;
    final maxCount = msg.maxUsers!;
    final remaining = maxCount - currentCount;
    
    return '$remaining명/$maxCount명';
  }
}