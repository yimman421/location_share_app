// lib/screens/temp_group_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/temp_groups_provider.dart';
import '../models/temp_group_model.dart';
import 'temp_group_invite_screen.dart';
import '../providers/locations_provider.dart';
import 'temp_group_chat_screen.dart';

class TempGroupDetailScreen extends StatefulWidget {
  final String userId;
  final String groupId;
  
  const TempGroupDetailScreen({
    Key? key,
    required this.userId,
    required this.groupId,
  }) : super(key: key);

  @override
  State<TempGroupDetailScreen> createState() => _TempGroupDetailScreenState();
}

class _TempGroupDetailScreenState extends State<TempGroupDetailScreen> {
  TempGroupModel? _group;
  List<TempGroupMemberModel> _members = [];
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadGroupData();
  }

  // ✅✅✅ 이 메서드를 추가하세요 (어디든 State 클래스 안에)
  void _openChat() {
    debugPrint('📱 채팅 화면 열기');
    debugPrint('   - groupId: ${widget.groupId}');
    debugPrint('   - userId: ${widget.userId}');
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TempGroupChatScreen(
          groupId: widget.groupId,
          userId: widget.userId,
        ),
      ),
    );
  }
  
  Future<void> _loadGroupData() async {
    setState(() => _isLoading = true);
    
    try {
      final provider = context.read<TempGroupsProvider>();
      
      // 그룹 정보 가져오기
      await provider.fetchMyGroups(widget.userId);
      _group = provider.getGroupById(widget.groupId);
      
      // 멤버 정보 가져오기
      if (_group != null) {
        await provider.fetchGroupMembers(widget.groupId);
        _members = provider.getMembersOfGroup(widget.groupId);
      }
    } catch (e) {
      debugPrint('❌ 그룹 데이터 로드 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('그룹 상세'),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    if (_group == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('그룹 상세'),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text('그룹을 찾을 수 없습니다'),
        ),
      );
    }
    
    final isCreator = _group!.creatorId == widget.userId;
    final isExpired = _group!.isExpired;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(_group!.groupName),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          // 설정 메뉴
          PopupMenuButton<String>(
            onSelected: (value) => _handleMenuAction(value),
            itemBuilder: (context) => [
              if (isCreator) ...[
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('그룹 삭제', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ] else ...[
                const PopupMenuItem(
                  value: 'leave',
                  child: Row(
                    children: [
                      Icon(Icons.exit_to_app, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('그룹 나가기', style: TextStyle(color: Colors.orange)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),

      // // ✅✅✅ 이 부분을 추가하세요 (body 위에)
      // floatingActionButton: FloatingActionButton.extended(
      //   onPressed: _openChat,
      //   icon: const Icon(Icons.chat),
      //   label: const Text('채팅하기'),
      //   backgroundColor: Colors.deepPurple,
      // ),

      body: RefreshIndicator(
        onRefresh: _loadGroupData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ✅ 그룹 정보 카드
            _buildGroupInfoCard(),
            
            const SizedBox(height: 16),
            
            // ✅ 만료 정보 카드
            _buildExpiryCard(),
            
            const SizedBox(height: 16),
            
            // ✅ 멤버 목록
            _buildMembersCard(),
            
            const SizedBox(height: 16),
            
            // ✅ 통계
            _buildStatsCard(),
            
            const SizedBox(height: 16),
            
            // ✅ 액션 버튼들
            if (!isExpired) _buildActionButtons(isCreator),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.group,
                    color: Colors.deepPurple,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _group!.groupName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_group!.description.isNotEmpty)
                        Text(
                          _group!.description,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpiryCard() {
    final isExpired = _group!.isExpired;
    final isExpiringSoon = !isExpired && _group!.remainingDays <= 3;
    
    return Card(
      color: isExpired
          ? Colors.grey[200]
          : isExpiringSoon
              ? Colors.red[50]
              : Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isExpired ? Icons.error : Icons.access_time,
                  color: isExpired
                      ? Colors.grey[600]
                      : isExpiringSoon
                          ? Colors.red[700]
                          : Colors.blue[700],
                ),
                const SizedBox(width: 8),
                Text(
                  isExpired ? '만료됨' : '만료일',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isExpired
                        ? Colors.grey[700]
                        : isExpiringSoon
                            ? Colors.red[700]
                            : Colors.blue[900],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _group!.expiresAt.toString().split('.')[0],
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isExpired ? '그룹이 만료되었습니다' : _group!.formattedRemainingTime,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isExpired
                    ? Colors.grey[700]
                    : isExpiringSoon
                        ? Colors.red[700]
                        : Colors.blue[700],
              ),
            ),
            
            if (!isExpired && _group!.canExtend) ...[
              const SizedBox(height: 8),
              Text(
                '연장 가능 • ${_group!.extensionCount}회 연장됨',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMembersCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.people, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '멤버',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_members.length}명',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            
            // ✅✅✅ 멤버 리스트 - shrinkWrap 제거하고 Container로 감싸기
            if (_members.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('멤버가 없습니다'),
                ),
              )
            else
              // ✅ ListView를 Column으로 변경
              Column(
                children: _members.map((member) => _buildMemberTile(member)).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '통계',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            // const SizedBox(height: 12),
            // _buildStatRow(Icons.message, '메시지', '${_group!.messageCount}개'),
            const SizedBox(height: 8),
            _buildStatRow(Icons.calendar_today, '생성일', 
                _group!.createdAt.toString().split(' ')[0]),
            const SizedBox(height: 8),
            _buildStatRow(Icons.update, '연장 횟수', '${_group!.extensionCount}회'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(bool isCreator) {
    return Column(
      children: [
        // 채팅 버튼
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _openChat,
            icon: const Icon(Icons.chat),
            label: const Text('채팅하기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // 초대 버튼
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _openInviteScreen,
            icon: const Icon(Icons.person_add),
            label: const Text('멤버 초대'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.deepPurple,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMemberTile(TempGroupMemberModel member) {
    final isCreator = member.role == MemberRole.creator;
    final isMe = member.userId == widget.userId;
    
    debugPrint('🔨 _buildMemberTile 호출: ${member.userId}');
    
    return InkWell(
      // ✅✅✅ 클릭 시 위치로 이동
      onTap: () {
        debugPrint('');
        debugPrint('🖱️ ════════════════════ 멤버 클릭 ════════════════════');
        debugPrint('👤 클릭한 멤버: ${member.userId}');
        debugPrint('👤 현재 사용자: ${widget.userId}');
        _moveToMemberLocation(member.userId);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            // 아바타
            CircleAvatar(
              radius: 20,
              backgroundColor: isMe ? Colors.blue[100] : Colors.grey[300],
              child: Icon(
                Icons.person,
                color: isMe ? Colors.blue[700] : Colors.grey[600],
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            
            // 이름 (userId)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          member.userId,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '나',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (isCreator)
                    Text(
                      '생성자',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
            
            // 역할 아이콘
            if (isCreator)
              const Icon(
                Icons.star,
                color: Colors.amber,
                size: 20,
              ),
            
            // ✅ 위치 이동 아이콘
            const SizedBox(width: 8),
            Icon(
              Icons.location_on,
              color: Colors.blue[400],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ✅✅✅ State 클래스 안에 추가
  Future<void> _moveToMemberLocation(String userId) async {
    debugPrint('📍 Step 1: _moveToMemberLocation 시작');
    
    try {
      final provider = context.read<LocationsProvider>();
      debugPrint('📍 Step 2: LocationsProvider 가져옴');
      
      // ✅ locations는 Map<String, LocationModel>
      final userLoc = provider.locations[userId];
      debugPrint('📍 Step 3: 위치 조회 시도 - userId: $userId');
      debugPrint('📍 전체 locations 수: ${provider.locations.length}개');
      debugPrint('📍 locations keys: ${provider.locations.keys.toList()}');
      
      if (userLoc == null) {
        debugPrint('❌ Step 4: 위치 정보 없음');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$userId의 위치 정보를 찾을 수 없습니다.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        debugPrint('🖱️ ═══════════════════════════════════════════════');
        debugPrint('');
        return;
      }

      debugPrint('✅ Step 4: 위치 발견!');
      debugPrint('   - lat: ${userLoc.lat}');  // ✅ latitude → lat
      debugPrint('   - lng: ${userLoc.lng}');  // ✅ longitude → lng
      debugPrint('   - timestamp: ${userLoc.timestamp}');

      // ✅ map_page로 돌아가기
      debugPrint('📍 Step 5: Navigator.popUntil 실행');
      Navigator.popUntil(context, (route) => route.isFirst);

      // ✅ 약간의 딜레이 (map_page가 준비될 시간)
      debugPrint('📍 Step 6: 300ms 대기 중...');
      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        debugPrint('📍 Step 7: triggerMapMove 호출');
        // ✅ provider를 통해 지도 이동 트리거 (lat, lng 사용)
        provider.triggerMapMove(userLoc.lat, userLoc.lng);
        
        debugPrint('✅ Step 8: 완료! 성공 메시지 표시');
        
        // 성공 메시지
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📍 $userId의 위치로 이동합니다'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
        
        debugPrint('🖱️ ═══════════════════════════════════════════════');
        debugPrint('');
      } else {
        debugPrint('⚠️ Step 8: mounted가 false - 위젯이 dispose됨');
        debugPrint('🖱️ ═══════════════════════════════════════════════');
        debugPrint('');
      }
      
    } catch (e, stackTrace) {
      debugPrint('❌ _moveToMemberLocation 에러: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('🖱️ ═══════════════════════════════════════════════');
      debugPrint('');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('위치 이동 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'delete':
        _confirmDeleteGroup();
        break;
      case 'leave':
        _confirmLeaveGroup();
        break;
    }
  }

  Future<void> _confirmDeleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('그룹 삭제'),
        content: Text('${_group!.groupName}을(를) 삭제하시겠습니까?\n\n'
            '모든 채팅 내역과 데이터가 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      final provider = context.read<TempGroupsProvider>();
      final success = await provider.deleteGroup(
        groupId: widget.groupId,
        userId: widget.userId,
      );
      
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 그룹이 삭제되었습니다')),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _confirmLeaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('그룹 나가기'),
        content: Text('${_group!.groupName}에서 나가시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      final provider = context.read<TempGroupsProvider>();
      final success = await provider.leaveGroup(
        groupId: widget.groupId,
        userId: widget.userId,
      );
      
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 그룹에서 나갔습니다')),
        );
        Navigator.pop(context);
      }
    }
  }

  void _openInviteScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TempGroupInviteScreen(
          userId: widget.userId,
          groupId: widget.groupId,
          groupName: _group!.groupName,
        ),
      ),
    );
  }
}