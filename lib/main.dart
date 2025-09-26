import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'models.dart';
import 'repository.dart';
import 'viewmodels.dart';
// import 'share_helper.dart'; // removed as not used after UI refactor

import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const ProviderScope(child: IdeaApp()));
}

class IdeaApp extends StatelessWidget {
  const IdeaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Colors.red;
    return MaterialApp(
      title: 'Idea App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: color),
        useMaterial3: true,
        textTheme: GoogleFonts.sourceCodeProTextTheme(),
        scaffoldBackgroundColor: Colors.white,
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          shape: CircleBorder(),
          elevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          disabledElevation: 0,
          backgroundColor: Color(0xFFE36868),
          foregroundColor: Colors.white,
        ),
        bottomAppBarTheme: const BottomAppBarThemeData(elevation: 0),
        inputDecorationTheme: const InputDecorationTheme(
          isDense: true,
          filled: false,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeViewModelProvider);
    final vm = ref.read(homeViewModelProvider.notifier);

    return Scaffold(
      // Usuwamy AppBar zgodnie z referencją, logo przenosimy do body powyżej wyszukiwarki
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo na górze
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Center(
                child: SvgPicture.asset(
                  'assets/ideasamaapp_logo.svg',
                  height: 28,
                  semanticsLabel: 'IdeaSama',
                ),
              ),
            ),
            // Search bar z obrysem #E36868 i ikoną
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Szukaj notatek…',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                    borderSide: BorderSide(color: Color(0xFFE36868)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                    borderSide: BorderSide(color: Color(0xFFE36868)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                    borderSide: BorderSide(color: Color(0xFFE36868), width: 1.6),
                  ),
                ),
                onChanged: vm.setSearchQuery,
              ),
            ),
            if (state.searchQuery.isNotEmpty)
              Expanded(child: _SearchList(results: state.searchResults))
            else
              Expanded(
                child: (state.folders.isEmpty && state.recentNotes.isEmpty)
                    ? const _EmptyState(text: 'Brak notatek. Dodaj pierwszą za pomocą przycisku +')
                    : _HomeLists(
                        folders: state.folders,
                        recent: state.recentNotes,
                      ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        elevation: 0,
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth * 0.82; // floating, not full width
              return Center(
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    ClipPath(
                      clipper: _NotchedBarClipper(notchRadius: 42),
                      child: Container(
                        width: barWidth,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEFEB), // subtle background
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Lewy: proste menu (ikonka)
                            SizedBox(
                              width: 48,
                              height: 48,
                              child: Center(
                                child: PopupMenuButton<String>(
                                  tooltip: 'Menu',
                                  icon: const Icon(Icons.more_horiz, color: Color(0xFFE36868)),
                                  position: PopupMenuPosition.over,
                                  constraints: const BoxConstraints(minWidth: 160, maxWidth: 200),
                                  onSelected: (value) {
                                    switch (value) {
                                      case 'all':
                                        vm.setStatusFilter(null);
                                        break;
                                      case 'idea':
                                        vm.setStatusFilter(NoteStatus.idea);
                                        break;
                                      case 'draft':
                                        vm.setStatusFilter(NoteStatus.draft);
                                        break;
                                    }
                                  },
                                  itemBuilder: (ctx) => const [
                                    PopupMenuItem(value: 'all', child: Text('Wszystkie')),
                                    PopupMenuItem(value: 'idea', child: Text('Tylko pomysły')),
                                    PopupMenuItem(value: 'draft', child: Text('Tylko szkice')),
                                  ],
                                ),
                              ),
                            ),

                            Semantics(
                              button: true,
                              label: 'Usuń',
                              child: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Color(0xFFE36868)),
                                onPressed: () {
                                  // TODO: akcja kosza (bulk) — brak scope’u backendowego
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('TODO: kosz — funkcja zbiorcza')),
                                  );
                                },
                                constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                                splashRadius: 24,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Centralny przycisk + wyraźnie wystający ponad pasek
                    Positioned(
                      top: -44,
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: Material(
                          color: const Color(0xFFE36868),
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: () async {
                              await showModalBottomSheet(
                                context: context,
                                showDragHandle: true,
                                useSafeArea: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                ),
                                builder: (_) {
                                  final textController = TextEditingController();
                                  return SafeArea(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          leading: const Icon(Icons.note_add_outlined),
                                          title: const Text('Szybka notatka'),
                                          subtitle: const Text(
                                            'Utwórz nową notatkę i przejdź do edycji',
                                          ),
                                          onTap: () async {
                                            Navigator.pop(context);
                                            final repo = ref.read(repositoryProvider);
                                            final state = ref.read(homeViewModelProvider);
                                            Folder folder;
                                            if (state.folders.isNotEmpty) {
                                              folder = state.folders.first;
                                            } else {
                                              folder = await ref
                                                  .read(homeViewModelProvider.notifier)
                                                  .createFolder('Quick Ideas');
                                            }
                                            final note = await repo.createNote(
                                              folder,
                                              title: 'Nowa notatka',
                                            );
                                            if (context.mounted) {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => NoteEditorPage(noteId: note.id),
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(
                                            Icons.create_new_folder_outlined,
                                          ),
                                          title: const Text('Nowy folder'),
                                          onTap: () async {
                                            Navigator.pop(context);
                                            String name = 'Nowy folder';
                                            final input = await showDialog<String>(
                                              context: context,
                                              builder: (ctx) {
                                                return AlertDialog(
                                                  title: const Text('Nazwa folderu'),
                                                  content: TextField(
                                                    controller: textController,
                                                    autofocus: true,
                                                    decoration: const InputDecoration(
                                                      hintText: 'Wpisz nazwę folderu',
                                                    ),
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(ctx),
                                                      child: const Text('Anuluj'),
                                                    ),
                                                    FilledButton(
                                                      onPressed: () => Navigator.pop(
                                                        ctx,
                                                        textController.text.trim(),
                                                      ),
                                                      child: const Text('Utwórz'),
                                                    ),
                                                  ],
                                                );
                                              },
                                            );
                                            if (input != null && input.isNotEmpty) {
                                              name = input;
                                            }
                                            final folder = await ref
                                                .read(homeViewModelProvider.notifier)
                                                .createFolder(name);
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Utworzono folder: ${folder.name}',
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                            customBorder: const CircleBorder(),
                            child: const Icon(Icons.add, color: Colors.white, size: 30),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class NoteEditorPage extends ConsumerStatefulWidget {
  final String noteId;
  const NoteEditorPage({super.key, required this.noteId});

  @override
  ConsumerState<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends ConsumerState<NoteEditorPage> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _controllersInitialized = false;
  bool _isApplyingExternalChange = false;

  @override
  void initState() {
    super.initState();
    // NasĹłuchiwanie zmian uĹĽytkownika i aktualizacja VM bez pÄ™tli zwrotnej
    _titleController.addListener(() {
      if (_isApplyingExternalChange || !_controllersInitialized) return;
      final provider = noteEditorViewModelProvider(widget.noteId);
      final current = ref.read(provider).note;
      final newText = _titleController.text;
      if (current != null && current.title == newText) return;
      ref.read(provider.notifier).updateTitle(newText);
    });
    _contentController.addListener(() {
      if (_isApplyingExternalChange || !_controllersInitialized) return;
      final provider = noteEditorViewModelProvider(widget.noteId);
      final current = ref.read(provider).note;
      final newText = _contentController.text;
      if (current != null && current.content == newText) return;
      ref.read(provider.notifier).updateContent(newText);
    });

    // Jednorazowa synchronizacja po pierwszej klatce, jeĹĽeli dane notatki sÄ… juĹĽ dostÄ™pne
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = noteEditorViewModelProvider(widget.noteId);
      final state = ref.read(provider);
      final newNote = state.note;
      if (newNote != null && !_controllersInitialized) {
        _isApplyingExternalChange = true;
        _titleController.value = TextEditingValue(
          text: newNote.title,
          selection: TextSelection.collapsed(offset: newNote.title.length),
        );
        _contentController.value = TextEditingValue(
          text: newNote.content,
          selection: TextSelection.collapsed(offset: newNote.content.length),
        );
        _isApplyingExternalChange = false;
        _controllersInitialized = true;
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Synchronizuj kontrolery z ZEWNÄTRZNYMI zmianami notatki (np. AI, forceSave, replace)
    ref.listen<NoteEditorState>(noteEditorViewModelProvider(widget.noteId), (
      prev,
      next,
    ) {
      final newNote = next.note;
      if (newNote == null) return;
      if (!_controllersInitialized) {
        _isApplyingExternalChange = true;
        _titleController.value = TextEditingValue(
          text: newNote.title,
          selection: TextSelection.collapsed(offset: newNote.title.length),
        );
        _contentController.value = TextEditingValue(
          text: newNote.content,
          selection: TextSelection.collapsed(offset: newNote.content.length),
        );
        _isApplyingExternalChange = false;
        _controllersInitialized = true;
        return;
      }
      if (_titleController.text != newNote.title) {
        _isApplyingExternalChange = true;
        final sel = _titleController.selection;
        final base = sel.baseOffset.clamp(0, newNote.title.length);
        final extent = sel.extentOffset.clamp(0, newNote.title.length);
        _titleController.value = TextEditingValue(
          text: newNote.title,
          selection: TextSelection(baseOffset: base, extentOffset: extent),
        );
        _isApplyingExternalChange = false;
      }
      if (_contentController.text != newNote.content) {
        _isApplyingExternalChange = true;
        final sel = _contentController.selection;
        final base = sel.baseOffset.clamp(0, newNote.content.length);
        final extent = sel.extentOffset.clamp(0, newNote.content.length);
        _contentController.value = TextEditingValue(
          text: newNote.content,
          selection: TextSelection(baseOffset: base, extentOffset: extent),
        );
        _isApplyingExternalChange = false;
      }
    });

    // Jedno ĹşrĂłdĹło SnackBarĂłw bĹłÄ™dĂłw (bez duplikatĂłw przy rebuildach)
    ref.listen<NoteEditorState>(noteEditorViewModelProvider(widget.noteId), (
      prev,
      next,
    ) {
      final err = next.error;
      if (err != null && err.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(err)));
        }
        ref
            .read(noteEditorViewModelProvider(widget.noteId).notifier)
            .dismissError();
      }
    });

    final state = ref.watch(noteEditorViewModelProvider(widget.noteId));
    final vm = ref.read(noteEditorViewModelProvider(widget.noteId).notifier);
    final note = state.note;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final vm = ref.read(
          noteEditorViewModelProvider(widget.noteId).notifier,
        );
        final currentState = ref.read(noteEditorViewModelProvider(widget.noteId));
        final note = currentState.note;
        // Take current controller values
        String newTitle = _titleController.text;
        String newContent = _contentController.text;
        // Do not wipe content: if controller has empty content but note has some, keep existing
        if ((newContent.isEmpty) && (note?.content.isNotEmpty ?? false)) {
          newContent = note!.content;
        }
        if (note != null) {
          if (note.title != newTitle) vm.updateTitle(newTitle);
          if (note.content != newContent) vm.updateContent(newContent);
        }
        final ok = await vm.forceSave();
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Błąd zapisu – sprawdź dziennik błędów'),
            ),
          );
        }
        if (context.mounted) {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Wróć',
            icon: Icon(Icons.chevron_left, color: Colors.grey[700]),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: const SizedBox.shrink(),
          centerTitle: false,
          actions: [
            IconButton(
              tooltip: 'Zapisz',
              icon: Icon(Icons.save_rounded, color: Colors.grey[700]),
              onPressed: () async {
                final vm = ref.read(
                  noteEditorViewModelProvider(widget.noteId).notifier,
                );
                final currentState = ref.read(
                  noteEditorViewModelProvider(widget.noteId),
                );
                final note = currentState.note;
                String newTitle = _titleController.text;
                String newContent = _contentController.text;
                if ((newContent.isEmpty) && (note?.content.isNotEmpty ?? false)) {
                  newContent = note!.content;
                }
                if (note != null) {
                  if (note.title != newTitle) vm.updateTitle(newTitle);
                  if (note.content != newContent) vm.updateContent(newContent);
                }
                final ok = await vm.forceSave();
                if (!context.mounted) return;
                if (ok) {
                   ScaffoldMessenger.of(
                     context,
                   ).showSnackBar(const SnackBar(content: Text('Zapisano')));
                 }
               },
            ),
            IconButton(
              tooltip: 'Pełny ekran',
              icon: Icon(Icons.open_in_full, color: Colors.grey[700]),
              onPressed: () {
                // TODO: Włączyć tryb pełnoekranowy edytora (wymaga decyzji produktowej)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('TODO: pełny ekran')),
                );
              },
            ),
            PopupMenuButton<String>(
               tooltip: 'Menu notatki',
               position: PopupMenuPosition.over,
               constraints: const BoxConstraints(minWidth: 140, maxWidth: 180),
               onSelected: (v) async {
                 switch (v) {
                   case 'pin':
                     await vm.togglePinned();
                     break;
                   case 'idea':
                     await vm.setStatus(NoteStatus.idea);
                     break;
                   case 'draft':
                     await vm.setStatus(NoteStatus.draft);
                     break;
                   case 'ready':
                     await vm.setStatus(NoteStatus.ready);
                     break;
                   case 'done':
                     await vm.setStatus(NoteStatus.done);
                     break;
                   case 'dropped':
                     await vm.setStatus(NoteStatus.dropped);
                     break;
                   case 'trash':
                     await vm.deleteCurrent();
                     if (context.mounted) Navigator.pop(context);
                     break;
                 }
               },
               itemBuilder: (_) => [
                 PopupMenuItem(
                   value: 'pin',
                   child: Row(
                     children: [
                       Icon(
                         (note?.pinned ?? false)
                             ? Icons.push_pin_outlined
                             : Icons.push_pin,
                         size: 18,
                       ),
                       const SizedBox(width: 8),
                       Text((note?.pinned ?? false) ? 'Odepnij' : 'Przypnij'),
                     ],
                   ),
                 ),
                 const PopupMenuDivider(),
                 const PopupMenuItem(
                   value: 'idea',
                   child: Text('Status: Pomysły'),
                 ),
                 const PopupMenuItem(
                   value: 'draft',
                   child: Text('Status: Szkice'),
                 ),
                 const PopupMenuItem(
                   value: 'ready',
                   child: Text('Status: Gotowe'),
                 ),
                 const PopupMenuItem(
                   value: 'done',
                   child: Text('Status: Zrobione'),
                 ),
                 const PopupMenuItem(
                   value: 'dropped',
                   child: Text('Status: Porzucone'),
                 ),
                 const PopupMenuDivider(),
                 const PopupMenuItem(
                   value: 'trash',
                   child: Row(
                     children: [
                       Icon(Icons.delete_outline, size: 18),
                       SizedBox(width: 8),
                       Text('Przenieś do kosza'),
                     ],
                   ),
                 ),
               ],
             ),
           ],
         ),
         body: note == null
             ? const Center(child: CircularProgressIndicator())
             : Column(
                 children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                    child: TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        hintText: 'Title',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide(color: Color(0xFFE36868)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide(color: Color(0xFFE36868)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide(color: Color(0xFFE36868), width: 1.6),
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      style: TextStyle(fontSize: 14),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        0,
                        24,
                        MediaQuery.of(context).viewInsets.bottom + 80,
                      ), // dynamic bottom space so FAB/panel don't cover content
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _contentController,
                            decoration: const InputDecoration(
                              hintText: 'Lorem ipsum dolor sit amet consectetur. Faucibus pellentesque tempus mauris augue sit.',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(12)),
                                borderSide: BorderSide(color: Color(0xFFE36868)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(12)),
                                borderSide: BorderSide(color: Color(0xFFE36868)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(12)),
                                borderSide: BorderSide(color: Color(0xFFE36868), width: 1.6),
                              ),
                              contentPadding: EdgeInsets.fromLTRB(12, 12, 12, 12),
                            ),
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            maxLines: null,
                            minLines: 10,
                          ),
                           const SizedBox(height: 12),
                           if (state.suggestions.isNotEmpty) ...[
                             // Zmieniamy nagĹ‚Ăłwek panelu sugestii na Wrap, aby nie nachodziĹ‚y na siebie przyciski
                             Wrap(
                               crossAxisAlignment: WrapCrossAlignment.center,
                               spacing: 8,
                               runSpacing: 4,
                               alignment: WrapAlignment.spaceBetween,
                               children: [
                                 const Text('Sugestie AI'),
                                 TextButton.icon(
                                   onPressed: vm.toggleSuggestionsPanel,
                                   icon: Icon(
                                     state.showSuggestions
                                         ? Icons.expand_less
                                         : Icons.expand_more,
                                   ),
                                   label: Text(
                                     state.showSuggestions ? 'ZwiĹ„' : 'RozwiĹ„',
                                   ),
                                 ),
                                 TextButton.icon(
                                   onPressed: vm.applyAllAppend,
                                   icon: const Icon(Icons.playlist_add),
                                   label: const Text('Dodaj wszystkie'),
                                 ),
                                 TextButton.icon(
                                   onPressed: vm.discardAllSuggestions,
                                   icon: const Icon(Icons.clear_all),
                                   label: const Text('OdrzuĹ‚ wszystkie'),
                                 ),
                               ],
                             ),
                           ],
                           if (state.showSuggestions && state.suggestions.isNotEmpty) ...[
                             const SizedBox(height: 8),
                             ...state.suggestions.map(
                               (s) => Card(
                                 child: Padding(
                                   padding: const EdgeInsets.all(8.0),
                                   child: Column(
                                     crossAxisAlignment:
                                         CrossAxisAlignment.start,
                                     children: [
                                       Text(s.content),
                                       const SizedBox(height: 8),
                                       LayoutBuilder(
                                         builder: (context, constraints) {
                                           final isNarrow = constraints.maxWidth < 420;

                                           final buttons = <Widget>[
                                             OutlinedButton.icon(
                                               onPressed: () => vm.applySuggestionAppend(s),
                                               icon: const Icon(Icons.add),
                                               label: const Text('Dodaj do koĹ„ca'),
                                             ),
                                             OutlinedButton.icon(
                                               onPressed: () => vm.applySuggestionReplace(s),
                                               icon: const Icon(Icons.swap_horiz),
                                               label: const Text('ZastĹ…p caĹ‚oĹ›Ä‡'),
                                             ),
                                             OutlinedButton.icon(
                                               onPressed: () => vm.applySuggestionAsSection(s),
                                               icon: const Icon(Icons.view_agenda_outlined),
                                               label: const Text('Nowa sekcja'),
                                             ),
                                           ];

                                           if (isNarrow) {
                                             return Column(
                                               crossAxisAlignment: CrossAxisAlignment.stretch,
                                               children: [
                                                 for (final b in buttons)
                                                   Padding(
                                                     padding: const EdgeInsets.only(bottom: 8),
                                                     child: SizedBox(
                                                       width: double.infinity,
                                                       child: b,
                                                     ),
                                                   ),
                                               ],
                                             );
                                           }

                                           return Wrap(
                                             spacing: 8,
                                             runSpacing: 8,
                                             children: buttons,
                                           );
                                         },
                                       ),
                                     ],
                                   ),
                                 ),
                               ),
                             ),
                           ],
                         ],
                       ),
                     ),
                   ),
                 ],
               ),
        floatingActionButton: Wrap(
          spacing: 10,
          children: [
            FloatingActionButton.small(
              heroTag: 'ai1',
              tooltip: state.isGenerating ? 'Generowanieâ€¦' : 'Pomysły AI',
              backgroundColor: const Color(0xFFE36868),
              onPressed: state.isGenerating ? null : vm.generateIdeasWithApi,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: state.isGenerating
                    ? const SizedBox(
                        key: ValueKey('ai1-loading'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lightbulb_outline, size: 18, key: ValueKey('ai1-icon'), color: Colors.white),
              ),
            ),
             FloatingActionButton.small(
               heroTag: 'ai2',
               tooltip: state.isGenerating ? 'Generowanieâ€¦' : 'Rozwiązanie AI',
              backgroundColor: const Color(0xFFE36868),
               onPressed: state.isGenerating ? null : vm.expandIdeaWithApi,
               child: AnimatedSwitcher(
                 duration: const Duration(milliseconds: 200),
                 child: state.isGenerating
                     ? const SizedBox(
                         key: ValueKey('ai2-loading'),
                         width: 18,
                         height: 18,
                         child: CircularProgressIndicator(strokeWidth: 2),
                       )
                    : const Icon(Icons.text_snippet_outlined, size: 18, key: ValueKey('ai2-icon'), color: Colors.white),
               ),
             ),
           ],
         ),
         floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
       ),
    );
  }
}

