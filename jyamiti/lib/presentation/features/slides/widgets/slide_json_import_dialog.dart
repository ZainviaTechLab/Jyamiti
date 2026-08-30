import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../domain/models/slide_deck_models.dart';
import '../../../../domain/models/slide_json_helper.dart';
import '../../../../providers/theme_provider.dart';

class SlideJsonImportResult {
  final List<SlideItem> slides;
  final SlideImportPlacement placement;
  final String? deckTitle;
  final String? deckDescription;
  final String? courseName;
  final bool updateDeckMetadata;

  const SlideJsonImportResult({
    required this.slides,
    required this.placement,
    this.deckTitle,
    this.deckDescription,
    this.courseName,
    this.updateDeckMetadata = false,
  });
}

class SlideJsonImportDialog extends StatefulWidget {
  final int currentSlideCount;
  final int activeSlideIndex;

  const SlideJsonImportDialog({
    super.key,
    required this.currentSlideCount,
    required this.activeSlideIndex,
  });

  static Future<SlideJsonImportResult?> show({
    required BuildContext context,
    required int currentSlideCount,
    required int activeSlideIndex,
  }) {
    return showDialog<SlideJsonImportResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SlideJsonImportDialog(
        currentSlideCount: currentSlideCount,
        activeSlideIndex: activeSlideIndex,
      ),
    );
  }

  @override
  State<SlideJsonImportDialog> createState() => _SlideJsonImportDialogState();
}

