import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../domain/models/slide_deck_models.dart';
import '../../../../providers/theme_provider.dart';
import '../../../../services/slide_cache_service.dart';
import '../../../widgets/writing_pad_widget.dart';
import '../widgets/columns_block_editor_screen.dart';
import '../widgets/slide_block_defaults.dart';
import '../widgets/slide_block_editor_dialog.dart';
import '../widgets/slide_block_renderer.dart';
import '../widgets/slide_color_utils.dart';

class StudentSlideViewerScreen extends StatefulWidget {
  final SlideDeck deck;
  final int initialSlideIndex;

  /// Opts this screen into an Edit Mode toggle in the header, letting
  /// whoever opened it add/reorder/edit/delete blocks directly on the
  /// exact styled preview a student would see -- instead of only being
  /// able to do that in the plainer block-list view. Defaults to false
  /// so every OTHER place this screen is pushed from (real student
  /// slide viewing, in student_learning_path_screen.dart,
  /// syllabus_explorer_screen.dart, course_syllabus_screen.dart,
  /// slide_decks_manager_screen.dart) is completely unaffected --
  /// AdminSlideCmsScreen's "Live Student Preview" button is currently
  /// the only caller that passes true. Deliberately scoped to block
  /// management only (add/reorder/edit/delete blocks on the slide
  /// currently in view) -- slide-level operations (add/delete a slide,
  /// background, quiz) still only happen back in the CMS screen.
  final bool editable;

  /// Called with the full updated slide list after every block add/
  /// reorder/edit/delete made while [editable] and edit mode is on --
  /// lets the caller (AdminSlideCmsScreen) keep its own state in sync
  /// live, while this screen stays open, rather than only handing
  /// anything back once the user leaves. Ignored when [editable] is
  /// false.
  final ValueChanged<List<SlideItem>>? onSlidesChanged;

  const StudentSlideViewerScreen({
    super.key,
    required this.deck,
    this.initialSlideIndex = 0,
    this.editable = false,
    this.onSlidesChanged,
  });

  @override
  State<StudentSlideViewerScreen> createState() =>
      _StudentSlideViewerScreenState();
}

class _StudentSlideViewerScreenState extends State<StudentSlideViewerScreen> {
  late PageController _pageController;
  late int _currentSlideIndex;
  late SlideProgress _progress;

  // Local, mutable working copy of the deck's slides -- only ever
  // written to when widget.editable (see the block-mutation helpers
  // below); read everywhere build() previously read widget.deck.slides
  // directly, so the read-only path (editable: false, the vast
  // majority of callers) renders identically to before this was added.
  late List<SlideItem> _slides;
  bool _editModeOn = false;

  // Active time tracking for analytics
  Timer? _timer;
  int _secondsOnCurrentSlide = 0;

  // Whiteboard drawing overlay states
  bool _isTransparentDrawingActive = false;
  bool _isFullWhiteboardActive = false;
  bool _isOfflineActive = false;
  bool _isLoadingProgress = true;

  @override
  void initState() {
    super.initState();
    _currentSlideIndex = widget.initialSlideIndex;
    _pageController = PageController(initialPage: widget.initialSlideIndex);
    _isOfflineActive = widget.deck.isDownloadedOffline;
    _slides = List<SlideItem>.from(widget.deck.slides);
    _loadProgress();
  }

  // ---------------------------------------------------------------------
  // Block management (only ever called when widget.editable) -- same
  // add/reorder/edit/delete shape as AdminSlideCmsScreen's own handlers
  // (_addBlockToActiveSlide/_editBlock/reorder/delete), just addressed
  // by slideIdx here since this screen pages through the whole deck
  // rather than editing one fixed "active" slide.
  // ---------------------------------------------------------------------

  void _updateSlide(int slideIdx, SlideItem Function(SlideItem) update) {
    setState(() {
      _slides = List<SlideItem>.from(_slides);
      _slides[slideIdx] = update(_slides[slideIdx]);
    });
    widget.onSlidesChanged?.call(_slides);
  }

  void _addBlock(int slideIdx, SlideBlockType type) {
    final defaults = defaultBlockContentFor(type);
    final newBlock = applyBannerDefaults(
      SlideBlock(
        id: 'b_${DateTime.now().microsecondsSinceEpoch}',
        type: type,
        content: defaults.content,
        extra: defaults.extra,
      ),
    );
    _updateSlide(
      slideIdx,
      (slide) => slide.copyWith(blocks: [...slide.blocks, newBlock]),
    );
  }

