// lib/widgets/message_bubble.dart
// ✅ 메시지 버블 위젯

import 'package:flutter/material.dart';
import '../models/temp_group_message_model.dart';

class MessageBubble extends StatelessWidget {
  final TempGroupMessageModel message;
  final bool isMe;
  final VoidCallback? onLongPress;
  final String? senderName; // 발신자 이름 (선택)

  const MessageBubble({
    Key? key,
    required this.message,
    required this.isMe,
    this.onLongPress,
    this.senderName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 시스템 메시지
    if (message.isSystemMessage) {
      return _buildSystemMessage(context);
    }

    // 일반 메시지
    return _buildUserMessage(context);
  }

  // ═══════════════════════════════════════════════════════════
  // 시스템 메시지
  // ═══════════════════════════════════════════════════════════
  Widget _buildSystemMessage(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message.message,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 일반 메시지
  // ═══════════════════════════════════════════════════════════
  Widget _buildUserMessage(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 내 메시지: 시간 왼쪽
            if (isMe) ...[
              _buildTime(),
              const SizedBox(width: 4),
            ],
            
            // 메시지 버블
            Flexible(
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  // 발신자 이름 (다른 사람 메시지만)
                  if (!isMe && senderName != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 4),
                      child: Text(
                        senderName!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  
                  // 메시지 내용
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.blue[600] : Colors.grey[200],
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
                        bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 메시지 텍스트
                        Text(
                          message.isDeleted ? '삭제된 메시지입니다' : message.message,
                          style: TextStyle(
                            fontSize: 15,
                            color: message.isDeleted
                                ? (isMe ? Colors.white70 : Colors.grey[500])
                                : (isMe ? Colors.white : Colors.black87),
                            fontStyle: message.isDeleted ? FontStyle.italic : FontStyle.normal,
                          ),
                        ),
                        
                        // 수정됨 표시
                        if (message.isEdited && !message.isDeleted) ...[
                          const SizedBox(height: 2),
                          Text(
                            '수정됨',
                            style: TextStyle(
                              fontSize: 10,
                              color: isMe ? Colors.white60 : Colors.grey[500],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // 다른 사람 메시지: 시간 오른쪽
            if (!isMe) ...[
              const SizedBox(width: 4),
              _buildTime(),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 시간 표시
  // ═══════════════════════════════════════════════════════════
  Widget _buildTime() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        message.formattedTime,
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey[600],
        ),
      ),
    );
  }
}