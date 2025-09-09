import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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
    this.showSuggestions = true,
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
  String? _lastAutoSig;
  bool _suppressAutoOnce = false;

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
    state = state.copyWith(showSuggestions: visible);
  }

  // --- Sugestie: operacje na UI ---
  void applySuggestionAppend(GeneratedSuggestion s) {
    final n = state.note;
    if (n == null) return;
    final sep = n.content.trim().isEmpty ? '' : '\n\n';
    final updated = n.content + sep + s.content.trim();
    updateContent(updated);
  }

  void applySuggestionReplace(GeneratedSuggestion s) {
    final n = state.note;
    if (n == null) return;
    updateContent(s.content.trim());
  }

  void applySuggestionAsSection(GeneratedSuggestion s) {
    final n = state.note;
    if (n == null) return;
    final sep = n.content.trim().isEmpty ? '' : '\n\n';
    final updated = "${n.content}$sep## Nowa sekcja\n\n${s.content.trim()}";
    updateContent(updated);
  }

  void applyAllAppend() {
    final n = state.note;
    if (n == null || state.suggestions.isEmpty) return;
    final joined = state.suggestions.map((e) => e.content.trim()).where((e) => e.isNotEmpty).join('\n\n');
    if (joined.isEmpty) return;
    final sep = n.content.trim().isEmpty ? '' : '\n\n';
    final updated = n.content + sep + joined;
    updateContent(updated);
  }

  void discardAllSuggestions() {
    state = state.copyWith(suggestions: const []);
  }

  // --- Operacje na notatce (pin/status/kosz) ---
  Future<void> togglePinned() async {
    final n = state.note;
    if (n == null) return;
    final newPinned = !n.pinned;
    try {
      await _repository.setNotePinned(n.id, newPinned);
      n.pinned = newPinned;
      n.updatedAt = DateTime.now();
      state = state.copyWith(note: n);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> setStatus(NoteStatus status) async {
    final n = state.note;
    if (n == null) return;
    try {
      await _repository.setNoteStatus(n.id, status);
      n.status = status;
      n.updatedAt = DateTime.now();
      state = state.copyWith(note: n);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteCurrent() async {
    final n = state.note;
    if (n == null) return;
    try {
      await _repository.deleteNoteById(n.id);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  String _buildContextSnippet() {
    // Jeśli przełącznik kontekstu jest wyłączony, nie wysyłamy treści notatki do modelu
    if (!state.useContext) return '';
    final n = state.note;
    if (n == null) return '';
    final title = n.title.trim();
    final content = n.content.trim();
    final max = 1200;
    String body = content.length <= max ? content : content.substring(0, max);
    if (title.isNotEmpty) {
      return '$title\n\n$body';
    }
    return body;
  }

  void toggleUseContext() {
    state = state.copyWith(useContext: !state.useContext);
  }

  Future<void> setCustomApiUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCustomApiUrl, url.trim());
  }

  Future<void> setOpenRouterKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOpenRouterKey, key.trim());
  }

  Future<void> setOpenRouterModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOpenRouterModel, model.trim());
  }

  Future<String?> getCustomApiUrl() async {
    // Preferuj build-time env; jeśli ustawione, ukrywa ustawienia użytkownika
    if (_envCustomApiUrl.trim().isNotEmpty) return _envCustomApiUrl.trim();
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kCustomApiUrl);
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }

  Future<String?> getOpenRouterKey() async {
    // Jeśli używamy Workera (custom url), klucz nie jest wymagany po stronie klienta
    final custom = await getCustomApiUrl();
    if (custom != null && custom.isNotEmpty) return '';
    if (_envOpenRouterKey.trim().isNotEmpty) return _envOpenRouterKey.trim();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kOpenRouterKey);
  }

  Future<String> getOpenRouterModel() async {
    // Model jest używany tylko dla OpenRouter bez pośrednika
    final custom = await getCustomApiUrl();
    if (custom != null && custom.isNotEmpty) return _defaultFreeModel;
    if (_envOpenRouterModel.trim().isNotEmpty) return _envOpenRouterModel.trim();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kOpenRouterModel) ?? _defaultFreeModel;
  }

  Future<bool> _checkAndIncrementDailyQuota() async {
    // TEMP: quota disabled; keep constants for future use to avoid breaking prefs schema
    final tag = _kDailyCount + _kDailyDate + _defaultDailyQuota.toString();
    if (tag.isEmpty) {
      // never happens, only to use constants
      return true;
    }
    return true;
  }

  // now add new methods inside class for auto-AI
  void _scheduleAutoAi() {
    _genDelay?.cancel();
    _genDelay = Timer(const Duration(milliseconds: 1200), _autoGenerate);
  }

  Future<void> _autoGenerate() async {
    if (state.isGenerating) return;
    final n = state.note;
    if (n == null) return;
    final content = n.content.trim();
    if (content.isEmpty) return;
    final snippet = _buildContextSnippet();
    final isQuestion = content.endsWith('?');
    final sigBase = snippet.isEmpty ? content : snippet;
    final sig = (isQuestion ? 'Q|' : 'S|') + (sigBase.length > 200 ? sigBase.substring(0, 200) : sigBase);
    if (_lastAutoSig == sig) return; // nic nowego do generowania
    _lastAutoSig = sig;

    if (isQuestion) {
      await expandIdeaWithApi(true); // auto: wstaw do notatki jako sekcję
    } else if (content.length >= 20) {
      await generateIdeasWithApi(false); // auto: tylko pokaż sugestie
    }
  }

  // ---- API calls ----
  Future<void> generateIdeasWithApi([bool auto = false]) async {
    if (state.note == null || state.isGenerating) return;
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
        state = state.copyWith(isGenerating: false, suggestions: [s]);
        if (auto) {
          // automatycznie dodaj rozwinięcie jako nową sekcję
          _suppressAutoOnce = true;
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
    if (state.note == null || state.isGenerating) return;
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
      if (customUrl == null || customUrl.isEmpty) {
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
        state = state.copyWith(isGenerating: false, suggestions: [s]);
        if (auto) {
          _suppressAutoOnce = true;
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