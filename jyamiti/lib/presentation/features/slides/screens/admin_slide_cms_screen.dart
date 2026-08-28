import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../domain/models/slide_deck_models.dart';
import '../../../../domain/models/slide_json_helper.dart';
import '../../../../providers/theme_provider.dart';
import '../../../../services/slide_cache_service.dart';
import '../widgets/columns_block_editor_screen.dart';
import '../widgets/slide_block_defaults.dart';
import '../widgets/slide_block_editor_dialog.dart';
import '../widgets/slide_block_renderer.dart';
import '../widgets/slide_color_utils.dart';
import '../widgets/slide_json_import_dialog.dart';
import 'student_slide_viewer_screen.dart';

class AdminSlideCmsScreen extends StatefulWidget {
  final SlideDeck? initialDeck;

  const AdminSlideCmsScreen({super.key, this.initialDeck});

  @override
  State<AdminSlideCmsScreen> createState() => _AdminSlideCmsScreenState();
}

class _AdminSlideCmsScreenState extends State<AdminSlideCmsScreen> {
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _courseController;
  late List<SlideItem> _slides;
  int _activeSlideIndex = 0;
  bool _isSaving = false;

  final List<String> _themeOptions = [
    'darkGlass',
    'jyamitiCosmos',
    'midnightNeon',
    'emeraldSlate',
    'sunsetViolet',
    'cleanLight',
  ];

