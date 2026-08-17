import 'package:flutter/material.dart';

import 'package:jyamiti/providers/theme_provider.dart';

import '../models/mathpad_library_models.dart';
import '../services/mathpad_library_storage_service.dart';

/// The Book -> Chapter -> Topic -> Sub-topic browser/editor for one batch's
/// already-loaded [index] -- shared by `MathPadLibraryScreen` (the
/// full-screen library tab) and the in-pad library drawer opened from
/// `MathPadPageEditorPage`'s top-left book icon, so both present/behave
/// identically and there's only one implementation of this tree UI to
/// maintain.
///
/// [index] must be the SAME object the caller persists via
/// [onPersistIndex] -- this widget mutates it in place (add/rename/delete
/// nodes) and expects the caller to write it to disk afterward.
class MathPadLibraryTreeView extends StatefulWidget {
  final String batchId;
  final MathPadLibraryIndex index;
  final MathPadLibraryStorageService storage;
  final Future<void> Function() onPersistIndex;
  final void Function(MathPadFoundNode node, {String? initialPageId}) onOpenNode;
  // When opened from inside a page (e.g. the pad's own library drawer),
  // the node the tutor is currently on -- pre-navigates so it's visible
  // in the initially-shown list, highlighted with a bright border instead
  // of starting back at the book selector every time.
  final String? currentNodeId;

  const MathPadLibraryTreeView({
    super.key,
    required this.batchId,
    required this.index,
    required this.storage,
    required this.onPersistIndex,
    required this.onOpenNode,
    this.currentNodeId,
  });

  @override
  State<MathPadLibraryTreeView> createState() => _MathPadLibraryTreeViewState();
}

class _MathPadLibraryTreeViewState extends State<MathPadLibraryTreeView> {
  MathPadBook? _selectedBook;
  int? _focusedChapterIndex;
  int? _focusedTopicIndex;

  @override
  void initState() {
    super.initState();
    final currentNodeId = widget.currentNodeId;
    if (currentNodeId != null) {
      final path = widget.index.findNodeContainerPath(currentNodeId);
      if (path != null) {
        _selectedBook = path.book;
        _focusedChapterIndex = path.chapterIndex;
        _focusedTopicIndex = path.topicIndex;
      }
    }
  }

  MathPadChapter? get _focusedChapter =>
      (_selectedBook != null &&
          _focusedChapterIndex != null &&
          _focusedChapterIndex! < _selectedBook!.chapters.length)
      ? _selectedBook!.chapters[_focusedChapterIndex!]
      : null;

  MathPadTopic? get _focusedTopic =>
      (_focusedChapter != null &&
          _focusedTopicIndex != null &&
          _focusedTopicIndex! < _focusedChapter!.topics.length)
      ? _focusedChapter!.topics[_focusedTopicIndex!]
      : null;

  /// Chapters, topics, or sub-topics -- whichever is the current drill
  /// level's set of children. Sub-topics are a dead end (nothing deeper
  /// to drill into) -- their tiles open the pad directly on tap instead.
  List<dynamic> get _currentChildNodes {
    if (_focusedTopic != null) return _focusedTopic!.subTopics;
    if (_focusedChapter != null) return _focusedChapter!.topics;
    if (_selectedBook != null) return _selectedBook!.chapters;
    return const [];
  }

