import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'repository.dart';
import 'models.dart';
import 'viewmodels.dart';
import 'share_helper.dart';
// import 'dart:math' show min;
import 'package:flutter_svg/flutter_svg.dart';

void main() {
  runApp(const ProviderScope(child: IdeaApp()));
}

class IdeaApp extends StatelessWidget {
  const IdeaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ideasamaapp',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      ref.read(homeViewModelProvider.notifier).setSearchQuery(_searchCtrl.text);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeViewModelProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset('assets/ideasamaapp_logo.svg', height: 22),
            const SizedBox(height: 2),
            const Text(
              'ideasama',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(state.showLast7Days ? Icons.filter_alt : Icons.filter_alt_outlined),
            tooltip: 'Last 7 days',
            color: state.showLast7Days ? Theme.of(context).colorScheme.primary : null,
            onPressed: () => ref.read(homeViewModelProvider.notifier).toggleShowLast7Days(),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Trash',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TrashPage()));
            },
          ),
          PopupMenuButton<NoteStatus?>(
            tooltip: 'Status filter',
            icon: Icon(Icons.filter_list, color: state.statusFilter != null ? Theme.of(context).colorScheme.primary : null),
            onSelected: (s) => ref.read(homeViewModelProvider.notifier).setStatusFilter(s),
            itemBuilder: (context) {
              String label(NoteStatus s) {
                final n = s.name;
                return n[0].toUpperCase() + n.substring(1);
              }
              return [
                CheckedPopupMenuItem<NoteStatus?>(
                  checked: state.statusFilter == null,
                  value: null,
                  child: const Text('All statuses'),
                ),
                ...NoteStatus.values.map((s) => CheckedPopupMenuItem<NoteStatus?>(
                      checked: state.statusFilter == s,
                      value: s,
                      child: Text(label(s)),
                    )),
              ];
            },
          ),
          PopupMenuButton<SortBy>(
            onSelected: (s) => ref.read(homeViewModelProvider.notifier).setSortBy(s),
            itemBuilder: (context) => const [
              PopupMenuItem(value: SortBy.updatedAtDesc, child: Text('Newest')),
              PopupMenuItem(value: SortBy.updatedAtAsc, child: Text('Oldest')),
              PopupMenuItem(value: SortBy.titleAsc, child: Text('Title A-Z')),
              PopupMenuItem(value: SortBy.titleDesc, child: Text('Title Z-A')),
            ],
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search notes...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: state.searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          FocusScope.of(context).unfocus();
                        },
                      ),
              ),
            ),
          ),
          if (state.isLoading) const LinearProgressIndicator(minHeight: 2),
          if (state.error != null) Padding(
            padding: const EdgeInsets.all(8),
            child: Text(state.error!, style: const TextStyle(color: Colors.red)),
          ),
          Expanded(
            child: state.searchQuery.isNotEmpty
              ? _SearchList(results: state.searchResults)
              : (state.folders.isEmpty && state.recentNotes.isEmpty
                ? _EmptyState(onCreate: () async {
                    final repo = ref.read(repositoryProvider);
                    final folder = await repo.getOrCreateFolderByName('Quick Ideas');
                    final note = await ref.read(homeViewModelProvider.notifier).createNote(folder, 'New note');
                    if (!context.mounted) return;
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => NoteEditorPage(noteId: note.id),
                    ));
                    if (!context.mounted) return;
                    await ref.read(homeViewModelProvider.notifier).loadData();
                  })
                : _HomeLists(folders: state.folders, notes: state.recentNotes)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final repo = ref.read(repositoryProvider);
          // Simple quick add flow
          final folder = await repo.getOrCreateFolderByName('Quick Ideas');
          final note = await ref.read(homeViewModelProvider.notifier).createNote(folder, 'New note');
          if (!context.mounted) return;
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => NoteEditorPage(noteId: note.id),
          ));
          if (!context.mounted) return;
          await ref.read(homeViewModelProvider.notifier).loadData();
        },
        label: const Text('Quick Add'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}

