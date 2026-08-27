import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import '../../../../domain/models/slide_deck_models.dart';
import '../../../../providers/theme_provider.dart';
import '../../../../services/api_service.dart';
import '../../../../services/slide_cache_service.dart';

class ImportPptxDialog extends StatefulWidget {
  final String? initialCourseName;
  final String? initialCourseId;

  const ImportPptxDialog({
    super.key,
    this.initialCourseName,
    this.initialCourseId,
  });

  @override
  State<ImportPptxDialog> createState() => _ImportPptxDialogState();
}

class _ImportPptxDialogState extends State<ImportPptxDialog> {
  PlatformFile? _selectedFile;
  late TextEditingController _titleCtrl;
  late TextEditingController _courseCtrl;
  String _selectedTheme = 'darkGlass';

  bool _isConverting = false;
  String _statusMessage = '';

  final List<Map<String, String>> _themes = [
    {'id': 'darkGlass', 'name': 'Dark Glass (Modern Sleek)'},
    {'id': 'jyamitiCosmos', 'name': 'Jyamiti Cosmos (Deep Blue)'},
    {'id': 'midnightNeon', 'name': 'Midnight Neon (Indigo Glow)'},
    {'id': 'emeraldSlate', 'name': 'Emerald Slate (Forest Dark)'},
    {'id': 'sunsetViolet', 'name': 'Sunset Violet (Rich Purple)'},
    {'id': 'cleanLight', 'name': 'Clean Light (Classroom Bright)'},
  ];

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _courseCtrl = TextEditingController(
      text: widget.initialCourseName ?? 'Mathematics',
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _courseCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPptxFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pptx', 'ppt'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          _selectedFile = file;
          if (_titleCtrl.text.trim().isEmpty) {
            final rawName = file.name.replaceAll(RegExp(r'\.pptx?$'), '');
            _titleCtrl.text = rawName.replaceAll(RegExp(r'[_-]'), ' ').trim();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting file: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _startConversion() async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a .pptx file first.')),
      );
      return;
    }

    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a presentation title.')),
      );
      return;
    }

    setState(() {
      _isConverting = true;
      _statusMessage = 'Uploading presentation & rendering 1080p slide images...';
    });

    try {
      final bytes = _selectedFile!.bytes;
      if (bytes == null) {
        throw Exception('Unable to read file bytes. Please re-select the file.');
      }

      final response = await ApiService.uploadPptx(
        bytes,
        _selectedFile!.name,
        title: _titleCtrl.text.trim(),
        courseName: _courseCtrl.text.trim(),
        courseId: widget.initialCourseId ?? 'course_101',
        theme: _selectedTheme,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final dynamic data = json.decode(response.body);
        final deck = SlideDeck.fromMap(data as Map<String, dynamic>);
        await SlideCacheService.instance.saveDeck(deck);

        if (mounted) {
          Navigator.pop(context, deck);
        }
      } else {
        String errorDetail = 'Server returned code ${response.statusCode}';
        try {
          final errJson = json.decode(response.body);
          if (errJson['message'] != null) errorDetail = errJson['message'];
        } catch (_) {}
        throw Exception(errorDetail);
      }
    } catch (e) {
      setState(() {
        _isConverting = false;
        _statusMessage = '';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Conversion failed: $e'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      child: Container(
        width: 580,
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.slideshow_rounded,
                      color: Color(0xFFD97706),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Import PowerPoint Presentation',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Converts .pptx slides into 100% identical high-fidelity interactive decks',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isConverting)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                ],
              ),
              const SizedBox(height: 20),

              if (_isConverting) ...[
                // Converting Progress State
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const JyamitiLoader(strokeWidth: 3),
                        const SizedBox(height: 20),
                        Text(
                          _statusMessage,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Color(0xFF6366F1),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Rendering 1080p visuals and setting up whiteboard annotations...',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                // 1. File Picker Box
                InkWell(
                  onTap: _pickPptxFile,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _selectedFile != null
                          ? const Color(0xFF10B981).withOpacity(0.08)
                          : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _selectedFile != null
                            ? const Color(0xFF10B981)
                            : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                        width: 1.5,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selectedFile != null
                              ? Icons.check_circle_rounded
                              : Icons.cloud_upload_outlined,
                          size: 36,
                          color: _selectedFile != null
                              ? const Color(0xFF10B981)
                              : const Color(0xFF6366F1),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedFile != null
                                    ? _selectedFile!.name
                                    : 'Click to select a .pptx presentation file',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: _selectedFile != null
                                      ? (_selectedFile != null ? const Color(0xFF10B981) : null)
                                      : null,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectedFile != null
                                    ? '${(_selectedFile!.size / (1024 * 1024)).toStringAsFixed(2)} MB • Ready to convert'
                                    : 'Supports PowerPoint presentations (.pptx, .ppt)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton(
                          onPressed: _pickPptxFile,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                            ),
                          ),
                          child: Text(_selectedFile != null ? 'Change' : 'Browse'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // 2. Deck Title
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Presentation Title',
                    hintText: 'e.g. Unit 3: Trigonometric Identities',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 14),

                // 3. Course Name
                TextField(
                  controller: _courseCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Course Name',
                    hintText: 'e.g. Mathematics, Physics, Geometry',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.school_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 14),

                // 4. Slide Theme Dropdown
                DropdownButtonFormField<String>(
                  value: _selectedTheme,
                  decoration: const InputDecoration(
                    labelText: 'Viewer Color Theme',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.palette_outlined, size: 20),
                  ),
                  items: _themes
                      .map(
                        (t) => DropdownMenuItem(
                          value: t['id'],
                          child: Text(t['name']!),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedTheme = val);
                  },
                ),
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _startConversion,
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text('Convert & Import Slide Deck'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
