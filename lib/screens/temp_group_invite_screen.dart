// lib/screens/temp_group_invite_screen.dart
// ✅ 최종 수정 버전 - Widget 타입 에러 해결

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/temp_groups_provider.dart';
import '../models/temp_group_model.dart';

class TempGroupInviteScreen extends StatefulWidget {
  final String userId;
  final String groupId;
  final String groupName;
  
  const TempGroupInviteScreen({
    Key? key,
    required this.userId,
    required this.groupId,
    required this.groupName,
  }) : super(key: key);

  @override
  State<TempGroupInviteScreen> createState() => _TempGroupInviteScreenState();
}

class _TempGroupInviteScreenState extends State<TempGroupInviteScreen> {
  TempGroupInviteModel? _currentInvite;
  bool _isGenerating = false;
  
  @override
  void initState() {
    super.initState();
    _generateInvite();
  }

  Future<void> _generateInvite() async {
    setState(() => _isGenerating = true);
    
    try {
      final provider = context.read<TempGroupsProvider>();
      final invite = await provider.createInviteLink(
        groupId: widget.groupId,
        userId: widget.userId,
        maxUses: null,
        expiryHours: 24,
      );
      
      if (invite != null && mounted) {
        setState(() => _currentInvite = invite);
      }
    } catch (e) {
      debugPrint('❌ 초대 링크 생성 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('초대 링크 생성에 실패했습니다')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('멤버 초대'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _isGenerating
          ? const Center(child: CircularProgressIndicator())
          : _currentInvite == null
              ? _buildErrorState()
              : _buildInviteContent(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          const Text('초대 링크 생성에 실패했습니다', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _generateInvite,
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildGroupInfoCard(),
        const SizedBox(height: 24),
        _buildInviteCodeCard(),
        const SizedBox(height: 16),
        _buildQRCodeCard(),
        const SizedBox(height: 16),
        _buildInviteInfoCard(),
        const SizedBox(height: 24),
        _buildShareButtons(),
      ],
    );
  }

  Widget _buildGroupInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.deepPurple[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.group, color: Colors.deepPurple, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.groupName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '초대하기',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteCodeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('초대 코드', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _currentInvite!.inviteCode,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _copyInviteCode,
                icon: const Icon(Icons.copy),
                label: const Text('코드 복사'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅✅✅ QR 코드 위젯 - 최종 수정 (Widget 타입 에러 해결)
  Widget _buildQRCodeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('QR 코드', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                // ✅✅✅ QrImageView 사용 (qr_flutter 4.x 버전)
                child: QrImageView(
                  data: _getInviteUrl(),
                  version: QrVersions.auto,
                  size: 200.0,
                  gapless: false,
                  errorStateBuilder: (cxt, err) {
                    return const Center(
                      child: Text(
                        'QR 코드 생성 오류',
                        style: TextStyle(color: Colors.red),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'QR 코드를 스캔하여 참여하세요',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteInfoCard() {
    final expiresAt = _currentInvite!.expiresAt;
    final remainingHours = expiresAt.difference(DateTime.now()).inHours;
    
    return Card(
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
                  '초대 정보',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue[900]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.access_time, '유효기간', '$remainingHours시간 남음'),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.people,
              '사용 횟수',
              _currentInvite!.maxUses == null
                  ? '무제한'
                  : '${_currentInvite!.usedCount}/${_currentInvite!.maxUses}회',
            ),
            const SizedBox(height: 8),
            _buildInfoRow(Icons.check_circle, '상태', _currentInvite!.isValid ? '활성' : '만료됨'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text('$label:', style: TextStyle(fontSize: 14, color: Colors.grey[700])),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildShareButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _shareInviteLink,
            icon: const Icon(Icons.share),
            label: const Text('초대 링크 공유'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _shareViaMessage,
            icon: const Icon(Icons.message),
            label: const Text('메시지로 공유'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.deepPurple),
          ),
        ),
      ],
    );
  }

  String _getInviteUrl() {
    return 'myapp://temp_group/join?code=${_currentInvite!.inviteCode}';
  }

  void _copyInviteCode() {
    Clipboard.setData(ClipboardData(text: _currentInvite!.inviteCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ 초대 코드가 복사되었습니다'), duration: Duration(seconds: 2)),
    );
  }

  void _shareInviteLink() {
    final inviteMessage = '''
안녕하세요! 📱

"${widget.groupName}" 그룹에 초대합니다!

초대 코드: ${_currentInvite!.inviteCode}

또는 이 링크를 클릭하세요:
${_getInviteUrl()}

초대는 24시간 동안 유효합니다.
''';
    
    Clipboard.setData(ClipboardData(text: inviteMessage));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ 초대 메시지가 복사되었습니다'), duration: Duration(seconds: 2)),
    );
  }

  void _shareViaMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('메시지 공유 기능은 추후 구현됩니다')),
    );
  }
}