class _HomeLists extends ConsumerWidget {
  final List<Folder> folders;
  final List<Note> notes; // recent notes
  const _HomeLists({required this.folders, required this.notes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String relativeTime(DateTime time) {
      final now = DateTime.now();
      final diff = now.difference(time);
      if (diff.inSeconds < 60) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      String two(int n) => n.toString().padLeft(2, '0');
      return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
    }

    return ListView(
      children: [
        if (folders.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text('Folders', style: Theme.of(context).textTheme.titleMedium),
          ),
        ...folders.map((f) => ListTile(
              leading: const Icon(Icons.folder),
              title: Text(f.name),
              subtitle: Text('Updated ${relativeTime(f.updatedAt)}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (f.pinned) const Icon(Icons.push_pin, size: 18),
                  IconButton(
                    icon: const Icon(Icons.share),
                    tooltip: 'Share all',
                    onPressed: () async {
                      final repo = ref.read(repositoryProvider);
                      final notes = await repo.listNotesInFolder(f.id);
                      final title = 'Ideas: ${f.name}';
                      final body = notes.isEmpty
                          ? '(no notes)'
                          : notes.map((n) {
                              final t = n.title.isEmpty ? '(untitled)' : n.title;
                              return '---\n$t\n\n${n.content}'.trim();
                            }).join('\n\n');
                      await shareTextAsAttachment(title, body);
                    },
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'rename') {
                        final controller = TextEditingController(text: f.name);
                        final newName = await showDialog<String>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Rename folder'),
                            content: TextField(
                              controller: controller,
                              decoration: const InputDecoration(hintText: 'Folder name'),
                              autofocus: true,
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
                            ],
                          ),
                        );
                        if (newName != null && newName.isNotEmpty && newName != f.name) {
                          await ref.read(homeViewModelProvider.notifier).renameFolder(f.id, newName);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Folder renamed')));
                        }
                      } else if (value == 'pin') {
                        await ref.read(homeViewModelProvider.notifier).toggleFolderPinned(f.id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f.pinned ? 'Unpinned' : 'Pinned')));
                      } else if (value == 'trash_page') {
                        if (!context.mounted) return;
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TrashPage()));
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'pin', child: Text(f.pinned ? 'Unpin' : 'Pin')),
                      const PopupMenuItem(value: 'trash_page', child: Text('Open Trash')),
                    ],
                  ),
                ],
              ),
              onLongPress: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Delete folder?'),
                    content: const Text('Deleting a folder will remove all its notes. This cannot be undone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ref.read(homeViewModelProvider.notifier).deleteFolder(f.id);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Folder deleted')));
                }
              },
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => FolderPage(folder: f),
                ));
              },
            )),
        if (notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text('Recent', style: Theme.of(context).textTheme.titleMedium),
          ),
        ...notes.map((n) {
          final preview = n.content.length > 120 ? '${n.content.substring(0, 120)}…' : n.content;
          Widget statusChip(NoteStatus s) {
            String label;
            Color? color;
            switch (s) {
              case NoteStatus.idea:
                label = 'Idea';
                color = Colors.blueGrey.shade200;
                break;
              case NoteStatus.draft:
                label = 'Draft';
                color = Colors.amber.shade300;
                break;
              case NoteStatus.ready:
                label = 'Ready';
                color = Colors.blue.shade300;
                break;
              case NoteStatus.done:
                label = 'Done';
                color = Colors.green.shade300;
                break;
              case NoteStatus.dropped:
                label = 'Dropped';
                color = Colors.red.shade300;
                break;
            }
            return Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(label, style: const TextStyle(fontSize: 11)),
            );
          }
          return ListTile(
            leading: const Icon(Icons.note),
            title: Row(
              children: [
                if (n.pinned)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.push_pin, size: 16),
                  ),
                Expanded(child: Text(n.title.isEmpty ? '(untitled)' : n.title)),
                statusChip(n.status),
              ],
            ),
            subtitle: Text(preview),
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'open') {
                  final nav = Navigator.of(context);
                  await nav.push(MaterialPageRoute(
                    builder: (_) => NoteEditorPage(noteId: n.id),
                  ));
                  await ref.read(homeViewModelProvider.notifier).loadData();
                } else if (value == 'share') {
                  final title = n.title.isEmpty ? '(untitled)' : n.title;
                  final body = '$title\n\n${n.content}';
                  shareTextAsAttachment(title, body);
                } else if (value == 'delete') {
                  await ref.read(homeViewModelProvider.notifier).deleteNoteById(n.id);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Moved to Trash')));
                  await ref.read(homeViewModelProvider.notifier).loadData();
                } else if (value == 'trash_page') {
                  if (!context.mounted) return;
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TrashPage()));
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'open', child: Text('Open')),
                PopupMenuItem(value: 'share', child: Text('Share')),
                PopupMenuItem(value: 'delete', child: Text('Move to Trash')),
                PopupMenuItem(value: 'trash_page', child: Text('Open Trash')),
              ],
            ),
            onTap: () async {
              final nav = Navigator.of(context);
              await nav.push(MaterialPageRoute(
                builder: (_) => NoteEditorPage(noteId: n.id),
              ));
              // Odśwież listy po powrocie z edytora
              await ref.read(homeViewModelProvider.notifier).loadData();
            },
          );
        }),
      ],
    );
  }
}