  @override
  void initState() {
    super.initState();
    final deck = widget.initialDeck;
    _titleController = TextEditingController(
      text: deck?.title ?? 'New Interactive Course Deck',
    );
    _descController = TextEditingController(
      text: deck?.description ?? 'Course slide deck description...',
    );
    _courseController = TextEditingController(
      text: deck?.courseName ?? 'Mathematics',
    );

    if (deck != null && deck.slides.isNotEmpty) {
      _slides = List<SlideItem>.from(deck.slides);
    } else {
      _slides = [
        SlideItem(
          id: 'slide_1',
          slideIndex: 0,
          title: 'Introduction & Overview',
          theme: 'darkGlass',
          blocks: [
            SlideBlock(
              id: 'b1',
              type: SlideBlockType.heading,
              content: 'Welcome to this Course Unit',
            ),
            SlideBlock(
              id: 'b2',
              type: SlideBlockType.paragraph,
              content: 'Add your lesson introduction text here for students.',
            ),
          ],
        ),
      ];
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _courseController.dispose();
    super.dispose();
  }

  void _reindexSlides() {
    // .copyWith rather than reconstructing SlideItem field-by-field --
    // the latter used to silently drop every field added after this
    // method was first written (background type/color/gradient/image,
    // contentVerticalAlign) every time a slide got reindexed, i.e. on
    // every delete/reorder/import. copyWith carries whatever isn't
    // explicitly overridden here forward automatically, so a future
    // field addition can't reintroduce the same bug.
    for (int i = 0; i < _slides.length; i++) {
      _slides[i] = _slides[i].copyWith(
        id: _slides[i].id.isNotEmpty
            ? _slides[i].id
            : 'slide_${DateTime.now().millisecondsSinceEpoch}_$i',
        slideIndex: i,
      );
    }
  }

  void _addNewSlide() {
    setState(() {
      final newIndex = _slides.length;
      _slides.add(
        SlideItem(
          id: 'slide_${DateTime.now().millisecondsSinceEpoch}',
          slideIndex: newIndex,
          title: 'Slide ${newIndex + 1}',
          theme: 'darkGlass',
          blocks: [
            SlideBlock(
              id: 'b_${DateTime.now().millisecondsSinceEpoch}',
              type: SlideBlockType.heading,
              content: 'New Slide Title',
            ),
            SlideBlock(
              id: 'b_${DateTime.now().millisecondsSinceEpoch + 1}',
              type: SlideBlockType.paragraph,
              content: 'Enter slide content details...',
            ),
          ],
        ),
      );
      _activeSlideIndex = newIndex;
    });
  }

  void _deleteActiveSlide() {
    if (_slides.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Slide deck must contain at least 1 slide.'),
        ),
      );
      return;
    }
    setState(() {
      _slides.removeAt(_activeSlideIndex);
      if (_activeSlideIndex >= _slides.length) {
        _activeSlideIndex = _slides.length - 1;
      }
      _reindexSlides();
    });
  }

  Future<void> _importFromJson() async {
    final result = await SlideJsonImportDialog.show(
      context: context,
      currentSlideCount: _slides.length,
      activeSlideIndex: _activeSlideIndex,
    );

    if (result == null || result.slides.isEmpty) return;

    setState(() {
      if (result.updateDeckMetadata) {
        if (result.deckTitle != null && result.deckTitle!.trim().isNotEmpty) {
          _titleController.text = result.deckTitle!.trim();
        }
        if (result.deckDescription != null &&
            result.deckDescription!.trim().isNotEmpty) {
          _descController.text = result.deckDescription!.trim();
        }
        if (result.courseName != null && result.courseName!.trim().isNotEmpty) {
          _courseController.text = result.courseName!.trim();
        }
      }

      switch (result.placement) {
        case SlideImportPlacement.appendToEnd:
          final newIdx = _slides.length;
          _slides.addAll(result.slides);
          _reindexSlides();
          _activeSlideIndex = newIdx.clamp(0, _slides.length - 1);
          break;

        case SlideImportPlacement.insertAfterActive:
          final insertIdx = (_activeSlideIndex + 1).clamp(0, _slides.length);
          _slides.insertAll(insertIdx, result.slides);
          _reindexSlides();
          _activeSlideIndex = insertIdx.clamp(0, _slides.length - 1);
          break;

        case SlideImportPlacement.replaceActive:
          if (_slides.isNotEmpty) {
            _slides.removeAt(_activeSlideIndex);
            _slides.insertAll(_activeSlideIndex, result.slides);
          } else {
            _slides.addAll(result.slides);
          }
          _reindexSlides();
          _activeSlideIndex = _activeSlideIndex.clamp(0, _slides.length - 1);
          break;

        case SlideImportPlacement.replaceAll:
          _slides = List<SlideItem>.from(result.slides);
          _reindexSlides();
          _activeSlideIndex = 0;
          break;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Successfully imported ${result.slides.length} slide(s)!',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _exportCurrentSlideJson() async {
    if (_slides.isEmpty || _activeSlideIndex >= _slides.length) return;
    final slide = _slides[_activeSlideIndex];
    final jsonStr = SlideJsonHelper.exportSlideJson(slide);
    await Clipboard.setData(ClipboardData(text: jsonStr));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.copy_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Slide "${slide.title}" JSON copied to clipboard!',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF6366F1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _exportFullDeckJson() async {
    final currentDeck = SlideDeck(
      id:
          widget.initialDeck?.id ??
          'deck_${DateTime.now().millisecondsSinceEpoch}',
      courseId: widget.initialDeck?.courseId ?? 'course_101',
      courseName: _courseController.text.trim(),
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      slides: _slides,
      createdAt: widget.initialDeck?.createdAt ?? DateTime.now(),
    );

    final jsonStr = SlideJsonHelper.exportDeckJson(currentDeck);
    await Clipboard.setData(ClipboardData(text: jsonStr));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.data_object_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Full Course Slide Deck JSON copied to clipboard!',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Color(0xFF0EA5E9),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _saveDeck() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a deck title.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final deck = SlideDeck(
      id:
          widget.initialDeck?.id ??
          'deck_${DateTime.now().millisecondsSinceEpoch}',
      courseId: widget.initialDeck?.courseId ?? 'course_101',
      courseName: _courseController.text.trim(),
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      slides: _slides,
      createdAt: widget.initialDeck?.createdAt ?? DateTime.now(),
      isPublished: true,
      isDownloadedOffline: true,
    );

    await SlideCacheService.instance.saveDeck(deck);

    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Slide Deck Saved Successfully!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  void _addBlockToActiveSlide(SlideBlockType type) {
    final defaults = defaultBlockContentFor(type);

    setState(() {
      final currentSlide = _slides[_activeSlideIndex];
      final updatedBlocks = List<SlideBlock>.from(currentSlide.blocks)
        ..add(
          applyBannerDefaults(
            SlideBlock(
              id: 'b_${DateTime.now().millisecondsSinceEpoch}',
              type: type,
              content: defaults.content,
              extra: defaults.extra,
            ),
          ),
        );

      _slides[_activeSlideIndex] = currentSlide.copyWith(blocks: updatedBlocks);
    });
  }

  /// Edits one block on the active slide. Columns blocks get their own
  /// dedicated full-screen editor (nested content, not a simple content/
  /// style form); everything else uses the shared block-edit dialog --
  /// see slide_block_editor_dialog.dart's doc comment for why that's a
  /// standalone function rather than a method here.
  Future<void> _editBlock(int blockIndex) async {
    final block = _slides[_activeSlideIndex].blocks[blockIndex];

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

    setState(() {
      final currentSlide = _slides[_activeSlideIndex];
      final updatedBlocks = List<SlideBlock>.from(currentSlide.blocks);
      updatedBlocks[blockIndex] = updated!;
      _slides[_activeSlideIndex] =
          currentSlide.copyWith(blocks: updatedBlocks);
    });
  }

  void _configureQuiz() {
    final currentQuiz = _slides[_activeSlideIndex].quiz;
    final qCtrl = TextEditingController(text: currentQuiz?.question ?? '');
    final opt0 = TextEditingController(
      text: currentQuiz?.options.elementAtOrNull(0) ?? 'Option A',
    );
    final opt1 = TextEditingController(
      text: currentQuiz?.options.elementAtOrNull(1) ?? 'Option B',
    );
    final opt2 = TextEditingController(
      text: currentQuiz?.options.elementAtOrNull(2) ?? 'Option C',
    );
    final opt3 = TextEditingController(
      text: currentQuiz?.options.elementAtOrNull(3) ?? 'Option D',
    );
    final expCtrl = TextEditingController(text: currentQuiz?.explanation ?? '');
    int correctIdx = currentQuiz?.correctIndex ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            title: const Text('Embedded Slide Quiz Builder'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: qCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Question Text',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: opt0,
                    decoration: const InputDecoration(labelText: 'Option 1'),
                  ),
                  TextField(
                    controller: opt1,
                    decoration: const InputDecoration(labelText: 'Option 2'),
                  ),
                  TextField(
                    controller: opt2,
                    decoration: const InputDecoration(labelText: 'Option 3'),
                  ),
                  TextField(
                    controller: opt3,
                    decoration: const InputDecoration(labelText: 'Option 4'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    value: correctIdx,
                    decoration: const InputDecoration(
                      labelText: 'Correct Option Index',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 0,
                        child: Text('Option 1 is Correct'),
                      ),
                      DropdownMenuItem(
                        value: 1,
                        child: Text('Option 2 is Correct'),
                      ),
                      DropdownMenuItem(
                        value: 2,
                        child: Text('Option 3 is Correct'),
                      ),
                      DropdownMenuItem(
                        value: 3,
                        child: Text('Option 4 is Correct'),
                      ),
                    ],
                    onChanged: (val) =>
                        setDlgState(() => correctIdx = val ?? 0),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: expCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Explanation for Students',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (currentQuiz != null)
                TextButton(
                  onPressed: () {
                    setState(() {
                      final s = _slides[_activeSlideIndex];
                      _slides[_activeSlideIndex] = s.copyWith(clearQuiz: true);
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text(
                    'Remove Quiz',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    final s = _slides[_activeSlideIndex];
                    _slides[_activeSlideIndex] = s.copyWith(
                      quiz: SlideQuiz(
                        question: qCtrl.text,
                        options: [opt0.text, opt1.text, opt2.text, opt3.text],
                        correctIndex: correctIdx,
                        explanation: expCtrl.text,
                      ),
                    );
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Save Quiz'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Custom per-slide background -- solid color, two-color gradient, or
  /// image, as an alternative to the fixed named-theme palettes (see
  /// SlideItem.backgroundType's doc comment). The Theme Dropdown next to
  /// the button that opens this stays the quick path for the common case;
  /// this is for when a tutor wants a specific look a named theme doesn't
  /// cover.
  void _openBackgroundEditor() {
    final activeSlide = _slides[_activeSlideIndex];
    SlideBackgroundType selectedType = activeSlide.backgroundType;
    String? color1 = activeSlide.backgroundColor;
    String? color2 = activeSlide.backgroundColor2;
    final imageCtrl =
        TextEditingController(text: activeSlide.backgroundImageUrl ?? '');
    String contentVerticalAlign = activeSlide.contentVerticalAlign;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Slide Background & Layout'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Content Position -- where the WHOLE content column
                // (header badge + blocks + quiz) sits vertically on the
                // slide. This is what actually centers a lone banner (or
                // any small amount of content) in the middle of an
                // otherwise-blank slide -- a block's own
                // horizontalAlign/verticalAlign only position that
                // block's content within its own box, not where the
                // block sits on the slide as a whole.
                const Text(
                  'Content Position',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'top', label: Text('Top')),
                    ButtonSegment(value: 'center', label: Text('Center')),
                    ButtonSegment(value: 'bottom', label: Text('Bottom')),
                  ],
                  selected: {contentVerticalAlign},
                  onSelectionChanged: (sel) =>
                      setDialogState(() => contentVerticalAlign = sel.first),
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 4),
                const Text(
                  'Background',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                SegmentedButton<SlideBackgroundType>(
                  segments: const [
                    ButtonSegment(
                      value: SlideBackgroundType.theme,
                      label: Text('Theme'),
                    ),
                    ButtonSegment(
                      value: SlideBackgroundType.solidColor,
                      label: Text('Solid'),
                    ),
                    ButtonSegment(
                      value: SlideBackgroundType.gradient,
                      label: Text('Gradient'),
                    ),
                    ButtonSegment(
                      value: SlideBackgroundType.image,
                      label: Text('Image'),
                    ),
                  ],
                  selected: {selectedType},
                  onSelectionChanged: (sel) =>
                      setDialogState(() => selectedType = sel.first),
                ),
                const SizedBox(height: 16),
                if (selectedType == SlideBackgroundType.theme)
                  Text(
                    'Uses the "${activeSlide.theme}" theme selected in the '
                    'dropdown next to this button.',
                    style: const TextStyle(color: Colors.grey, fontSize: 12.5),
                  ),
                if (selectedType == SlideBackgroundType.solidColor)
                  SlideColorPickerField(
                    label: 'Background Color',
                    initialHex: color1,
                    onChanged: (val) => color1 = val,
                  ),
                if (selectedType == SlideBackgroundType.gradient) ...[
                  SlideColorPickerField(
                    label: 'Gradient Start',
                    initialHex: color1,
                    onChanged: (val) => color1 = val,
                  ),
                  const SizedBox(height: 16),
                  SlideColorPickerField(
                    label: 'Gradient End',
                    initialHex: color2,
                    onChanged: (val) => color2 = val,
                  ),
                ],
                if (selectedType == SlideBackgroundType.image)
                  TextField(
                    controller: imageCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Image URL',
                      border: OutlineInputBorder(),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _slides[_activeSlideIndex] = activeSlide.copyWith(
                    backgroundType: selectedType,
                    backgroundColor: color1,
                    clearBackgroundColor: color1 == null,
                    backgroundColor2: color2,
                    clearBackgroundColor2: color2 == null,
                    backgroundImageUrl: imageCtrl.text.trim().isNotEmpty
                        ? imageCtrl.text.trim()
                        : null,
                    clearBackgroundImageUrl: imageCtrl.text.trim().isEmpty,
                    contentVerticalAlign: contentVerticalAlign,
                  );
                });
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final activeSlide = _slides[_activeSlideIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Admin Slide Deck CMS',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: _importFromJson,
            icon: const Icon(Icons.file_download_rounded, size: 16),
            label: const Text('Import JSON', style: TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1),
              side: BorderSide(
                color: isDark
                    ? const Color(0xFF818CF8).withOpacity(0.5)
                    : const Color(0xFF6366F1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 6),
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share_rounded, size: 20),
            tooltip: 'Export & Share JSON',
            onSelected: (val) {
              if (val == 'export_slide') _exportCurrentSlideJson();
              if (val == 'export_deck') _exportFullDeckJson();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'export_slide',
                child: Row(
                  children: [
                    Icon(
                      Icons.content_copy_rounded,
                      size: 16,
                      color: Color(0xFF6366F1),
                    ),
                    SizedBox(width: 8),
                    Text('Copy Active Slide JSON'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export_deck',
                child: Row(
                  children: [
                    Icon(
                      Icons.data_object_rounded,
                      size: 16,
                      color: Color(0xFF0EA5E9),
                    ),
                    SizedBox(width: 8),
                    Text('Copy Full Course Deck JSON'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.remove_red_eye_rounded),
            tooltip: 'Live Student Preview',
            onPressed: () {
              final tempDeck = SlideDeck(
                id: 'preview_deck',
                courseId: 'c_preview',
                courseName: _courseController.text,
                title: _titleController.text,
                description: _descController.text,
                slides: _slides,
                createdAt: DateTime.now(),
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudentSlideViewerScreen(
                    deck: tempDeck,
                    editable: true,
                    // Live callback -- the preview screen's own Edit
                    // Mode (add/reorder/edit/delete blocks directly on
                    // the styled slide) reports every change back
                    // immediately, so this screen's block-list view
                    // reflects it as soon as you return to it, exactly
                    // as if the edit had been made here directly.
                    onSlidesChanged: (updated) =>
                        setState(() => _slides = updated),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveDeck,
            icon: _isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: JyamitiLoader(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: const Text('Save Deck'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          // Left Sidebar: Deck Settings & Slide Thumbnails
          Container(
            width: 280,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'Deck Title',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _courseController,
                        decoration: const InputDecoration(
                          labelText: 'Course Name',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 4.0,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'SLIDES (${_slides.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(
                          Icons.file_download_outlined,
                          color: Color(0xFF818CF8),
                          size: 20,
                        ),
                        onPressed: _importFromJson,
                        tooltip: 'Import Slide(s) from JSON',
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.add_circle_outline_rounded,
                          color: Color(0xFF6366F1),
                          size: 20,
                        ),
                        onPressed: _addNewSlide,
                        tooltip: 'Add Blank Slide',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  // Drag-to-reorder -- was a plain ListView.builder, which
                  // gave no way to change slide order except re-importing
                  // JSON from scratch.
                  child: ReorderableListView.builder(
                    itemCount: _slides.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final moved = _slides.removeAt(oldIndex);
                        _slides.insert(newIndex, moved);
                        _reindexSlides();
                        _activeSlideIndex = newIndex;
                      });
                    },
                    itemBuilder: (context, idx) {
                      final slide = _slides[idx];
                      final isSelected = idx == _activeSlideIndex;
                      return ListTile(
                        key: ValueKey(slide.id),
                        selected: isSelected,
                        selectedTileColor: const Color(
                          0xFF6366F1,
                        ).withOpacity(0.15),
                        leading: CircleAvatar(
                          radius: 12,
                          backgroundColor: isSelected
                              ? const Color(0xFF6366F1)
                              : Colors.grey.shade700,
                          child: Text(
                            '${idx + 1}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        title: Text(
                          slide.title,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${slide.blocks.length} blocks • ${slide.theme}',
                          style: const TextStyle(fontSize: 10),
                        ),
                        onTap: () => setState(() => _activeSlideIndex = idx),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Main Center Editor Panel
          Expanded(
            child: Column(
              children: [
                // Slide Toolbar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF1F5F9),
                  child: Row(
                    children: [
                      Text(
                        'Editing Slide ${_activeSlideIndex + 1}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 16),
                      // Slide Title TextField
                      Expanded(
                        child: TextField(
                          controller: TextEditingController(
                            text: activeSlide.title,
                          ),
                          onChanged: (val) {
                            _slides[_activeSlideIndex] =
                                activeSlide.copyWith(title: val);
                          },
                          decoration: const InputDecoration(
                            hintText: 'Slide Title',
                            isDense: true,
                            border: InputBorder.none,
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),

                      // Theme Dropdown
                      DropdownButton<String>(
                        value: activeSlide.theme,
                        underline: const SizedBox(),
                        items: _themeOptions
                            .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _slides[_activeSlideIndex] = activeSlide.copyWith(
                                theme: val,
                                // Picking a named theme here also switches
                                // backgroundType back to `theme` -- so this
                                // dropdown still "just works" as the quick
                                // path even after a solid/gradient/image
                                // background was set via the Background
                                // button.
                                backgroundType: SlideBackgroundType.theme,
                              );
                            });
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(
                          Icons.wallpaper_rounded,
                          color: Color(0xFF10B981),
                        ),
                        tooltip: 'Custom Background (color / gradient / image)',
                        onPressed: _openBackgroundEditor,
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(
                          Icons.copy_all_rounded,
                          color: Color(0xFF818CF8),
                        ),
                        tooltip: 'Copy Slide JSON',
                        onPressed: _exportCurrentSlideJson,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.quiz_outlined,
                          color: Color(0xFF0EA5E9),
                        ),
                        tooltip: 'Configure Quiz',
                        onPressed: _configureQuiz,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
                        ),
                        tooltip: 'Delete Slide',
                        onPressed: _deleteActiveSlide,
                      ),
                    ],
                  ),
                ),

                // Add Block Bar
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: SlideBlockType.values.map((type) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: ActionChip(
                          avatar: Icon(_getIconForBlock(type), size: 14),
                          label: Text(
                            type.name.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () => _addBlockToActiveSlide(type),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // Blocks List Editor -- drag-to-reorder via an explicit
                // handle (buildDefaultDragHandles: false) rather than
                // making the whole card draggable, since each card
                // already has its own edit/delete tap targets that a
                // default long-press-anywhere drag handle would fight
                // with.
                Expanded(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.all(16.0),
                    itemCount: activeSlide.blocks.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final currentSlide = _slides[_activeSlideIndex];
                        final updatedBlocks =
                            List<SlideBlock>.from(currentSlide.blocks);
                        final moved = updatedBlocks.removeAt(oldIndex);
                        updatedBlocks.insert(newIndex, moved);
                        _slides[_activeSlideIndex] =
                            currentSlide.copyWith(blocks: updatedBlocks);
                      });
                    },
                    itemBuilder: (context, blockIdx) {
                      final block = activeSlide.blocks[blockIdx];
                      return Card(
                        key: ValueKey(block.id),
                        margin: const EdgeInsets.only(bottom: 12),
                        color: isDark ? const Color(0xFF0F172A) : Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
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
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_rounded,
                                      size: 16,
                                    ),
                                    onPressed: () => _editBlock(blockIdx),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_rounded,
                                      size: 16,
                                      color: Colors.red,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        final currentSlide =
                                            _slides[_activeSlideIndex];
                                        final updatedBlocks =
                                            List<SlideBlock>.from(
                                              currentSlide.blocks,
                                            )..removeAt(blockIdx);
                                        _slides[_activeSlideIndex] =
                                            currentSlide.copyWith(
                                                blocks: updatedBlocks);
                                      });
                                    },
                                  ),
                                ],
                              ),
                              SlideBlockRenderer(block: block, isDark: isDark),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForBlock(SlideBlockType type) => iconForSlideBlockType(type);
}
