import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';
import 'repository.dart';

// Home screen state
class HomeState {
  final List<Folder> folders;
  final List<Note> recentNotes;
  final List<SearchResult> searchResults;
  final bool isLoading;
  final String? error;
  final String searchQuery;
  final SortBy sortBy;
  final bool showLast7Days;
  final NoteStatus? statusFilter;

  const HomeState({
    this.folders = const [],
    this.recentNotes = const [],
    this.searchResults = const [],
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
    this.sortBy = SortBy.updatedAtDesc,
    this.showLast7Days = false,
    this.statusFilter,
  });

  HomeState copyWith({
    List<Folder>? folders,
    List<Note>? recentNotes,
    List<SearchResult>? searchResults,
    bool? isLoading,
    String? error,
    String? searchQuery,
    SortBy? sortBy,
    bool? showLast7Days,
    NoteStatus? statusFilter,
    bool updateStatusFilter = false,
  }) {
    return HomeState(
      folders: folders ?? this.folders,
      recentNotes: recentNotes ?? this.recentNotes,
      searchResults: searchResults ?? this.searchResults,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      searchQuery: searchQuery ?? this.searchQuery,
      sortBy: sortBy ?? this.sortBy,
      showLast7Days: showLast7Days ?? this.showLast7Days,
      statusFilter: updateStatusFilter ? statusFilter : (statusFilter ?? this.statusFilter),
    );
  }
}

// Home ViewModel
class HomeViewModel extends StateNotifier<HomeState> {
  final Repository _repository;
  Timer? _searchDebounce;

  HomeViewModel(this._repository) : super(const HomeState()) {
    loadData();
  }

