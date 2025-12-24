// lib/screens/temp_group_chat_screen.dart
// ✅ 시간 제한 그룹 채팅 화면 (TempGroupsProvider 사용)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/temp_group_messages_provider.dart';
import '../providers/temp_groups_provider.dart'; // ✅ 이것만 사용
import '../models/temp_group_message_model.dart';
import '../models/temp_group_model.dart';
import '../widgets/message_bubble.dart';
import '../widgets/date_separator.dart';

class TempGroupChatScreen extends StatefulWidget {
  final String groupId;
  final String userId;

  const TempGroupChatScreen({
    Key? key,
    required this.groupId,
    required this.userId,
  }) : super(key: key);

  @override
  State<TempGroupChatScreen> createState() => _TempGroupChatScreenState();
}

class _TempGroupChatScreenState extends State<TempGroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  
  TempGroupModel? _group;
  bool _isLoadingMore = false;

  // ✅ Provider 참조 저장
  TempGroupMessagesProvider? _messagesProvider;

  @override
  void initState() {
    super.initState();
    _initializeChat();
    _setupScrollListener();
  }

  void _initializeChat() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // ✅ Provider 참조 저장
      _messagesProvider = context.read<TempGroupMessagesProvider>();
      final groupsProvider = context.read<TempGroupsProvider>();

      _messagesProvider?.calculateUnreadCount(widget.groupId, widget.userId);
      _messagesProvider?.markAsRead(widget.groupId, widget.userId);

      // ✅ 그룹 정보 가져오기 (memberCount 포함)
      _group = groupsProvider.myGroups.firstWhere(
        (g) => g.id == widget.groupId,
        orElse: () => null as TempGroupModel,
      );

      // ✅ setState로 UI 업데이트
      if (mounted && _group != null) {
        setState(() {});
      }

      await _messagesProvider!.fetchMessages(widget.groupId);
      await _messagesProvider!.subscribeToMessages(widget.groupId);
      await _messagesProvider!.calculateUnreadCount(widget.groupId, widget.userId);
      await _messagesProvider!.markAsRead(widget.groupId, widget.userId);
      
      _scrollToBottom();
    });
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (_scrollController.position.pixels <= 100) {
        _loadMoreMessages();
      }
    });
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || _messagesProvider == null) return;

    if (!_messagesProvider!.hasMoreMessages(widget.groupId)) return;

    setState(() => _isLoadingMore = true);
    await _messagesProvider!.loadMoreMessages(widget.groupId);
    setState(() => _isLoadingMore = false);
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _messagesProvider == null) return;

    final success = await _messagesProvider!.sendMessage(
      groupId: widget.groupId,
      userId: widget.userId,
      message: message,
    );

    if (success) {
      _messageController.clear();
      _scrollToBottom();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메시지 전송 실패')),
        );
      }
    }
  }

  // ✅✅✅ 이미지 선택 및 전송
  Future<void> _pickAndSendImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image == null || !mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이미지 업로드 중...'),
          duration: Duration(seconds: 1),
        ),
      );

      if (_messagesProvider == null) return;

      // TODO: Appwrite Storage에 이미지 업로드 후 URL 받기
      // 현재는 임시로 파일명만 메시지로 전송
      final fileName = image.name;
      
      final success = await _messagesProvider!.sendMessage(
        groupId: widget.groupId,
        userId: widget.userId,
        message: '[이미지] $fileName',
        type: MessageType.image,
      );

      if (success) {
        _scrollToBottom();
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('이미지 전송 완료!'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이미지 전송 실패')),
          );
        }
      }
    } catch (e) {
      debugPrint('이미지 선택 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 선택 실패: $e')),
        );
      }
    }
  }

  void _showMessageOptions(TempGroupMessageModel message) {
    if (message.userId != widget.userId) return;
    if (message.isDeleted) return;
    if (message.isSystemMessage) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('수정'),
              onTap: () {
                Navigator.pop(context);
                _showEditDialog(message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('삭제', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('취소'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(TempGroupMessageModel message) {
    final controller = TextEditingController(text: message.message);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('메시지 수정'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '수정할 내용을 입력하세요',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newMessage = controller.text.trim();
              if (newMessage.isEmpty || _messagesProvider == null) return;

              Navigator.pop(context);

              final success = await _messagesProvider!.updateMessage(
                messageId: message.id,
                newMessage: newMessage,
              );

              if (!success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('메시지 수정 실패')),
                );
              }
            },
            child: const Text('수정'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(TempGroupMessageModel message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('메시지 삭제'),
        content: const Text('이 메시지를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              if (_messagesProvider == null) return;

              final success = await _messagesProvider!.deleteMessage(message.id);

              if (!success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('메시지 삭제 실패')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildInputArea(),
        ],
      ),
    );
  }

  // ✅✅✅ AppBar (TempGroupModel의 memberCount 사용)
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_group?.groupName ?? '채팅', style: const TextStyle(fontSize: 16)),
          if (_group != null)
            Text(
              '${_group!.memberCount}명 · ${_group!.formattedRemainingTime}', // ✅ _group.memberCount
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
      actions: [
        Center(
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                const Icon(Icons.people, size: 20),
                const SizedBox(width: 4),
                Text(
                  '${_group?.memberCount ?? 0}', // ✅ _group.memberCount
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageList() {
    return Consumer<TempGroupMessagesProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.getMessages(widget.groupId).isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final messages = provider.getMessages(widget.groupId);

        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text('첫 메시지를 보내보세요!', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: messages.length + (_isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (_isLoadingMore && index == 0) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final messageIndex = _isLoadingMore ? index - 1 : index;
            final message = messages[messageIndex];

            bool showDateSeparator = false;
            if (messageIndex == 0) {
              showDateSeparator = true;
            } else {
              final prevMessage = messages[messageIndex - 1];
              showDateSeparator = message.dateOnly != prevMessage.dateOnly;
            }

            return Column(
              children: [
                if (showDateSeparator) DateSeparator(date: message.createdAt),
                
                // ✅✅✅ 이미지 메시지 미리보기
                message.type == MessageType.image
                    ? _buildImageMessage(message)
                    : MessageBubble(
                        message: message,
                        isMe: message.userId == widget.userId,
                        senderName: message.userId,
                        onLongPress: () => _showMessageOptions(message),
                      ),
              ],
            );
          },
        );
      },
    );
  }

  // ✅✅✅ 이미지 메시지 위젯
  Widget _buildImageMessage(TempGroupMessageModel message) {
    final isMe = message.userId == widget.userId;
    
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left: isMe ? 64 : 8,
          right: isMe ? 8 : 64,
          top: 4,
          bottom: 4,
        ),
        child: GestureDetector(
          onLongPress: () => _showMessageOptions(message),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // 발신자 이름 (다른 사람 메시지만)
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Text(
                    message.userId,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              
              // 이미지 컨테이너
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isMe ? Colors.blue[100] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 이미지 아이콘 (임시)
                    Container(
                      width: 200,
                      height: 150,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.image,
                            size: 60,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '이미지',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // 파일명
                    Text(
                      message.message.replaceAll('[이미지] ', ''),
                      style: const TextStyle(fontSize: 12),
                    ),
                    
                    // 시간
                    Text(
                      message.formattedTime,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                      ),
                    ),
                    
                    // 수정/삭제 표시
                    if (message.isEdited)
                      Text(
                        '(수정됨)',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅✅✅ 입력 영역 (이미지 버튼 활성화)
  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // ✅ 이미지 선택 버튼 (활성화)
            IconButton(
              onPressed: _pickAndSendImage,
              icon: Icon(Icons.add_circle_outline, color: Colors.grey[600]),
              tooltip: '이미지 전송',
            ),
            
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    hintText: '메시지 입력...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            
            IconButton(
              onPressed: _sendMessage,
              icon: const Icon(Icons.send, color: Colors.blue),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messagesProvider?.unsubscribeFromMessages();
    super.dispose();
  }
}