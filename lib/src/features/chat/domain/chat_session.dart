import 'package:uuid/uuid.dart';

class ChatSession {
  ChatSession({
    String? id,
    required this.number,
    required this.title,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  final String id;
  final int number;
  final String title;
  final DateTime createdAt;

  ChatSession copyWith({String? title}) {
    return ChatSession(
      id: id,
      number: number,
      title: title ?? this.title,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'title': title,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'] as String,
      number: json['number'] as int,
      title: json['title'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
    );
  }
}