  Future<void> loadData() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final folders = await _repository.listFolders(sortBy: state.sortBy);
      final recentNotes = await _repository.listRecentNotes(
        onlyLast7Days: state.showLast7Days,
        status: state.statusFilter,
      );
      state = state.copyWith(
        folders: folders,
        recentNotes: recentNotes,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setSortBy(SortBy sortBy) {
    state = state.copyWith(sortBy: sortBy);
    // Reload folders (and recent notes) to reflect new sort order
    loadData();
  }

  void toggleShowLast7Days() {
    state = state.copyWith(showLast7Days: !state.showLast7Days);
    loadData();
  }

  void setStatusFilter(NoteStatus? status) {
    state = state.copyWith(statusFilter: status, updateStatusFilter: true);
    loadData();
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      state = state.copyWith(searchResults: []);
      return;
    }
    try {
      final results = await _repository.searchNotes(query);
      state = state.copyWith(searchResults: results);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteNoteById(String noteId) async {
    try {
      await _repository.deleteNoteById(noteId);
      // Usuń z recentNotes i searchResults
      final updatedRecent = state.recentNotes.where((n) => n.id != noteId).toList();
      final updatedSearch = state.searchResults.where((r) => r.note.id != noteId).toList();
      state = state.copyWith(recentNotes: updatedRecent, searchResults: updatedSearch);
      // Jeśli aktywne wyszukiwanie, odśwież wyniki (na wypadek dodatkowych dopasowań)
      if (state.searchQuery.trim().isNotEmpty) {
        await _performSearch(state.searchQuery);
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  // Przywróć notatkę z kosza
  Future<void> restoreNote(String noteId) async {
    try {
      await _repository.restoreNote(noteId);
      await loadData();
      if (state.searchQuery.trim().isNotEmpty) {
        await _performSearch(state.searchQuery);
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  // Ustaw status notatki
  Future<void> setNoteStatus(String noteId, NoteStatus status) async {
    try {
      await _repository.setNoteStatus(noteId, status);
      await loadData();
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  // Przełącz przypięcie notatki
  Future<void> toggleNotePinned(String noteId) async {
    try {
      final current = state.recentNotes.firstWhere((n) => n.id == noteId, orElse: () => state.recentNotes.isNotEmpty ? state.recentNotes.first : throw Exception('Note not in recent list'));
      await _repository.setNotePinned(noteId, !current.pinned);
      await loadData();
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> deleteFolder(String folderId) async {
    try {
      await _repository.deleteFolder(folderId);
      // Przeładuj dane (foldery i ostatnie notatki)
      await loadData();
      if (state.searchQuery.trim().isNotEmpty) {
        await _performSearch(state.searchQuery);
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> renameFolder(String folderId, String newName) async {
    try {
      await _repository.renameFolder(folderId, newName);
      // Update local state
      final updated = state.folders.map((f) => f.id == folderId
          ? Folder(
              id: f.id,
              name: newName,
              parentId: f.parentId,
              createdAt: f.createdAt,
              updatedAt: DateTime.now(),
              pinned: f.pinned,
            )
          : f).toList();
      state = state.copyWith(folders: updated);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> toggleFolderPinned(String folderId) async {
    try {
      final current = state.folders.firstWhere((f) => f.id == folderId);
      await _repository.setFolderPinned(folderId, !current.pinned);
      // Reload folders to reflect pin order
      await loadData();
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<Folder> createFolder(String name) async {
    try {
      final folder = await _repository.createFolder(name);
      state = state.copyWith(folders: [...state.folders, folder]);
      return folder;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<Note> createNote(Folder folder, String title) async {
    try {
      final note = await _repository.createNote(folder, title: title);
      state = state.copyWith(recentNotes: [note, ...state.recentNotes]);
      return note;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}

final homeViewModelProvider = StateNotifierProvider<HomeViewModel, HomeState>((ref) {
  return HomeViewModel(ref.read(repositoryProvider));
});

// Note Editor state
class NoteEditorState {
  final Note? note;
  final bool isLoading;
  final bool isSaving;
  final String? error;
  final bool hasUnsavedChanges;

  const NoteEditorState({
    this.note,
    this.isLoading = false,
    this.isSaving = false,
    this.error,
    this.hasUnsavedChanges = false,
  });

  NoteEditorState copyWith({
    Note? note,
    bool? isLoading,
    bool? isSaving,
    String? error,
    bool? hasUnsavedChanges,
  }) {
    return NoteEditorState(
      note: note ?? this.note,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      error: error ?? this.error,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
    );
  }
}

// Note Editor ViewModel with autosave
class NoteEditorViewModel extends StateNotifier<NoteEditorState> {
  final Repository _repository;
  Timer? _saveDebounce;

  NoteEditorViewModel(this._repository, String noteId) : super(const NoteEditorState()) {
    loadNote(noteId);
  }

  Future<void> loadNote(String noteId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final note = await _repository.loadNote(noteId);
      state = state.copyWith(note: note, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void updateTitle(String title) {
    final note = state.note;
    if (note == null) return;
    
    final updatedNote = Note(
      id: note.id,
      folderId: note.folderId,
      title: title,
      content: note.content,
      createdAt: note.createdAt,
      updatedAt: DateTime.now(),
      status: note.status,
      pinned: note.pinned,
      deletedAt: note.deletedAt,
    );
    
    state = state.copyWith(note: updatedNote, hasUnsavedChanges: true);
    _scheduleAutoSave();
  }

  void updateContent(String content) {
    final note = state.note;
    if (note == null) return;
    
    final updatedNote = Note(
      id: note.id,
      folderId: note.folderId,
      title: note.title,
      content: content,
      createdAt: note.createdAt,
      updatedAt: DateTime.now(),
      status: note.status,
      pinned: note.pinned,
      deletedAt: note.deletedAt,
    );
    
    state = state.copyWith(note: updatedNote, hasUnsavedChanges: true);
    _scheduleAutoSave();
  }

  void _scheduleAutoSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      _autoSave();
    });
  }

  Future<void> _autoSave() async {
    final note = state.note;
    if (note == null || !state.hasUnsavedChanges) return;
    
    state = state.copyWith(isSaving: true);
    try {
      await _repository.saveNote(note);
      state = state.copyWith(isSaving: false, hasUnsavedChanges: false);
    } catch (e) {
      state = state.copyWith(isSaving: false, error: e.toString());
    }
  }

  Future<void> forceSave() async {
    _saveDebounce?.cancel();
    await _autoSave();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }
}

final noteEditorViewModelProvider = StateNotifierProvider.family<NoteEditorViewModel, NoteEditorState, String>((ref, noteId) {
  return NoteEditorViewModel(ref.read(repositoryProvider), noteId);
});