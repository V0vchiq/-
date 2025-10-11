import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/chat_message.dart';

class ChatRepository {
  Database? _database;

  Future<Database> _db() async {
    if (_database != null) {
      return _database!;
    }
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'starmind_chat.db');
    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE messages(id TEXT PRIMARY KEY, sender TEXT, content TEXT, timestamp INTEGER)',
        );
      },
    );
    return _database!;
  }

  Future<List<ChatMessage>> loadMessages({int limit = 200}) async {
    final db = await _db();
    final rows = await db.query(
      'messages',
      orderBy: 'timestamp ASC',
      limit: limit,
    );
    return rows.map((e) => ChatMessage.fromJson(e)).toList();
  }

  Future<void> saveMessage(ChatMessage message) async {
    final db = await _db();
    await db.insert(
      'messages',
      message.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ChatMessage>> search(String query) async {
    final db = await _db();
    final rows = await db.query(
      'messages',
      where: 'content LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'timestamp DESC',
      limit: 50,
    );
    return rows.map((e) => ChatMessage.fromJson(e)).toList();
  }

  Future<void> clear() async {
    final db = await _db();
    await db.delete('messages');
  }

  Future<void> dispose() async {
    await _database?.close();
    _database = null;
  }
}