class _SearchList extends ConsumerWidget {
  final List<SearchResult> results;
  const _SearchList({required this.results});

  String relativeTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (results.isEmpty) {
      return const Center(child: Text('No results'));
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final r = results[index].note;
        final preview = r.content.length > 120 ? '${r.content.substring(0, 120)}…' : r.content;
        return ListTile(
          leading: const Icon(Icons.search),
          title: Text(r.title.isEmpty ? '(untitled)' : r.title),
          subtitle: Text(preview),
          trailing: Text(relativeTime(r.updatedAt), style: Theme.of(context).textTheme.bodySmall),
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => NoteEditorPage(noteId: r.id),
            ));
          },
          onLongPress: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Delete note?'),
                content: const Text('This action cannot be undone.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                ],
              ),
            );
            if (confirm == true) {
              await ref.read(homeViewModelProvider.notifier).deleteNoteById(r.id);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note deleted')));
            }
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lightbulb, size: 64, color: Colors.amber),
          const SizedBox(height: 12),
          const Text('No folders or notes yet'),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Create your first idea'),
          ),
        ],
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
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  bool _programmaticUpdate = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _contentCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  void _syncFromVm(Note? note) {
    if (note == null) return;
    _programmaticUpdate = true;
    if (_titleCtrl.text != note.title) _titleCtrl.text = note.title;
    if (_contentCtrl.text != note.content) _contentCtrl.text = note.content;
    _programmaticUpdate = false;
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(noteEditorViewModelProvider(widget.noteId));
    final editing = vm.note;
    if (editing != null && (_titleCtrl.text != editing.title || _contentCtrl.text != editing.content)) {
      _syncFromVm(editing);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(editing?.title.isEmpty == true ? 'Edit note' : editing?.title ?? 'Edit note'),
        actions: [
          if (vm.isSaving) const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          if (editing != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: _StatusBadge(status: editing.status),
            ),
          if (editing != null) IconButton(
            icon: Icon(editing.pinned ? Icons.push_pin : Icons.push_pin_outlined),
            tooltip: editing.pinned ? 'Unpin' : 'Pin',
            onPressed: () async {
              await ref.read(repositoryProvider).setNotePinned(editing.id, !editing.pinned);
              if (!mounted) return;
              await ref.read(noteEditorViewModelProvider(widget.noteId).notifier).loadNote(widget.noteId);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(editing.pinned ? 'Unpinned' : 'Pinned')));
            },
          ),
          if (editing != null) PopupMenuButton<String>(
            onSelected: (value) async {
              if (editing == null) return;
              NoteStatus? newStatus;
              switch (value) {
                case 'status_idea': newStatus = NoteStatus.idea; break;
                case 'status_draft': newStatus = NoteStatus.draft; break;
                case 'status_ready': newStatus = NoteStatus.ready; break;
                case 'status_done': newStatus = NoteStatus.done; break;
                case 'status_dropped': newStatus = NoteStatus.dropped; break;
              }
              if (newStatus != null) {
                await ref.read(repositoryProvider).setNoteStatus(editing.id, newStatus);
                if (!mounted) return;
                await ref.read(noteEditorViewModelProvider(widget.noteId).notifier).loadNote(widget.noteId);
                final label = newStatus.name[0].toUpperCase() + newStatus.name.substring(1);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status: $label')));
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'status_idea', child: Text('Set status: Idea')),
              PopupMenuItem(value: 'status_draft', child: Text('Set status: Draft')),
              PopupMenuItem(value: 'status_ready', child: Text('Set status: Ready')),
              PopupMenuItem(value: 'status_done', child: Text('Set status: Done')),
              PopupMenuItem(value: 'status_dropped', child: Text('Set status: Dropped')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () => ref.read(noteEditorViewModelProvider(widget.noteId).notifier).forceSave(),
            tooltip: 'Save now',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: editing == null ? null : () {
              final title = editing.title.isEmpty ? '(untitled)' : editing.title;
              final body = '$title\n\n${editing.content}';
              shareTextAsAttachment(title, body);
            },
            tooltip: 'Share',
          ),
        ],
      ),
      body: editing == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  TextField(
                    controller: _titleCtrl,
                    onChanged: (v) {
                      if (_programmaticUpdate) return;
                      ref.read(noteEditorViewModelProvider(widget.noteId).notifier).updateTitle(v);
                    },
                    decoration: const InputDecoration(
                      hintText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TextField(
                      controller: _contentCtrl,
                      onChanged: (v) {
                        if (_programmaticUpdate) return;
                        ref.read(noteEditorViewModelProvider(widget.noteId).notifier).updateContent(v);
                      },
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText: 'Start typing...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  if (vm.error != null) Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(vm.error!, style: const TextStyle(color: Colors.red)),
                  )
                ],
              ),
            ),
    );
  }
}

