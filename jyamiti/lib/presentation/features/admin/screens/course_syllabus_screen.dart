import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'package:jyamiti/presentation/widgets/symbol_picker_toolbar.dart';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:provider/provider.dart';
import '../../../../providers/auth_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:jyamiti/services/api_service.dart';
import '../bloc/course/course_bloc.dart';
import '../bloc/course/course_event.dart';
import '../bloc/course/course_state.dart';
import '../../exams/screens/assessment_question_form_screen.dart';
import '../../exams/screens/assessment_taking_screen.dart';
import '../../academic/screens/video_player_screen.dart';
import '../../academic/screens/student_learning_path_screen.dart';
import '../../academic/screens/live_classroom_presentation_screen.dart';
import 'package:jyamiti/utils/file_downloader.dart';
import '../../../../domain/models/slide_deck_models.dart';
import '../../../../services/slide_cache_service.dart';
import '../../slides/screens/admin_slide_cms_screen.dart'
    deferred as cms_screen;
import '../../slides/screens/admin_slide_analytics_screen.dart'
    deferred as analytics_screen;
import '../../slides/screens/student_slide_viewer_screen.dart'
    deferred as student_viewer_screen;

class CourseSyllabusScreen extends StatefulWidget {
  final String courseId;
  final String courseName;
  final VoidCallback? onBack;

  const CourseSyllabusScreen({
    super.key,
    required this.courseId,
    required this.courseName,
    this.onBack,
  });

  static Route<T> route<T>({
    required BuildContext context,
    required String courseId,
    required String courseName,
    VoidCallback? onBack,
  }) {
    CourseBloc? existingBloc;
    try {
      existingBloc = context.read<CourseBloc>();
    } catch (_) {}

    return MaterialPageRoute<T>(
      builder: (_) {
        final screen = CourseSyllabusScreen(
          courseId: courseId,
          courseName: courseName,
          onBack: onBack,
        );
        if (existingBloc != null) {
          return BlocProvider<CourseBloc>.value(
            value: existingBloc,
            child: screen,
          );
        }
        return BlocProvider<CourseBloc>(
          create: (_) => CourseBloc()..add(FetchCourses()),
          child: screen,
        );
      },
    );
  }

  @override
  State<CourseSyllabusScreen> createState() => _CourseSyllabusScreenState();
}

