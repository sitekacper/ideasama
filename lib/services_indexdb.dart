import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

class IndexDb {
  Database? _db;

  Future<void> _onCreate(Database db, int v) async {
    await db.execute('''
        CREATE TABLE folders(
          id TEXT PRIMARY KEY,
          parentId TEXT,
          name TEXT NOT NULL,
          pinned INTEGER NOT NULL DEFAULT 0,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL
        );
      ''');
    await db.execute('''
        CREATE TABLE notes(
          id TEXT PRIMARY KEY,
          folderId TEXT NOT NULL,
          title TEXT NOT NULL,
          contentPreview TEXT NOT NULL,
          content TEXT,
          status TEXT NOT NULL DEFAULT 'idea',
          pinned INTEGER NOT NULL DEFAULT 0,
          deletedAt INTEGER,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL
        );
      ''');
    await db.execute('CREATE INDEX idx_notes_title ON notes(title);');
    await db.execute('CREATE INDEX idx_notes_updated ON notes(updatedAt);');
    await db.execute('CREATE INDEX idx_notes_deleted ON notes(deletedAt);');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE folders ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0;');
    }
    if (oldVersion < 3) {
      // Dodaj kolumnę content do notatek
      await db.execute('ALTER TABLE notes ADD COLUMN content TEXT;');
    }
    if (oldVersion < 4) {
      await db.execute("ALTER TABLE notes ADD COLUMN status TEXT NOT NULL DEFAULT 'idea';");
      await db.execute('ALTER TABLE notes ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0;');
      await db.execute('ALTER TABLE notes ADD COLUMN deletedAt INTEGER;');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_notes_deleted ON notes(deletedAt);');
    }
  }

  Future<Database> _open() async {
    if (_db != null) return _db!;

    if (kIsWeb) {
      final factory = databaseFactoryFfiWeb;
      _db = await factory.openDatabase(
        'idea_app_index.db',
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
    } else {
      final dbDir = await getDatabasesPath();
      final path = p.join(dbDir, 'ideasamaapp_index.db');
      _db = await openDatabase(
        path,
        version: 4,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }

    return _db!;
  }

  Future<void> upsertFolder({
    required String id,
    String? parentId,
    required String name,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    final db = await _open();
    await db.insert('folders', {
      'id': id,
      'parentId': parentId,
      'name': name,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertNote({
    required String id,
    required String folderId,
    required String title,
    required String contentPreview,
    String? content,
    String status = 'idea',
    bool pinned = false,
    DateTime? deletedAt,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    final db = await _open();
    await db.insert('notes', {
      'id': id,
      'folderId': folderId,
      'title': title,
      'contentPreview': contentPreview,
      'content': content,
      'status': status,
      'pinned': pinned ? 1 : 0,
      'deletedAt': deletedAt?.millisecondsSinceEpoch,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> searchNotes(String query) async {
    final db = await _open();
    final q = '%${query.replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
    return db.query('notes',
        where: '(title LIKE ? OR contentPreview LIKE ?) AND deletedAt IS NULL',
        whereArgs: [q, q],
        orderBy: 'updatedAt DESC');
  }

  Future<List<Map<String, Object?>>> listNotes(String folderId, String orderBy) async {
    final db = await _open();
    return db.query('notes', where: 'folderId = ? AND deletedAt IS NULL', whereArgs: [folderId], orderBy: orderBy);
  }

  Future<List<Map<String, Object?>>> listFolders({String orderBy = 'updatedAt DESC'}) async {
    final db = await _open();
    return db.query('folders', orderBy: orderBy);
  }

  // Zwróć notatki znajdujące się w koszu (deletedAt != NULL)
  Future<List<Map<String, Object?>>> listTrashedNotes({String orderBy = 'updatedAt DESC'}) async {
    final db = await _open();
    return db.query('notes', where: 'deletedAt IS NOT NULL', orderBy: orderBy);
  }

  Future<List<Map<String, Object?>>> listRecentNotes({int limit = 50}) async {
    final db = await _open();
    return db.query('notes', where: 'deletedAt IS NULL', orderBy: 'pinned DESC, updatedAt DESC', limit: limit);
  }

  Future<Map<String, Object?>?> getNoteMeta(String id) async {
    final db = await _open();
    final rows = await db.query('notes', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<Map<String, Object?>?> getFolder(String id) async {
    final db = await _open();
    final rows = await db.query('folders', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<void> updateNoteMeta({
    required String id,
    required String title,
    required String contentPreview,
    required DateTime updatedAt,
  }) async {
    final db = await _open();
    await db.update('notes', {
      'title': title,
      'contentPreview': contentPreview,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<String?> getNoteContent(String id) async {
    final db = await _open();
    final rows = await db.query('notes', columns: ['content'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['content'] as String?;
  }

  Future<void> updateNoteContent({
    required String id,
    required String content,
    required DateTime updatedAt,
  }) async {
    final db = await _open();
    await db.update('notes', {
      'content': content,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateFolderName({
    required String id,
    required String name,
    required DateTime updatedAt,
  }) async {
    final db = await _open();
    await db.update('folders', {
      'name': name,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setFolderPinned({
    required String id,
    required bool pinned,
    required DateTime updatedAt,
  }) async {
    final db = await _open();
    await db.update('folders', {
      'pinned': pinned ? 1 : 0,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteNote(String id) async {
    final db = await _open();
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteNotesByFolder(String folderId) async {
    final db = await _open();
    await db.delete('notes', where: 'folderId = ?', whereArgs: [folderId]);
  }

  Future<void> deleteFolder(String id) async {
    final db = await _open();
    await db.delete('folders', where: 'id = ?', whereArgs: [id]);
  }

  // SOFT DELETE: oznacz notatkę jako usuniętą (deletedAt != null)
  Future<void> softDeleteNote(String id, DateTime when) async {
    final db = await _open();
    await db.update('notes', {
      'deletedAt': when.millisecondsSinceEpoch,
      'updatedAt': when.millisecondsSinceEpoch,
    }, where: 'id = ?', whereArgs: [id]);
  }

  // Przywrócenie notatki z kosza
  Future<void> restoreNote(String id) async {
    final db = await _open();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update('notes', {
      'deletedAt': null,
      'updatedAt': now,
    }, where: 'id = ?', whereArgs: [id]);
  }

  // Trwałe usunięcie wszystkich notatek starszych niż próg (tylko tych w koszu)
  Future<void> purgeDeletedNotes(int olderThanMillisSinceEpoch) async {
    final db = await _open();
    await db.delete('notes',
        where: 'deletedAt IS NOT NULL AND deletedAt < ?',
        whereArgs: [olderThanMillisSinceEpoch]);
  }

  // Ustaw status notatki
  Future<void> setNoteStatus({required String id, required String status, required DateTime updatedAt}) async {
    final db = await _open();
    await db.update('notes', {
      'status': status,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    }, where: 'id = ?', whereArgs: [id]);
  }

  // Ustaw przypięcie notatki
  Future<void> setNotePinned({required String id, required bool pinned, required DateTime updatedAt}) async {
    final db = await _open();
    await db.update('notes', {
      'pinned': pinned ? 1 : 0,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    }, where: 'id = ?', whereArgs: [id]);
  }
}