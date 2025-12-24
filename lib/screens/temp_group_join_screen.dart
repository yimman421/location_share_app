// lib/screens/temp_group_join_screen.dart
// ✅ 초대 코드로 그룹 참여하기

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/temp_groups_provider.dart';
//import '../models/temp_group_model.dart';
import 'temp_group_detail_screen.dart';

class TempGroupJoinScreen extends StatefulWidget {
  final String userId;
  
  const TempGroupJoinScreen({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<TempGroupJoinScreen> createState() => _TempGroupJoinScreenState();
}

class _TempGroupJoinScreenState extends State<TempGroupJoinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _isJoining = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('초대 코드로 참여'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ✅ 안내 카드
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          '초대 코드 입력',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '친구에게 받은 6자리 초대 코드를 입력하세요',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // ✅ 초대 코드 입력
            TextFormField(
              controller: _codeController,
              decoration: InputDecoration(
                labelText: '초대 코드 *',
                hintText: 'ABC123',
                prefixIcon: const Icon(Icons.vpn_key),
                border: const OutlineInputBorder(),
                helperText: '대소문자 구분 없음',
                counterText: '',
              ),
              maxLength: 6,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.center,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '초대 코드를 입력하세요';
                }
                if (value.trim().length != 6) {
                  return '6자리 코드를 입력하세요';
                }
                return null;
              },
              onChanged: (value) {
                // 자동으로 대문자 변환
                if (value.length <= 6) {
                  _codeController.value = _codeController.value.copyWith(
                    text: value.toUpperCase(),
                    selection: TextSelection.collapsed(
                      offset: value.length,
                    ),
                  );
                }
              },
            ),
            
            const SizedBox(height: 24),
            
            // ✅ 참여 버튼
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isJoining ? null : _joinGroup,
                icon: _isJoining
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.group_add),
                label: Text(
                  _isJoining ? '참여 중...' : '그룹 참여하기',
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
            
            const SizedBox(height: 16),
            
            // ✅ QR 코드 스캔 버튼 (추후 구현)
            OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('QR 스캔 기능은 추후 구현됩니다'),
                  ),
                );
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('QR 코드 스캔'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.deepPurple,
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // ✅ 안내 문구
            Center(
              child: Text(
                '초대 코드는 24시간 동안 유효합니다',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _joinGroup() async {
    if (!_formKey.currentState!.validate()) return;
    
    final inviteCode = _codeController.text.trim().toUpperCase();
    
    setState(() => _isJoining = true);
    
    try {
      final provider = context.read<TempGroupsProvider>();
      
      final group = await provider.joinGroupByInvite(
        inviteCode: inviteCode,
        userId: widget.userId,
      );
      
      if (group != null && mounted) {
        // 성공 - 그룹 상세 화면으로 이동
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "${group.groupName}" 그룹에 참여했습니다!'),
            backgroundColor: Colors.green,
          ),
        );
        
        // 현재 화면 닫고 그룹 상세로 이동
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => TempGroupDetailScreen(
              userId: widget.userId,
              groupId: group.id,
            ),
          ),
        );
      } else if (mounted) {
        // 실패
        _showErrorDialog(
          '참여 실패',
          '초대 코드가 유효하지 않거나 만료되었습니다.\n\n'
          '• 초대 코드를 다시 확인하세요\n'
          '• 그룹이 만료되었을 수 있습니다\n'
          '• 그룹이 인원 제한에 도달했을 수 있습니다',
        );
      }
    } catch (e) {
      debugPrint('❌ 그룹 참여 오류: $e');
      if (mounted) {
        _showErrorDialog('오류', '그룹 참여 중 오류가 발생했습니다.\n\n$e');
      }
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}