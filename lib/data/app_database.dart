import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// SQLite handle for ChatHalis, opened once per process.
class AppDatabase {
  AppDatabase._();

  static Database? _db;

  static Future<Database> get() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'chathalis.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE conversations(
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL DEFAULT '',
            last_preview TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE messages(
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            seq INTEGER NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL DEFAULT '',
            reasoning TEXT NOT NULL DEFAULT '',
            state TEXT NOT NULL DEFAULT 'ok',
            error TEXT,
            finish_reason TEXT,
            reasoning_ms INTEGER,
            created_at INTEGER NOT NULL,
            FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE UNIQUE INDEX idx_messages_conv_seq ON messages(conversation_id, seq)',
        );
      },
    );
    return _db!;
  }
}