  Future<String?> _promptForTitle(String dialogTitle, {String initialValue = ''}) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final isDark = ctx.isDark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Text(
            dialogTitle,
            style: TextStyle(color: ctx.textColor, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: ctx.textColor),
            decoration: InputDecoration(
              hintText: 'Title',
              hintStyle: TextStyle(color: ctx.textColor54),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: ctx.glassBorder),
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onSubmitted: (val) => Navigator.pop(ctx, val.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: ctx.textColor60)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _confirmDelete(String what) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: ctx.isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text('Delete $what?', style: TextStyle(color: ctx.textColor, fontWeight: FontWeight.bold)),
        content: Text(
          what == 'Page'
              ? 'This page and its drawing will be permanently deleted.'
              : 'This $what and everything inside it (including any saved pages) will be permanently deleted.',
          style: TextStyle(color: ctx.textColor70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: ctx.textColor60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _addBook() async {
    final title = await _promptForTitle('New Book Title');
    if (title == null || title.isEmpty) return;
    setState(() => widget.index.addBook(title));
    await widget.onPersistIndex();
  }

  void _selectBook(MathPadBook book) {
    setState(() {
      _selectedBook = book;
      _focusedChapterIndex = null;
      _focusedTopicIndex = null;
    });
  }

  Future<void> _addChildNode() async {
    final levelName = _focusedTopic != null
        ? 'Sub-topic'
        : _focusedChapter != null
        ? 'Topic'
        : 'Chapter';
    final title = await _promptForTitle('New $levelName Title');
    if (title == null || title.isEmpty) return;
    setState(() {
      if (_focusedTopic != null) {
        _focusedTopic!.addSubTopic(title);
      } else if (_focusedChapter != null) {
        _focusedChapter!.addTopic(title);
      } else if (_selectedBook != null) {
        _selectedBook!.addChapter(title);
      }
    });
    await widget.onPersistIndex();
  }

  Future<void> _renameChildNode(int index) async {
    final nodes = _currentChildNodes;
    if (index >= nodes.length) return;
    final node = nodes[index];
    final currentTitle = node.title as String;
    final title = await _promptForTitle('Rename', initialValue: currentTitle);
    if (title == null || title.isEmpty) return;
    setState(() => node.title = title);
    await widget.onPersistIndex();
  }

  Future<void> _deleteChildNode(int index) async {
    final levelName = _focusedTopic != null
        ? 'Sub-topic'
        : _focusedChapter != null
        ? 'Topic'
        : 'Chapter';
    if (!await _confirmDelete(levelName)) return;

    final nodes = _currentChildNodes;
    if (index >= nodes.length) return;
    final id = (nodes[index] as dynamic).id as String;

    List<MathPadPageRef> removedPages = const [];
    setState(() {
      if (_focusedTopic != null) {
        removedPages = _focusedTopic!.removeSubTopic(id);
      } else if (_focusedChapter != null) {
        removedPages = _focusedChapter!.removeTopic(id);
      } else if (_selectedBook != null) {
        removedPages = _selectedBook!.removeChapter(id);
      }
    });
    if (removedPages.isNotEmpty) {
      await widget.storage.deletePages(widget.batchId, removedPages.map((p) => p.id).toList());
    }
    await widget.onPersistIndex();
  }

  /// Drills into a Chapter or Topic tile's children. Never called for a
  /// Sub-topic tile -- those have nothing further to drill into, so their
  /// tap opens the pad directly instead (see `_buildChildTile`'s `isLeaf`).
  void _drillInto(int index) {
    setState(() {
      if (_focusedChapter != null) {
        _focusedTopicIndex = index;
      } else {
        _focusedChapterIndex = index;
      }
    });
  }

  String get _breadcrumbTitle {
    final parts = <String>[if (_selectedBook != null) _selectedBook!.title];
    if (_focusedChapter != null) parts.add(_focusedChapter!.title);
    if (_focusedTopic != null) parts.add(_focusedTopic!.title);
    return parts.join(' › ');
  }

  void _openNodePad(int index) {
    final nodes = _currentChildNodes;
    if (index >= nodes.length) return;
    final node = nodes[index];
    widget.onOpenNode((
      nodeId: node.id as String,
      nodeTitle: '$_breadcrumbTitle › ${node.title as String}',
      pages: node.pages as List<MathPadPageRef>,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedBook == null) {
      return _buildBookSelector(context);
    }
    return _buildBookContents(context);
  }

  Widget _buildBookSelector(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Books', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            children: [
              ...widget.index.books.map(
                (book) => Card(
                  color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: context.glassBorder),
                  ),
                  child: ListTile(
                    leading: Icon(
                      book.isDefault ? Icons.menu_book_rounded : Icons.book_outlined,
                      color: const Color(0xFF6366F1),
                    ),
                    title: Text(book.title, style: TextStyle(color: context.textColor, fontWeight: FontWeight.w600)),
                    subtitle: book.isDefault
                        ? const Text('Course Book', style: TextStyle(color: Color(0xFF6366F1), fontSize: 12))
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!book.isDefault)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                            onPressed: () async {
                              final confirmed = await _confirmDelete('Book');
                              if (confirmed) {
                                final removedPages = widget.index.removeBook(book.id);
                                if (removedPages.isNotEmpty) {
                                  await widget.storage.deletePages(
                                    widget.batchId,
                                    removedPages.map((p) => p.id).toList(),
                                  );
                                }
                                await widget.onPersistIndex();
                                setState(() {});
                              }
                            },
                          ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                    onTap: () => _selectBook(book),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _addBook,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New Book'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6366F1),
                  side: const BorderSide(color: Color(0xFF6366F1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              if (widget.index.recentPageIds.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Recent Pages', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 10),
                ...widget.index.recentPageIds.map((pageId) {
                  final node = widget.index.findNodeForPage(pageId);
                  if (node == null) return const SizedBox.shrink();
                  final page = node.pages.firstWhere((p) => p.id == pageId);
                  
                  return Card(
                    color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: context.glassBorder),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.description_rounded, color: Color(0xFF6366F1)),
                      title: Text(page.title, style: TextStyle(color: context.textColor, fontWeight: FontWeight.w600)),
                      subtitle: Text(node.nodeTitle, style: const TextStyle(color: Color(0xFF6366F1), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
                      onTap: () {
                         widget.onOpenNode(node, initialPageId: page.id);
                      },
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBookContents(BuildContext context) {
    final levelName = _focusedTopic != null
        ? 'Sub-topic'
        : _focusedChapter != null
        ? 'Topic'
        : 'Chapter';
    // Sub-topics have no further drill level -- their tile's tap opens the
    // pad directly instead of drilling in.
    final isLeafLevel = _focusedTopic != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBreadcrumbBar(context),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Double-click a $levelName to open its Math Pad.',
            style: TextStyle(color: context.textColor60, fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              Text(
                '${levelName}s',
                style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 8),
              ..._currentChildNodes.asMap().entries.map(
                (e) => _buildChildTile(
                  context,
                  e.key,
                  e.value.title as String,
                  isLeaf: isLeafLevel,
                  isCurrent: e.value.id == widget.currentNodeId,
                ),
              ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _addChildNode,
                icon: const Icon(Icons.add_rounded),
                label: Text('Add $levelName'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6366F1),
                  side: const BorderSide(color: Color(0xFF6366F1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChildTile(
    BuildContext context,
    int index,
    String title, {
    required bool isLeaf,
    bool isCurrent = false,
  }) {
    return GestureDetector(
      onDoubleTap: isLeaf ? null : () => _drillInto(index),
      child: Card(
        color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isCurrent
              ? const BorderSide(color: Color(0xFF22D3EE), width: 2.5)
              : BorderSide(color: context.glassBorder),
        ),
        child: ListTile(
          leading: isCurrent
              ? const Icon(Icons.my_location_rounded, color: Color(0xFF22D3EE))
              : (isLeaf ? const Icon(Icons.edit_note_rounded, color: Color(0xFF10B981)) : null),
          title: Text(
            title,
            style: TextStyle(
              color: context.textColor,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: isCurrent
              ? const Text(
                  "You're here",
                  style: TextStyle(color: Color(0xFF22D3EE), fontSize: 11, fontWeight: FontWeight.bold),
                )
              : (!isLeaf
                    ? Text('Double-click to expand', style: TextStyle(color: context.textColor60, fontSize: 11))
                    : null),
          onTap: () => _openNodePad(index),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_rounded, size: 18),
                tooltip: 'Rename',
                onPressed: () => _renameChildNode(index),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                tooltip: 'Delete',
                onPressed: () => _deleteChildNode(index),
              ),
              if (!isLeaf) const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreadcrumbBar(BuildContext context) {
    final crumbs = <MapEntry<String, VoidCallback>>[
      MapEntry(_selectedBook!.title, () => setState(() {
        _focusedChapterIndex = null;
        _focusedTopicIndex = null;
      })),
      if (_focusedChapter != null)
        MapEntry(_focusedChapter!.title, () => setState(() => _focusedTopicIndex = null)),
      if (_focusedTopic != null) MapEntry(_focusedTopic!.title, () {}),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.isDark
            ? const Color(0xFF1E1B4B).withValues(alpha: 0.9)
            : const Color(0xFFE0E7FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.4)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            InkWell(
              onTap: () => setState(() => _selectedBook = null),
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Icon(Icons.home_rounded, size: 16, color: Color(0xFF6366F1)),
              ),
            ),
            for (final crumb in crumbs) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              InkWell(
                onTap: crumb.value,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    crumb.key,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: identical(crumb, crumbs.last) ? context.textColor : const Color(0xFF6366F1),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
