import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart'
    show FocusManager; // potrzebne do chowania klawiatury
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
      var recentNotes = await _repository.listRecentNotes(
        onlyLast7Days: state.showLast7Days,
        status: state.statusFilter,
      );

      // Jeśli nie ma żadnych ostatnich notatek, utwórz jedną startową,
      // aby sekcja "Ostatnie notatki" nie była pusta.
      if (recentNotes.isEmpty) {
        // Użyj istniejącego folderu lub załóż "Quick Ideas"
        final folderToUse = folders.isNotEmpty
            ? folders.first
            : await _repository.getOrCreateFolderByName('Quick Ideas');
        // Utwórz prostą notatkę startową
        await _repository.createNote(
          folderToUse,
          title: 'Nowa notatka',
          content: '',
        );
        // Odśwież listy po seedzie
        final refreshedFolders = await _repository.listFolders(sortBy: state.sortBy);
        recentNotes = await _repository.listRecentNotes(
          onlyLast7Days: state.showLast7Days,
          status: state.statusFilter,
        );
        state = state.copyWith(
          folders: refreshedFolders,
          recentNotes: recentNotes,
          isLoading: false,
        );
        return;
      }

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

  // Dodane: mapowanie wartości UI (String) na enum SortBy używany w stanie
  void setSort(String value) {
    switch (value) {
      case 'date_desc':
        setSortBy(SortBy.updatedAtDesc);
        break;
      case 'date_asc':
        setSortBy(SortBy.updatedAtAsc);
        break;
      case 'title_asc':
        setSortBy(SortBy.titleAsc);
        break;
      case 'title_desc':
        setSortBy(SortBy.titleDesc);
        break;
      default:
        // Jeśli nieznana wartość – nic nie rób, zachowaj bieżące sortowanie
        break;
    }
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
  // --- AI generation state ---
  final bool isGenerating;
  final bool useContext;
  final List<GeneratedSuggestion> suggestions;
  // Panel UI: widoczność sekcji sugestii
  final bool showSuggestions;

  const NoteEditorState({
    this.note,
    this.isLoading = false,
    this.isSaving = false,
    this.error,
    this.hasUnsavedChanges = false,
    this.isGenerating = false,
    this.useContext = true,
    this.suggestions = const [],
    this.showSuggestions = false,
  });

  NoteEditorState copyWith({
    Note? note,
    bool? isLoading,
    bool? isSaving,
    String? error,
    bool? hasUnsavedChanges,
    bool? isGenerating,
    bool? useContext,
    List<GeneratedSuggestion>? suggestions,
    bool? showSuggestions,
  }) {
    return NoteEditorState(
      note: note ?? this.note,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      error: error ?? this.error,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      isGenerating: isGenerating ?? this.isGenerating,
      useContext: useContext ?? this.useContext,
      suggestions: suggestions ?? this.suggestions,
      showSuggestions: showSuggestions ?? this.showSuggestions,
    );
  }
}

// Note Editor ViewModel with autosave
class NoteEditorViewModel extends StateNotifier<NoteEditorState> {
  final Repository _repository;
  final String _noteId;
  Timer? _saveDebounce;
  Timer? _genDelay;

  // Klucze do SharedPreferences
  static const _kOpenRouterKey = 'ai_openrouter_key';
  static const _kOpenRouterModel = 'ai_openrouter_model';
  static const _kCustomApiUrl = 'ai_custom_api_url';
  // Build-time env (set with --dart-define); domyślnie nasz Worker CF
  static const String _envCustomApiUrl = String.fromEnvironment('CUSTOM_API_URL', defaultValue: 'https://purple-frog-0aef.kacper19961996.workers.dev/');
  static const String _envOpenRouterKey = String.fromEnvironment('OPENROUTER_API_KEY', defaultValue: '');
  static const String _envOpenRouterModel = String.fromEnvironment('OPENROUTER_MODEL', defaultValue: _defaultFreeModel);
  static const _kDailyCount = 'ai_daily_count';
  static const _kDailyDate = 'ai_daily_date';

