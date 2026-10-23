import 'package:sqflite/sqflite.dart' show Database, Sqflite;

import '../core/utils.dart';
import '../gateway/models.dart';
import 'app_database.dart';

/// All persistence goes through this repository — no SQL outside this file.
class ChatRepository {
  ChatRepository._();
  static final instance = ChatRepository._();

  Future<Database> get _db => AppDatabase.get();

  // ------------------------------------------------------------------ writes

  Future<void> createConversation(Conversation c) async {
    final db = await _db;
    await db.insert('conversations', {
      'id': c.id,
      'title': c.title,
      'last_preview': c.lastPreview,
      'created_at': c.createdAt.millisecondsSinceEpoch,
      'updated_at': c.updatedAt.millisecondsSinceEpoch,
    });
  }

  Future<void> ensureConversation(Conversation c) async {
    final db = await _db;
    final exists = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM conversations WHERE id = ?', [c.id]),
    );
    if (exists == 0) await createConversation(c);
  }

  Future<void> renameConversation(String id, String title) async {
    final db = await _db;
    await db.update(
      'conversations',
      {'title': title},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Persists a message snapshot; assigns `seq` from the conversation counter.
  Future<void> insertMessage(String conversationId, ChatMessage m) async {
    final db = await _db;
    await db.transaction((txn) async {
      final next = (Sqflite.firstIntValue(
        await txn.rawQuery(
          'SELECT COALESCE(MAX(seq), 0) + 1 FROM messages WHERE conversation_id = ?',
          [conversationId],
        ),
      )) ?? 1;
      await txn.insert('messages', _messageRow(conversationId, m, next));
      await txn.update(
        'conversations',
        {
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'last_preview': m.role == Role.user
              ? HalisUtils.previewOf(m.content)
              : _lastPreviewValue(m),
        },
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    });
  }

  static String _lastPreviewValue(ChatMessage m) {
    final base = m.content.trim().isNotEmpty ? m.content : m.reasoning;
    return HalisUtils.previewOf(base);
  }

  Map<String, Object?> _messageRow(String conversationId, ChatMessage m, int seq) => {
        'id': m.id,
        'conversation_id': conversationId,
        'seq': seq,
        'role': m.role.name,
        'content': m.content,
        'reasoning': m.reasoning,
        'state': m.state.name,
        'error': m.error,
        'finish_reason': m.truncated ? 'length' : 'stop',
        'reasoning_ms': m.reasoningMs,
        'created_at': m.createdAt.millisecondsSinceEpoch,
      };

  Future<void> deleteConversation(String id) async {
    final db = await _db;
    await db.delete('conversations', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAll() async {
    final db = await _db;
    await db.delete('messages');
    await db.delete('conversations');
  }

  // ------------------------------------------------------------------- reads

  Future<List<Conversation>> listConversations() async {
    final db = await _db;
    final rows = await db.query(
      'conversations',
      orderBy: 'updated_at DESC',
    );
    return [
      for (final r in rows)
        Conversation(
          id: r['id']! as String,
          title: (r['title']! as String).isEmpty
              ? 'Cuộc trò chuyện mới'
              : r['title']! as String,
          createdAt:
              DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
          updatedAt:
              DateTime.fromMillisecondsSinceEpoch(r['updated_at']! as int),
          lastPreview: (r['last_preview'] ?? '') as String,
        ),
    ];
  }

  Future<Conversation?> getConversation(String id) async {
    final db = await _db;
    final rows = await db
        .query('conversations', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return Conversation(
      id: r['id']! as String,
      title: (r['title']! as String).isEmpty
          ? 'Cuộc trò chuyện mới'
          : r['title']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at']! as int),
      lastPreview: (r['last_preview'] ?? '') as String,
    );
  }

  Future<List<ChatMessage>> listMessages(String conversationId) async {
    final db = await _db;
    final rows = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'seq ASC',
    );
    return [
      for (final r in rows)
        ChatMessage(
          id: r['id']! as String,
          role: r['role']! as String == 'user' ? Role.user : Role.assistant,
          createdAt:
              DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
          content: (r['content'] ?? '') as String,
          reasoning: (r['reasoning'] ?? '') as String,
          state: switch (r['state'] as String?) {
            'interrupted' => MessageState.interrupted,
            'failed' => MessageState.failed,
            _ => MessageState.ok,
          },
          error: r['error'] as String?,
          truncated: r['finish_reason'] == 'length',
          reasoningMs: r['reasoning_ms'] as int?,
          seq: r['seq'] as int?,
        ),
    ];
  }

  Future<(int, int)> counts() async {
    final db = await _db;
    final convs = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM conversations'),
    );
    final msgs = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM messages'),
    );
    return (convs ?? 0, msgs ?? 0);
  }

  Future<void> deleteMessage(String id) async {
    final db = await _db;
    await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }
}
