import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:jyamiti/providers/theme_provider.dart';
import '../../recording/mathpad_recording_service.dart';

import '../../screens/mathpad.dart';
import '../models/mathpad_library_models.dart';
import '../models/page_snapshot.dart';
import '../services/mathpad_library_storage_service.dart';
import '../widgets/mathpad_library_tree_view.dart';

/// The full Math Pad experience for one library node (a Chapter, Topic, or
/// Sub-topic) -- opened by double-clicking that node in
/// `MathPadLibraryScreen`. Pages themselves are created/switched/deleted
/// HERE, inside the pad, via the floating page-switcher bar -- the library
/// tree itself no longer has any page UI. A book icon at the top-left opens
/// a drawer with the SAME tree (any book, any level) so the tutor can jump
/// straight to a different page without leaving the pad.
///
/// [pages] is a LIVE reference into the node's own list inside
/// [libraryIndex] (`MathPadChapter.pages` / `.topics`/`.subTopics` etc.) --
/// mutating it (add/remove/rename) is automatically reflected back into the
/// SAME index object the drawer browses, and [onPagesChanged] must be
/// called after any such mutation so the caller persists it to disk.
/// [libraryIndex] must be the exact same object the opening
/// `MathPadLibraryScreen` (or whoever else) is holding -- not a separately
/// re-loaded copy -- so [pages], the drawer, and [onPagesChanged] all stay
/// in sync with one shared in-memory tree instead of silently forking.
class MathPadPageEditorPage extends StatefulWidget {
  final String nodeId;
  final String nodeTitle;
  final List<MathPadPageRef> pages;
  final String batchId;
  final MathPadLibraryIndex libraryIndex;
  final MathPadLibraryStorageService storage;
  final Future<void> Function() onPagesChanged;
  // When resuming a specific "last worked" page (rather than opening a
  // node fresh), the exact page to land on -- falls back to the first
  // page if omitted, not found (e.g. since deleted), or the node turns
  // out to have no pages yet.
  final String? initialPageId;

  const MathPadPageEditorPage({
    super.key,
    required this.nodeId,
    required this.nodeTitle,
    required this.pages,
    required this.batchId,
    required this.libraryIndex,
    required this.storage,
    required this.onPagesChanged,
    this.initialPageId,
  });

  @override
  State<MathPadPageEditorPage> createState() => _MathPadPageEditorPageState();
}

