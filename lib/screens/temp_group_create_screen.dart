// lib/screens/temp_group_create_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/temp_groups_provider.dart';
import '../models/temp_group_model.dart';

class TempGroupCreateScreen extends StatefulWidget {
  final String userId;
  
  const TempGroupCreateScreen({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<TempGroupCreateScreen> createState() => _TempGroupCreateScreenState();
}

class _TempGroupCreateScreenState extends State<TempGroupCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  int _selectedDuration = TempGroupDuration.week2; // 기본 2주
  bool _canExtend = true;
  int? _maxMembers; // null = 무제한
  bool _hasMaxMembers = false;
  
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('새 그룹 만들기'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ✅ 그룹 이름
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '그룹 이름 *',
                hintText: '예: 주말 여행 모임',
                prefixIcon: Icon(Icons.group),
                border: OutlineInputBorder(),
              ),
              maxLength: 50,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '그룹 이름을 입력하세요';
                }
                if (value.trim().length < 2) {
                  return '2글자 이상 입력하세요';
                }
                return null;
              },
            ),
            
            const SizedBox(height: 16),
            
            // ✅ 설명
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '설명',
                hintText: '그룹에 대한 간단한 설명',
                prefixIcon: Icon(Icons.description),
                border: OutlineInputBorder(),
              ),
              maxLength: 200,
              maxLines: 3,
            ),
            
            const SizedBox(height: 24),
            
            // ✅ 기간 선택
            const Text(
              '기간 선택 *',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TempGroupDuration.all.map((duration) {
                final isSelected = _selectedDuration == duration;
                return ChoiceChip(
                  label: Text(TempGroupDuration.label(duration)),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedDuration = duration);
                    }
                  },
                  selectedColor: Colors.deepPurple,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),
            
            const SizedBox(height: 24),
            
            // ✅ 연장 허용
            Card(
              child: SwitchListTile(
                title: const Text('연장 허용'),
                subtitle: const Text('기간 만료 전 연장 가능'),
                value: _canExtend,
                onChanged: (value) {
                  setState(() => _canExtend = value);
                },
                secondary: const Icon(Icons.update),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // ✅ 최대 인원 설정
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('최대 인원 제한'),
                    subtitle: Text(
                      _hasMaxMembers 
                          ? '${_maxMembers ?? 10}명까지' 
                          : '무제한'
                    ),
                    value: _hasMaxMembers,
                    onChanged: (value) {
                      setState(() {
                        _hasMaxMembers = value;
                        if (value && _maxMembers == null) {
                          _maxMembers = 10;
                        }
                      });
                    },
                    secondary: const Icon(Icons.people),
                  ),
                  
                  if (_hasMaxMembers) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Text('최대 인원: '),
                          Expanded(
                            child: Slider(
                              value: (_maxMembers ?? 10).toDouble(),
                              min: 2,
                              max: 50,
                              divisions: 48,
                              label: '${_maxMembers ?? 10}명',
                              onChanged: (value) {
                                setState(() => _maxMembers = value.toInt());
                              },
                            ),
                          ),
                          Text(
                            '${_maxMembers ?? 10}명',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // ✅ 정보 카드
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Text(
                        '그룹 정보',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[900],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• 그룹은 ${TempGroupDuration.label(_selectedDuration)} 후 자동으로 만료됩니다',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  if (_canExtend)
                    Text(
                      '• 만료 전 광고 시청 또는 결제로 연장할 수 있습니다',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  Text(
                    '• 그룹 채팅 및 모든 데이터는 만료 시 삭제됩니다',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // ✅ 생성 버튼
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isCreating ? null : _createGroup,
                icon: _isCreating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_circle),
                label: Text(
                  _isCreating ? '생성 중...' : '그룹 만들기',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isCreating = true);
    
    try {
      final provider = context.read<TempGroupsProvider>();
      
      final group = await provider.createGroup(
        userId: widget.userId,
        groupName: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        duration: _selectedDuration,
        canExtend: _canExtend,
        maxMembers: _hasMaxMembers ? _maxMembers : null,
      );
      
      if (group != null && mounted) {
        // 성공 메시지
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "${group.groupName}" 그룹이 생성되었습니다!'),
            backgroundColor: Colors.green,
          ),
        );
        
        // 이전 화면으로 돌아가기 (그룹 ID 전달)
        Navigator.pop(context, group);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ 그룹 생성에 실패했습니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ 그룹 생성 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }
}