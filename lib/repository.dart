import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';
import 'services_filesystem.dart';
import 'services_indexdb.dart';

class Repository {
  final FileSystemService fs;
  final IndexDb index;
  Repository(this.fs, this.index);

  Future<Folder> createFolder(String name, {String? parentId}) async {
    final now = DateTime.now();
    final folder = Folder(
      id: generateId(),
      name: name,
      parentId: parentId,
      createdAt: now,
      updatedAt: now,
      pinned: false,
    );
    if (!kIsWeb) {
      await fs.ensureFolderDir(folder.id, folder.name);
    }
    await index.upsertFolder(
      id: folder.id,
      parentId: parentId,
      name: name,
      createdAt: now,
      updatedAt: now,
    );
    return folder;
  }

  Future<Note> createNote(
    Folder folder, {
    required String title,
    String content = '',
  }) async {
    final now = DateTime.now();
    final note = Note(
      id: generateId(),
      folderId: folder.id,
      title: title,
      content: content,
      createdAt: now,
      updatedAt: now,
      status: NoteStatus.idea,
      pinned: false,
      deletedAt: null,
    );

    if (!kIsWeb) {
      await fs.createNoteFile(
        folderId: folder.id,
        folderName: folder.name,
        noteId: note.id,
        title: title,
        content: content,
      );
    }

    final preview = content.length > 140 ? content.substring(0, 140) : content;
    await index.upsertNote(
      id: note.id,
      folderId: folder.id,
      title: title,
      contentPreview: preview,
      createdAt: now,
      updatedAt: now,
      // Dla Web zapiszemy też pełną treść w DB
      content: kIsWeb ? content : null,
      status: note.status.name,
      pinned: note.pinned,
      deletedAt: null,
    );
    return note;
  }

