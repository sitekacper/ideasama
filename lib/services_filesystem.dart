import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Filesystem layout:
/// rootDir/
///   folders.db (sqlite index, future use)
///   data/
///     FOLDER_ID__FOLDER_NAME/
///       NOTE_ID.txt
///
class FileSystemService {
  Directory? _root;

  Future<Directory> getRoot() async {
    if (kIsWeb) {
      throw UnsupportedError('FileSystemService is not supported on Web');
    }
    if (_root != null) return _root!;
    final appDir = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(appDir.path, 'ideasamaapp'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    final data = Directory(p.join(root.path, 'data'));
    if (!await data.exists()) {
      await data.create(recursive: true);
    }
    _root = root;
    return root;
  }

  Future<Directory> ensureFolderDir(String folderId, String folderName) async {
    if (kIsWeb) {
      throw UnsupportedError('FileSystemService is not supported on Web');
    }
    final root = await getRoot();
    final dir = Directory(p.join(root.path, 'data', '${folderId}__${folderName.trim()}'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _noteFile(String folderId, String folderName, String noteId) async {
    final dir = await ensureFolderDir(folderId, folderName);
    return File(p.join(dir.path, '$noteId.txt'));
  }

  Future<File> createNoteFile({
    required String folderId,
    required String folderName,
    required String noteId,
    required String title,
    required String content,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('FileSystemService is not supported on Web');
    }
    final file = await _noteFile(folderId, folderName, noteId);
    await file.writeAsString('$title\n\n$content');
    return file;
  }

  Future<void> updateNoteFile({
    required String folderId,
    required String folderName,
    required String noteId,
    required String title,
    required String content,
  }) async {
    final file = await _noteFile(folderId, folderName, noteId);
    await file.writeAsString('$title\n\n$content');
  }

  Future<void> deleteNoteFile({
    required String folderId,
    required String folderName,
    required String noteId,
  }) async {
    final file = await _noteFile(folderId, folderName, noteId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  // Added methods expected by Repository
  Future<Map<String, String>> readNoteFile({
    required String folderId,
    required String folderName,
    required String noteId,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('FileSystemService is not supported on Web');
    }
    final file = await _noteFile(folderId, folderName, noteId);
    if (!await file.exists()) {
      return {'title': '', 'content': ''};
    }
    final text = await file.readAsString();
    final lines = text.split(RegExp(r'\r?\n'));
    final String title = lines.isNotEmpty ? lines.first : '';
    final String content = lines.length > 1 ? lines.sublist(1).join('\n') : '';
    return {'title': title, 'content': content};
  }

  Future<void> saveNoteFile({
    required String folderId,
    required String folderName,
    required String noteId,
    required String title,
    required String content,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('FileSystemService is not supported on Web');
    }
    final file = await _noteFile(folderId, folderName, noteId);
    await file.writeAsString('$title\n\n$content');
  }

  Future<void> deleteFolderDir({
    required String folderId,
    required String folderName,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('FileSystemService is not supported on Web');
    }
    final root = await getRoot();
    final dir = Directory(p.join(root.path, 'data', '${folderId}__${folderName.trim()}'));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> renameFolderDir({
    required String folderId,
    required String oldName,
    required String newName,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('FileSystemService is not supported on Web');
    }
    final root = await getRoot();
    final from = Directory(p.join(root.path, 'data', '${folderId}__${oldName.trim()}'));
    final to = Directory(p.join(root.path, 'data', '${folderId}__${newName.trim()}'));
    if (await from.exists()) {
      await to.parent.create(recursive: true);
      await from.rename(to.path);
    } else {
      await to.create(recursive: true);
    }
  }
}