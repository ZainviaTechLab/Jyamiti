import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../domain/models/slide_deck_models.dart';
import '../../../../providers/theme_provider.dart';
import '../../../../services/slide_cache_service.dart';
import '../../../widgets/writing_pad_widget.dart';
import '../widgets/slide_block_renderer.dart';
import '../widgets/slide_color_utils.dart';

class StudentSlideViewerScreen extends StatefulWidget {
  final SlideDeck deck;
  final int initialSlideIndex;

  const StudentSlideViewerScreen({
    super.key,
    required this.deck,
    this.initialSlideIndex = 0,
  });

  @override
  State<StudentSlideViewerScreen> createState() =>
      _StudentSlideViewerScreenState();
}

class _StudentSlideViewerScreenState extends State<StudentSlideViewerScreen> {
  late PageController _pageController;
  late int _currentSlideIndex;
  late SlideProgress _progress;

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
    _loadProgress();
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
    if (_isLoadingProgress || widget.deck.slides.isEmpty) {
      return const Scaffold(body: Center(child: JyamitiLoader()));
    }

    final totalSlides = widget.deck.slides.length;
    final activeSlide = widget.deck.slides[_currentSlideIndex];
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
                        final slide = widget.deck.slides[idx];
                        return _buildSlideContent(context, slide, isDark);
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
        ],
      ),
    );
  }

  Widget _buildSlideContent(
    BuildContext context,
    SlideItem slide,
    bool isDark,
  ) {
    final Widget contentColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
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

        // Modular Slide Blocks
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
    );

    final Widget constrainedContent = Container(
      constraints: const BoxConstraints(maxWidth: 860),
      child: contentColumn,
    );

    // 'top' (the default -- every existing deck) is the original,
    // unconstrained-height behavior: content just starts below the
    // padding like a normal scrollable document. 'center'/'bottom' are
    // what actually make "a banner centered on an otherwise-blank slide"
    // possible -- a block's own horizontalAlign/verticalAlign (see
    // SlideBlock) only position that block's content within its OWN box,
    // not where the block sits on the slide as a whole. Needs
    // LayoutBuilder to know the viewport's real height before deciding
    // how tall to force the content area to be; still scrolls normally
    // if the content is taller than that (ConstrainedBox's minHeight is
    // a minimum, not a cap).
    if (slide.contentVerticalAlign == 'top') {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(child: constrainedContent),
      );
    }

    final Alignment align = slide.contentVerticalAlign == 'bottom'
        ? Alignment.bottomCenter
        : Alignment.center;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            // -48 accounts for the 24px top+bottom padding above, so the
            // centering is against the actual visible height, not the
            // padding-inclusive one.
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 48).clamp(0, double.infinity),
            ),
            child: Align(alignment: align, child: constrainedContent),
          ),
        );
      },
    );
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