  Future<void> _editBlockAt(int slideIdx, int blockIdx) async {
    final block = _slides[slideIdx].blocks[blockIdx];

    final SlideBlock? updated;
    if (block.type == SlideBlockType.columns) {
      updated = await Navigator.push<SlideBlock>(
        context,
        MaterialPageRoute(
          builder: (_) => ColumnsBlockEditorScreen(block: block),
        ),
      );
    } else {
      if (!mounted) return;
      updated = await showSlideBlockEditorDialog(context, block);
    }
    if (updated == null || !mounted) return;

    _updateSlide(slideIdx, (slide) {
      final updatedBlocks = List<SlideBlock>.from(slide.blocks);
      updatedBlocks[blockIdx] = updated!;
      return slide.copyWith(blocks: updatedBlocks);
    });
  }

  void _deleteBlockAt(int slideIdx, int blockIdx) {
    _updateSlide(slideIdx, (slide) {
      final updatedBlocks = List<SlideBlock>.from(slide.blocks)
        ..removeAt(blockIdx);
      return slide.copyWith(blocks: updatedBlocks);
    });
  }

  void _reorderBlocks(int slideIdx, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    _updateSlide(slideIdx, (slide) {
      final updatedBlocks = List<SlideBlock>.from(slide.blocks);
      final moved = updatedBlocks.removeAt(oldIndex);
      updatedBlocks.insert(newIndex, moved);
      return slide.copyWith(blocks: updatedBlocks);
    });
  }

  Future<void> _loadProgress() async {
    final prog = await SlideCacheService.instance.getProgress(widget.deck.id);
    setState(() {
      _progress = prog;
      _isLoadingProgress = false;
      _startTimer();
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsOnCurrentSlide = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      _secondsOnCurrentSlide++;
    });
  }

  void _saveCurrentSlideTime() {
    if (_secondsOnCurrentSlide <= 0) return;

    final updatedTime = Map<int, int>.from(_progress.timeSpentPerSlide);
    updatedTime[_currentSlideIndex] =
        (updatedTime[_currentSlideIndex] ?? 0) + _secondsOnCurrentSlide;

    final updatedCompleted = Set<int>.from(_progress.completedSlides)
      ..add(_currentSlideIndex);

    _progress = SlideProgress(
      deckId: _progress.deckId,
      timeSpentPerSlide: updatedTime,
      completedSlides: updatedCompleted,
      bookmarkedSlides: _progress.bookmarkedSlides,
      quizAnswers: _progress.quizAnswers,
      slideDrawings: _progress.slideDrawings,
      lastViewedSlideIndex: _currentSlideIndex,
      lastUpdated: DateTime.now(),
    );

    SlideCacheService.instance.saveProgress(_progress);
  }

  @override
  void dispose() {
    _saveCurrentSlideTime();
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    _saveCurrentSlideTime();
    setState(() {
      _currentSlideIndex = index;
      _isTransparentDrawingActive = false;
      _isFullWhiteboardActive = false;
    });
    _startTimer();
  }

  void _toggleBookmark() {
    setState(() {
      final updatedBookmarks = Set<int>.from(_progress.bookmarkedSlides);
      if (updatedBookmarks.contains(_currentSlideIndex)) {
        updatedBookmarks.remove(_currentSlideIndex);
      } else {
        updatedBookmarks.add(_currentSlideIndex);
      }

      _progress = SlideProgress(
        deckId: _progress.deckId,
        timeSpentPerSlide: _progress.timeSpentPerSlide,
        completedSlides: _progress.completedSlides,
        bookmarkedSlides: updatedBookmarks,
        quizAnswers: _progress.quizAnswers,
        slideDrawings: _progress.slideDrawings,
        lastViewedSlideIndex: _currentSlideIndex,
        lastUpdated: DateTime.now(),
      );
    });

    SlideCacheService.instance.saveProgress(_progress);
  }

  void _recordQuizAnswer(int slideIndex, int optionIndex) {
    setState(() {
      final updatedAnswers = Map<int, int>.from(_progress.quizAnswers);
      updatedAnswers[slideIndex] = optionIndex;

      _progress = SlideProgress(
        deckId: _progress.deckId,
        timeSpentPerSlide: _progress.timeSpentPerSlide,
        completedSlides: _progress.completedSlides,
        bookmarkedSlides: _progress.bookmarkedSlides,
        quizAnswers: updatedAnswers,
        slideDrawings: _progress.slideDrawings,
        lastViewedSlideIndex: _currentSlideIndex,
        lastUpdated: DateTime.now(),
      );
    });

    SlideCacheService.instance.saveProgress(_progress);
  }

