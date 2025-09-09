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

  // -- helpers --
  /// Ensure we always store exactly one empty line between title and content.
  /// Trims any leading new lines from content to avoid accumulating blank lines
  /// when saving multiple times.
  String _normalizeContentForWrite(String content) {
    return content.replaceFirst(RegExp(r'^\r?\n+'), '');
  }

  /// Compose final file payload from title and content with a single blank line separator.
  String _composePayload({required String title, required String content}) {
    final body = _normalizeContentForWrite(content);
    return '$title\n\n$body';
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
    // Write title + one empty line + content
    await file.writeAsString(
      _composePayload(title: title, content: content),
      mode: FileMode.write,
      flush: true,
    );
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
    await file.writeAsString(
      _composePayload(title: title, content: content),
      mode: FileMode.write,
      flush: true,
    );
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
    // Skip a single blank line after the title if present (our separator)
    int startIndex = 1;
    if (lines.length >= 2 && lines[1].trim().isEmpty) {
      startIndex = 2;
    }
    final String content = lines.length > startIndex ? lines.sublist(startIndex).join('\n') : '';
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
    await file.writeAsString(
      _composePayload(title: title, content: content),
      mode: FileMode.write,
      flush: true,
    );
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