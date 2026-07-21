import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'video_player_screen.dart';
import '../../exams/screens/assessment_taking_screen.dart';
import 'package:provider/provider.dart';
import 'package:jyamiti/providers/auth_provider.dart';
import '../../../../services/api_service.dart';
import '../../../../domain/models/slide_deck_models.dart';
import '../../slides/screens/student_slide_viewer_screen.dart' deferred as slide_viewer;

class StudentLearningPathScreen extends StatefulWidget {
  final Map<String, dynamic> batch;
  final bool isInline;
  final VoidCallback? onBack;

  const StudentLearningPathScreen({
    super.key,
    required this.batch,
    this.isInline = false,
    this.onBack,
  });

  @override
  State<StudentLearningPathScreen> createState() =>
      _StudentLearningPathScreenState();
}

class _StudentLearningPathScreenState extends State<StudentLearningPathScreen> {
  bool _isLoading = true;
  bool _showResourcesAsList = false;
  Map<String, dynamic>? _course;
  List<dynamic> _syllabus = [];

  @override
  void initState() {
    super.initState();
    _fetchCourseDetails();
  }

  Future<void> _fetchCourseDetails() async {
    setState(() => _isLoading = true);
    try {
      final courseId =
          widget.batch['course']['id'] ?? widget.batch['course']['_id'];
      final res = await ApiService.get('/courses/$courseId');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _course = data;
          _syllabus = data['syllabus'] ?? [];
        });
      }
    } catch (e) {
      debugPrint('Error fetching course syllabus: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _viewVideos(Map<String, dynamic> item) {
    final List<dynamic> videos = item['videos'] ?? [];
    if (videos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No videos added for this topic yet.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: context.isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Videos: ${item['title']}',
                style: TextStyle(
                  color: context.textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: videos.length,
                  itemBuilder: (context, idx) {
                    final video = videos[idx];
                    return Card(
                      color: context.isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF1F5F9),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        leading: const Icon(
                          Icons.play_circle_fill,
                          color: Colors.red,
                          size: 36,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          final videoId = _extractYoutubeId(video['url'] ?? '');
                          if (videoId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Invalid YouTube URL'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                            return;
                          }
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => VideoPlayerScreen(
                                title: video['title'] ?? '',
                                videoId: videoId,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }



  void _takePracticeTest(Map<String, dynamic> item) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isTeacher =
        auth.userRole?.toUpperCase() == 'TUTOR' ||
        auth.userRole?.toUpperCase() == 'ADMIN' ||
        auth.userRole?.toUpperCase() == 'MENTOR';
    final List<dynamic> rawQuestions = item['practiceQuestions'] ?? [];
    final List<dynamic> questions = isTeacher
        ? rawQuestions
        : rawQuestions
              .where(
                (q) => q['isClasswork'] != true && q['category'] != 'classwork',
              )
              .toList();

    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No public practice questions available for this topic.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AssessmentTakingScreen(practiceQuestions: questions),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isInline,
        leading: widget.isInline && widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onBack,
              )
            : null,
        title: Text(
          'Learning Path: ${widget.batch['name']}',
          style: TextStyle(
            color: context.textColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: context.isDark
            ? const Color(0xFF1E293B)
            : Colors.white.withOpacity(0.85),
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        iconTheme: IconThemeData(color: context.textColor),
        actions: [
          IconButton(
            icon: Icon(
              _showResourcesAsList
                  ? Icons.grid_view_rounded
                  : Icons.list_rounded,
            ),
            onPressed: () {
              setState(() {
                _showResourcesAsList = !_showResourcesAsList;
              });
            },
            tooltip: _showResourcesAsList ? 'Grid View' : 'List View',
          ),
        ],
      ),
      body: Container(
        decoration: widget.isInline
            ? null
            : BoxDecoration(
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
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF6366F1)),
              )
            : _syllabus.isEmpty
            ? Center(
                child: Text(
                  'No syllabus structured for this course yet.',
                  style: TextStyle(color: context.textColor60, fontSize: 16),
                ),
              )
            : ListView.builder(
                padding: EdgeInsets.only(
                  top: kToolbarHeight + MediaQuery.of(context).padding.top + 24,
                  left: 16,
                  right: 16,
                  bottom: 80,
                ),
                itemCount: _syllabus.length,
                itemBuilder: (context, cIndex) {
                  final chapter = _syllabus[cIndex];
                  final topics = chapter['topics'] ?? [];
                  final animationDelay = (cIndex % 10) * 50;

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
                            child: Material(
                              color: Colors.transparent,
                              child: ExpansionTile(
                              iconColor: context.textColor,
                              collapsedIconColor: context.textColor70,
                              title: Row(
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
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  _showResourcesAsList
                                      ? const SizedBox.shrink()
                                      : _buildItemActions(chapter),
                                ],
                              ),
                              children: [
                                if (_showResourcesAsList)
                                  _buildResourceList(chapter),
                                for (
                                  int tIndex = 0;
                                  tIndex < topics.length;
                                  tIndex++
                                )
                                  Padding(
                                    padding: const EdgeInsets.only(left: 16.0),
                                    child: ExpansionTile(
                                      iconColor: context.textColor70,
                                      collapsedIconColor: context.textColor60,
                                      title: Row(
                                        children: [
                                          const Icon(
                                            Icons.topic,
                                            color: Color(0xFF3B82F6),
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              topics[tIndex]['title'] ?? '',
                                              style: TextStyle(
                                                color: context.textColor,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      trailing: _showResourcesAsList
                                          ? const SizedBox.shrink()
                                          : _buildItemActions(topics[tIndex]),
                                      children: [
                                        if (_showResourcesAsList)
                                          _buildResourceList(topics[tIndex]),
                                        for (
                                          int sIndex = 0;
                                          sIndex <
                                              (topics[tIndex]['subTopics'] ??
                                                      [])
                                                  .length;
                                          sIndex++
                                        )
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              ListTile(
                                                contentPadding:
                                                    const EdgeInsets.only(
                                                      left: 48,
                                                      right: 16,
                                                    ),
                                                leading: Icon(
                                                  Icons
                                                      .subdirectory_arrow_right,
                                                  color: context.textColor54
                                                      .withOpacity(0.5),
                                                  size: 16,
                                                ),
                                                title: Text(
                                                  topics[tIndex]['subTopics'][sIndex]['title'] ??
                                                      '',
                                                  style: TextStyle(
                                                    color: context.textColor70,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                trailing: _showResourcesAsList
                                                    ? const SizedBox.shrink()
                                                    : _buildItemActions(
                                                        topics[tIndex]['subTopics'][sIndex],
                                                      ),
                                              ),
                                              if (_showResourcesAsList)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        left: 32.0,
                                                      ),
                                                  child: _buildResourceList(
                                                    topics[tIndex]['subTopics'][sIndex],
                                                  ),
                                                ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            ),
                          ),
                        ),
                      )
                      .animate()
                      .fade(duration: 400.ms, delay: animationDelay.ms)
                      .slideX(begin: 0.1, end: 0);
                },
              ),
      ),
    );
  }

  Widget _buildResourceList(Map<String, dynamic> item) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isTutor = auth.userRole?.toUpperCase() == 'TUTOR';

    final List<dynamic> videos = item['videos'] ?? [];
    final List<dynamic> slides = item['slides'] ?? [];
    final List<dynamic> questions = item['practiceQuestions'] ?? [];

    if (videos.isEmpty && slides.isEmpty && questions.isEmpty && !isTutor) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 32.0, right: 16.0, bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (videos.isNotEmpty)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: const Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.redAccent,
                size: 20,
              ),
              title: Text(
                'Videos (${videos.length})',
                style: TextStyle(color: context.textColor70, fontSize: 13),
              ),
              onTap: () => _viewVideos(item),
            ),
          if (slides.isNotEmpty)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: const Icon(
                Icons.slideshow_rounded,
                color: Color(0xFFEC4899),
                size: 20,
              ),
              title: Text(
                'Learning Slides (${slides.length})',
                style: TextStyle(color: context.textColor70, fontSize: 13),
              ),
              onTap: () => _viewSlides(item),
            ),
          if (questions.isNotEmpty)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: const Icon(
                Icons.assignment_turned_in_rounded,
                color: Color(0xFF10B981),
                size: 20,
              ),
              title: Text(
                'Practice Quiz (${questions.length} Qs)',
                style: TextStyle(color: context.textColor70, fontSize: 13),
              ),
              onTap: () => _takePracticeTest(item),
            ),
          if (isTutor)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: const Icon(
                Icons.add_task_rounded,
                color: Color(0xFF3B82F6),
                size: 20,
              ),
              title: Text(
                'Assign Resource',
                style: TextStyle(color: context.textColor70, fontSize: 13),
              ),
              onTap: () => _openAssignDialog(item),
            ),
        ],
      ),
    );
  }

  Widget _buildItemActions(Map<String, dynamic> item) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isTutor = auth.userRole?.toUpperCase() == 'TUTOR';

    final List<dynamic> videos = item['videos'] ?? [];
    final List<dynamic> slides = item['slides'] ?? [];
    final List<dynamic> questions = item['practiceQuestions'] ?? [];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (videos.isNotEmpty)
          IconButton(
            icon: const Icon(
              Icons.play_circle_fill_rounded,
              color: Colors.redAccent,
              size: 20,
            ),
            onPressed: () => _viewVideos(item),
            tooltip: 'Watch Videos',
          ),
        if (slides.isNotEmpty)
          IconButton(
            icon: const Icon(
              Icons.slideshow_rounded,
              color: Color(0xFFEC4899),
              size: 20,
            ),
            onPressed: () => _viewSlides(item),
            tooltip: 'View Slides',
          ),
        if (questions.isNotEmpty)
          IconButton(
            icon: const Icon(
              Icons.assignment_turned_in_rounded,
              color: Color(0xFF10B981),
              size: 20,
            ),
            onPressed: () => _takePracticeTest(item),
            tooltip: 'Practice Quiz',
          ),
        if (isTutor)
          IconButton(
            icon: const Icon(
              Icons.add_task_rounded,
              color: Color(0xFF3B82F6),
              size: 20,
            ),
            onPressed: () => _openAssignDialog(item),
            tooltip: 'Assign Resource',
          ),
      ],
    );
  }

  void _openAssignDialog(Map<String, dynamic> item) {
    String? selectedType;
    String? selectedStudent;
    DateTime? selectedDate = DateTime.now().add(const Duration(days: 7));
    bool isAssigning = false;

    // Available types to assign
    final Map<String, String> availableTypes = {};
    if ((item['videos'] as List?)?.isNotEmpty ?? false)
      availableTypes['video'] = 'Video';
    if ((item['slides'] as List?)?.isNotEmpty ?? false)
      availableTypes['slide'] = 'Slides';
    if ((item['practiceQuestions'] as List?)?.isNotEmpty ?? false)
      availableTypes['practice_question'] = 'Practice Questions';

    // Always can assign the topic itself
    availableTypes['topic'] = 'Whole Topic';

    if (availableTypes.isNotEmpty) selectedType = availableTypes.keys.first;

    final List<dynamic> students = widget.batch['students'] ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Assign: ${item['title']}',
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Resource Type Dropdown
                  Text(
                    'Resource Type',
                    style: TextStyle(
                      color: context.textColor70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    dropdownColor: context.isDark
                        ? const Color(0xFF1E293B)
                        : Colors.white,
                    style: TextStyle(color: context.textColor),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: context.isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF1F5F9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: availableTypes.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (val) => setModalState(() => selectedType = val),
                  ),
                  const SizedBox(height: 16),

                  // Assign To Dropdown
                  Text(
                    'Assign To',
                    style: TextStyle(
                      color: context.textColor70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: selectedStudent,
                    dropdownColor: context.isDark
                        ? const Color(0xFF1E293B)
                        : Colors.white,
                    style: TextStyle(color: context.textColor),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: context.isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF1F5F9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Whole Batch'),
                      ),
                      ...students.map(
                        (s) => DropdownMenuItem(
                          value: s['_id'],
                          child: Text(s['name'] ?? 'Unknown Student'),
                        ),
                      ),
                    ],
                    onChanged: (val) =>
                        setModalState(() => selectedStudent = val),
                  ),
                  const SizedBox(height: 16),

                  // Due Date
                  Text(
                    'Due Date',
                    style: TextStyle(
                      color: context.textColor70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setModalState(() => selectedDate = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: context.isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            selectedDate == null
                                ? 'Select Date'
                                : '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}',
                            style: TextStyle(color: context.textColor),
                          ),
                          Icon(
                            Icons.calendar_month,
                            color: context.textColor60,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isAssigning
                          ? null
                          : () async {
                              if (selectedType == null || selectedDate == null)
                                return;
                              setModalState(() => isAssigning = true);
                              try {
                                final res = await ApiService.createAssignment({
                                  'batch':
                                      widget.batch['_id'] ?? widget.batch['id'],
                                  'student': selectedStudent,
                                  'itemType': selectedType,
                                  'itemTitle': item['title'],
                                  'itemData': item,
                                  'dueDate': selectedDate!.toIso8601String(),
                                });

                                if (res.statusCode == 201 && mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Successfully assigned resource!',
                                      ),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                } else {
                                  throw Exception('Failed to assign');
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted)
                                  setModalState(() => isAssigning = false);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isAssigning
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Confirm Assignment',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _viewSlides(Map<String, dynamic> item) async {
    final List<dynamic> slidesData = item['slides'] ?? [];
    if (slidesData.isEmpty) return;

    final first = slidesData.first;
    final SlideDeck deck;
    if (first is Map<String, dynamic> && first.containsKey('slides')) {
      deck = SlideDeck.fromMap(first);
    } else {
      final String topicTitle = item['title'] ?? 'Lesson Slides';
      final String courseName =
          widget.batch['courseTitle'] ?? widget.batch['name'] ?? 'Mathematics';
      deck = SlideDeck(
        id: 'deck_${item['title'].hashCode}',
        courseId: widget.batch['_id'] ?? 'course_101',
        courseName: courseName,
        title: '$topicTitle - Slide Deck',
        description: 'Interactive course slides for $topicTitle.',
        createdAt: DateTime.now(),
        slides: slidesData.asMap().entries.map((entry) {
          final idx = entry.key;
          final s = entry.value;
          final title = s['title'] ?? 'Slide ${idx + 1}';
          final content = s['content'] ?? '';
          final img = s['image'] ?? '';
          return SlideItem(
            id: 's_$idx',
            slideIndex: idx,
            title: title,
            theme: 'darkGlass',
            blocks: [
              SlideBlock(
                id: 'b1',
                type: SlideBlockType.heading,
                content: title,
              ),
              if (content.isNotEmpty)
                SlideBlock(
                  id: 'b2',
                  type: SlideBlockType.paragraph,
                  content: content,
                ),
              if (img.toString().isNotEmpty)
                SlideBlock(
                  id: 'b3',
                  type: SlideBlockType.imageUrl,
                  content: 'https://api.jyamitimath.com/$img',
                ),
            ],
          );
        }).toList(),
      );
    }

    await slide_viewer.loadLibrary();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => slide_viewer.StudentSlideViewerScreen(deck: deck)),
    );
  }

  String? _extractYoutubeId(String url) {
    final regExp = RegExp(
      r'(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?)\/|.*[?&]v=)|youtu\.be\/)([^"&?\/\s]{11})',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(url);
    return match?.group(1);
  }
}