  BoxDecoration _getThemeDecoration(String themeName, bool isDark) {
    switch (themeName) {
      case 'jyamitiCosmos':
      case 'jyamitiBg':
        return const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F2B52), Color(0xFF071B36)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        );
      case 'midnightNeon':
        return const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        );
      case 'emeraldSlate':
        return const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF064E3B), Color(0xFF0F172A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        );
      case 'sunsetViolet':
        return const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2E1065), Color(0xFF0F172A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        );
      case 'cleanLight':
        return const BoxDecoration(color: Color(0xFFF8FAFC));
      case 'darkGlass':
      default:
        return BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFFCFDFE),
        );
    }
  }

  /// Resolves a slide's actual background: the named-theme decoration
  /// (existing behavior, and still the default -- `backgroundType ==
  /// SlideBackgroundType.theme`) unless the slide overrides it with its
  /// own solid color, gradient, or image (see SlideItem's own doc
  /// comments). Falls back to the theme decoration if an override field
  /// that's actually needed is missing (e.g. `image` picked but no URL
  /// set yet), rather than rendering nothing.
  BoxDecoration _getSlideDecoration(SlideItem slide, bool isDark) {
    switch (slide.backgroundType) {
      case SlideBackgroundType.solidColor:
        final color = parseHexColor(slide.backgroundColor);
        if (color != null) return BoxDecoration(color: color);
        break;
      case SlideBackgroundType.gradient:
        final c1 = parseHexColor(slide.backgroundColor);
        final c2 = parseHexColor(slide.backgroundColor2);
        if (c1 != null && c2 != null) {
          return BoxDecoration(
            gradient: LinearGradient(
              colors: [c1, c2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          );
        }
        break;
      case SlideBackgroundType.image:
        final url = slide.backgroundImageUrl;
        if (url != null && url.trim().isNotEmpty) {
          return BoxDecoration(
            image: DecorationImage(
              image: NetworkImage(url),
              fit: BoxFit.cover,
            ),
          );
        }
        break;
      case SlideBackgroundType.theme:
        break;
    }
    return _getThemeDecoration(slide.theme, isDark);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    if (_isLoadingProgress || _slides.isEmpty) {
      return const Scaffold(body: Center(child: JyamitiLoader()));
    }

    final totalSlides = _slides.length;
    final activeSlide = _slides[_currentSlideIndex];
    final isBookmarked = _progress.bookmarkedSlides.contains(
      _currentSlideIndex,
    );

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Slide Main Body PageView
            Column(
              children: [
                // Top Custom Header Navigation Bar
                _buildHeaderBar(context, isDark, totalSlides, isBookmarked),

                // Slide Progress Indicator Line
                LinearProgressIndicator(
                  value: (_currentSlideIndex + 1) / totalSlides,
                  backgroundColor: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF6366F1),
                  ),
                  minHeight: 3,
                ),

                // Slide Content View
                Expanded(
                  child: Container(
                    decoration: _getSlideDecoration(activeSlide, isDark),
                    child: PageView.builder(
                      controller: _pageController,
                      onPageChanged: _onPageChanged,
                      itemCount: totalSlides,
                      itemBuilder: (context, idx) {
                        final slide = _slides[idx];
                        return _buildSlideContent(context, idx, slide, isDark);
                      },
                    ),
                  ),
                ),

                // Bottom Floating Control Bar
                _buildBottomControlBar(context, isDark, totalSlides),
              ],
            ),

            // 1. Transparent Drawing Overlay directly on top of Slide Content
            if (_isTransparentDrawingActive)
              Positioned.fill(
                child: WritingPadWidget(
                  isTransparentBg: true,
                  isFullScreen: true,
                  onClose: () =>
                      setState(() => _isTransparentDrawingActive = false),
                ),
              ),

            // 2. Full Standalone Opaque Whiteboard Scratchpad
            if (_isFullWhiteboardActive)
              Positioned.fill(
                child: Container(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFFCFDFE),
                  child: WritingPadWidget(
                    isTransparentBg: false,
                    isFullScreen: true,
                    onClose: () =>
                        setState(() => _isFullWhiteboardActive = false),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBar(
    BuildContext context,
    bool isDark,
    int totalSlides,
    bool isBookmarked,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: isDark ? const Color(0xFF0F172A) : Colors.white,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.deck.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${widget.deck.courseName} • Slide ${_currentSlideIndex + 1} of $totalSlides',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),

          // Offline Indicator Chip
          if (_isOfflineActive)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Color(0xFF10B981).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Color(0xFF10B981), width: 1),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.offline_pin_rounded,
                    size: 14,
                    color: Color(0xFF10B981),
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Offline Mode',
                    style: TextStyle(
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),

          // Bookmark Button
          IconButton(
            icon: Icon(
              isBookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              color: isBookmarked ? const Color(0xFFF59E0B) : context.textColor,
            ),
            tooltip: isBookmarked ? 'Bookmarked' : 'Bookmark Slide',
            onPressed: _toggleBookmark,
          ),

          // 1. Draw directly on Slide button (Transparent Overlay)
          IconButton(
            icon: Icon(
              _isTransparentDrawingActive
                  ? Icons.edit_off_rounded
                  : Icons.gesture_rounded,
              color: _isTransparentDrawingActive
                  ? const Color(0xFF6366F1)
                  : context.textColor,
            ),
            tooltip: 'Draw directly on Slide (Transparent)',
            onPressed: () {
              setState(() {
                _isTransparentDrawingActive = !_isTransparentDrawingActive;
                _isFullWhiteboardActive = false;
              });
            },
          ),

          // 2. Open Full Whiteboard button (Opaque Scratchpad)
          IconButton(
            icon: Icon(
              _isFullWhiteboardActive
                  ? Icons.tab_unselected_rounded
                  : Icons.draw_rounded,
              color: _isFullWhiteboardActive
                  ? const Color(0xFF0EA5E9)
                  : context.textColor,
            ),
            tooltip: 'Open Full Whiteboard Scratchpad',
            onPressed: () {
              setState(() {
                _isFullWhiteboardActive = !_isFullWhiteboardActive;
                _isTransparentDrawingActive = false;
              });
            },
          ),

          // Edit Mode toggle -- only ever shown when this screen was
          // opened as an editable preview (see widget.editable's doc
          // comment); a real student never sees this button at all.
          if (widget.editable)
            IconButton(
              icon: Icon(
                _editModeOn ? Icons.edit_rounded : Icons.edit_outlined,
                color: _editModeOn ? const Color(0xFF6366F1) : context.textColor,
              ),
              tooltip: _editModeOn
                  ? 'Exit Edit Mode'
                  : 'Edit Mode -- add/reorder/edit/delete blocks here',
              onPressed: () => setState(() => _editModeOn = !_editModeOn),
            ),
        ],
      ),
    );
  }

  Widget _buildSlideContent(
    BuildContext context,
    int slideIdx,
    SlideItem slide,
    bool isDark,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Slide Header Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'SLIDE ${slide.slideIndex + 1}',
                  style: const TextStyle(
                    color: Color(0xFF818CF8),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Modular Slide Blocks -- the plain read-only mapping
              // (unchanged from before edit mode existed) unless edit
              // mode is actually on, in which case each block gets a
              // reorder handle + edit/delete controls, plus an Add
              // Block bar underneath, mirroring AdminSlideCmsScreen's
              // own block-list editor.
              if (_editModeOn)
                ..._buildEditableBlocks(context, slideIdx, slide, isDark)
              else
                ...slide.blocks.map(
                  (block) => SlideBlockRenderer(block: block, isDark: isDark),
                ),

              // Embedded Interactive Quiz Card (If Present)
              if (slide.quiz != null) ...[
                const SizedBox(height: 24),
                _buildEmbeddedQuizCard(
                  context,
                  slide.slideIndex,
                  slide.quiz!,
                  isDark,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The edit-mode block list: drag-to-reorder (an explicit handle,
  /// same reasoning as AdminSlideCmsScreen's own list -- each block
  /// already has edit/delete tap targets a default long-press-anywhere
  /// handle would fight with), plus an Add Block bar. Returns a list
  /// (not a single widget) so callers can splice it into a larger
  /// Column's children via the spread operator, same as the plain
  /// block-mapping it replaces when edit mode is on.
  List<Widget> _buildEditableBlocks(
    BuildContext context,
    int slideIdx,
    SlideItem slide,
    bool isDark,
  ) {
    return [
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: slide.blocks.length,
        onReorder: (oldIndex, newIndex) =>
            _reorderBlocks(slideIdx, oldIndex, newIndex),
        itemBuilder: (context, blockIdx) {
          final block = slide.blocks[blockIdx];
          return Container(
            key: ValueKey(block.id),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                width: 1.4,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ReorderableDragStartListener(
                      index: blockIdx,
                      child: const Padding(
                        padding: EdgeInsets.only(right: 8.0),
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: 18,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(
                        block.type.name.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                        ),
                      ),
                      backgroundColor: const Color(0xFF6366F1),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      tooltip: 'Edit block',
                      onPressed: () => _editBlockAt(slideIdx, blockIdx),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_rounded,
                        size: 16,
                        color: Colors.red,
                      ),
                      tooltip: 'Delete block',
                      onPressed: () => _deleteBlockAt(slideIdx, blockIdx),
                    ),
                  ],
                ),
                SlideBlockRenderer(block: block, isDark: isDark),
              ],
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: SlideBlockType.values.map((type) {
            return Padding(
              padding: const EdgeInsets.only(right: 6.0),
              child: ActionChip(
                avatar: Icon(iconForSlideBlockType(type), size: 14),
                label: Text(
                  type.name.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () => _addBlock(slideIdx, type),
              ),
            );
          }).toList(),
        ),
      ),
    ];
  }

  Widget _buildEmbeddedQuizCard(
    BuildContext context,
    int slideIndex,
    SlideQuiz quiz,
    bool isDark,
  ) {
    final selectedIdx = _progress.quizAnswers[slideIndex];
    final bool hasAnswered = selectedIdx != null;
    final bool isCorrect = hasAnswered && selectedIdx == quiz.correctIndex;

    return Container(
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasAnswered
              ? (isCorrect ? Color(0xFF10B981) : Colors.redAccent)
              : const Color(0xFF6366F1).withOpacity(0.4),
          width: 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.quiz_rounded,
                color: Color(0xFF6366F1),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Interactive Knowledge Check',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF6366F1),
                ),
              ),
              const Spacer(),
              if (hasAnswered)
                Chip(
                  avatar: Icon(
                    isCorrect
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                  label: Text(
                    isCorrect ? 'Correct!' : 'Incorrect',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  backgroundColor: isCorrect
                      ? Color(0xFF10B981)
                      : Colors.redAccent,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            quiz.question,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),

          // Options List
          ...List.generate(quiz.options.length, (optIdx) {
            final optionText = quiz.options[optIdx];
            final bool isThisSelected = selectedIdx == optIdx;
            final bool isThisCorrect = optIdx == quiz.correctIndex;

            Color optionBg = isDark
                ? const Color(0xFF0F172A)
                : const Color(0xFFF1F5F9);
            Color borderCol = Colors.transparent;

            if (hasAnswered) {
              if (isThisCorrect) {
                optionBg = Color(0xFF10B981).withOpacity(0.18);
                borderCol = Color(0xFF10B981);
              } else if (isThisSelected) {
                optionBg = Colors.redAccent.withOpacity(0.18);
                borderCol = Colors.redAccent;
              }
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: InkWell(
                onTap: hasAnswered
                    ? null
                    : () => _recordQuizAnswer(slideIndex, optIdx),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: optionBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: borderCol != Colors.transparent
                          ? borderCol
                          : (isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFCBD5E1)),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: hasAnswered
                            ? (isThisCorrect
                                  ? Color(0xFF10B981)
                                  : (isThisSelected
                                        ? Colors.redAccent
                                        : Colors.grey.shade700))
                            : const Color(0xFF6366F1).withOpacity(0.2),
                        child: Text(
                          String.fromCharCode(65 + optIdx),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          optionText,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          // Explanation Banner
          if (hasAnswered && quiz.explanation.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF6366F1).withOpacity(0.3),
                ),
              ),
              child: Text(
                '💡 Explanation: ${quiz.explanation}',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: isDark
                      ? const Color(0xFFCBD5E1)
                      : const Color(0xFF334155),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomControlBar(
    BuildContext context,
    bool isDark,
    int totalSlides,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: isDark ? const Color(0xFF0F172A) : Colors.white,
      child: Row(
        children: [
          ElevatedButton.icon(
            onPressed: _currentSlideIndex > 0
                ? () {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                : null,
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Previous'),
          ),
          const Spacer(),
          Text(
            '${_currentSlideIndex + 1} / $totalSlides',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _currentSlideIndex < totalSlides - 1
                ? () {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                : null,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: const Text('Next'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
