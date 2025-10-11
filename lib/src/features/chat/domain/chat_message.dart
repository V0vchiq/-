import 'package:uuid/uuid.dart';

enum ChatSender { user, assistant, system }

class ChatMessage {
  ChatMessage({required this.sender, required this.content, DateTime? timestamp, String? id})
      : timestamp = timestamp ?? DateTime.now(),
        id = id ?? const Uuid().v4();

  final String id;
  final ChatSender sender;
  final String content;
  final DateTime timestamp;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender': sender.name,
      'content': content,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      sender: ChatSender.values.firstWhere((element) => element.name == json['sender']),
      content: json['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
    );
  }
}