  Future<List<Folder>> listFolders({
    SortBy sortBy = SortBy.updatedAtDesc,
  }) async {
    final orderBy = 'pinned DESC, ${_sortToOrderBy(sortBy)}';
    final rows = await index.listFolders(orderBy: orderBy);
    return rows
        .map(
          (row) => Folder(
            id: row['id'] as String,
            name: row['name'] as String,
            parentId: row['parentId'] as String?,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['createdAt'] as int,
            ),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              row['updatedAt'] as int,
            ),
            pinned: ((row['pinned'] ?? 0) as int) == 1,
          ),
        )
        .toList();
  }

  Future<List<Note>> listRecentNotes({
    int limit = 20,
    bool onlyLast7Days = false,
    NoteStatus? status,
  }) async {
    final rows = await index.listRecentNotes(limit: limit);
    var notes = rows.map(
      (row) => Note(
        id: row['id'] as String,
        folderId: row['folderId'] as String,
        title: row['title'] as String,
        content: row['contentPreview'] as String, // Preview only for listing
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['createdAt'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updatedAt'] as int),
        status: _parseStatus(row['status'] as String?),
        pinned: ((row['pinned'] ?? 0) as int) == 1,
        deletedAt: (row['deletedAt'] != null)
            ? DateTime.fromMillisecondsSinceEpoch(row['deletedAt'] as int)
            : null,
      ),
    );
    if (status != null) {
      notes = notes.where((n) => n.status == status);
    }
    if (!onlyLast7Days) return notes.toList();
    final threshold = DateTime.now().subtract(const Duration(days: 7));
    return notes.where((n) => n.updatedAt.isAfter(threshold)).toList();
  }

  Future<List<SearchResult>> searchNotes(String query) async {
    if (query.trim().isEmpty) return [];
    final rows = await index.searchNotes(query);
    return rows
        .map(
          (row) => SearchResult(
            Note(
              id: row['id'] as String,
              folderId: row['folderId'] as String,
              title: row['title'] as String,
              content: row['contentPreview'] as String,
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                row['createdAt'] as int,
              ),
              updatedAt: DateTime.fromMillisecondsSinceEpoch(
                row['updatedAt'] as int,
              ),
              status: _parseStatus(row['status'] as String?),
              pinned: ((row['pinned'] ?? 0) as int) == 1,
              deletedAt: (row['deletedAt'] != null)
                  ? DateTime.fromMillisecondsSinceEpoch(row['deletedAt'] as int)
                  : null,
            ),
          ),
        )
        .toList();
  }

  Future<Note> loadNote(String noteId) async {
    final meta = await index.getNoteMeta(noteId);
    if (meta == null) throw Exception('Note not found: $noteId');

    String content;
    String title = meta['title'] as String;

    if (kIsWeb) {
      content = await index.getNoteContent(noteId) ?? '';
    } else {
      final folderMeta = await index.getFolder(meta['folderId'] as String);
      if (folderMeta == null)
        throw Exception('Folder not found for note: $noteId');
      final fileData = await fs.readNoteFile(
        folderId: meta['folderId'] as String,
        folderName: folderMeta['name'] as String,
        noteId: noteId,
      );
      title = fileData['title'] ?? title;
      content = fileData['content'] ?? '';
    }

    return Note(
      id: noteId,
      folderId: meta['folderId'] as String,
      title: title,
      content: content,
      createdAt: DateTime.fromMillisecondsSinceEpoch(meta['createdAt'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(meta['updatedAt'] as int),
      status: _parseStatus(meta['status'] as String?),
      pinned: ((meta['pinned'] ?? 0) as int) == 1,
      deletedAt: (meta['deletedAt'] != null)
          ? DateTime.fromMillisecondsSinceEpoch(meta['deletedAt'] as int)
          : null,
    );
  }

  Future<void> saveNote(Note note) async {
    if (kIsWeb) {
      // Ensure we never accidentally overwrite non-empty content with empty string
      String contentToPersist = note.content;
      final existing = await index.getNoteContent(note.id) ?? '';
      if (contentToPersist.isEmpty && existing.isNotEmpty) {
        contentToPersist = existing;
      }

      // 1) Zapis treści do IndexedDB
      await index.updateNoteContent(
        id: note.id,
        content: contentToPersist,
        updatedAt: note.updatedAt,
      );
      // 2) Weryfikacja: odczytaj i porównaj
      final stored = await index.getNoteContent(note.id) ?? '';
      if (stored != contentToPersist) {
        throw Exception(
          'Weryfikacja zapisu (Web) nie powiodła się: treść różni się od źródła',
        );
      }
      // 3) Aktualizacja metadanych (z finalnym contentem)
      final preview = contentToPersist.length > 140
          ? contentToPersist.substring(0, 140)
          : contentToPersist;
      await index.updateNoteMeta(
        id: note.id,
        title: note.title,
        contentPreview: preview,
        updatedAt: note.updatedAt,
      );
      return;
    }

    final folderMeta = await index.getFolder(note.folderId);
    if (folderMeta == null)
      throw Exception('Folder not found: ${note.folderId}');

    // Read existing content to guard against accidental wipe
    final existingFileData = await fs.readNoteFile(
      folderId: note.folderId,
      folderName: folderMeta['name'] as String,
      noteId: note.id,
    );
    String existingContent = existingFileData['content'] ?? '';
    String contentToPersist = note.content;
    if (contentToPersist.isEmpty && existingContent.isNotEmpty) {
      contentToPersist = existingContent;
    }

    // 1) Zapis pliku na dysku (title + pusta linia + content)
    await fs.saveNoteFile(
      folderId: note.folderId,
      folderName: folderMeta['name'] as String,
      noteId: note.id,
      title: note.title,
      content: contentToPersist,
    );

    // 2) Weryfikacja: odczytaj i porównaj (z uwzględnieniem normalizacji w zapisie)
    final fileData = await fs.readNoteFile(
      folderId: note.folderId,
      folderName: folderMeta['name'] as String,
      noteId: note.id,
    );
    final String persistedTitle = fileData['title'] ?? '';
    final String persistedContent = fileData['content'] ?? '';
    // Normalizacja w taki sam sposób jak podczas zapisu (usuwamy wiodące nowe linie)
    final String expectedContent = contentToPersist.replaceFirst(
      RegExp(r'^\r?\n+'),
      '',
    );
    if (persistedTitle != note.title || persistedContent != expectedContent) {
      throw Exception(
        'Weryfikacja zapisu (Desktop) nie powiodła się: tytuł/treść różnią się od źródła',
      );
    }

    // 3) Aktualizacja metadanych w indeksie na podstawie finalnej treści
    final preview = contentToPersist.length > 140
        ? contentToPersist.substring(0, 140)
        : contentToPersist;
    await index.updateNoteMeta(
      id: note.id,
      title: note.title,
      contentPreview: preview,
      updatedAt: note.updatedAt,
    );
  }

  Future<void> deleteNoteById(String noteId) async {
    final meta = await index.getNoteMeta(noteId);
    if (meta == null) return;

    // Soft delete: ustaw deletedAt i zaktualizuj updatedAt
    final now = DateTime.now();
    await index.softDeleteNote(noteId, now);

    if (!kIsWeb) {
      // Opcjonalnie: nie usuwamy fizycznych plików przy soft delete
    }
  }

  Future<void> restoreNote(String noteId) async {
    await index.restoreNote(noteId);
  }

  Future<void> purgeDeleted({int olderThanDays = 30}) async {
    final threshold = DateTime.now()
        .subtract(Duration(days: olderThanDays))
        .millisecondsSinceEpoch;
    await index.purgeDeletedNotes(threshold);
  }

  Future<void> setNoteStatus(String noteId, NoteStatus status) async {
    await index.setNoteStatus(
      id: noteId,
      status: status.name,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> setNotePinned(String noteId, bool pinned) async {
    await index.setNotePinned(
      id: noteId,
      pinned: pinned,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> deleteFolder(String folderId) async {
    final folderMeta = await index.getFolder(folderId);
    if (folderMeta == null) return;
    if (!kIsWeb) {
      await fs.deleteFolderDir(
        folderId: folderId,
        folderName: folderMeta['name'] as String,
      );
    }
    await index.deleteNotesByFolder(folderId);
    await index.deleteFolder(folderId);
  }

  Future<void> renameFolder(String folderId, String newName) async {
    final folderMeta = await index.getFolder(folderId);
    if (folderMeta == null) return;
    final oldName = folderMeta['name'] as String;
    if (!kIsWeb) {
      await fs.renameFolderDir(
        folderId: folderId,
        oldName: oldName,
        newName: newName,
      );
    }
    await index.updateFolderName(
      id: folderId,
      name: newName,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> setFolderPinned(String folderId, bool pinned) async {
    await index.setFolderPinned(
      id: folderId,
      pinned: pinned,
      updatedAt: DateTime.now(),
    );
  }

  Future<Folder> getOrCreateFolderByName(String name) async {
    final rows = await index.listFolders(orderBy: 'updatedAt DESC');
    Map<String, Object?>? found;
    for (final r in rows) {
      final n = (r['name'] as String?)?.toLowerCase() ?? '';
      if (n == name.toLowerCase()) {
        found = r;
        break;
      }
    }
    if (found != null) {
      return Folder(
        id: found['id'] as String,
        name: found['name'] as String,
        parentId: found['parentId'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          found['createdAt'] as int,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          found['updatedAt'] as int,
        ),
        pinned: ((found['pinned'] ?? 0) as int) == 1,
      );
    }
    return createFolder(name);
  }

  // NEW: list notes inside a folder
  Future<List<Note>> listNotesInFolder(
    String folderId, {
    SortBy sortBy = SortBy.updatedAtDesc,
  }) async {
    final orderBy = _noteSortToOrderBy(sortBy);
    final rows = await index.listNotes(folderId, orderBy);
    return rows
        .map(
          (row) => Note(
            id: row['id'] as String,
            folderId: row['folderId'] as String,
            title: row['title'] as String,
            content: row['contentPreview'] as String,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['createdAt'] as int,
            ),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              row['updatedAt'] as int,
            ),
            status: _parseStatus(row['status'] as String?),
            pinned: ((row['pinned'] ?? 0) as int) == 1,
            deletedAt: (row['deletedAt'] != null)
                ? DateTime.fromMillisecondsSinceEpoch(row['deletedAt'] as int)
                : null,
          ),
        )
        .toList();
  }

  String _sortToOrderBy(SortBy sortBy) {
    switch (sortBy) {
      case SortBy.updatedAtDesc:
        return 'updatedAt DESC';
      case SortBy.updatedAtAsc:
        return 'updatedAt ASC';
      case SortBy.titleAsc:
        return 'name ASC';
      case SortBy.titleDesc:
        return 'name DESC';
    }
  }

  // NEW: order by for notes table
  String _noteSortToOrderBy(SortBy sortBy) {
    switch (sortBy) {
      case SortBy.updatedAtDesc:
        return 'pinned DESC, updatedAt DESC';
      case SortBy.updatedAtAsc:
        return 'pinned DESC, updatedAt ASC';
      case SortBy.titleAsc:
        return 'pinned DESC, title ASC';
      case SortBy.titleDesc:
        return 'pinned DESC, title DESC';
    }
  }

  // Helper: bezpieczne mapowanie string->NoteStatus z domyślną wartością
  NoteStatus _parseStatus(String? s) {
    if (s == null || s.isEmpty) return NoteStatus.idea;
    try {
      return NoteStatus.values.firstWhere((e) => e.name == s);
    } catch (_) {
      return NoteStatus.idea;
    }
  }

  Future<List<Note>> listTrashedNotes({
    SortBy sortBy = SortBy.updatedAtDesc,
  }) async {
    final orderBy = _noteSortToOrderBy(sortBy);
    final rows = await index.listTrashedNotes(orderBy: orderBy);
    return rows
        .map(
          (row) => Note(
            id: row['id'] as String,
            folderId: row['folderId'] as String,
            title: row['title'] as String,
            content: row['contentPreview'] as String,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['createdAt'] as int,
            ),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              row['updatedAt'] as int,
            ),
            status: _parseStatus(row['status'] as String?),
            pinned: ((row['pinned'] ?? 0) as int) == 1,
            deletedAt: (row['deletedAt'] != null)
                ? DateTime.fromMillisecondsSinceEpoch(row['deletedAt'] as int)
                : null,
          ),
        )
        .toList();
  }
}

final repositoryProvider = Provider<Repository>((ref) {
  return Repository(FileSystemService(), IndexDb());
});