class _CourseSyllabusScreenState extends State<CourseSyllabusScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  List<dynamic> _syllabus = [];
  bool _hasChanges = false;
  final Set<String> _expandedKeys = {};
  int? _focusedChapterIndex;
  int? _focusedTopicIndex;

  @override
  void initState() {
    super.initState();
    _fetchCourse();
  }

  Future<bool> _handleBackPress() async {
    if (_focusedTopicIndex != null) {
      setState(() => _focusedTopicIndex = null);
      return false;
    }
    if (_focusedChapterIndex != null) {
      setState(() => _focusedChapterIndex = null);
      return false;
    }
    if (_hasChanges) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.isDark
              ? const Color(0xFF1E293B)
              : Colors.white,
          title: Text(
            'Unsaved Changes',
            style: TextStyle(color: context.textColor),
          ),
          content: Text(
            'You have unsaved changes. Do you want to discard them?',
            style: TextStyle(color: context.textColor70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: context.textColor60),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Discard',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
      return confirm == true;
    }
    return true;
  }

  Widget _buildBreadcrumbBar() {
    if (_focusedChapterIndex == null) return const SizedBox.shrink();

    final chTitle = (_syllabus.length > _focusedChapterIndex!)
        ? (_cleanSingleLine(_syllabus[_focusedChapterIndex!]['title']))
        : '';

    String? topTitle;
    if (_focusedTopicIndex != null &&
        _focusedChapterIndex! < _syllabus.length) {
      final topics =
          (_syllabus[_focusedChapterIndex!]['topics'] as List?) ?? [];
      if (_focusedTopicIndex! < topics.length) {
        topTitle = _cleanSingleLine(topics[_focusedTopicIndex!]['title']);
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.isDark
            ? const Color(0xFF1E1B4B).withOpacity(0.9)
            : const Color(0xFFE0E7FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF6366F1).withOpacity(0.4),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  _focusedChapterIndex = null;
                  _focusedTopicIndex = null;
                });
              },
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    const Icon(
                      Icons.home_rounded,
                      size: 16,
                      color: Color(0xFF6366F1),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.courseName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey),
            const SizedBox(width: 6),
            InkWell(
              onTap: () {
                setState(() {
                  _focusedTopicIndex = null;
                });
              },
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  chTitle.isNotEmpty
                      ? chTitle
                      : 'Chapter ${_focusedChapterIndex! + 1}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: _focusedTopicIndex == null
                        ? FontWeight.bold
                        : FontWeight.w500,
                    color: _focusedTopicIndex == null
                        ? context.textColor
                        : const Color(0xFF6366F1),
                  ),
                ),
              ),
            ),
            if (topTitle != null && topTitle.isNotEmpty) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                topTitle,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: context.textColor,
                ),
              ),
            ],
            const SizedBox(width: 14),
            InkWell(
              onTap: () {
                setState(() {
                  _focusedChapterIndex = null;
                  _focusedTopicIndex = null;
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.close_rounded,
                        size: 13, color: Colors.redAccent),
                    SizedBox(width: 4),
                    Text(
                      'Exit Focus Mode',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchCourse() async {
    try {
      final state = context.read<CourseBloc>().state;
      if (state is CourseLoaded) {
        final course = state.courses.firstWhere(
          (c) => (c['id'] ?? c['_id']) == widget.courseId,
          orElse: () => null,
        );
        if (course != null && course['syllabus'] != null) {
          if (mounted) {
            setState(() {
              _syllabus = List<dynamic>.from(course['syllabus']);
              _isLoading = false;
            });
          }
          return;
        }
      }
    } catch (_) {}

    try {
      final res = await ApiService.get('/courses/${widget.courseId}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _syllabus = List<dynamic>.from(data['syllabus'] ?? []);
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _saveSyllabus() {
    setState(() => _isSaving = true);
    context.read<CourseBloc>().add(
      UpdateCourseSyllabus(id: widget.courseId, syllabus: _syllabus),
    );
  }

  void _showFullSyllabusStructure() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: context.isDark
              ? const Color(0xFF0F172A)
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.2)),
          ),
          title: Row(
            children: [
              const Icon(Icons.account_tree_rounded, color: Color(0xFF6366F1)),
              const SizedBox(width: 10),
              Text(
                'Syllabus Structure',
                style: TextStyle(
                  color: context.textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.7,
            child: _syllabus.isEmpty
                ? Center(
                    child: Text(
                      'No syllabus structure available.',
                      style: TextStyle(color: context.textColor70),
                    ),
                  )
                : ListView.builder(
                    itemCount: _syllabus.length,
                    itemBuilder: (context, cIndex) {
                      final chapter = _syllabus[cIndex];
                      final topics = chapter['topics'] as List? ?? [];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chapter ${cIndex + 1}: ${chapter['title'] ?? ''}',
                              style: TextStyle(
                                color: const Color(0xFF8B5CF6),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (topics.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 16.0),
                                child: Text(
                                  'No topics defined',
                                  style: TextStyle(
                                    color: context.textColor54,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ...topics.asMap().entries.map((topicEntry) {
                              final topic = topicEntry.value;
                              final subTopics =
                                  topic['subTopics'] as List? ?? [];

                              return Padding(
                                padding: const EdgeInsets.only(
                                  left: 16.0,
                                  top: 6.0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '• ${topic['title'] ?? ''}',
                                      style: TextStyle(
                                        color: context.textColor,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    ...subTopics.map((subTopic) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          left: 16.0,
                                          top: 4.0,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '- ',
                                              style: TextStyle(
                                                color: context.textColor60,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                subTopic['title'] ?? '',
                                                style: TextStyle(
                                                  color: context.textColor70,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              );
                            }),
                            const Divider(height: 24),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Close',
                style: TextStyle(
                  color: Color(0xFF6366F1),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(
    String itemType,
    String itemName,
    VoidCallback onDelete,
  ) async {
    final textController = TextEditingController();
    bool isDeleteEnabled = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: context.isDark
                  ? const Color(0xFF1E293B)
                  : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Delete $itemType',
                    style: TextStyle(
                      color: context.textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to delete this $itemType?',
                    style: TextStyle(color: context.textColor),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      itemName,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Please type the name of the $itemType to confirm:',
                    style: TextStyle(color: context.textColor70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: textController,
                    style: TextStyle(color: context.textColor),
                    decoration: InputDecoration(
                      hintText: 'Type item name',
                      hintStyle: TextStyle(
                        color: context.textColor54.withOpacity(0.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: context.textColor54.withOpacity(0.4),
                        ),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.redAccent),
                      ),
                    ),
                    onChanged: (val) {
                      setStateDialog(() {
                        isDeleteEnabled = val.trim() == itemName.trim();
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: context.textColor60),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    disabledBackgroundColor: Colors.redAccent.withOpacity(0.4),
                  ),
                  onPressed: isDeleteEnabled
                      ? () {
                          Navigator.pop(ctx);
                          onDelete();
                        }
                      : null,
                  child: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _moveChapter(int index, bool up) async {
    final targetIndex = up ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= _syllabus.length) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark
            ? const Color(0xFF1E293B)
            : Colors.white,
        title: Text('Change Order', style: TextStyle(color: context.textColor)),
        content: Text(
          'Are you sure you want to change the order of the chapters?',
          style: TextStyle(color: context.textColor70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: context.textColor60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        final temp = _syllabus[index];
        _syllabus[index] = _syllabus[targetIndex];
        _syllabus[targetIndex] = temp;
        _hasChanges = true;
        _expandedKeys.clear();
      });
      _saveSyllabus();
    }
  }

  Future<void> _moveTopic(int chapterIndex, int index, bool up) async {
    final topics = _syllabus[chapterIndex]['topics'] as List;
    final targetIndex = up ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= topics.length) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark
            ? const Color(0xFF1E293B)
            : Colors.white,
        title: Text('Change Order', style: TextStyle(color: context.textColor)),
        content: Text(
          'Are you sure you want to change the order of the topics?',
          style: TextStyle(color: context.textColor70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: context.textColor60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        final temp = topics[index];
        topics[index] = topics[targetIndex];
        topics[targetIndex] = temp;
        _hasChanges = true;
        _expandedKeys.clear();
      });
      _saveSyllabus();
    }
  }

  Future<void> _moveSubTopic(
    int chapterIndex,
    int topicIndex,
    int index,
    bool up,
  ) async {
    final subTopics =
        _syllabus[chapterIndex]['topics'][topicIndex]['subTopics'] as List;
    final targetIndex = up ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= subTopics.length) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark
            ? const Color(0xFF1E293B)
            : Colors.white,
        title: Text('Change Order', style: TextStyle(color: context.textColor)),
        content: Text(
          'Are you sure you want to change the order of the sub-topics?',
          style: TextStyle(color: context.textColor70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: context.textColor60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        final temp = subTopics[index];
        subTopics[index] = subTopics[targetIndex];
        subTopics[targetIndex] = temp;
        _hasChanges = true;
      });
      _saveSyllabus();
    }
  }

  Future<String?> _showInputDialog(
    String title, {
    String initialValue = '',
  }) async {
    final ctrl = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark
            ? const Color(0xFF1E293B)
            : Colors.white,
        title: Text(title, style: TextStyle(color: context.textColor)),
        content: SizedBox(
          width: 400,
          child: SymbolInputFieldWrapper(
            controller: ctrl,
            child: TextField(
              controller: ctrl,
              style: TextStyle(color: context.textColor),
              decoration: InputDecoration(
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: context.textColor54.withOpacity(0.4),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: const Color(0xFF6366F1)),
                ),
              ),
              autofocus: true,
              onSubmitted: (val) {
                final text = val.trim();
                if (text.isNotEmpty) {
                  Navigator.pop(ctx, text);
                }
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: context.textColor60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  static const String _samplePlainTextTemplate = '''Chapter 1: Real Numbers
  - Topic 1.1: Fundamental Theorem of Arithmetic
      * Subtopic 1.1.1: Prime Factorization & HCF / LCM
      * Subtopic 1.1.2: Proofs of Irrational Numbers
  - Topic 1.2: Polynomials
      * Subtopic 1.2.1: Zeros of a Polynomial

Chapter 2: Polynomials
  - Topic 2.1: Geometrical Meaning of Zeros
      * Subtopic 2.1.1: Relationship between Zeros and Coefficients''';

  static const String _sampleSimpleJsonTemplate = '''[
  {
    "title": "Chapter 1: Real Numbers",
    "topics": [
      {
        "title": "Topic 1.1: Fundamental Theorem of Arithmetic",
        "subTopics": [
          { "title": "Subtopic 1.1.1: Prime Factorization & HCF / LCM" },
          { "title": "Subtopic 1.1.2: Proofs of Irrational Numbers" }
        ]
      },
      {
        "title": "Topic 1.2: Polynomials",
        "subTopics": [
          { "title": "Subtopic 1.2.1: Zeros of a Polynomial" }
        ]
      }
    ]
  },
  {
    "title": "Chapter 2: Polynomials",
    "topics": [
      {
        "title": "Topic 2.1: Geometrical Meaning of Zeros",
        "subTopics": [
          { "title": "Subtopic 2.1.1: Relationship between Zeros and Coefficients" }
        ]
      }
    ]
  }
]''';

  List<dynamic> _extractChaptersFromJson(dynamic decoded) {
    if (decoded is List) {
      return decoded;
    } else if (decoded is Map<String, dynamic>) {
      if (decoded['syllabus'] is List) {
        return decoded['syllabus'] as List;
      } else if (decoded['chapters'] is List) {
        return decoded['chapters'] as List;
      } else if (decoded['topics'] is List) {
        return [decoded];
      }
    }
    return [];
  }

  String _cleanSingleLine(dynamic raw) {
    if (raw == null) return '';
    return raw
        .toString()
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<dynamic> _parseSyllabusFromInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return [];

    // 1. Try parsing JSON first
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(trimmed);
        final chapters = _extractChaptersFromJson(decoded);
        if (chapters.isNotEmpty) return chapters;
      } catch (_) {}
    }

    // 2. Parse Plain Text Outline (Line by Line)
    final lines = LineSplitter.split(input);
    final List<Map<String, dynamic>> chapters = [];
    Map<String, dynamic>? currentChapter;
    Map<String, dynamic>? currentTopic;

    for (var line in lines) {
      final cleanLine = _cleanSingleLine(line);
      if (cleanLine.isEmpty) continue;

      final leadingSpaces = line.length - line.trimLeft().length;

      final isSubtopicMarker = cleanLine.startsWith('*') ||
          cleanLine.startsWith('•') ||
          cleanLine.startsWith('>') ||
          (cleanLine.startsWith('- ') && leadingSpaces >= 4);

      final isTopicMarker = (cleanLine.startsWith('-') ||
              cleanLine.startsWith('Topic') ||
              leadingSpaces >= 2) &&
          !isSubtopicMarker;

      if (isSubtopicMarker && currentTopic != null) {
        final cleanTitle = cleanLine
            .replaceAll(RegExp(r'^[\*\•\->\s]+'), '')
            .trim();
        if (cleanTitle.isNotEmpty) {
          (currentTopic['subTopics'] as List).add({'title': cleanTitle});
        }
      } else if (isTopicMarker && currentChapter != null) {
        final cleanTitle = cleanLine
            .replaceAll(RegExp(r'^-+\s*'), '')
            .trim();
        if (cleanTitle.isNotEmpty) {
          final newTopic = <String, dynamic>{
            'title': cleanTitle,
            'subTopics': <Map<String, dynamic>>[],
          };
          (currentChapter['topics'] as List).add(newTopic);
          currentTopic = newTopic;
        }
      } else {
        // It's a new Chapter
        final cleanTitle = cleanLine
            .replaceAll(RegExp(r'^\d+[\.\)]\s*'), '')
            .trim();
        if (cleanTitle.isNotEmpty) {
          currentChapter = <String, dynamic>{
            'title': cleanTitle,
            'topics': <Map<String, dynamic>>[],
          };
          chapters.add(currentChapter);
          currentTopic = null;
        }
      }
    }

    return chapters;
  }

  String _generatePlainTextOutline() {
    final sb = StringBuffer();

    List<dynamic> targetChapters = [];
    if (_focusedChapterIndex != null &&
        _focusedChapterIndex! < _syllabus.length) {
      targetChapters = [_syllabus[_focusedChapterIndex!]];
    } else {
      targetChapters = _syllabus;
    }

    for (int i = 0; i < targetChapters.length; i++) {
      final ch = targetChapters[i];
      var rawTitle = _cleanSingleLine(ch['title']);
      if (rawTitle.isEmpty) {
        rawTitle = 'Chapter ${i + 1}';
      }

      final hasLeadingNumber = RegExp(r'^\d+[\.\:\)]').hasMatch(rawTitle) ||
          RegExp(r'^Chapter\s+\d+', caseSensitive: false).hasMatch(rawTitle);

      if (hasLeadingNumber) {
        sb.writeln(rawTitle);
      } else {
        sb.writeln('${i + 1}. $rawTitle');
      }

      final allTopics = (ch['topics'] as List?) ?? [];
      List<dynamic> targetTopics = [];
      if (_focusedTopicIndex != null &&
          _focusedTopicIndex! < allTopics.length) {
        targetTopics = [allTopics[_focusedTopicIndex!]];
      } else {
        targetTopics = allTopics;
      }

      for (int j = 0; j < targetTopics.length; j++) {
        final top = targetTopics[j];
        var topTitle = _cleanSingleLine(top['title']);
        if (topTitle.isEmpty) {
          topTitle = 'Topic ${j + 1}';
        }
        sb.writeln('  - $topTitle');

        final subTopics = (top['subTopics'] as List?) ?? [];
        for (int k = 0; k < subTopics.length; k++) {
          final sub = subTopics[k];
          var subTitle = _cleanSingleLine(sub['title']);
          if (subTitle.isEmpty) {
            subTitle = 'Subtopic ${k + 1}';
          }
          sb.writeln('      * $subTitle');
        }
      }
      sb.writeln();
    }
    return sb.toString().trim();
  }

  String _generateSimpleJsonOutline() {
    List<dynamic> targetChapters = [];
    if (_focusedChapterIndex != null &&
        _focusedChapterIndex! < _syllabus.length) {
      targetChapters = [_syllabus[_focusedChapterIndex!]];
    } else {
      targetChapters = _syllabus;
    }

    final cleanSyllabus = targetChapters.map((ch) {
      final allTopics = (ch['topics'] as List?) ?? [];
      List<dynamic> targetTopics = [];
      if (_focusedTopicIndex != null &&
          _focusedTopicIndex! < allTopics.length) {
        targetTopics = [allTopics[_focusedTopicIndex!]];
      } else {
        targetTopics = allTopics;
      }

      return {
        'title': ch['title'] ?? '',
        'topics': targetTopics.map((top) {
          final subTopics = (top['subTopics'] as List?) ?? [];
          return {
            'title': top['title'] ?? '',
            'subTopics':
                subTopics.map((sub) => {'title': sub['title'] ?? ''}).toList(),
          };
        }).toList(),
      };
    }).toList();

    return const JsonEncoder.withIndent('  ').convert(cleanSyllabus);
  }

  void _downloadJsonFile(String fileName, String content) async {
    final success = await FileDownloader.downloadFile(
      fileName: fileName,
      content: content,
    );
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Syllabus file ($fileName) downloaded successfully to device!',
          ),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } else {
      Clipboard.setData(ClipboardData(text: content));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Syllabus ($fileName) copied to clipboard!',
          ),
          backgroundColor: const Color(0xFF6366F1),
        ),
      );
    }
  }

  void _showBulkImportDialog() {
    final textCtrl = TextEditingController();
    String? validationMessage;
    bool isValid = false;
    List<dynamic> parsedChapters = [];
    bool replaceExisting = false;

    final isChapterFocus =
        _focusedChapterIndex != null && _focusedTopicIndex == null;
    final isTopicFocus =
        _focusedChapterIndex != null && _focusedTopicIndex != null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          void validateInput(String input) {
            final trimmed = input.trim();
            if (trimmed.isEmpty) {
              setDialogState(() {
                validationMessage = null;
                isValid = false;
                parsedChapters = [];
              });
              return;
            }

            final chapters = _parseSyllabusFromInput(trimmed);
            if (chapters.isEmpty) {
              setDialogState(() {
                validationMessage =
                    'Warning: Could not parse chapters/topics from text.';
                isValid = false;
                parsedChapters = [];
              });
            } else {
              int totalTopics = 0;
              int totalSubtopics = 0;

              for (var ch in chapters) {
                final topics = (ch['topics'] as List?) ?? [];
                totalTopics += topics.length;
                for (var top in topics) {
                  final sub = (top['subTopics'] as List?) ?? [];
                  totalSubtopics += sub.length;
                }
              }

              final scopeLabel = isTopicFocus
                  ? 'Subtopic Import Mode'
                  : (isChapterFocus
                      ? 'Topic Import Mode'
                      : 'Full Syllabus Mode');

              setDialogState(() {
                validationMessage =
                    '✓ Parsed ($scopeLabel): ${chapters.length} Chapter(s), $totalTopics Topic(s), $totalSubtopics Subtopic(s).';
                isValid = true;
                parsedChapters = chapters;
              });
            }
          }

          return Dialog(
            backgroundColor:
                context.isDark ? const Color(0xFF0F172A) : Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              height: MediaQuery.of(context).size.height * 0.85,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Dialog Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.file_upload_rounded,
                          color: Color(0xFF10B981),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isTopicFocus
                                  ? 'Scoped Import: Topic Subtopics'
                                  : (isChapterFocus
                                      ? 'Scoped Import: Chapter Topics'
                                      : 'Bulk Import Full Syllabus'),
                              style: TextStyle(
                                color: context.textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              isTopicFocus
                                  ? 'Importing will affect ONLY subtopics of focused topic.'
                                  : (isChapterFocus
                                      ? 'Importing will affect ONLY topics inside focused chapter.'
                                      : 'Paste plain text outline (Chapter / Topic / Subtopic) or clean JSON in 1 click.'),
                              style: TextStyle(
                                color: isChapterFocus || isTopicFocus
                                    ? const Color(0xFF10B981)
                                    : context.textColor60,
                                fontSize: 12,
                                fontWeight: isChapterFocus || isTopicFocus
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // Quick Action Toolbar
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: _samplePlainTextTemplate));
                            textCtrl.text = _samplePlainTextTemplate;
                            validateInput(_samplePlainTextTemplate);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Plain text syllabus template loaded!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          },
                          icon: const Icon(Icons.description_rounded, size: 16),
                          label: const Text('📄 Plain Text Sample'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6366F1),
                            side: const BorderSide(color: Color(0xFF6366F1)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: _sampleSimpleJsonTemplate));
                            textCtrl.text = _sampleSimpleJsonTemplate;
                            validateInput(_sampleSimpleJsonTemplate);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Simple JSON syllabus template loaded!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          },
                          icon: const Icon(Icons.code_rounded, size: 16),
                          label: const Text('📊 Simple JSON Sample'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF10B981),
                            side: const BorderSide(color: Color(0xFF10B981)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            try {
                              final data =
                                  await Clipboard.getData(Clipboard.kTextPlain);
                              if (data != null &&
                                  data.text != null &&
                                  data.text!.isNotEmpty) {
                                textCtrl.text = data.text!;
                                validateInput(data.text!);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Pasted text from clipboard directly into editor!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Clipboard is empty!'),
                                    backgroundColor: Colors.amber,
                                  ),
                                );
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Clipboard read error: $e'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.paste_rounded, size: 16),
                          label: const Text('📋 Paste Clipboard'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: () async {
                            try {
                              final result = await FilePicker.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['txt', 'json'],
                                withData: true,
                              );
                              if (result != null && result.files.isNotEmpty) {
                                final bytes = result.files.first.bytes;
                                if (bytes != null) {
                                  final content = utf8.decode(bytes);
                                  textCtrl.text = content;
                                  validateInput(content);
                                }
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error reading file: $e'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.folder_open_rounded, size: 16),
                          label: const Text('📂 Open File'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Validation Banner
                  if (validationMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isValid
                            ? const Color(0xFF10B981).withOpacity(0.12)
                            : Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isValid
                              ? const Color(0xFF10B981).withOpacity(0.4)
                              : Colors.amber.withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isValid
                                ? Icons.check_circle_rounded
                                : Icons.warning_rounded,
                            color: isValid
                                ? const Color(0xFF10B981)
                                : Colors.amber,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              validationMessage!,
                              style: TextStyle(
                                color: isValid
                                    ? const Color(0xFF10B981)
                                    : Colors.amber[800],
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Text Editor Area
                  Expanded(
                    child: TextField(
                      controller: textCtrl,
                      maxLines: null,
                      expands: true,
                      style: GoogleFonts.firaCode(
                        fontSize: 13,
                        color: context.textColor,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'Paste plain syllabus text outline or JSON here:\n\nChapter 1: Real Numbers\n  - Topic 1.1: Prime Factorization\n      * Subtopic 1.1.1: HCF / LCM',
                        hintStyle: TextStyle(
                          color: context.textColor54.withOpacity(0.5),
                          fontSize: 13,
                        ),
                        filled: true,
                        fillColor: context.isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.glassBorder),
                        ),
                      ),
                      onChanged: validateInput,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Import Options & Footer
                  Row(
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: replaceExisting,
                            activeColor: Colors.redAccent,
                            onChanged: (val) {
                              setDialogState(() {
                                replaceExisting = val ?? false;
                              });
                            },
                          ),
                          Text(
                            isTopicFocus
                                ? 'Replace existing subtopics in this topic'
                                : (isChapterFocus
                                    ? 'Replace existing topics in this chapter'
                                    : 'Replace existing syllabus'),
                            style: TextStyle(
                              color: context.textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: context.textColor60),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: isValid
                            ? () {
                                Navigator.pop(ctx);
                                setState(() {
                                  if (_focusedChapterIndex != null &&
                                      _focusedChapterIndex! <
                                          _syllabus.length) {
                                    final chapter =
                                        _syllabus[_focusedChapterIndex!];
                                    if (chapter['topics'] == null) {
                                      chapter['topics'] = [];
                                    }
                                    final topicsList =
                                        chapter['topics'] as List;

                                    if (_focusedTopicIndex != null &&
                                        _focusedTopicIndex! <
                                            topicsList.length) {
                                      // Scoped Topic Import: Subtopics
                                      final topic =
                                          topicsList[_focusedTopicIndex!];
                                      if (topic['subTopics'] == null) {
                                        topic['subTopics'] = [];
                                      }

                                      final importedSubs =
                                          <Map<String, dynamic>>[];
                                      for (var ch in parsedChapters) {
                                        final tops =
                                            (ch['topics'] as List?) ?? [];
                                        for (var top in tops) {
                                          final subs =
                                              (top['subTopics'] as List?) ??
                                                  [];
                                          for (var s in subs) {
                                            importedSubs
                                                .add({'title': s['title'] ?? ''});
                                          }
                                        }
                                      }

                                      if (replaceExisting) {
                                        topic['subTopics'] = importedSubs;
                                      } else {
                                        (topic['subTopics'] as List)
                                            .addAll(importedSubs);
                                      }
                                    } else {
                                      // Scoped Chapter Import: Topics
                                      final importedTopics =
                                          <Map<String, dynamic>>[];
                                      for (var ch in parsedChapters) {
                                        final tops =
                                            (ch['topics'] as List?) ?? [];
                                        if (tops.isNotEmpty) {
                                          importedTopics.addAll(
                                              List<Map<String, dynamic>>.from(
                                                  tops));
                                        } else {
                                          importedTopics.add({
                                            'title': ch['title'] ?? '',
                                            'subTopics': []
                                          });
                                        }
                                      }

                                      if (replaceExisting) {
                                        chapter['topics'] = importedTopics;
                                      } else {
                                        (chapter['topics'] as List)
                                            .addAll(importedTopics);
                                      }
                                    }
                                  } else {
                                    // Root Syllabus Import
                                    if (replaceExisting) {
                                      _syllabus = parsedChapters;
                                    } else {
                                      _syllabus.addAll(parsedChapters);
                                    }
                                  }
                                  _hasChanges = true;
                                });
                                _saveSyllabus();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _focusedChapterIndex != null
                                          ? 'Imported into focused section successfully!'
                                          : 'Imported ${parsedChapters.length} chapter(s) into syllabus!',
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            : null,
                        icon: const Icon(Icons.file_upload_rounded),
                        label: Text(
                          replaceExisting ? 'Replace & Import' : 'Append & Import',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              const Color(0xFF10B981).withOpacity(0.4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showExportSyllabusDialog() {
    String exportFormat = 'TEXT'; // 'TEXT' or 'JSON'

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final String currentExportText = exportFormat == 'TEXT'
              ? _generatePlainTextOutline()
              : _generateSimpleJsonOutline();

          return Dialog(
            backgroundColor:
                context.isDark ? const Color(0xFF0F172A) : Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              height: MediaQuery.of(context).size.height * 0.85,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.file_download_rounded,
                          color: Color(0xFF6366F1),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Export Course Syllabus: ${widget.courseName}',
                              style: TextStyle(
                                color: context.textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Copy or download plain text syllabus outline (Chapter / Topic / Subtopic) for external use.',
                              style: TextStyle(
                                color: context.textColor60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // Format Selector & Quick Actions
                  Row(
                    children: [
                      // Format Switcher
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: context.isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () {
                                setDialogState(() => exportFormat = 'TEXT');
                              },
                              borderRadius: BorderRadius.circular(7),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: exportFormat == 'TEXT'
                                      ? const Color(0xFF6366F1)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.description_rounded,
                                      size: 14,
                                      color: exportFormat == 'TEXT'
                                          ? Colors.white
                                          : context.textColor60,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Plain Text (.txt)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: exportFormat == 'TEXT'
                                            ? Colors.white
                                            : context.textColor60,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () {
                                setDialogState(() => exportFormat = 'JSON');
                              },
                              borderRadius: BorderRadius.circular(7),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: exportFormat == 'JSON'
                                      ? const Color(0xFF6366F1)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.code_rounded,
                                      size: 14,
                                      color: exportFormat == 'JSON'
                                          ? Colors.white
                                          : context.textColor60,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Simple JSON (.json)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: exportFormat == 'JSON'
                                            ? Colors.white
                                            : context.textColor60,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: currentExportText));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  '${exportFormat == 'TEXT' ? 'Plain text' : 'JSON'} syllabus outline copied to clipboard!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('📋 Copy to Clipboard'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          final ext = exportFormat == 'TEXT' ? 'txt' : 'json';
                          _downloadJsonFile(
                            '${widget.courseName.replaceAll(RegExp(r'[^\w\s\-]'), '_')}_Syllabus.$ext',
                            currentExportText,
                          );
                        },
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: Text(
                            '💾 Download .${exportFormat.toLowerCase()} File'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF10B981),
                          side: const BorderSide(color: Color(0xFF10B981)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Code Preview Area
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.glassBorder),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          currentExportText,
                          style: GoogleFonts.firaCode(
                            fontSize: 13,
                            color: context.textColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _addChapter() async {
    final title = await _showInputDialog('Add Chapter / Unit');
    if (title != null && title.isNotEmpty) {
      final newIndex = _syllabus.length;
      setState(() {
        _syllabus.add({'title': title, 'topics': []});
        _hasChanges = true;
        _expandedKeys.add('c_$newIndex');
      });
      _saveSyllabus();
    }
  }

  void _addTopic(int chapterIndex) async {
    final title = await _showInputDialog('Add Topic');
    if (title != null && title.isNotEmpty) {
      setState(() {
        if (_syllabus[chapterIndex]['topics'] == null) {
          _syllabus[chapterIndex]['topics'] = [];
        }
        final topics = _syllabus[chapterIndex]['topics'] as List;
        final newTopicIndex = topics.length;
        topics.add({'title': title, 'subTopics': []});
        _hasChanges = true;
        _expandedKeys.add('c_$chapterIndex');
        _expandedKeys.add('c_${chapterIndex}_t_$newTopicIndex');
      });
      _saveSyllabus();
    }
  }

  void _addSubTopic(int chapterIndex, int topicIndex) async {
    final title = await _showInputDialog('Add Sub-topic');
    if (title != null && title.isNotEmpty) {
      setState(() {
        if (_syllabus[chapterIndex]['topics'][topicIndex]['subTopics'] ==
            null) {
          _syllabus[chapterIndex]['topics'][topicIndex]['subTopics'] = [];
        }
        _syllabus[chapterIndex]['topics'][topicIndex]['subTopics'].add({
          'title': title,
        });
        _hasChanges = true;
        _expandedKeys.add('c_$chapterIndex');
        _expandedKeys.add('c_${chapterIndex}_t_$topicIndex');
      });
      _saveSyllabus();
    }
  }

  void _editTitle(dynamic node, String type) async {
    final title = await _showInputDialog(
      'Edit $type',
      initialValue: node['title'] ?? '',
    );
    if (title != null && title.isNotEmpty) {
      setState(() {
        node['title'] = title;
        _hasChanges = true;
      });
      _saveSyllabus();
    }
  }



  Widget _buildItemPopupMenu({
    required String type,
    required dynamic item,
    VoidCallback? onMoveUp,
    VoidCallback? onMoveDown,
    VoidCallback? onManageResources,
    required VoidCallback onDelete,
  }) {
    final itemMap = item is Map ? item : <String, dynamic>{};
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert_rounded,
        size: 18,
        color: context.textColor70,
      ),
      tooltip: '$type Options',
      onSelected: (value) {
        if (value == 'move_up') {
          onMoveUp?.call();
        } else if (value == 'move_down') {
          onMoveDown?.call();
        } else if (value == 'manage_resources') {
          onManageResources?.call();
        } else if (value == 'edit') {
          _editTitle(itemMap, type);
        } else if (value == 'delete') {
          _confirmDelete(type, (itemMap['title'] ?? '').toString(), onDelete);
        }
      },
      itemBuilder: (context) => [
        if (onMoveUp != null)
          PopupMenuItem<String>(
            value: 'move_up',
            child: Row(
              children: [
                const Icon(Icons.arrow_upward_rounded,
                    size: 16, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Text(
                  'Move Up',
                  style: TextStyle(
                    color: context.textColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        if (onMoveDown != null)
          PopupMenuItem<String>(
            value: 'move_down',
            child: Row(
              children: [
                const Icon(Icons.arrow_downward_rounded,
                    size: 16, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Text(
                  'Move Down',
                  style: TextStyle(
                    color: context.textColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        if (onManageResources != null)
          PopupMenuItem<String>(
            value: 'manage_resources',
            child: Row(
              children: [
                const Icon(Icons.folder_special_rounded,
                    size: 16, color: Color(0xFF8B5CF6)),
                const SizedBox(width: 8),
                Text(
                  'Manage Resources',
                  style: TextStyle(
                    color: context.textColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_rounded, size: 16, color: context.textColor),
              const SizedBox(width: 8),
              Text(
                'Edit $type',
                style: TextStyle(
                  color: context.textColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline_rounded,
                  size: 16, color: Colors.redAccent),
              const SizedBox(width: 8),
              const Text(
                'Delete',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<dynamic> _collectAllQuestions() {
    final List<dynamic> questions = [];

    void processNode(dynamic rawNode) {
      if (rawNode is! Map) return;
      final node = Map<String, dynamic>.from(rawNode);

      if (node['practiceQuestions'] is List) {
        questions.addAll(node['practiceQuestions'] as List);
      }
      if (node['practiceSets'] is List) {
        for (var set in node['practiceSets']) {
          if (set is Map && set['questions'] is List) {
            questions.addAll(set['questions'] as List);
          }
        }
      }
      if (node['topics'] is List) {
        for (var topic in node['topics']) {
          if (topic is Map) processNode(topic);
        }
      }
      if (node['subTopics'] is List) {
        for (var sub in node['subTopics']) {
          if (sub is Map) processNode(sub);
        }
      }
    }

    if (_focusedChapterIndex != null && _focusedTopicIndex != null) {
      if (_focusedChapterIndex! < _syllabus.length) {
        final chapter = _syllabus[_focusedChapterIndex!];
        final topics = (chapter['topics'] as List?) ?? [];
        if (_focusedTopicIndex! < topics.length) {
          final topic = topics[_focusedTopicIndex!];
          if (topic is Map) processNode(topic);
        }
      }
    } else if (_focusedChapterIndex != null) {
      if (_focusedChapterIndex! < _syllabus.length) {
        final chapter = _syllabus[_focusedChapterIndex!];
        if (chapter is Map) processNode(chapter);
      }
    } else {
      for (var chapter in _syllabus) {
        if (chapter is Map) processNode(chapter);
      }
    }

    return questions;
  }

  Widget _buildFocusedTopicCard(int cIndex, int tIndex) {
    if (cIndex >= _syllabus.length) return const SizedBox.shrink();
    final chapter = _syllabus[cIndex];
    final topics = (chapter['topics'] as List?) ?? [];
    if (tIndex >= topics.length) return const SizedBox.shrink();

    final topic = topics[tIndex];
    final subTopics = (topic['subTopics'] as List?) ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.isDark
              ? const Color(0xFF3B82F6).withOpacity(0.4)
              : const Color(0xFF3B82F6).withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Topic Header Row
                Row(
                  children: [
                    const Icon(
                      Icons.topic,
                      color: Color(0xFF3B82F6),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        topic['title'] ?? '',
                        style: TextStyle(
                          color: context.textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(
                        Icons.center_focus_strong_rounded,
                        size: 18,
                        color: Color(0xFF10B981),
                      ),
                      onPressed: () {
                        setState(() {
                          _focusedTopicIndex = null;
                        });
                      },
                      tooltip: 'Exit Topic Focus Mode',
                    ),
                    _buildItemPopupMenu(
                      type: 'Topic',
                      item: topic,
                      onManageResources: () => _manageResources(topic),
                      onDelete: () {
                        setState(() {
                          topics.removeAt(tIndex);
                          _focusedTopicIndex = null;
                          _hasChanges = true;
                        });
                        _saveSyllabus();
                      },
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Subtopics Section Title
                Text(
                  'Subtopics & Practice Areas:',
                  style: TextStyle(
                    color: context.textColor70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),

                // Subtopics List
                for (int sIndex = 0; sIndex < subTopics.length; sIndex++)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(
                      Icons.subdirectory_arrow_right,
                      color: context.textColor54.withOpacity(0.5),
                      size: 18,
                    ),
                    title: Text(
                      subTopics[sIndex]['title'] ?? '',
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildItemPopupMenu(
                          type: 'Sub-topic',
                          item: subTopics[sIndex],
                          onMoveUp: sIndex > 0
                              ? () => _moveSubTopic(
                                    cIndex,
                                    tIndex,
                                    sIndex,
                                    true,
                                  )
                              : null,
                          onMoveDown: sIndex < subTopics.length - 1
                              ? () => _moveSubTopic(
                                    cIndex,
                                    tIndex,
                                    sIndex,
                                    false,
                                  )
                              : null,
                          onManageResources: () => _manageResources(
                            subTopics[sIndex],
                          ),
                          onDelete: () {
                            setState(() {
                              subTopics.removeAt(sIndex);
                              _hasChanges = true;
                            });
                            _saveSyllabus();
                          },
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _addSubTopic(cIndex, tIndex),
                    icon: const Icon(
                      Icons.add,
                      size: 16,
                      color: Color(0xFF10B981),
                    ),
                    label: const Text(
                      'Add Sub-topic',
                      style: TextStyle(
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final shouldPop = await _handleBackPress();
        if (shouldPop && widget.onBack != null) {
          widget.onBack!();
          return false;
        }
        return shouldPop;
      },
      child: BlocListener<CourseBloc, CourseState>(
        listener: (context, state) {
          if (state is CourseOperationSuccess) {
            setState(() {
              _isSaving = false;
              _hasChanges = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          } else if (state is CourseOperationFailure) {
            setState(() => _isSaving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.redAccent,
              ),
            );
          } else if (state is CourseLoaded) {
            if (!_hasChanges && !_isSaving) {
              final course = state.courses.firstWhere(
                (c) => (c['id'] ?? c['_id']) == widget.courseId,
                orElse: () => null,
              );
              if (course != null && course['syllabus'] != null) {
                setState(() {
                  _syllabus = List<dynamic>.from(course['syllabus']);
                });
              }
            }
          }
        },
        child: Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () async {
                final shouldPop = await _handleBackPress();
                if (shouldPop) {
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else {
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  }
                }
              },
            ),
            title: Text(
              'Syllabus: ${widget.courseName}',
              style: TextStyle(
                color: context.textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: context.isDark
                ? const Color(0xFF0F172A).withOpacity(0.8)
                : Colors.white.withOpacity(0.7),
            elevation: 0,
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: Colors.transparent),
              ),
            ),
            iconTheme: IconThemeData(color: context.textColor),
            bottom: _isSaving
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(3),
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.transparent,
                      color: Color(0xFF6366F1),
                      minHeight: 3,
                    ),
                  )
                : null,
            actions: [
              IconButton(
                icon: const Icon(Icons.file_upload_rounded, color: Color(0xFF10B981)),
                onPressed: _showBulkImportDialog,
                tooltip: 'Bulk Import Syllabus (JSON)',
              ),
              IconButton(
                icon: const Icon(Icons.file_download_rounded, color: Color(0xFF6366F1)),
                onPressed: _showExportSyllabusDialog,
                tooltip: 'Download / Export Syllabus (JSON)',
              ),
              IconButton(
                icon: const Icon(Icons.account_tree_rounded),
                onPressed: _showFullSyllabusStructure,
                tooltip: 'Syllabus Structure',
              ),
              IconButton(
                icon: const Icon(Icons.tv_rounded, color: Color(0xFF8B5CF6)),
                onPressed: () {
                  final allQuestions = _collectAllQuestions();
                  if (allQuestions.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'No practice or classwork questions found in this syllabus section yet.'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LiveClassroomPresentationScreen(
                        title: widget.courseName,
                        questions: allQuestions,
                      ),
                    ),
                  );
                },
                tooltip: 'Live Classroom Presentation Mode (Smartboard)',
              ),
              IconButton(
                icon: const Icon(Icons.explore_rounded, color: Color(0xFF6366F1)),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StudentLearningPathScreen(
                        batch: {
                          'id': widget.courseId,
                          'name': widget.courseName,
                          'course': {
                            'id': widget.courseId,
                            '_id': widget.courseId,
                            'title': widget.courseName,
                          },
                        },
                      ),
                    ),
                  );
                },
                tooltip: 'Explore Course (Student View)',
              ),
              if (_hasChanges)
                IconButton(
                  icon: const Icon(Icons.save, color: Color(0xFF10B981)),
                  onPressed: _saveSyllabus,
                  tooltip: 'Save Changes',
                ),
            ],
          ),
          body: _isLoading
              ? const Center(child: JyamitiLoader(color: Color(0xFF6366F1)))
              : _syllabus.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'No syllabus defined yet.',
                        style: TextStyle(
                          color: context.textColor54,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _addChapter,
                            icon: const Icon(Icons.add, color: Colors.white),
                            label: const Text(
                              'Add Chapter',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _showBulkImportDialog,
                            icon: const Icon(Icons.file_upload_rounded, color: Colors.white),
                            label: const Text(
                              'Bulk Import Syllabus',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: context.isDark
                          ? const [
                              Color(0xFF0F172A),
                              Color(0xFF1E1B4B),
                              Color(0xFF0F172A),
                            ]
                          : const [
                              Color(0xFFF1F5F9),
                              Color(0xFFE2E8F0),
                              Color(0xFFF1F5F9),
                            ],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 95),
                      _buildBreadcrumbBar(),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.only(
                            top: 8,
                            left: 16,
                            right: 16,
                            bottom: 100,
                          ),
                          itemCount: _syllabus.length,
                          itemBuilder: (context, cIndex) {
                            if (_focusedChapterIndex != null &&
                                cIndex != _focusedChapterIndex) {
                              return const SizedBox.shrink();
                            }
                            if (_focusedChapterIndex != null &&
                                _focusedTopicIndex != null) {
                              return _buildFocusedTopicCard(
                                  cIndex, _focusedTopicIndex!);
                            }

                            final chapter = _syllabus[cIndex];
                            final topics = chapter['topics'] ?? [];
                            final chapterKey = 'c_$cIndex';
                            final isChapterExpanded = _expandedKeys.contains(
                              chapterKey,
                            );

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: context.isDark
                                    ? context.glassBg
                                    : Colors.white.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: context.isDark
                                      ? const Color(0xFF8B5CF6).withOpacity(0.3)
                                      : const Color(0xFF8B5CF6).withOpacity(0.15),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF8B5CF6).withOpacity(0.05),
                                    blurRadius: 10,
                                    spreadRadius: 0,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                  child: ExpansionTile(
                                    key: Key('chapter_${cIndex}_$isChapterExpanded'),
                                    initiallyExpanded: isChapterExpanded,
                                    onExpansionChanged: (expanded) {
                                      setState(() {
                                        if (expanded) {
                                          _expandedKeys.add(chapterKey);
                                        } else {
                                          _expandedKeys.remove(chapterKey);
                                        }
                                      });
                                    },
                                    iconColor: context.textColor,
                                    collapsedIconColor: context.textColor70,
                                    title: GestureDetector(
                                      onDoubleTap: () {
                                        setState(() {
                                          _focusedChapterIndex = cIndex;
                                          _focusedTopicIndex = null;
                                          _expandedKeys.add(chapterKey);
                                        });
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Focused on Chapter: ${_cleanSingleLine(chapter['title'])}',
                                            ),
                                            backgroundColor: const Color(0xFF6366F1),
                                            duration: const Duration(seconds: 1),
                                          ),
                                        );
                                      },
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.menu_book,
                                            color: Color(0xFF8B5CF6),
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              chapter['title'] ?? '',
                                              style: TextStyle(
                                                color: context.textColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              _focusedChapterIndex == cIndex &&
                                                      _focusedTopicIndex == null
                                                  ? Icons.center_focus_strong_rounded
                                                  : Icons.center_focus_weak_rounded,
                                              size: 18,
                                              color: _focusedChapterIndex == cIndex
                                                  ? const Color(0xFF10B981)
                                                  : const Color(0xFF6366F1),
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                if (_focusedChapterIndex == cIndex &&
                                                    _focusedTopicIndex == null) {
                                                  _focusedChapterIndex = null;
                                                } else {
                                                  _focusedChapterIndex = cIndex;
                                                  _focusedTopicIndex = null;
                                                  _expandedKeys.add(chapterKey);
                                                }
                                              });
                                            },
                                            tooltip: _focusedChapterIndex == cIndex
                                                ? 'Exit Chapter Focus'
                                                : 'Focus Chapter (Double-Tap)',
                                          ),
                                          _buildItemPopupMenu(
                                            type: 'Chapter',
                                            item: chapter,
                                            onMoveUp: cIndex > 0
                                                ? () => _moveChapter(cIndex, true)
                                                : null,
                                            onMoveDown: cIndex < _syllabus.length - 1
                                                ? () => _moveChapter(cIndex, false)
                                                : null,
                                            onManageResources: () =>
                                                _manageResources(chapter),
                                            onDelete: () {
                                              setState(() {
                                                _syllabus.removeAt(cIndex);
                                                _focusedChapterIndex = null;
                                                _hasChanges = true;
                                              });
                                              _saveSyllabus();
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    children: [
                                      for (
                                        int tIndex = 0;
                                        tIndex < topics.length;
                                        tIndex++
                                      ) ...[
                                        Builder(
                                          builder: (context) {
                                            if (_focusedTopicIndex != null &&
                                                tIndex != _focusedTopicIndex) {
                                              return const SizedBox.shrink();
                                            }

                                            final topic = topics[tIndex];
                                            final topicKey = 'c_${cIndex}_t_$tIndex';
                                            final isTopicExpanded = _expandedKeys
                                                .contains(topicKey);
                                            final subTopics =
                                                topic['subTopics'] ?? [];

                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                left: 16.0,
                                              ),
                                              child: ExpansionTile(
                                                key: Key(
                                                  'topic_${cIndex}_${tIndex}_$isTopicExpanded',
                                                ),
                                                initiallyExpanded: isTopicExpanded,
                                                onExpansionChanged: (expanded) {
                                                  setState(() {
                                                    if (expanded) {
                                                      _expandedKeys.add(topicKey);
                                                    } else {
                                                      _expandedKeys.remove(topicKey);
                                                    }
                                                  });
                                                },
                                                iconColor: context.textColor70,
                                                collapsedIconColor: context.textColor60,
                                                title: GestureDetector(
                                                  onDoubleTap: () {
                                                    setState(() {
                                                      _focusedChapterIndex = cIndex;
                                                      _focusedTopicIndex = tIndex;
                                                      _expandedKeys.add(topicKey);
                                                    });
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          'Focused on Topic: ${_cleanSingleLine(topic['title'])}',
                                                        ),
                                                        backgroundColor: const Color(0xFF6366F1),
                                                        duration: const Duration(seconds: 1),
                                                      ),
                                                    );
                                                  },
                                                  child: Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.topic,
                                                        color: Color(0xFF3B82F6),
                                                        size: 18,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          topic['title'] ?? '',
                                                          style: TextStyle(
                                                            color: context.textColor,
                                                          ),
                                                        ),
                                                      ),
                                                      IconButton(
                                                        icon: Icon(
                                                          _focusedTopicIndex == tIndex
                                                              ? Icons.center_focus_strong_rounded
                                                              : Icons.center_focus_weak_rounded,
                                                          size: 16,
                                                          color: _focusedTopicIndex == tIndex
                                                              ? const Color(0xFF10B981)
                                                              : const Color(0xFF6366F1),
                                                        ),
                                                        onPressed: () {
                                                          setState(() {
                                                            if (_focusedTopicIndex == tIndex) {
                                                              _focusedTopicIndex = null;
                                                            } else {
                                                              _focusedChapterIndex = cIndex;
                                                              _focusedTopicIndex = tIndex;
                                                              _expandedKeys.add(topicKey);
                                                            }
                                                          });
                                                        },
                                                        tooltip: _focusedTopicIndex == tIndex
                                                            ? 'Exit Topic Focus'
                                                            : 'Focus Topic (Double-Tap)',
                                                      ),
                                                      _buildItemPopupMenu(
                                                        type: 'Topic',
                                                        item: topic,
                                                        onMoveUp: tIndex > 0
                                                            ? () => _moveTopic(
                                                                  cIndex,
                                                                  tIndex,
                                                                  true,
                                                                )
                                                            : null,
                                                        onMoveDown: tIndex < topics.length - 1
                                                            ? () => _moveTopic(
                                                                  cIndex,
                                                                  tIndex,
                                                                  false,
                                                                )
                                                            : null,
                                                        onManageResources: () =>
                                                            _manageResources(topic),
                                                        onDelete: () {
                                                          setState(() {
                                                            topics.removeAt(tIndex);
                                                            _hasChanges = true;
                                                          });
                                                          _saveSyllabus();
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                children: [
                                                  for (
                                                    int sIndex = 0;
                                                    sIndex < subTopics.length;
                                                    sIndex++
                                                  )
                                                    ListTile(
                                                      leading: Icon(
                                                  Icons
                                                      .subdirectory_arrow_right,
                                                  color: context.textColor54
                                                      .withOpacity(0.5),
                                                  size: 16,
                                                ),
                                                title: Text(
                                                  subTopics[sIndex]['title'] ??
                                                      '',
                                                  style: TextStyle(
                                                    color: context.textColor70,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                trailing: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    _buildItemPopupMenu(
                                                      type: 'Sub-topic',
                                                      item: subTopics[sIndex],
                                                      onMoveUp: sIndex > 0
                                                          ? () => _moveSubTopic(
                                                                cIndex,
                                                                tIndex,
                                                                sIndex,
                                                                true,
                                                              )
                                                          : null,
                                                      onMoveDown: sIndex < subTopics.length - 1
                                                          ? () => _moveSubTopic(
                                                                cIndex,
                                                                tIndex,
                                                                sIndex,
                                                                false,
                                                              )
                                                          : null,
                                                      onManageResources: () =>
                                                          _manageResources(
                                                        subTopics[sIndex],
                                                      ),
                                                      onDelete: () {
                                                        setState(() {
                                                          subTopics.removeAt(sIndex);
                                                          _hasChanges = true;
                                                        });
                                                        _saveSyllabus();
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ListTile(
                                              contentPadding:
                                                  const EdgeInsets.only(
                                                    left: 64,
                                                  ),
                                              title: TextButton.icon(
                                                onPressed: () => _addSubTopic(
                                                  cIndex,
                                                  tIndex,
                                                ),
                                                icon: const Icon(
                                                  Icons.add,
                                                  size: 16,
                                                  color: Color(0xFF10B981),
                                                ),
                                                label: const Text(
                                                  'Add Sub-topic',
                                                  style: TextStyle(
                                                    color: Color(0xFF10B981),
                                                  ),
                                                ),
                                                style: TextButton.styleFrom(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                    vertical: 8.0,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: () => _addTopic(cIndex),
                                      icon: const Icon(
                                        Icons.add,
                                        size: 16,
                                        color: Color(0xFF6366F1),
                                      ),
                                      label: const Text(
                                        'Add Topic',
                                        style: TextStyle(
                                          color: Color(0xFF6366F1),
                                        ),
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
          ).animate().fade(duration: 400.ms),
          floatingActionButton: _syllabus.isNotEmpty
              ? FloatingActionButton.extended(
                  backgroundColor: const Color(0xFF6366F1),
                  onPressed: _addChapter,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text(
                    'Add Chapter',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ).animate().scale(delay: 500.ms)
              : null,
        ),
      ),
    );
  }

  void _manageResources(Map<String, dynamic> node) async {
    final state = context.read<CourseBloc>().state;
    int grade = 10;
    if (state is CourseLoaded) {
      final course = state.courses.firstWhere(
        (c) => c['id'] == widget.courseId,
        orElse: () => null,
      );
      if (course != null) {
        final gradeStr = course['grade']?.toString() ?? '';
        final match = RegExp(r'\d+').firstMatch(gradeStr);
        grade = match != null ? int.tryParse(match.group(0)!) ?? 10 : 10;
      }
    }

    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SyllabusResourceEditor(item: node, grade: grade),
    );

    if (updated != null) {
      setState(() {
        node['videos'] = updated['videos'];
        node['slides'] = updated['slides'];
        node['practiceQuestions'] = updated['practiceQuestions'];
        node['practiceSets'] = updated['practiceSets'];
        _hasChanges = true;
      });
      _saveSyllabus();
    }
  }
}

class SyllabusResourceEditor extends StatefulWidget {
  final Map<String, dynamic> item;
  final int grade;

  const SyllabusResourceEditor({
    super.key,
    required this.item,
    required this.grade,
  });

  @override
  State<SyllabusResourceEditor> createState() => _SyllabusResourceEditorState();
}

class _SyllabusResourceEditorState extends State<SyllabusResourceEditor>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _videos = [];
  List<dynamic> _slides = [];
  List<dynamic> _practiceQuestions = [];
  List<dynamic> _practiceSets = [];

  bool _loadingQuestions = true;
  List<dynamic> _allGradeQuestions = [];

  late String _initialVideosJson;
  late String _initialSlidesJson;
  late String _initialQuestionsJson;
  late String _initialSetsJson;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _videos = List.from(widget.item['videos'] ?? []);
    _slides = List.from(widget.item['slides'] ?? []);
    _practiceQuestions = List.from(widget.item['practiceQuestions'] ?? []);

    final List<dynamic> rawSets = widget.item['practiceSets'] ?? [];
    if (rawSets.isEmpty) {
      final List<dynamic> legacyQuestions =
          widget.item['practiceQuestions'] ?? [];
      if (legacyQuestions.isNotEmpty) {
        _practiceSets = [
          {'title': 'Level 0', 'questions': List.from(legacyQuestions)},
        ];
      } else {
        _practiceSets = [];
      }
    } else {
      _practiceSets = rawSets
          .map(
            (s) => {
              'title': s['title'] ?? 'Level 0',
              'questions': List.from(s['questions'] ?? []),
            },
          )
          .toList();
    }

    _initialVideosJson = jsonEncode(_videos);
    _initialSlidesJson = jsonEncode(_slides);
    _initialQuestionsJson = jsonEncode(_practiceQuestions);
    _initialSetsJson = jsonEncode(_practiceSets);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String? _extractYoutubeId(String url) {
    final regExp = RegExp(
      r'^.*(youtu.be\/|v\/|u\/\w\/|embed\/|watch\?v=|\&v=)([^#\&\?]*).*',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(url);
    if (match != null && match.group(2)!.length == 11) {
      return match.group(2);
    }
    return null;
  }

  void _editVideoDialog({
    Map<String, dynamic>? initialVideo,
    int? index,
  }) async {
    final titleCtrl = TextEditingController(text: initialVideo?['title'] ?? '');
    final urlCtrl = TextEditingController(text: initialVideo?['url'] ?? '');

    void submit() {
      final title = titleCtrl.text.trim();
      final url = urlCtrl.text.trim();
      if (title.isEmpty || url.isEmpty) return;
      Navigator.pop(context);
      setState(() {
        final videoData = {'title': title, 'url': url};
        if (index != null) {
          _videos[index] = videoData;
        } else {
          _videos.add(videoData);
        }
      });
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark
            ? const Color(0xFF1E293B)
            : Colors.white,
        title: Text(
          initialVideo == null ? 'Add Video' : 'Edit Video',
          style: TextStyle(color: context.textColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(
                labelText: 'Video Title',
                labelStyle: TextStyle(color: context.textColor60),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: context.textColor54.withOpacity(0.3),
                  ),
                ),
              ),
              style: TextStyle(color: context.textColor),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              decoration: InputDecoration(
                labelText: 'Video URL',
                labelStyle: TextStyle(color: context.textColor60),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: context.textColor54.withOpacity(0.3),
                  ),
                ),
              ),
              style: TextStyle(color: context.textColor),
              onSubmitted: (_) => submit(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: context.textColor60)),
          ),
          ElevatedButton(
            onPressed: submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _editSlideDialog({
    Map<String, dynamic>? initialSlide,
    int? index,
  }) async {
    final titleCtrl = TextEditingController(text: initialSlide?['title'] ?? '');
    final contentCtrl = TextEditingController(
      text: initialSlide?['content'] ?? '',
    );
    String imageUrl = initialSlide?['image'] ?? '';
    bool isUploading = false;

    void submitSlide() {
      final title = titleCtrl.text.trim();
      if (title.isEmpty) return;
      Navigator.pop(context);
      setState(() {
        final slideData = {
          'title': title,
          'content': contentCtrl.text.trim(),
          'image': imageUrl,
        };
        if (index != null) {
          _slides[index] = slideData;
        } else {
          _slides.add(slideData);
        }
      });
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> _pickAndUploadImage() async {
              setDialogState(() => isUploading = true);
              try {
                final result = await FilePicker.pickFiles(type: FileType.image);
                if (result != null && result.files.single.bytes != null) {
                  final bytes = result.files.single.bytes!;
                  final filename = result.files.single.name;
                  final res = await ApiService.uploadFile(
                    '/assessment-questions/upload',
                    bytes,
                    filename,
                    fieldName: 'file',
                  );
                  if (res.statusCode == 200) {
                    final response = await http.Response.fromStream(res);
                    final data = jsonDecode(response.body);
                    setDialogState(() {
                      imageUrl = data['fileUrl'];
                    });
                  }
                }
              } catch (e) {
                debugPrint('Upload error: $e');
              } finally {
                setDialogState(() => isUploading = false);
              }
            }

            return AlertDialog(
              backgroundColor: context.isDark
                  ? const Color(0xFF1E293B)
                  : Colors.white,
              title: Text(
                initialSlide == null ? 'Add Slide' : 'Edit Slide',
                style: TextStyle(color: context.textColor),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: InputDecoration(
                        labelText: 'Slide Title',
                        labelStyle: TextStyle(color: context.textColor60),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: context.textColor54.withOpacity(0.3),
                          ),
                        ),
                      ),
                      style: TextStyle(color: context.textColor),
                      onSubmitted: (_) => submitSlide(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: contentCtrl,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Slide Content',
                        labelStyle: TextStyle(color: context.textColor60),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: context.textColor54.withOpacity(0.3),
                          ),
                        ),
                      ),
                      style: TextStyle(color: context.textColor),
                    ),
                    const SizedBox(height: 20),
                    if (imageUrl.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          'https://api.jyamitimath.com/$imageUrl',
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image, size: 50),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    ElevatedButton.icon(
                      onPressed: isUploading ? null : _pickAndUploadImage,
                      icon: isUploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: JyamitiLoader(strokeWidth: 2),
                            )
                          : const Icon(Icons.image, size: 18),
                      label: Text(
                        imageUrl.isEmpty ? 'Upload Image' : 'Change Image',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: context.textColor60),
                  ),
                ),
                ElevatedButton(
                  onPressed: submitSlide,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                  ),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _hasUnsavedChanges() {
    final currentVideosJson = jsonEncode(_videos);
    final currentSlidesJson = jsonEncode(_slides);
    final currentQuestionsJson = jsonEncode(_practiceQuestions);
    final currentSetsJson = jsonEncode(_practiceSets);

    return currentVideosJson != _initialVideosJson ||
        currentSlidesJson != _initialSlidesJson ||
        currentQuestionsJson != _initialQuestionsJson ||
        currentSetsJson != _initialSetsJson;
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges()) {
      return true;
    }

    final nav = Navigator.of(context);
    final String? action = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Text(
            'Unsaved Changes',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'You have unsaved changes to resources. Would you like to save them before closing?',
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: Text(
                'Cancel',
                style: TextStyle(color: context.textColor60),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text(
                'Discard',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
              ),
              child: const Text(
                'Save',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (action == 'save') {
      nav.pop({
        'videos': _videos,
        'slides': _slides,
        'practiceQuestions': _practiceQuestions,
        'practiceSets': _practiceSets,
      });
      return false;
    } else if (action == 'discard') {
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Dialog(
        backgroundColor: context.isDark
            ? const Color(0xFF0F172A)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Resources: ${widget.item['title']}',
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: context.textColor60),
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      final shouldPop = await _onWillPop();
                      if (shouldPop) {
                        nav.pop();
                      }
                    },
                  ),
                ],
              ),
              TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF6366F1),
                unselectedLabelColor: context.textColor60,
                indicatorColor: const Color(0xFF6366F1),
                tabs: const [
                  Tab(icon: Icon(Icons.video_library), text: 'Videos'),
                  Tab(icon: Icon(Icons.slideshow), text: 'Slides'),
                  Tab(icon: Icon(Icons.assignment), text: 'Practice'),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildVideosTab(),
                    _buildSlidesTab(),
                    _buildQuestionsTab(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      final shouldPop = await _onWillPop();
                      if (shouldPop) {
                        nav.pop();
                      }
                    },
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: context.textColor60),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context, {
                        'videos': _videos,
                        'slides': _slides,
                        'practiceQuestions': _practiceQuestions,
                        'practiceSets': _practiceSets,
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Save Resources',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideosTab() {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _editVideoDialog(),
            icon: const Icon(Icons.add, size: 16, color: Color(0xFF6366F1)),
            label: const Text(
              'Add Video',
              style: TextStyle(color: Color(0xFF6366F1)),
            ),
          ),
        ),
        Expanded(
          child: _videos.isEmpty
              ? Center(
                  child: Text(
                    'No videos added.',
                    style: TextStyle(color: context.textColor60),
                  ),
                )
              : ListView.builder(
                  itemCount: _videos.length,
                  itemBuilder: (context, index) {
                    final video = _videos[index];
                    return ListTile(
                      leading: const Icon(
                        Icons.play_circle_fill,
                        color: Colors.red,
                        size: 30,
                      ),
                      title: Text(
                        video['title'] ?? '',
                        style: TextStyle(
                          color: context.textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        video['url'] ?? '',
                        style: TextStyle(
                          color: context.textColor60,
                          fontSize: 12,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.play_circle_fill_rounded,
                              color: Colors.red,
                              size: 22,
                            ),
                            tooltip: 'Watch Video',
                            onPressed: () {
                              final videoId = _extractYoutubeId(
                                video['url'] ?? '',
                              );
                              if (videoId == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Invalid YouTube URL'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VideoPlayerScreen(
                                    videoId: videoId,
                                    title: video['title'] ?? 'Video Preview',
                                  ),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () => _editVideoDialog(
                              initialVideo: video,
                              index: index,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              size: 18,
                              color: Colors.redAccent,
                            ),
                            onPressed: () =>
                                setState(() => _videos.removeAt(index)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSlidesTab() {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: () async {
              final topicTitle = widget.item['title'] ?? 'Topic Slide Deck';
              final initialDeck = SlideDeck(
                id: 'deck_${DateTime.now().millisecondsSinceEpoch}',
                courseId: 'course_${widget.grade}',
                courseName: 'Grade ${widget.grade} Mathematics',
                title: '$topicTitle - Learning Slides',
                description: 'Interactive slide deck for $topicTitle.',
                slides: [
                  SlideItem(
                    id: 's1',
                    slideIndex: 0,
                    title: 'Welcome to $topicTitle',
                    theme: 'darkGlass',
                    blocks: [
                      SlideBlock(
                        id: 'b1',
                        type: SlideBlockType.heading,
                        content: topicTitle,
                      ),
                      SlideBlock(
                        id: 'b2',
                        type: SlideBlockType.paragraph,
                        content:
                            'Enter main lesson notes and explanations here.',
                      ),
                    ],
                  ),
                ],
                createdAt: DateTime.now(),
              );

              await cms_screen.loadLibrary();
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      cms_screen.AdminSlideCmsScreen(initialDeck: initialDeck),
                ),
              );

              setState(() {
                _slides.add(initialDeck.toMap());
              });
            },
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Create Slide Deck in CMS'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _slides.isEmpty
              ? Center(
                  child: Text(
                    'No slide decks added yet.',
                    style: TextStyle(color: context.textColor60),
                  ),
                )
              : ListView.builder(
                  itemCount: _slides.length,
                  itemBuilder: (context, index) {
                    final slideData = _slides[index];
                    final SlideDeck deck =
                        slideData is Map<String, dynamic> &&
                            slideData.containsKey('slides')
                        ? SlideDeck.fromMap(slideData)
                        : SlideDeck(
                            id: 'deck_$index',
                            courseId: 'c101',
                            courseName: 'Mathematics',
                            title:
                                slideData['title'] ?? 'Slide Deck ${index + 1}',
                            description:
                                slideData['content'] ?? 'Topic slide deck',
                            createdAt: DateTime.now(),
                            slides: [
                              SlideItem(
                                id: 's_$index',
                                slideIndex: 0,
                                title: slideData['title'] ?? 'Slide 1',
                                blocks: [
                                  SlideBlock(
                                    id: 'b1',
                                    type: SlideBlockType.heading,
                                    content: slideData['title'] ?? '',
                                  ),
                                  SlideBlock(
                                    id: 'b2',
                                    type: SlideBlockType.paragraph,
                                    content: slideData['content'] ?? '',
                                  ),
                                ],
                              ),
                            ],
                          );

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      color: context.isDark
                          ? const Color(0xFF1E293B)
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFF6366F1),
                          child: Icon(
                            Icons.slideshow_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          deck.title,
                          style: TextStyle(
                            color: context.textColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          '${deck.slides.length} slides • ${deck.courseName}',
                          style: TextStyle(
                            color: context.textColor60,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.play_circle_fill_rounded,
                                color: Color(0xFF10B981),
                                size: 22,
                              ),
                              tooltip: 'Live Student Preview',
                              onPressed: () async {
                                await student_viewer_screen.loadLibrary();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        student_viewer_screen.StudentSlideViewerScreen(
                                          deck: deck,
                                        ),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.edit_note_rounded,
                                color: Color(0xFF6366F1),
                                size: 22,
                              ),
                              tooltip: 'Open CMS Editor',
                              onPressed: () async {
                                await cms_screen.loadLibrary();
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        cms_screen.AdminSlideCmsScreen(
                                          initialDeck: deck,
                                        ),
                                  ),
                                );
                                setState(() {
                                  _slides[index] = deck.toMap();
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.analytics_outlined,
                                color: Color(0xFF0EA5E9),
                                size: 20,
                              ),
                              tooltip: 'View Analytics',
                              onPressed: () async {
                                await analytics_screen.loadLibrary();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        analytics_screen.AdminSlideAnalyticsScreen(
                                          deck: deck,
                                        ),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                                color: Colors.redAccent,
                              ),
                              tooltip: 'Delete Deck',
                              onPressed: () =>
                                  setState(() => _slides.removeAt(index)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildQuestionsTab() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Practice Sets (${_practiceSets.length}):',
              style: TextStyle(
                color: context.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _practiceSets.add({
                    'title': 'Level ${_practiceSets.length}',
                    'questions': [],
                  });
                });
              },
              icon: const Icon(Icons.add_circle_outline, size: 16),
              label: const Text('Add Practice Set'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _practiceSets.isEmpty
              ? Center(
                  child: Text(
                    'No practice sets created yet.\nClick "Add Practice Set" to begin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.textColor60),
                  ),
                )
              : ListView.builder(
                  itemCount: _practiceSets.length,
                  itemBuilder: (context, setIndex) {
                    final setItem =
                        _practiceSets[setIndex] as Map<String, dynamic>;
                    final String title = setItem['title'] ?? 'Level $setIndex';
                    final List<dynamic> questions = setItem['questions'] ?? [];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: context.isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF8FAFC),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: context.isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.assignment_turned_in_rounded,
                                color: Color(0xFF10B981),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        title,
                                        style: TextStyle(
                                          color: context.textColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 16,
                                        ),
                                        onPressed: () =>
                                            _editSetTitleDialog(setIndex, title),
                                        tooltip: 'Rename Set',
                                        constraints: const BoxConstraints(),
                                        padding: EdgeInsets.zero,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${questions.length} Question(s) inside this set',
                                    style: TextStyle(
                                      color: context.textColor60,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              onPressed: () => _openManageQuestionsDialog(setIndex),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.quiz_rounded, size: 16),
                              label: const Text(
                                'Manage Questions',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              onPressed: () => _deleteSet(setIndex, title),
                              tooltip: 'Delete Practice Set',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _openManageQuestionsDialog(int setIndex) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final setItem = _practiceSets[setIndex] as Map<String, dynamic>;
          final String title = setItem['title'] ?? 'Level $setIndex';
          final List<dynamic> questions = setItem['questions'] ?? [];

          return Dialog(
            backgroundColor: context.isDark ? const Color(0xFF0F172A) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.8,
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.quiz_rounded,
                          color: Color(0xFF6366F1),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Manage Questions: $title',
                              style: TextStyle(
                                color: context.textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${questions.length} Question(s) in this Practice Set',
                              style: TextStyle(
                                color: context.textColor60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final created = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AssessmentQuestionFormScreen(
                                initialGrade: widget.grade,
                                isPracticeMode: true,
                              ),
                            ),
                          );
                          if (created != null) {
                            setState(() {
                              final targetList = _practiceSets[setIndex]['questions'] as List;
                              if (created is List) {
                                targetList.addAll(List<Map<String, dynamic>>.from(created));
                              } else if (created is Map) {
                                targetList.add(Map<String, dynamic>.from(created));
                              }
                            });
                            setDialogState(() {});
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Question', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // Questions List
                  Expanded(
                    child: questions.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.quiz_outlined, size: 48, color: context.textColor54.withOpacity(0.3)),
                                const SizedBox(height: 12),
                                Text(
                                  'No questions in this set yet.',
                                  style: TextStyle(color: context.textColor60, fontSize: 14),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    final created = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AssessmentQuestionFormScreen(
                                          initialGrade: widget.grade,
                                          isPracticeMode: true,
                                        ),
                                      ),
                                    );
                                    if (created != null) {
                                      setState(() {
                                        final targetList = _practiceSets[setIndex]['questions'] as List;
                                        if (created is List) {
                                          targetList.addAll(List<Map<String, dynamic>>.from(created));
                                        } else if (created is Map) {
                                          targetList.add(Map<String, dynamic>.from(created));
                                        }
                                      });
                                      setDialogState(() {});
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(Icons.add_rounded, size: 16),
                                  label: const Text('Add First Question'),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: questions.length,
                            itemBuilder: (context, qIndex) {
                              final q = questions[qIndex] as Map<String, dynamic>;
                              bool parseBool(dynamic val) {
                                if (val == null) return false;
                                if (val is bool) return val;
                                if (val is num) return val != 0;
                                final str = val.toString().toLowerCase().trim();
                                return str == 'true' || str == '1' || str == 'yes';
                              }

                              final bool isClasswork = parseBool(q['isClasswork']) ||
                                  parseBool(q['forTutorOnly']) ||
                                  parseBool(q['isTutorOnly']) ||
                                  (q['category'] ?? q['tag'] ?? '')
                                          .toString()
                                          .toLowerCase()
                                          .trim() ==
                                      'classwork';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: context.isDark
                                      ? const Color(0xFF1E293B)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: context.isDark
                                        ? const Color(0xFF334155)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6366F1).withOpacity(0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '${qIndex + 1}',
                                      style: const TextStyle(
                                        color: Color(0xFF6366F1),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  title: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isClasswork
                                                  ? const Color(0xFF10B981).withOpacity(0.18)
                                                  : const Color(0xFF6366F1).withOpacity(0.14),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: isClasswork
                                                    ? const Color(0xFF10B981).withOpacity(0.5)
                                                    : const Color(0xFF6366F1).withOpacity(0.4),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  isClasswork
                                                      ? Icons.cast_for_education_rounded
                                                      : Icons.school_rounded,
                                                  size: 12,
                                                  color: isClasswork
                                                      ? const Color(0xFF10B981)
                                                      : const Color(0xFF6366F1),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  isClasswork
                                                      ? 'Classwork (Tutor Only)'
                                                      : 'Student Practice',
                                                  style: TextStyle(
                                                    color: isClasswork
                                                        ? const Color(0xFF10B981)
                                                        : const Color(0xFF6366F1),
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        q['text'] ?? '',
                                        style: TextStyle(
                                          color: context.textColor,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Type: ${q['type']} | Marks: ${q['marks'] ?? 1}',
                                      style: TextStyle(
                                        color: context.textColor60,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.play_arrow_rounded,
                                          size: 18,
                                          color: Color(0xFF818CF8),
                                        ),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => AssessmentTakingScreen(trySingleQuestion: q),
                                            ),
                                          );
                                        },
                                        tooltip: 'Try Question',
                                      ),
                                      const SizedBox(width: 2),
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            final newStatus = !isClasswork;
                                            q['isClasswork'] = newStatus;
                                            q['category'] = newStatus ? 'classwork' : 'practice';
                                          });
                                          setDialogState(() {});
                                        },
                                        child: Tooltip(
                                          message: isClasswork
                                              ? 'Click to change to Student Practice'
                                              : 'Click to change to Classwork (Tutor Only)',
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isClasswork
                                                  ? const Color(0xFF10B981).withOpacity(0.15)
                                                  : context.textColor.withOpacity(0.06),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: isClasswork
                                                    ? const Color(0xFF10B981).withOpacity(0.4)
                                                    : context.textColor.withOpacity(0.12),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  isClasswork
                                                      ? Icons.check_circle_rounded
                                                      : Icons.add_circle_outline_rounded,
                                                  size: 13,
                                                  color: isClasswork
                                                      ? const Color(0xFF10B981)
                                                      : context.textColor60,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  isClasswork ? 'Classwork' : 'Set Classwork',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: isClasswork
                                                        ? const Color(0xFF10B981)
                                                        : context.textColor60,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 18,
                                          color: Color(0xFF6366F1),
                                        ),
                                        onPressed: () async {
                                          final updated = await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => AssessmentQuestionFormScreen(
                                                initialGrade: widget.grade,
                                                existingQuestion: q,
                                                isPracticeMode: true,
                                              ),
                                            ),
                                          );
                                          if (updated != null) {
                                            setState(() {
                                              if (updated is List) {
                                                // Practice-mode save always pops a list
                                                // (the edited question, plus any Ditto/AI
                                                // variations added while editing).
                                                final updatedList =
                                                    List<Map<String, dynamic>>.from(updated);
                                                if (updatedList.isNotEmpty) {
                                                  questions[qIndex] = updatedList.first;
                                                  if (updatedList.length > 1) {
                                                    questions.addAll(
                                                      updatedList.sublist(1),
                                                    );
                                                  }
                                                }
                                              } else if (updated is Map<String, dynamic>) {
                                                questions[qIndex] = updated;
                                              }
                                            });
                                            setDialogState(() {});
                                          }
                                        },
                                        tooltip: 'Edit Question',
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 18,
                                          color: Colors.redAccent,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            questions.removeAt(qIndex);
                                          });
                                          setDialogState(() {});
                                        },
                                        tooltip: 'Delete Question',
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _editSetTitleDialog(int setIndex, String currentTitle) {
    final titleCtrl = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark
            ? const Color(0xFF1E293B)
            : Colors.white,
        title: Text(
          'Rename Practice Set',
          style: TextStyle(color: context.textColor),
        ),
        content: TextField(
          controller: titleCtrl,
          decoration: InputDecoration(
            labelText: 'Set Label',
            labelStyle: TextStyle(color: context.textColor60),
          ),
          style: TextStyle(color: context.textColor),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: context.textColor60)),
          ),
          ElevatedButton(
            onPressed: () {
              final newTitle = titleCtrl.text.trim();
              if (newTitle.isNotEmpty) {
                setState(() {
                  _practiceSets[setIndex]['title'] = newTitle;
                });
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteSet(int setIndex, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark
            ? const Color(0xFF1E293B)
            : Colors.white,
        title: Text(
          'Delete Practice Set',
          style: TextStyle(color: context.textColor),
        ),
        content: Text(
          'Are you sure you want to delete the set "$title" and all its questions? This cannot be undone.',
          style: TextStyle(color: context.textColor70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: context.textColor60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _practiceSets.removeAt(setIndex);
      });
    }
  }

  void _addQuestionToSet(int setIndex) async {
    final created = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssessmentQuestionFormScreen(
          initialGrade: widget.grade,
          isPracticeMode: true,
        ),
      ),
    );
    if (created != null) {
      setState(() {
        final targetList = _practiceSets[setIndex]['questions'] as List;
        if (created is List) {
          targetList.addAll(List<Map<String, dynamic>>.from(created));
        } else if (created is Map) {
          targetList.add(Map<String, dynamic>.from(created));
        }
      });
    }
  }

  void _editQuestionInSet(
    int setIndex,
    int qIndex,
    Map<String, dynamic> q,
  ) async {
    final updated = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssessmentQuestionFormScreen(
          initialGrade: widget.grade,
          existingQuestion: q,
          isPracticeMode: true,
        ),
      ),
    );
    if (updated != null) {
      setState(() {
        final targetList = _practiceSets[setIndex]['questions'] as List;
        if (updated is List) {
          if (updated.isNotEmpty) {
            targetList[qIndex] = updated[0];
            if (updated.length > 1) {
              targetList.insertAll(
                qIndex + 1,
                List<Map<String, dynamic>>.from(updated.sublist(1)),
              );
            }
          }
        } else if (updated is Map) {
          targetList[qIndex] = Map<String, dynamic>.from(updated);
        }
      });
    }
  }

  void _deleteQuestionFromSet(int setIndex, int qIndex) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark
            ? const Color(0xFF1E293B)
            : Colors.white,
        title: Text(
          'Delete Question',
          style: TextStyle(color: context.textColor),
        ),
        content: Text(
          'Are you sure you want to delete this practice question?',
          style: TextStyle(color: context.textColor70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: context.textColor60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() {
        final targetList = _practiceSets[setIndex]['questions'] as List;
        targetList.removeAt(qIndex);
      });
    }
  }
}
