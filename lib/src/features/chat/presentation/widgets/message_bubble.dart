import 'package:flutter/material.dart';

import '../../domain/chat_message.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({required this.message, super.key});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = message.sender == ChatSender.user;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    
    final color = isUser 
        ? Colors.blueAccent 
        : (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08));
    final textColor = isUser 
        ? Colors.white 
        : (isDark ? Colors.white70 : const Color(0xFF1a1a2e));

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: SelectableText(
          message.content,
          style: TextStyle(color: textColor, fontSize: 15, height: 1.4),
        ),
      ),
    );
  }
}
