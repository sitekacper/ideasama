
// Core data models for Idea App

// Folder entity
class Folder {
  final String id;
  final String name;
  final String? parentId;
  final DateTime createdAt;
  DateTime updatedAt;
  bool pinned;

  Folder({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdAt,
    required this.updatedAt,
    this.pinned = false,
  });
}

// Status of a note in workflow
enum NoteStatus { idea, draft, ready, done, dropped }

// Note entity
class Note {
  final String id;
  final String folderId; // logical parent folder id
  String title;
  String content;
  final DateTime createdAt;
  DateTime updatedAt;

  // Workflow fields
  NoteStatus status;
  bool pinned;
  DateTime? deletedAt; // null = active, !null = in trash

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

// Sorting options
enum SortBy { updatedAtDesc, updatedAtAsc, titleAsc, titleDesc }

// Search result wrapper
class SearchResult {
  final Note note;
  SearchResult(this.note);
}

// --- AI generation models ---
enum GenerationMode { expand, ideas }

class GeneratedSuggestion {
  final String id;
  final String content;
  const GeneratedSuggestion({required this.id, required this.content});
}

class AiSettings {
  final String openRouterKey;
  final String model;
  final int dailyQuota; // e.g., 2 or 3

  const AiSettings({
    required this.openRouterKey,
    required this.model,
    required this.dailyQuota,
  });

  AiSettings copyWith({String? openRouterKey, String? model, int? dailyQuota}) => AiSettings(
        openRouterKey: openRouterKey ?? this.openRouterKey,
        model: model ?? this.model,
        dailyQuota: dailyQuota ?? this.dailyQuota,
      );
}