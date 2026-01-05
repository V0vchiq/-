import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/chat_message.dart';
import '../domain/chat_session.dart';

class ChatRepository {
  Database? _database;

  Future<Database> _db() async {
    if (_database != null) {
      return _database!;
    }
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'nexus_chat.db');
    _database = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sessions(
            id TEXT PRIMARY KEY,
            number INTEGER,
            title TEXT,
            created_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE messages(
            id TEXT PRIMARY KEY,
            session_id TEXT,
            sender TEXT,
            content TEXT,
            timestamp INTEGER,
            FOREIGN KEY (session_id) REFERENCES sessions(id)
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Create sessions table
          await db.execute('''
            CREATE TABLE IF NOT EXISTS sessions(
              id TEXT PRIMARY KEY,
              number INTEGER,
              title TEXT,
              created_at INTEGER
            )
          ''');
          // Add session_id column to messages
          await db.execute('ALTER TABLE messages ADD COLUMN session_id TEXT');
        }
      },
    );
    return _database!;
  }

  // Session methods
  Future<List<ChatSession>> loadSessions() async {
    final db = await _db();
    final rows = await db.query('sessions', orderBy: 'number DESC');
    return rows.map((e) => ChatSession.fromJson(e)).toList();
  }

  Future<ChatSession> createSession(String title) async {
    final db = await _db();
    final countResult = await db.rawQuery('SELECT MAX(number) as max_num FROM sessions');
    final maxNum = (countResult.first['max_num'] as int?) ?? 0;
    
    final session = ChatSession(number: maxNum + 1, title: title);
    await db.insert('sessions', session.toJson());
    return session;
  }

  Future<void> updateSessionTitle(String sessionId, String title) async {
    final db = await _db();
    await db.update(
      'sessions',
      {'title': title},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> deleteSession(String sessionId) async {
    final db = await _db();
    await db.delete('messages', where: 'session_id = ?', whereArgs: [sessionId]);
    await db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  // Message methods
  Future<List<ChatMessage>> loadMessages({String? sessionId, int limit = 200}) async {
    final db = await _db();
    final rows = await db.query(
      'messages',
      where: sessionId != null ? 'session_id = ?' : null,
      whereArgs: sessionId != null ? [sessionId] : null,
      orderBy: 'timestamp ASC',
      limit: limit,
    );
    return rows.map((e) => ChatMessage.fromJson(e)).toList();
  }

  Future<void> saveMessage(ChatMessage message, {String? sessionId}) async {
    final db = await _db();
    final json = message.toJson();
    json['session_id'] = sessionId;
    await db.insert(
      'messages',
      json,
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

  Future<void> clearSession(String sessionId) async {
    final db = await _db();
    await db.delete('messages', where: 'session_id = ?', whereArgs: [sessionId]);
  }

  Future<void> clear() async {
    final db = await _db();
    await db.delete('messages');
    await db.delete('sessions');
  }

  Future<void> dispose() async {
    await _database?.close();
    _database = null;
  }
}
