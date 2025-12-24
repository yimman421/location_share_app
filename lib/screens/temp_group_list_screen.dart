// lib/screens/temp_group_list_screen.dart
// ✅ 전체 코드 (초대 코드 참여 버튼 추가)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/temp_groups_provider.dart';
import '../models/temp_group_model.dart';
import 'temp_group_create_screen.dart';
import 'temp_group_detail_screen.dart';
import 'temp_group_join_screen.dart';  // ✅ 추가

class TempGroupListScreen extends StatefulWidget {
  final String userId;
  
  const TempGroupListScreen({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<TempGroupListScreen> createState() => _TempGroupListScreenState();
}

class _TempGroupListScreenState extends State<TempGroupListScreen> {
  bool _showExpired = false;
  
  @override
  void initState() {
    super.initState();
    
    // ✅✅✅ build 중에 notifyListeners 호출 방지
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadGroups();
      
      // Realtime 구독도 postFrameCallback 안에서
      final provider = context.read<TempGroupsProvider>();
      provider.subscribeToGroups(widget.userId);
    });
  }

  Future<void> _loadGroups() async {
    final provider = context.read<TempGroupsProvider>();
    await provider.fetchMyGroups(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 그룹'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          // 만료된 그룹 표시 토글
          IconButton(
            icon: Icon(_showExpired ? Icons.visibility_off : Icons.visibility),
            tooltip: _showExpired ? '만료된 그룹 숨기기' : '만료된 그룹 보기',
            onPressed: () {
              setState(() => _showExpired = !_showExpired);
            },
          ),
        ],
      ),
      body: Consumer<TempGroupsProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          
          final groups = _showExpired 
              ? provider.myGroups 
              : provider.activeGroups;
          
          if (groups.isEmpty) {
            return _buildEmptyState();
          }
          
          return RefreshIndicator(
            onRefresh: _loadGroups,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                return _buildGroupCard(group);
              },
            ),
          );
        },
      ),
      // ✅✅✅ FAB를 2개로 변경
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // 초대 코드로 참여
          FloatingActionButton.extended(
            onPressed: _joinWithCode,
            heroTag: 'join',
            icon: const Icon(Icons.vpn_key),
            label: const Text('초대 코드'),
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 12),
          
          // 새 그룹 만들기
          FloatingActionButton.extended(
            onPressed: _createNewGroup,
            heroTag: 'create',
            icon: const Icon(Icons.add),
            label: const Text('새 그룹'),
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.group_off,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            _showExpired ? '그룹이 없습니다' : '활성 그룹이 없습니다',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '새 그룹을 만들거나 초대 코드로 참여하세요!',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _createNewGroup,
                icon: const Icon(Icons.add),
                label: const Text('그룹 만들기'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _joinWithCode,
                icon: const Icon(Icons.vpn_key),
                label: const Text('초대 코드'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(TempGroupModel group) {
    final isExpired = group.isExpired;
    final isExpiringSoon = !isExpired && group.remainingDays <= 3;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () => _openGroupDetail(group),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ 헤더 (이름 & 상태)
              Row(
                children: [
                  // 아이콘
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isExpired 
                          ? Colors.grey[300] 
                          : Colors.deepPurple[100],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.group,
                      color: isExpired 
                          ? Colors.grey[600] 
                          : Colors.deepPurple,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // 그룹명
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.groupName,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isExpired ? Colors.grey[600] : Colors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (group.description.isNotEmpty)
                          Text(
                            group.description,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  
                  // 상태 뱃지
                  if (isExpired)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '만료됨',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                ],
              ),
              
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              
              // ✅ 정보 행
              Row(
                children: [
                  // 멤버 수
                  Icon(Icons.people, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${group.memberCount}명',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                  
                  // const SizedBox(width: 16),
                  
                  // // 메시지 수
                  // Icon(Icons.message, size: 16, color: Colors.grey[600]),
                  // const SizedBox(width: 4),
                  // Text(
                  //   '${group.messageCount}개',
                  //   style: TextStyle(
                  //     fontSize: 14,
                  //     color: Colors.grey[700],
                  //   ),
                  // ),
                  
                  const Spacer(),
                  
                  // 남은 시간
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isExpired
                          ? Colors.grey[200]
                          : isExpiringSoon
                              ? Colors.red[50]
                              : Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: isExpired
                              ? Colors.grey[600]
                              : isExpiringSoon
                                  ? Colors.red[700]
                                  : Colors.blue[700],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isExpired ? '만료' : group.formattedRemainingTime,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isExpired
                                ? Colors.grey[600]
                                : isExpiringSoon
                                    ? Colors.red[700]
                                    : Colors.blue[700],
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
      ),
    );
  }

  Future<void> _createNewGroup() async {
    final result = await Navigator.push<TempGroupModel>(
      context,
      MaterialPageRoute(
        builder: (context) => TempGroupCreateScreen(
          userId: widget.userId,
        ),
      ),
    );
    
    // 그룹 생성 후 상세 화면으로 이동
    if (result != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TempGroupDetailScreen(
            userId: widget.userId,
            groupId: result.id,
          ),
        ),
      );
    }
  }

  // ✅✅✅ 초대 코드로 참여 (새로 추가)
  void _joinWithCode() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TempGroupJoinScreen(
          userId: widget.userId,
        ),
      ),
    );
  }

  void _openGroupDetail(TempGroupModel group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TempGroupDetailScreen(
          userId: widget.userId,
          groupId: group.id,
        ),
      ),
    );
  }
}