// NEW: Simple page listing notes inside a folder
class FolderPage extends ConsumerStatefulWidget {
  final Folder folder;
  const FolderPage({super.key, required this.folder});

  @override
  ConsumerState<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends ConsumerState<FolderPage> {
  late Future<List<Note>> _future;
  bool _pinned = false;

  @override
  void initState() {
    super.initState();
    _pinned = widget.folder.pinned;
    _load();
  }

  void _load() {
    final repo = ref.read(repositoryProvider);
    _future = repo.listNotesInFolder(widget.folder.id);
  }

  Future<void> _shareFolder() async {
    final repo = ref.read(repositoryProvider);
    final notes = await repo.listNotesInFolder(widget.folder.id);
    final title = 'Ideas: ${widget.folder.name}';
    final body = notes.isEmpty
        ? '(no notes)'
        : notes.map((n) {
            final t = n.title.isEmpty ? '(untitled)' : n.title;
            return '---\n$t\n\n${n.content}'.trim();
          }).join('\n\n');
    await shareTextAsAttachment(title, body);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.folder.name),
        actions: [
          IconButton(
            icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
            tooltip: _pinned ? 'Unpin' : 'Pin',
            onPressed: () async {
              await ref.read(homeViewModelProvider.notifier).toggleFolderPinned(widget.folder.id);
              if (!mounted) return;
              setState(() {
                _pinned = !_pinned;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(_pinned ? 'Pinned' : 'Unpinned')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share all',
            onPressed: _shareFolder,
          )
        ],
      ),
      body: FutureBuilder<List<Note>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final notes = snap.data ?? const <Note>[];
          if (notes.isEmpty) {
            return const Center(child: Text('No notes in this folder'));
          }
          return ListView.builder(
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final n = notes[index];
              final preview = n.content.length > 120 ? '${n.content.substring(0, 120)}…' : n.content;
              Widget statusChip(NoteStatus s) {
                String label;
                Color? color;
                switch (s) {
                  case NoteStatus.idea:
                    label = 'Idea';
                    color = Colors.blueGrey.shade200;
                    break;
                  case NoteStatus.draft:
                    label = 'Draft';
                    color = Colors.amber.shade300;
                    break;
                  case NoteStatus.ready:
                    label = 'Ready';
                    color = Colors.blue.shade300;
                    break;
                  case NoteStatus.done:
                    label = 'Done';
                    color = Colors.green.shade300;
                    break;
                  case NoteStatus.dropped:
                    label = 'Dropped';
                    color = Colors.red.shade300;
                    break;
                }
                return Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(label, style: const TextStyle(fontSize: 11)),
                );
              }
              return ListTile(
                leading: const Icon(Icons.note),
                title: Row(
                  children: [
                    if (n.pinned) const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.push_pin, size: 16),
                    ),
                    Expanded(child: Text(n.title.isEmpty ? '(untitled)' : n.title)),
                    statusChip(n.status),
                  ],
                ),
                subtitle: Text(preview),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'open') {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => NoteEditorPage(noteId: n.id),
                      ));
                      if (!mounted) return;
                      setState(_load);
                    } else if (value == 'share') {
                      final title = n.title.isEmpty ? '(untitled)' : n.title;
                      final body = '$title\n\n${n.content}';
                      shareTextAsAttachment(title, body);
                    } else if (value == 'delete') {
                      await ref.read(homeViewModelProvider.notifier).deleteNoteById(n.id);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Moved to Trash')));
                      await ref.read(homeViewModelProvider.notifier).loadData();
                    } else if (value == 'toggle_pin') {
                      await ref.read(homeViewModelProvider.notifier).toggleNotePinned(n.id);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n.pinned ? 'Unpinned' : 'Pinned')));
                      await ref.read(homeViewModelProvider.notifier).loadData();
                    } else if (value == 'trash_page') {
                      if (!context.mounted) return;
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TrashPage()));
                    } else if (value.startsWith('status_')) {
                      NoteStatus? newStatus;
                      switch (value) {
                        case 'status_idea':
                          newStatus = NoteStatus.idea;
                          break;
                        case 'status_draft':
                          newStatus = NoteStatus.draft;
                          break;
                        case 'status_ready':
                          newStatus = NoteStatus.ready;
                          break;
                        case 'status_done':
                          newStatus = NoteStatus.done;
                          break;
                        case 'status_dropped':
                          newStatus = NoteStatus.dropped;
                          break;
                      }
                      if (newStatus != null) {
                        await ref.read(repositoryProvider).setNoteStatus(n.id, newStatus);
                        if (!context.mounted) return;
                        final label = newStatus.name[0].toUpperCase() + newStatus.name.substring(1);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status: $label')));
                        setState(_load);
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'open', child: Text('Open')),
                    const PopupMenuItem(value: 'share', child: Text('Share')),
                    PopupMenuItem(value: 'toggle_pin', child: Text(n.pinned ? 'Unpin' : 'Pin')),
                    const PopupMenuItem(value: 'delete', child: Text('Move to Trash')),
                    const PopupMenuItem(value: 'trash_page', child: Text('Open Trash')),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'status_idea', child: Text('Set status: Idea')),
                    const PopupMenuItem(value: 'status_draft', child: Text('Set status: Draft')),
                    const PopupMenuItem(value: 'status_ready', child: Text('Set status: Ready')),
                    const PopupMenuItem(value: 'status_done', child: Text('Set status: Done')),
                    const PopupMenuItem(value: 'status_dropped', child: Text('Set status: Dropped')),
                  ],
                ),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => NoteEditorPage(noteId: n.id),
                  ));
                  if (!mounted) return;
                  setState(_load);
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final nav = Navigator.of(context);
          final note = await ref.read(homeViewModelProvider.notifier).createNote(widget.folder, 'New note');
          if (!mounted) return;
          await nav.push(MaterialPageRoute(
            builder: (_) => NoteEditorPage(noteId: note.id),
          ));
          if (!mounted) return;
          setState(_load);
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class TrashPage extends ConsumerStatefulWidget {
  const TrashPage({super.key});

  @override
  ConsumerState<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends ConsumerState<TrashPage> {
  late Future<List<Note>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = ref.read(repositoryProvider).listTrashedNotes();
  }

  Future<void> _purge() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Empty trash?'),
        content: const Text('Permanently delete notes in trash older than 30 days.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Empty')),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(repositoryProvider).purgeDeleted();
      if (!mounted) return;
      setState(_load);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trash cleaned')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Empty trash',
            onPressed: _purge,
          )
        ],
      ),
      body: FutureBuilder<List<Note>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const <Note>[];
          if (items.isEmpty) return const Center(child: Text('Trash is empty'));
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final n = items[index];
              final preview = n.content.length > 120 ? '${n.content.substring(0, 120)}…' : n.content;
              return ListTile(
                leading: const Icon(Icons.note_outlined),
                title: Text(n.title.isEmpty ? '(untitled)' : n.title),
                subtitle: Text(preview),
                trailing: IconButton(
                  icon: const Icon(Icons.restore),
                  tooltip: 'Restore',
                  onPressed: () async {
                    await ref.read(homeViewModelProvider.notifier).restoreNote(n.id);
                    if (!mounted) return;
                    setState(_load);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note restored')));
                  },
                ),
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

  @override
  Widget build(BuildContext context) {
    String label;
    Color? color;
    switch (status) {
      case NoteStatus.idea:
        label = 'Idea';
        color = Colors.blueGrey.shade200;
        break;
      case NoteStatus.draft:
        label = 'Draft';
        color = Colors.amber.shade300;
        break;
      case NoteStatus.ready:
        label = 'Ready';
        color = Colors.blue.shade300;
        break;
      case NoteStatus.done:
        label = 'Done';
        color = Colors.green.shade300;
        break;
      case NoteStatus.dropped:
        label = 'Dropped';
        color = Colors.red.shade300;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