class TrashPage extends ConsumerWidget {
  const TrashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kosz'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('OprĂłĹĽniÄ‡ kosz?'),
                  content: const Text(
                    'Tych notatek nie bÄ™dzie moĹĽna przywrĂłciÄ‡.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Anuluj'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('OprĂłĹĽnij'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await repo.purgeDeleted(olderThanDays: 0);
                // ignore: use_build_context_synchronously
                if (context.mounted) Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('OprĂłĹĽnij'),
          ),
        ],
      ),
      body: FutureBuilder<List<Note>>(
        future: repo.listTrashedNotes(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const _EmptyState(text: 'Kosz jest pusty');
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = items[i];
              return ListTile(
                title: Text(n.title.isEmpty ? '(bez tytuĹ‚u)' : n.title),
                subtitle: Text(formatDatePL(n.updatedAt)),
                trailing: TextButton.icon(
                  onPressed: () async {
                    await repo.restoreNote(n.id);
                    // ignore: use_build_context_synchronously
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.restore_outlined),
                  label: const Text('PrzywrĂłÄ‡'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SearchList extends ConsumerWidget {
  final List<SearchResult> results;
  const _SearchList({required this.results});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (results.isEmpty) return const _EmptyState(text: 'Brak wynikĂłw');
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = results[i];
        return ListTile(
          leading: const Icon(Icons.search),
          title: Text(r.note.title.isEmpty ? '(bez tytuĹ‚u)' : r.note.title),
          subtitle: Text(
            r.note.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: PopupMenuButton<String>(
            tooltip: 'Menu',
            icon: const Icon(Icons.more_vert),
            position: PopupMenuPosition.over,
            constraints: const BoxConstraints(minWidth: 140, maxWidth: 180),
            onSelected: (v) async {
              final vm = ref.read(homeViewModelProvider.notifier);
              switch (v) {
                case 'pin':
                  await vm.toggleNotePinned(r.note.id);
                  break;
                case 'trash':
                  await vm.deleteNoteById(r.note.id);
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'pin',
                child: Row(
                  children: [
                    Icon(
                      r.note.pinned ? Icons.push_pin_outlined : Icons.push_pin,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(r.note.pinned ? 'Odepnij' : 'Przypnij'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'trash',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18),
                    SizedBox(width: 8),
                    Text('PrzenieĹ› do kosza'),
                  ],
                ),
              ),
            ],
          ),
          onTap: () async {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => NoteEditorPage(noteId: r.note.id),
              ),
            );
            if (context.mounted) {
              await ref.read(homeViewModelProvider.notifier).loadData();
            }
          },
        );
      },
    );
  }
}

class _HomeLists extends ConsumerWidget {
  final List<Folder> folders;
  final List<Note> recent;
  const _HomeLists({required this.folders, required this.recent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.read(homeViewModelProvider.notifier);
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Text('Foldery', style: TextStyle(fontSize: 14)),
        ),
        // Folders as outlined pills (accent #E36868, radius 8, no shadows)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: folders
                .map(
                  (f) => Semantics(
                    label: 'Folder: ${f.name}',
                    button: true,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE36868),
                        side: const BorderSide(color: Color(0xFFE36868)),
                        textStyle: const TextStyle(fontSize: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _FolderPage(folder: f),
                          ),
                        );
                      },
                      child: Text(f.name),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Text(
            'Ostatnie notatki',
            style: TextStyle(fontSize: 14),
          ),
        ),
        // Notes as flat cards with red outline and radius 8, no shadows
        ...recent.map(
          (n) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Semantics(
              label:
                  'Notatka: ${n.title.isEmpty ? "(bez tytułu)" : n.title}. Zaktualizowano: ${formatDatePL(n.updatedAt)}',
              hint: 'Otwórz notatkę',
              button: true,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Color(0xFFE36868)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  title: Text(n.title.isEmpty ? '(bez tytułu)' : n.title),
                  subtitle: Row(
                    children: [
                      _StatusBadge(status: n.status),
                      const SizedBox(width: 8),
                      Text(formatDatePL(n.updatedAt)),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Menu',
                    icon: const Icon(Icons.more_vert),
                    position: PopupMenuPosition.over,
                    constraints: const BoxConstraints(minWidth: 140, maxWidth: 180),
                    onSelected: (v) async {
                      switch (v) {
                        case 'pin':
                          await vm.toggleNotePinned(n.id);
                          break;
                        case 'trash':
                          await vm.deleteNoteById(n.id);
                          break;
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'pin',
                        child: Row(
                          children: [
                            Icon(Icons.push_pin_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Przypnij'),
                          ],
                        ),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'trash',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18),
                            SizedBox(width: 8),
                            Text('Przenieś do kosza'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  onTap: () async {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => NoteEditorPage(noteId: n.id)),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FolderPage extends ConsumerWidget {
  final Folder folder;
  const _FolderPage({required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(folder.name, style: const TextStyle(fontSize: 14))),
      body: FutureBuilder<List<Note>>(
        future: repo.listNotesInFolder(folder.id),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) return const _EmptyState(text: 'Brak notatek w folderze');
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, index) {
              final n = items[index];
              return ListTile(
                title: Text(n.title.isEmpty ? '(bez tytułu)' : n.title, style: const TextStyle(fontSize: 14)),
                subtitle: Row(
                  children: [
                    _StatusBadge(status: n.status),
                    const SizedBox(width: 8),
                    Text(formatDatePL(n.updatedAt), style: const TextStyle(fontSize: 10)),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Menu',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) async {
                    final vm = ref.read(homeViewModelProvider.notifier);
                    switch (v) {
                      case 'pin':
                        await vm.toggleNotePinned(n.id);
                        break;
                      case 'trash':
                        await vm.deleteNoteById(n.id);
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'pin',
                      child: Row(
                        children: [
                          Icon(n.pinned ? Icons.push_pin_outlined : Icons.push_pin, size: 18),
                          const SizedBox(width: 8),
                          Text(n.pinned ? 'Odepnij' : 'Przypnij'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'trash',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18),
                          SizedBox(width: 8),
                          Text('Przenieś do kosza'),
                        ],
                      ),
                    ),
                  ],
                ),
                onTap: () async {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => NoteEditorPage(noteId: n.id)),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final NoteStatus status;
  const _StatusBadge({required this.status});

  Color _color(NoteStatus s, BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    switch (s) {
      case NoteStatus.idea:
        return cs.secondary;
      case NoteStatus.draft:
        return cs.tertiary;
      case NoteStatus.ready:
        return cs.primary;
      case NoteStatus.done:
        return Colors.green; // wyróżnienie Done
      case NoteStatus.dropped:
        return cs.error;
    }
  }

  String _label(NoteStatus s) {
    switch (s) {
      case NoteStatus.idea:
        return 'POMYSŁ';
      case NoteStatus.draft:
        return 'SZKIC';
      case NoteStatus.ready:
        return 'GOTOWE';
      case NoteStatus.done:
        return 'ZROBIONE';
      case NoteStatus.dropped:
        return 'PORZUCONE';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: _color(status, context).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _color(status, context).withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        _label(status),
        style: TextStyle(
          fontSize: 6,
          height: 1.0,
          color: _color(status, context),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 48),
            const SizedBox(height: 12),
            Text(text),
          ],
        ),
      ),
    );
  }
}
String formatDatePL(DateTime dt) {
  final d = dt.toLocal();
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final yyyy = d.year.toString();
  return '$dd.$mm.$yyyy';
}

// Wycięcie na środkowy przycisk w dolnym pasku
class _NotchedBarClipper extends CustomClipper<Path> {
  final double notchRadius;
  _NotchedBarClipper({required this.notchRadius});

  @override
  Path getClip(Size size) {
    const corner = 6.0;
    final path = Path()..fillType = PathFillType.evenOdd;
    final outer = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(corner),
    );
    path.addRRect(outer);

    // Centralny półokrągły notch w górnej krawędzi paska
    final notchRect = Rect.fromCircle(
      center: Offset(size.width / 2, 0),
      radius: notchRadius,
    );
    path.addOval(notchRect);

    return path;
  }

  @override
  bool shouldReclip(covariant _NotchedBarClipper oldClipper) =>
      oldClipper.notchRadius != notchRadius;
}