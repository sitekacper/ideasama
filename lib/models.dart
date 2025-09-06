
class Folder {
  final String id;
  final String? parentId;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;
  bool pinned;

  Folder({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
    this.pinned = false,
  });
}

// Status notatki na potrzeby workflow
enum NoteStatus { idea, draft, ready, done, dropped }

class Note {
  final String id;
  final String folderId; // logical parent folder id
  String title;
  String content;
  final DateTime createdAt;
  DateTime updatedAt;
  // Nowe pola
  NoteStatus status;
  bool pinned;
  DateTime? deletedAt; // null = aktywna, !null = w koszu

  Note({
    required this.id,
    required this.folderId,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.status = NoteStatus.idea,
    this.pinned = false,
    this.deletedAt,
  });
}

// Simple ID generator without external deps
String generateId() => DateTime.now().microsecondsSinceEpoch.toString();

// Sort enums
enum SortBy { updatedAtDesc, updatedAtAsc, titleAsc, titleDesc }

// Search result union
class SearchResult {
  final Note note;
  SearchResult(this.note);
}