class _MathPadPageEditorPageState extends State<MathPadPageEditorPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Start as the node the pad was opened for, but can be swapped to a
  // different node picked from the library drawer -- so these live on the
  // State, not read directly from `widget`.
  late String _nodeId;
  late String _nodeTitle;
  late List<MathPadPageRef> _pages;

  int _currentIndex = 0;
  MathPadPageSnapshot? _snapshot;
  bool _loading = true;
  // Mirrors the pad's own internal "canvas only" full-screen mode -- while
  // active, this page's OWN floating chrome (book button, page-preview
  // toggle, bottom path label/page-switcher bar) hides too, so the pad
  // really does get the whole screen instead of just its own toolbar.
  bool _isPadCanvasOnly = false;
  MathsPadLiveStateReader? _liveReader;
  // Registered by the currently-mounted `MathsPadWidget` (re-registered on
  // every page switch, same as `_liveReader`) -- called right after every
  // save to regenerate that page's cached preview image (see
  // `_saveCurrentLive`/`onSaveRequested` below).
  Future<Uint8List?> Function()? _thumbnailCapture;
  Timer? _autosaveTimer;
  bool _showBottomBar = true;
  Timer? _bottomBarTimer;
  Timer? _hoverTimer;
  // Every save (periodic autosave tick, page switch, the pad's own manual
  // Save Page button, close) is chained onto this so at most one
  // `savePage` call for a given page is ever in flight -- see
  // `_saveCurrentLive`.
  Future<void> _pendingSave = Future.value();

  // Cached preview images (PNG bytes, or `null` while none has been
  // generated yet -- see `MathPadLibraryStorageService.loadThumbnail`),
  // keyed by page id. Deliberately NOT full `MathPadPageSnapshot`s: the
  // pages sidebar only ever needs to show a small image, so loading it
  // this way skips the full JSON/stroke/image-codec decode `loadPage`
  // does entirely -- that decode is real, non-trivial work (the same cost
  // that used to freeze opening a heavy page), and doing it once per page
  // just to populate a drawer was the actual reason it felt slow.
  final Map<String, Uint8List?> _pageThumbnails = {};

  Future<void> _loadAllPreviews() async {
    // Plain file reads with no shared resource to serialize on (unlike
    // `savePage`'s `images_tmp` writes) -- parallelize rather than the
    // sequential `await` loop this replaced.
    final results = await Future.wait(
      _pages.map((ref) async {
        try {
          return MapEntry(ref.id, await widget.storage.loadThumbnail(widget.batchId, ref.id));
        } catch (e) {
          debugPrint('Failed to load thumbnail for page ${ref.id}: $e');
          return MapEntry(ref.id, null);
        }
      }),
    );
    if (!mounted) return;
    setState(() {
      for (final entry in results) {
        _pageThumbnails[entry.key] = entry.value;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _nodeId = widget.nodeId;
    _nodeTitle = widget.nodeTitle;
    _pages = widget.pages;
    _ensurePagesAndLoad(preferredPageId: widget.initialPageId);
    // Everything drawn here is autosaved continuously -- no explicit save
    // step needed, and nothing is lost if the app closes unexpectedly
    // mid-drawing (page-switch/close already save immediately on top of
    // this periodic tick). Deliberately NOT capturing a thumbnail on this
    // tick (see `_saveCurrentLive`'s `captureThumbnail` doc comment) --
    // that's real rasterization work, and doing it every 5 seconds while
    // actively drawing/panning was landing a stutter in the middle of
    // whatever gesture was in progress.
    _autosaveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _saveCurrentLive(),
    );
    _bottomBarTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _showBottomBar = false);
    });
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _bottomBarTimer?.cancel();
    _hoverTimer?.cancel();
    
    // Auto-stop recording if they leave the editor entirely
    try {
      final recordingService = Provider.of<MathPadRecordingService>(context, listen: false);
      if (recordingService.state == MathPadRecordingState.recording) {
        recordingService.stopCapture().then((_) {
          recordingService.encode(fastEncode: true);
        });
      }
    } catch (_) {
      // Ignore if Provider can't be read during dispose
    }
    
    super.dispose();
  }

  Future<void> _ensurePagesAndLoad({String? preferredPageId}) async {
    if (_pages.isEmpty) {
      _pages.add(MathPadPageRef.create('Page 1'));
      await widget.onPagesChanged();
    }
    int index = 0;
    if (preferredPageId != null) {
      final found = _pages.indexWhere((p) => p.id == preferredPageId);
      if (found != -1) index = found;
    }
    await _loadPage(index);
    _loadAllPreviews();
  }

  Future<void> _loadPage(int index) async {
    setState(() => _loading = true);
    final ref = _pages[index];
    final snapshot = await widget.storage.loadPage(widget.batchId, ref.id);
    if (!mounted) return;
    setState(() {
      _currentIndex = index;
      _snapshot = snapshot;
      _loading = false;
      _liveReader = null; // the freshly-keyed MathsPadWidget will re-register
      _thumbnailCapture = null; // ditto
    });
    // Record this as the tutor's current spot so the sidebar's Math Pad
    // tab can resume directly here next time, instead of always showing
    // the book/chapter browser first.
    await widget.storage.saveLastWorked((
      batchId: widget.batchId,
      nodeId: _nodeId,
      pageId: ref.id,
    ));
    
    // Add to recent pages and persist
    widget.libraryIndex.recordPageOpened(ref.id);
    widget.onPagesChanged?.call();
  }

  /// Silently persists whatever's currently on screen (via the live reader
  /// registered by the mounted `MathsPadWidget`) to the current page's slot
  /// on disk -- used before switching/adding/deleting pages so nothing is
  /// lost, without interrupting the tutor with a save dialog every flip.
  ///
  /// Chained onto [_pendingSave] rather than run directly: the periodic
  /// autosave tick, an explicit page switch, and the manual Save button can
  /// all call this within moments of each other, and `savePage` writes
  /// through a shared `images_tmp` directory per page -- two overlapping
  /// writes there race and can crash with a `PathNotFoundException`. Queuing
  /// guarantees only one `savePage` call for a given page is ever in flight
  /// at a time.
  ///
  /// [captureThumbnail] defaults to false and must be opted into explicitly
  /// by callers that represent actually LEAVING this page (page switch,
  /// add-page, switching library node) -- NOT the plain periodic 5-second
  /// autosave tick. Capturing a thumbnail means rasterizing the whole
  /// canvas (`RenderRepaintBoundary.toImage` + PNG encode), which is real,
  /// non-trivial work regardless of the output image's small size -- doing
  /// that on every autosave tick meant it was firing continuously while
  /// the tutor was actively drawing/panning, landing a real stutter every
  /// 5 seconds in the middle of whatever gesture was in progress. Once per
  /// page-leave (a much rarer, already-loading-spinner-covered moment) is
  /// what "once per save" should have meant in practice; the periodic tick
  /// still saves the lightweight JSON exactly as before this feature
  /// existed.
  Future<void> _saveCurrentLive({bool captureThumbnail = false}) {
    final reader = _liveReader;
    if (reader == null) return _pendingSave;
    final live = reader();
    final ref = _pages[_currentIndex];
    final snapshot = MathPadPageSnapshot(
      lines: live.lines,
      instruments: live.instruments,
      textLabels: live.textLabels,
      fixedAngleLabels: live.fixedAngleLabels,
      bgMode: live.bgMode,
      themeMode: live.themeMode,
    );
    final capture = captureThumbnail ? _thumbnailCapture : null;
    _pendingSave = _pendingSave.then((_) async {
      await widget.storage.savePage(widget.batchId, ref.id, snapshot);
      ref.updatedAt = DateTime.now();
      Uint8List? thumbBytes;
      if (capture != null) {
        thumbBytes = await capture();
        if (thumbBytes != null) {
          await widget.storage.saveThumbnail(widget.batchId, ref.id, thumbBytes);
        }
      }
      if (mounted) {
        setState(() {
          if (thumbBytes != null) _pageThumbnails[ref.id] = thumbBytes;
        });
      }
      await widget.onPagesChanged();
    });
    return _pendingSave;
  }

  Future<void> _goToPage(int index) async {
    if (index == _currentIndex || index < 0 || index >= _pages.length) {
      return;
    }
    await _saveCurrentLive(captureThumbnail: true);
    await _loadPage(index);
  }

  Future<void> _addPage() async {
    await _saveCurrentLive(captureThumbnail: true);

    // Carry the current page's theme forward onto the new page instead of
    // always resetting to the light-theme default -- reading from the live
    // editor state (freshest source, same as `_saveCurrentLive` itself just
    // used), falling back to the last-loaded snapshot if the editor hasn't
    // registered a reader yet.
    final MathPadTheme carriedTheme =
        _liveReader?.call().themeMode ?? _snapshot?.themeMode ?? MathPadTheme.light;

    final newRef = MathPadPageRef.create('Page ${_pages.length + 1}');
    // Pre-save a blank page carrying that theme, so `_loadPage` below finds
    // an actual file on disk instead of falling through to
    // `MathPadPageSnapshot.empty()`'s hardcoded light-theme default.
    await widget.storage.savePage(
      widget.batchId,
      newRef.id,
      MathPadPageSnapshot.empty(themeMode: carriedTheme),
    );
    setState(() => _pages.add(newRef));
    await widget.onPagesChanged();
    await _loadPage(_pages.length - 1);
    _loadAllPreviews();
  }

  Future<void> _deletePageAt(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: ctx.isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text(
          'Delete this page?',
          style: TextStyle(color: ctx.textColor, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This page and its drawing will be permanently deleted.',
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
    if (confirmed != true) return;

    final removed = _pages.removeAt(index);
    await widget.storage.deletePages(widget.batchId, [removed.id]);
    if (_pages.isEmpty) {
      _pages.add(MathPadPageRef.create('Page 1'));
    }
    await widget.onPagesChanged();
    
    if (index == _currentIndex) {
      final nextIndex = _currentIndex >= _pages.length ? _pages.length - 1 : _currentIndex;
      await _loadPage(nextIndex);
    } else if (index < _currentIndex) {
      _currentIndex--;
    }
    _loadAllPreviews();
    if (mounted) setState(() {});
  }

  Future<void> _renamePageAt(int index) async {
    final controller = TextEditingController(text: _pages[index].title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: ctx.isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text('Rename Page', style: TextStyle(color: ctx.textColor, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: ctx.textColor),
          decoration: InputDecoration(
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
      ),
    );
    if (title == null || title.isEmpty) return;
    setState(() => _pages[index].title = title);
    await widget.onPagesChanged();
  }

  Future<void> _showPageListSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'Pages',
                    style: TextStyle(
                      color: ctx.textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _pages.length,
                    itemBuilder: (_, i) {
                      final page = _pages[i];
                      final isCurrent = i == _currentIndex;
                      return ListTile(
                        leading: Icon(
                          Icons.description_outlined,
                          color: isCurrent ? const Color(0xFF10B981) : ctx.textColor60,
                        ),
                        title: Text(
                          page.title,
                          style: TextStyle(
                            color: ctx.textColor,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _goToPage(i);
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          tooltip: 'Rename',
                          onPressed: () {
                            Navigator.pop(ctx);
                            _renamePageAt(i);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Switches the pad in place to a different Chapter/Topic/Sub-topic
  /// picked from the library drawer -- saves whatever was on screen for
  /// the OLD node first, then loads (or starts) page 1 of the new one.
  Future<void> _switchToNode(MathPadFoundNode node, {String? initialPageId}) async {
    await _saveCurrentLive(captureThumbnail: true);
    if (!mounted) return;
    Navigator.of(context).pop(); // close the drawer
    setState(() {
      _nodeId = node.nodeId;
      _nodeTitle = node.nodeTitle;
      _pages = node.pages;
      _loading = true;
    });
    await _ensurePagesAndLoad(preferredPageId: initialPageId);
  }

  /// The Book › Chapter › ... › Page breadcrumb -- shown above the page
  /// switcher bar at the bottom of the canvas instead of the pad's own top
  /// "question banner" (which is for tutor-set questions, not navigation).
  Widget _buildPathLabel(BuildContext context, String path) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.glassBorder),
      ),
      child: Text(
        path,
        style: TextStyle(color: context.textColor60, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildPageSwitcherBar(BuildContext context) {
    final total = _pages.length;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: context.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              tooltip: 'Previous Page',
              onPressed: _currentIndex > 0 ? () => _goToPage(_currentIndex - 1) : null,
            ),
            InkWell(
              onTap: _showPageListSheet,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Page ${_currentIndex + 1} / $total',
                  style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              tooltip: 'Next Page',
              onPressed: _currentIndex < total - 1 ? () => _goToPage(_currentIndex + 1) : null,
            ),
            const SizedBox(width: 4),
            Container(width: 1, height: 22, color: context.glassBorder),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.add_rounded, color: Color(0xFF10B981)),
              tooltip: 'New Page',
              onPressed: _addPage,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              tooltip: 'Delete Page',
              onPressed: () => _deletePageAt(_currentIndex),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: context.glassBorder),
        ),
        child: IconButton(
          icon: const Icon(Icons.menu_book_rounded, color: Color(0xFF6366F1)),
          tooltip: 'Browse Library',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
      ),
    );
  }

  /// Same circular-badge look as [_buildLibraryButton], on the right edge
  /// instead -- opens the `endDrawer` (page previews) rather than the left
  /// `drawer` (library tree).
  Widget _buildPagePreviewToggleButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: context.glassBorder),
        ),
        child: IconButton(
          icon: const Icon(Icons.layers_rounded, color: Color(0xFF6366F1)),
          tooltip: 'Page Previews',
          onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
        ),
      ),
    );
  }

  Widget _buildLibraryDrawer(BuildContext context) {
    return Drawer(
      width: 340,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.menu_book_rounded, color: Color(0xFF6366F1)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Math Pad Library',
                      style: TextStyle(
                        color: context.textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: MathPadLibraryTreeView(
                  // Re-key on the current node so re-opening the drawer
                  // after switching nodes re-runs its pre-navigation/
                  // highlight logic for the NEW current node, rather than
                  // reusing State left over from the previous one.
                  key: ValueKey(_nodeId),
                  batchId: widget.batchId,
                  index: widget.libraryIndex,
                  storage: widget.storage,
                  onPersistIndex: widget.onPagesChanged,
                  onOpenNode: _switchToNode,
                  currentNodeId: _nodeId,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Same `Drawer` treatment as [_buildLibraryDrawer] (slide-in panel,
  /// modal scrim, tap-outside-to-close), just anchored on the right as the
  /// `Scaffold`'s `endDrawer` instead of the left `drawer`, holding page
  /// thumbnails instead of the library tree.
  Widget _buildPagePreviewDrawer(BuildContext context) {
    return Drawer(
      width: 300,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.layers_rounded, color: Color(0xFF6366F1)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pages',
                      style: TextStyle(
                        color: context.textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_rounded, color: Color(0xFF10B981)),
                    tooltip: 'New Page',
                    onPressed: () {
                      Navigator.of(context).pop();
                      _addPage();
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _pages.length,
                itemBuilder: (ctx, i) {
                  final page = _pages[i];
                  final isCurrent = i == _currentIndex;
                  final thumbBytes = _pageThumbnails[page.id];

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        _goToPage(i);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 120,
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? (context.isDark
                                    ? const Color(0xFF6366F1).withValues(alpha: 0.2)
                                    : const Color(0xFF6366F1).withValues(alpha: 0.1))
                              : (context.isDark ? Colors.black26 : Colors.white60),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent
                                ? const Color(0xFF6366F1)
                                : context.glassBorder,
                            width: isCurrent ? 2 : 1,
                          ),
                          boxShadow: isCurrent
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : [],
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Opacity(
                                opacity: isCurrent ? 1.0 : 0.6,
                                // A cached image generated once per save
                                // (see `_saveCurrentLive`/`onThumbnailCaptureReady`
                                // in mathpad.dart) -- trivially cheap to
                                // display, unlike the live vector redraw
                                // this replaced. A placeholder icon shows
                                // for a page that's never been saved since
                                // this feature shipped.
                                child: thumbBytes != null
                                    ? Image.memory(
                                        thumbBytes,
                                        fit: BoxFit.contain,
                                      )
                                    : Center(
                                        child: Icon(
                                          Icons.description_outlined,
                                          size: 36,
                                          color: context.textColor.withValues(
                                            alpha: 0.25,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            Positioned(
                              right: 4,
                              top: 4,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: Icon(
                                  Icons.cancel_rounded,
                                  size: 20,
                                  color: Colors.redAccent.withValues(alpha: 0.6),
                                ),
                                onPressed: () => _deletePageAt(i),
                              ),
                            ),
                            Positioned(
                              left: 6,
                              bottom: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: context.isDark ? Colors.black54 : Colors.white70,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  page.title,
                                  style: TextStyle(
                                    color: context.textColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _snapshot == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final pageTitle = '$_nodeTitle › ${_pages[_currentIndex].title}';
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildLibraryDrawer(context),
      endDrawer: _buildPagePreviewDrawer(context),
      body: SafeArea(
        child: Stack(
          children: [
            MathsPadWidget(
              key: ValueKey(_pages[_currentIndex].id),
              isFullScreen: true,
              isInline: false,
              initialLines: _snapshot!.lines,
              initialInstruments: _snapshot!.instruments,
              initialTextLabels: _snapshot!.textLabels,
              initialFixedAngleLabels: _snapshot!.fixedAngleLabels,
              initialBgMode: _snapshot!.bgMode,
              initialThemeMode: _snapshot!.themeMode,
              onEditorReady: (reader) => _liveReader = reader,
              onThumbnailCaptureReady: (capture) => _thumbnailCapture = capture,
              onSaveRequested:
                  ({
                    required lines,
                    required instruments,
                    required textLabels,
                    required fixedAngleLabels,
                    required bgMode,
                    required themeMode,
                  }) {
                    final ref = _pages[_currentIndex];
                    final snapshot = MathPadPageSnapshot(
                      lines: lines,
                      instruments: instruments,
                      textLabels: textLabels,
                      fixedAngleLabels: fixedAngleLabels,
                      bgMode: bgMode,
                      themeMode: themeMode,
                    );
                    final capture = _thumbnailCapture;
                    // Queued the same way as `_saveCurrentLive` -- this
                    // fires from the pad's own Save button/close flow and
                    // must not run concurrently with the periodic autosave
                    // tick or a page-switch save (see `_pendingSave`).
                    _pendingSave = _pendingSave.then((_) async {
                      await widget.storage.savePage(widget.batchId, ref.id, snapshot);
                      ref.updatedAt = DateTime.now();
                      // Regenerate the cached preview image alongside this
                      // save too (see `_saveCurrentLive`'s matching
                      // comment) -- both save paths keep it in sync.
                      if (capture != null) {
                        final thumbBytes = await capture();
                        if (thumbBytes != null) {
                          await widget.storage.saveThumbnail(widget.batchId, ref.id, thumbBytes);
                          if (mounted) {
                            setState(() => _pageThumbnails[ref.id] = thumbBytes);
                          }
                        }
                      }
                      await widget.onPagesChanged();
                    });
                    return _pendingSave;
                  },
              onClose: () => Navigator.of(context).pop(),
              onCanvasOnlyModeChanged: (isCanvasOnly) {
                setState(() {
                  _isPadCanvasOnly = isCanvasOnly;
                  if (!isCanvasOnly) {
                    _showBottomBar = true;
                    _bottomBarTimer?.cancel();
                    _bottomBarTimer = Timer(const Duration(seconds: 10), () {
                      if (mounted) setState(() => _showBottomBar = false);
                    });
                  }
                });
              },
              leadingToolbarAction: _buildLibraryButton(context),
              trailingToolbarAction: _buildPagePreviewToggleButton(context),
            ),
            if (!_isPadCanvasOnly) ...[
              AnimatedPositioned(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInCubic,
                left: 0,
                right: 0,
                bottom: _showBottomBar ? 16 : -200,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPathLabel(context, pageTitle),
                    const SizedBox(height: 6),
                    _buildPageSwitcherBar(context),
                  ],
                ),
              ),
              if (!_showBottomBar)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 40,
                  child: Center(
                    child: MouseRegion(
                      onEnter: (_) {
                        _hoverTimer?.cancel();
                        _hoverTimer = Timer(const Duration(seconds: 2), () {
                          if (mounted) {
                            setState(() {
                              _showBottomBar = true;
                              _bottomBarTimer?.cancel();
                              _bottomBarTimer = Timer(const Duration(seconds: 10), () {
                                if (mounted) setState(() => _showBottomBar = false);
                              });
                            });
                          }
                        });
                      },
                      onExit: (_) {
                        _hoverTimer?.cancel();
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () {
                          setState(() {
                            _showBottomBar = true;
                            _bottomBarTimer?.cancel();
                            _bottomBarTimer = Timer(const Duration(seconds: 10), () {
                              if (mounted) setState(() => _showBottomBar = false);
                            });
                          });
                        },
                        child: const SizedBox(width: 300, height: 40),
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