  // Domyślne wartości (bez ustawień w UI)
  static const String _defaultFreeModel = 'gpt-4o-mini';
  static const int _defaultDailyQuota = 2;

  NoteEditorViewModel(this._repository, this._noteId) : super(const NoteEditorState()) {
    // Automatycznie załaduj notatkę po utworzeniu VM
    Future.microtask(() => loadNote(_noteId));
  }

  // --- UI helpers: ładowanie, autosave, edycja ---
  Future<void> loadNote(String noteId) async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final note = await _repository.loadNote(noteId);
      state = state.copyWith(note: note, isLoading: false, hasUnsavedChanges: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void updateTitle(String title) {
    final n = state.note;
    if (n == null) return;
    n.title = title;
    n.updatedAt = DateTime.now();
    state = state.copyWith(note: n, hasUnsavedChanges: true);
    _scheduleAutosave();
  }

  void updateContent(String content) {
    final n = state.note;
    if (n == null) return;
    n.content = content;
    n.updatedAt = DateTime.now();
    state = state.copyWith(note: n, hasUnsavedChanges: true);
    _scheduleAutosave();
    // Auto‑AI wyłączone: generowanie tylko po kliknięciu przycisków w UI
  }

  void _scheduleAutosave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      forceSave();
    });
  }

  /// Zapisuje aktualny stan notatki do repozytorium.
  /// Zwraca true, jeśli zapis zakończył się powodzeniem (bez wyjątków),
  /// w przeciwnym razie ustawia state.error i zwraca false.
  Future<bool> forceSave() async {
    _saveDebounce?.cancel();
    final n = state.note;
    if (n == null) return false;
    try {
      final toSave = Note(
        id: n.id,
        folderId: n.folderId,
        title: n.title,
        content: n.content,
        createdAt: n.createdAt,
        updatedAt: DateTime.now(),
        status: n.status,
        pinned: n.pinned,
        deletedAt: n.deletedAt,
      );
      await _repository.saveNote(toSave);
      state = state.copyWith(note: toSave, hasUnsavedChanges: false);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  void dismissError() {
    state = state.copyWith(error: null);
  }

  // Panel sugestii AI: zwijanie/rozwijanie
  void toggleSuggestionsPanel() {
    state = state.copyWith(showSuggestions: !state.showSuggestions);
  }

  void setSuggestionsPanel(bool visible) {
    if (state.showSuggestions != visible) {
      state = state.copyWith(showSuggestions: visible);
    }
  }

  // --- Operacje na sugestiach i stanie notatki ---
  void applySuggestionAppend(GeneratedSuggestion s) {
    final n = state.note;
    if (n == null) return;
    final base = n.content.trimRight();
    final append = s.content.trim();
    final newContent = base.isEmpty ? append : '$base\n\n$append';
    n.content = newContent;
    n.updatedAt = DateTime.now();
    state = state.copyWith(note: n, hasUnsavedChanges: true);
    _scheduleAutosave();
  }

  void applySuggestionReplace(GeneratedSuggestion s) {
    final n = state.note;
    if (n == null) return;
    n.content = s.content.trim();
    n.updatedAt = DateTime.now();
    state = state.copyWith(note: n, hasUnsavedChanges: true);
    _scheduleAutosave();
  }

  void applySuggestionAsSection(GeneratedSuggestion s) {
    final n = state.note;
    if (n == null) return;
    final base = n.content.trimRight();
    final section = s.content.trim();
    final newContent = base.isEmpty ? section : '$base\n\n$section';
    n.content = newContent;
    n.updatedAt = DateTime.now();
    state = state.copyWith(note: n, hasUnsavedChanges: true);
    _scheduleAutosave();
  }

  void applyAllAppend() {
    final n = state.note;
    if (n == null) return;
    if (state.suggestions.isEmpty) return;
    final base = n.content.trimRight();
    final bundle = state.suggestions.map((e) => e.content.trim()).where((e) => e.isNotEmpty).join('\n\n');
    final newContent = base.isEmpty ? bundle : '$base\n\n$bundle';
    n.content = newContent;
    n.updatedAt = DateTime.now();
    state = state.copyWith(note: n, hasUnsavedChanges: true, showSuggestions: false);
    _scheduleAutosave();
  }

  void discardAllSuggestions() {
    if (state.suggestions.isEmpty) return;
    state = state.copyWith(suggestions: const [], showSuggestions: false);
  }

  Future<void> togglePinned() async {
    final n = state.note;
    if (n == null) return;
    final newPinned = !n.pinned;
    await _repository.setNotePinned(n.id, newPinned);
    n.pinned = newPinned;
    n.updatedAt = DateTime.now();
    state = state.copyWith(note: n);
  }

  Future<void> setStatus(NoteStatus status) async {
    final n = state.note;
    if (n == null) return;
    await _repository.setNoteStatus(n.id, status);
    n.status = status;
    n.updatedAt = DateTime.now();
    state = state.copyWith(note: n);
  }

  Future<void> deleteCurrent() async {
    final n = state.note;
    if (n == null) return;
    await _repository.deleteNoteById(n.id);
    n.deletedAt = DateTime.now();
    state = state.copyWith(note: n);
  }

  // --- Preferencje i limity AI ---
  Future<bool> _checkAndIncrementDailyQuota() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final lastDate = prefs.getString(_kDailyDate);
      int count = prefs.getInt(_kDailyCount) ?? 0;
      if (lastDate != today) {
        await prefs.setString(_kDailyDate, today);
        count = 0;
      }
      final limit = _defaultDailyQuota; // można później pobrać z ustawień
      if (count >= limit) return false;
      await prefs.setInt(_kDailyCount, count + 1);
      return true;
    } catch (_) {
      // jeżeli brak prefs, nie blokuj
      return true;
    }
  }

  Future<String> getOpenRouterModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final m = prefs.getString(_kOpenRouterModel);
      return (m != null && m.isNotEmpty) ? m : _envOpenRouterModel;
    } catch (_) {
      return _envOpenRouterModel;
    }
  }

  Future<String?> getCustomApiUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final u = prefs.getString(_kCustomApiUrl);
      if (u != null && u.isNotEmpty) return u;
      return _envCustomApiUrl;
    } catch (_) {
      return _envCustomApiUrl;
    }
  }

  Future<String?> getOpenRouterKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final k = prefs.getString(_kOpenRouterKey);
      if (k != null && k.isNotEmpty) return k;
      return _envOpenRouterKey.isNotEmpty ? _envOpenRouterKey : null;
    } catch (_) {
      return _envOpenRouterKey.isNotEmpty ? _envOpenRouterKey : null;
    }
  }

  String _buildContextSnippet() {
    if (!state.useContext) return '';
    final n = state.note;
    final src = (n?.content ?? '').trim();
    if (src.isEmpty) return '';
    const maxLen = 1200;
    if (src.length <= maxLen) return src;
    return src.substring(src.length - maxLen);
  }

  Future<void> generateIdeasWithApi([bool auto = false]) async {
    // hide keyboard on start
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await _checkAndIncrementDailyQuota();
    if (!ok) {
      state = state.copyWith(error: 'Dzienny limit generacji został wykorzystany');
      return;
    }

    final model = await getOpenRouterModel();
    final customUrl = await getCustomApiUrl();
    final key = await getOpenRouterKey();
    if ((customUrl == null || customUrl.isEmpty) && (key == null || key.isEmpty)) {
      state = state.copyWith(error: 'Skonfiguruj własny endpoint lub wklej klucz OpenRouter w Ustawieniach');
      return;
    }

    state = state.copyWith(isGenerating: true, error: null, suggestions: const []);

    final snippet = _buildContextSnippet();
    final prompt = snippet.isEmpty
        ? 'Zaproponuj dokładnie 5 krótkich, konkretnych punktów rozwinięcia tej notatki. Każdy punkt ma być jednolinijkowy i zaczynać się od "+ ". Unikaj ogólników.'
        : 'Na podstawie fragmentu notatki: \n"""\n$snippet\n"""\n\nZaproponuj dokładnie 5 krótkich, konkretnych punktów rozwinięcia tej notatki. Każdy punkt jednolinijkowy zaczynający się od "+ ". Unikaj ogólników.';

    try {
      final uri = Uri.parse((customUrl != null && customUrl.isNotEmpty)
          ? customUrl
          : 'https://openrouter.ai/api/v1/chat/completions');
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (customUrl == null || customUrl.isEmpty) {
        headers['Authorization'] = 'Bearer $key';
      }
      final res = await http.post(
        uri,
        headers: headers,
        body: jsonEncode({
          'model': model,
          'messages': [
            {
              'role': 'system',
              'content': 'Odpowiadasz po polsku. Zwróć wyłącznie czysty markdown: nagłówki sekcji (##) i wypunktowania (-). Bez wstępów i podsumowań.'
            },
            {'role': 'user', 'content': prompt},
          ],
        }),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final text = (data['choices']?[0]?['message']?['content'] ?? '').toString().trim();
        final s = GeneratedSuggestion(id: 'e${DateTime.now().microsecondsSinceEpoch}', content: text);
        state = state.copyWith(isGenerating: false, suggestions: [s], showSuggestions: true);
        if (auto) {
          // automatycznie dodaj rozwinięcie jako nową sekcję
          applySuggestionAsSection(s);
        }
      } else {
        state = state.copyWith(isGenerating: false, error: 'Błąd API (${res.statusCode})');
      }
    } catch (e) {
      state = state.copyWith(isGenerating: false, error: 'Błąd sieci: $e');
    }
  }

  Future<void> expandIdeaWithApi([bool auto = false]) async {
    // hide keyboard on start
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await _checkAndIncrementDailyQuota();
    if (!ok) {
      state = state.copyWith(error: 'Dzienny limit generacji został wykorzystany');
      return;
    }

    final model = await getOpenRouterModel();
    final customUrl = await getCustomApiUrl();
    final key = await getOpenRouterKey();
    if ((customUrl == null || customUrl.isEmpty) && (key == null || key.isEmpty)) {
      state = state.copyWith(error: 'Skonfiguruj własny endpoint lub wklej klucz OpenRouter w Ustawieniach');
      return;
    }

    state = state.copyWith(isGenerating: true, error: null, suggestions: const []);

    final base = _buildContextSnippet();
    final prompt = base.isEmpty
        ? 'Na podstawie idei rozwiń ją w 3-6 zwięzłych sekcjach: Cel, Funkcje, Ryzyka, Następne kroki. Każda sekcja ma mieć nagłówek i 2-4 punktów.'
        : 'Fragment notatki: \n"""\n$base\n"""\n\nRozwiń ideę w 3-6 zwięzłych sekcjach: Cel, Funkcje, Ryzyka, Następne kroki. Każda sekcja: nagłówek + 2-4 punktów.';

    try {
      final uri = Uri.parse((customUrl != null && customUrl.isNotEmpty)
          ? customUrl
          : 'https://openrouter.ai/api/v1/chat/completions');
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (customUrl == null || customUrl.isNotEmpty) {
        // nothing
      } else {
        headers['Authorization'] = 'Bearer $key';
      }
      final res = await http.post(
        uri,
        headers: headers,
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'system', 'content': 'Odpowiadaj po polsku. Bądź konkretny i sekcyjny.'},
            {'role': 'user', 'content': prompt},
          ],
        }),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final text = (data['choices']?[0]?['message']?['content'] ?? '').toString();
        final s = GeneratedSuggestion(id: 'e${DateTime.now().microsecondsSinceEpoch}', content: text.trim());
        state = state.copyWith(isGenerating: false, suggestions: [s], showSuggestions: true);
        if (auto) {
          applySuggestionAsSection(s);
        }
      } else {
        state = state.copyWith(isGenerating: false, error: 'Błąd API (${res.statusCode})');
      }
    } catch (e) {
      state = state.copyWith(isGenerating: false, error: 'Błąd sieci: $e');
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _genDelay?.cancel();
    super.dispose();
  }
}

final noteEditorViewModelProvider = StateNotifierProvider.family<NoteEditorViewModel, NoteEditorState, String>((ref, noteId) {
  return NoteEditorViewModel(ref.read(repositoryProvider), noteId);
});


// duplicate removed (second provider + duplicate class)