class _SlideJsonImportDialogState extends State<SlideJsonImportDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _jsonController = TextEditingController();

  SlideImportPlacement _placement = SlideImportPlacement.appendToEnd;
  bool _updateDeckMetadata = true;

  SlideImportParseResult? _parseResult;
  String? _selectedFileName;
  bool _isLoadingFile = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _jsonController.addListener(_onJsonTextChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _jsonController.removeListener(_onJsonTextChanged);
    _jsonController.dispose();
    super.dispose();
  }

  void _onJsonTextChanged() {
    final text = _jsonController.text.trim();
    if (text.isEmpty) {
      setState(() => _parseResult = null);
      return;
    }
    final result = SlideJsonHelper.parseJson(text);
    setState(() => _parseResult = result);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      _jsonController.text = data.text!;
      _onJsonTextChanged();
    }
  }

  void _beautifyJson() {
    if (_jsonController.text.isNotEmpty) {
      final beautified = SlideJsonHelper.beautifyJson(_jsonController.text);
      _jsonController.text = beautified;
    }
  }

  void _loadSample(String sampleJson) {
    _jsonController.text = sampleJson;
    _onJsonTextChanged();
  }

  /// Copies (doesn't load into the editor -- see the button's own doc
  /// comment) the PPTX-to-slide-JSON conversion prompt to the clipboard.
  Future<void> _copyPptxConversionPrompt() async {
    await Clipboard.setData(
      ClipboardData(text: SlideJsonHelper.pptxConversionPrompt),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Conversion prompt copied! Paste it into ChatGPT/Claude/etc. '
          'along with your PPTX content, then paste the JSON it gives '
          'back into the box on the left.',
        ),
        backgroundColor: Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 5),
      ),
    );
  }

  Future<void> _pickJsonFile() async {
    setState(() => _isLoadingFile = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        _selectedFileName = file.name;

        String content = '';
        if (file.bytes != null) {
          content = utf8.decode(file.bytes!);
        }

        if (content.isNotEmpty) {
          _jsonController.text = content;
          _onJsonTextChanged();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading file: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingFile = false);
      }
    }
  }

  void _onConfirmImport() {
    if (_parseResult == null ||
        !_parseResult!.isSuccess ||
        _parseResult!.slides.isEmpty) {
      return;
    }

    final result = SlideJsonImportResult(
      slides: _parseResult!.slides,
      placement: _placement,
      deckTitle: _parseResult!.deckTitle,
      deckDescription: _parseResult!.deckDescription,
      courseName: _parseResult!.courseName,
      updateDeckMetadata:
          _updateDeckMetadata && _parseResult!.deckTitle != null,
    );

    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final size = MediaQuery.of(context).size;
    final dialogWidth = (size.width * 0.85).clamp(550.0, 950.0);
    final dialogHeight = (size.height * 0.88).clamp(550.0, 800.0);

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.data_object_rounded,
                    color: Color(0xFF818CF8),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Import Slide(s) from JSON',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Import a single slide, multiple slides, or a full course deck structure.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Tabs
            Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: const Color(0xFF6366F1),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: isDark
                    ? Colors.grey.shade400
                    : Colors.grey.shade700,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.edit_note_rounded, size: 18),
                    text: 'Paste JSON Text',
                  ),
                  Tab(
                    icon: Icon(Icons.file_upload_outlined, size: 18),
                    text: 'Upload JSON File',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Tab View Body & Live Preview
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left Side: Editor / File Picker
                  Expanded(
                    flex: 6,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // Tab 1: Paste JSON Code Area
                        _buildPasteTab(isDark),
                        // Tab 2: Upload File Area
                        _buildUploadTab(isDark),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Right Side: Live Inspection & Placement Settings
                  Expanded(
                    flex: 5,
                    child: _buildInspectionAndSettingsPanel(isDark),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Footer Actions
            _buildFooter(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildPasteTab(bool isDark) {
    return Column(
      children: [
        // Quick Action Bar for Editor -- horizontally scrollable, since
        // the left panel (flex: 6 of a dialog that clamps as narrow as
        // 550px) isn't wide enough to fit every button on one line once
        // "Copy Conversion Prompt" joined the original 3 -- a plain Row
        // overflowed on the right instead of just scrolling to reach it.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pasteFromClipboard,
                icon: const Icon(Icons.content_paste_rounded, size: 15),
                label: const Text(
                  'Paste Clipboard',
                  style: TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _beautifyJson,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 15),
                label: const Text(
                  'Format / Beautify',
                  style: TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Load Sample Template',
                onSelected: _loadSample,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF6366F1).withOpacity(0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 14,
                        color: Color(0xFF818CF8),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Load Sample',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF818CF8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 16,
                        color: Color(0xFF818CF8),
                      ),
                    ],
                  ),
                ),
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: SlideJsonHelper.sampleSingleSlideJson,
                    child: const Text('Single Slide (Math + Quiz)'),
                  ),
                  PopupMenuItem(
                    value: SlideJsonHelper.sampleMultiSlideJson,
                    child: const Text('Multi-Slide Array (2 Slides)'),
                  ),
                  PopupMenuItem(
                    value: SlideJsonHelper.sampleFullDeckJson,
                    child: const Text('Full Course Slide Deck'),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              // Copies (not loads into the editor -- this is instructions
              // for an external AI tool, not app JSON) a ready-made prompt
              // for converting an existing presentation (PPTX or otherwise)
              // into this exact slide JSON format. Workflow: tap this, paste
              // the prompt plus the PPTX content into ChatGPT/Claude/etc.,
              // then paste ITS json output into the Paste JSON tab here.
              OutlinedButton.icon(
                onPressed: _copyPptxConversionPrompt,
                icon: const Icon(Icons.smart_toy_outlined, size: 15),
                label: const Text(
                  'Copy Conversion Prompt',
                  style: TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: const BorderSide(color: Color(0xFF10B981)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Text Editor Area
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF030712) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF1F2937)
                    : const Color(0xFFCBD5E1),
              ),
            ),
            child: TextField(
              controller: _jsonController,
              maxLines: null,
              expands: true,
              style: TextStyle(
                fontFamily: 'Courier',
                fontSize: 12.5,
                color: isDark
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFF1E293B),
                height: 1.45,
              ),
              decoration: InputDecoration(
                hintText:
                    '{\n  "title": "Slide Title",\n  "blocks": [\n    {\n      "type": "heading",\n      "content": "..." \n    }\n  ]\n}',
                hintStyle: TextStyle(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade400,
                  fontFamily: 'Courier',
                ),
                contentPadding: const EdgeInsets.all(12),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadTab(bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        InkWell(
          onTap: _isLoadingFile ? null : _pickJsonFile,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF6366F1).withOpacity(0.5),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.file_upload_rounded,
                    size: 36,
                    color: Color(0xFF818CF8),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Click to Browse & Upload .json file',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 6),
                Text(
                  'Supports exported slide decks, slide arrays, or single slide JSON files.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_selectedFileName != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF10B981)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: Color(0xFF10B981),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _selectedFileName!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInspectionAndSettingsPanel(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Validation Status Badge
          _buildValidationHeader(isDark),
          const Divider(height: 20),

          // Placement Options
          const Text(
            'IMPORT PLACEMENT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: Color(0xFF818CF8),
            ),
          ),
          const SizedBox(height: 8),

          _buildPlacementTile(
            title: 'Append to End',
            subtitle: 'Add as slide #${widget.currentSlideCount + 1}',
            value: SlideImportPlacement.appendToEnd,
            icon: Icons.playlist_add_rounded,
          ),
          _buildPlacementTile(
            title: 'Insert After Active Slide',
            subtitle:
                'Insert right after slide #${widget.activeSlideIndex + 1}',
            value: SlideImportPlacement.insertAfterActive,
            icon: Icons.add_to_photos_rounded,
          ),
          _buildPlacementTile(
            title: 'Replace Active Slide',
            subtitle: 'Overwrite slide #${widget.activeSlideIndex + 1}',
            value: SlideImportPlacement.replaceActive,
            icon: Icons.sync_rounded,
          ),
          _buildPlacementTile(
            title: 'Replace Entire Deck',
            subtitle: 'Clear current slides and replace all',
            value: SlideImportPlacement.replaceAll,
            icon: Icons.restart_alt_rounded,
            isDestructive: true,
          ),

          if (_parseResult != null && _parseResult!.deckTitle != null) ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Apply Deck Title ("${_parseResult!.deckTitle}")',
                style: const TextStyle(fontSize: 12),
              ),
              value: _updateDeckMetadata,
              onChanged: (val) =>
                  setState(() => _updateDeckMetadata = val ?? true),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],

          const Divider(height: 16),

          // Detected Slides Summary / Preview
          const Text(
            'DETECTED SLIDES PREVIEW',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 6),

          Expanded(child: _buildSlidesPreviewList(isDark)),
        ],
      ),
    );
  }

  Widget _buildValidationHeader(bool isDark) {
    if (_parseResult == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: Colors.grey),
            SizedBox(width: 8),
            Text(
              'Paste JSON or load a file to validate structure',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (!_parseResult!.isSuccess) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 16,
              color: Colors.redAccent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _parseResult!.errorMessage ?? 'Invalid JSON format',
                style: const TextStyle(fontSize: 12, color: Colors.redAccent),
              ),
            ),
          ],
        ),
      );
    }

    final slideCount = _parseResult!.slides.length;
    final totalBlocks = _parseResult!.slides.fold<int>(
      0,
      (sum, s) => sum + s.blocks.length,
    );
    final quizCount = _parseResult!.slides.where((s) => s.quiz != null).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: Color(0xFF10B981),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '✓ Valid JSON: $slideCount Slide(s) Ready',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10B981),
                  ),
                ),
                Text(
                  '$totalBlocks blocks total • $quizCount quizzes included',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlacementTile({
    required String title,
    required String subtitle,
    required SlideImportPlacement value,
    required IconData icon,
    bool isDestructive = false,
  }) {
    final isSelected = _placement == value;
    return InkWell(
      onTap: () => setState(() => _placement = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDestructive
                    ? Colors.red.withOpacity(0.12)
                    : const Color(0xFF6366F1).withOpacity(0.15))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? (isDestructive ? Colors.redAccent : const Color(0xFF6366F1))
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? (isDestructive ? Colors.redAccent : const Color(0xFF818CF8))
                  : Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected
                          ? (isDestructive
                                ? Colors.redAccent
                                : const Color(0xFF818CF8))
                          : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Radio<SlideImportPlacement>(
              value: value,
              groupValue: _placement,
              activeColor: isDestructive
                  ? Colors.redAccent
                  : const Color(0xFF6366F1),
              onChanged: (val) {
                if (val != null) setState(() => _placement = val);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlidesPreviewList(bool isDark) {
    if (_parseResult == null ||
        !_parseResult!.isSuccess ||
        _parseResult!.slides.isEmpty) {
      return Center(
        child: Text(
          'No slides parsed yet.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      );
    }

    final slides = _parseResult!.slides;
    return ListView.builder(
      itemCount: slides.length,
      itemBuilder: (ctx, i) {
        final slide = slides[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: const Color(0xFF6366F1),
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slide.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${slide.blocks.length} blocks • theme: ${slide.theme}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (slide.quiz != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0EA5E9).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Quiz',
                    style: TextStyle(
                      fontSize: 9,
                      color: Color(0xFF0EA5E9),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFooter(bool isDark) {
    final canImport =
        _parseResult != null &&
        _parseResult!.isSuccess &&
        _parseResult!.slides.isNotEmpty;
    final slideCount = _parseResult?.slides.length ?? 0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: canImport ? _onConfirmImport : null,
          icon: const Icon(Icons.file_download_done_rounded, size: 18),
          label: Text(
            canImport ? 'Import $slideCount Slide(s)' : 'Import Slides',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.withOpacity(0.3),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}
