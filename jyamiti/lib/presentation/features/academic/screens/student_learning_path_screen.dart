import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
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
import 'syllabus_explorer_screen.dart';
import '../../admin/screens/course_syllabus_screen.dart';
import '../../competitions/screens/student_competition_game_screen.dart';

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

    final List<dynamic> sets = item['practiceSets'] ?? [];
    List<Map<String, dynamic>> resolvedSets = [];

    if (sets.isNotEmpty) {
      for (var s in sets) {
        final List<dynamic> rawQuestions = s['questions'] ?? [];
        if (rawQuestions.isNotEmpty) {
          resolvedSets.add({
            'title': s['title'] ?? 'Level 0',
            'questions': rawQuestions,
          });
        }
      }
    } else {
      final List<dynamic> rawQuestions = item['practiceQuestions'] ?? [];
      if (rawQuestions.isNotEmpty) {
        resolvedSets.add({
          'title': 'Practice Quiz',
          'questions': rawQuestions,
        });
      }
    }

    if (resolvedSets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No public practice questions available for this topic.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (resolvedSets.length == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AssessmentTakingScreen(
            practiceQuestions: resolvedSets.first['questions']!,
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: context.glassBorder),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.textColor54.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Select Practice Set',
                  style: TextStyle(
                    color: context.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: resolvedSets.length,
                    itemBuilder: (context, idx) {
                      final s = resolvedSets[idx];
                      return ListTile(
                        leading: const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFF10B981)),
                        title: Text(
                          s['title']!,
                          style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('${s['questions']!.length} questions', style: TextStyle(color: context.textColor60)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AssessmentTakingScreen(
                                practiceQuestions: s['questions']!,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  void _navigateToExplorer(Map<String, dynamic> item, String type, String pathText) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SyllabusExplorerScreen(
          batch: widget.batch,
          categoryItem: item,
          itemType: type,
          breadcrumbText: pathText,
        ),
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
            icon: const Icon(Icons.sports_esports_rounded, color: Color(0xFF6366F1)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StudentCompetitionGameScreen(),
                ),
              );
            },
            tooltip: 'Join Live Arena Competition',
          ),
          IconButton(
            icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF10B981)),
            onPressed: () {
              final courseId = (widget.batch['course'] != null)
                  ? (widget.batch['course']['id'] ?? widget.batch['course']['_id'] ?? widget.batch['courseId'])
                  : (widget.batch['courseId'] ?? widget.batch['id'] ?? widget.batch['_id']);
              final courseName = widget.batch['name'] ?? widget.batch['title'] ?? 'Course';
              if (courseId != null) {
                Navigator.push(
                  context,
                  CourseSyllabusScreen.route(
                    context: context,
                    courseId: courseId.toString(),
                    courseName: courseName.toString(),
                  ),
                );
              }
            },
            tooltip: 'Manage Course / Edit Syllabus',
          ),
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
                child: JyamitiLoader(color: Color(0xFF6366F1)),
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
                itemCount: _syllabus.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildSyllabusProgressHeader();
                  }
                  final cIndex = index - 1;
                  final isTutor = Provider.of<AuthProvider>(context, listen: false).userRole?.toUpperCase() == 'TUTOR';
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
                              title: GestureDetector(
                                onDoubleTap: () {
                                  _navigateToExplorer(
                                    chapter,
                                    'Chapter',
                                    '${widget.batch['name']} > ${chapter['title']}',
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
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    _showResourcesAsList
                                        ? (isTutor ? _buildAssignButtonOnly(chapter) : const SizedBox.shrink())
                                        : _buildItemActions(chapter),
                                  ],
                                ),
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
                                      title: GestureDetector(
                                        onDoubleTap: () {
                                          _navigateToExplorer(
                                            topics[tIndex],
                                            'Topic',
                                            '${widget.batch['name']} > ${chapter['title']} > ${topics[tIndex]['title']}',
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
                                                topics[tIndex]['title'] ?? '',
                                                style: TextStyle(
                                                  color: context.textColor,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      trailing: _showResourcesAsList
                                          ? (isTutor ? _buildAssignButtonOnly(topics[tIndex]) : const SizedBox.shrink())
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
                                                title: GestureDetector(
                                                  onDoubleTap: () {
                                                    _navigateToExplorer(
                                                      topics[tIndex]['subTopics'][sIndex],
                                                      'Sub-topic',
                                                      '${widget.batch['name']} > ${chapter['title']} > ${topics[tIndex]['title']} > ${topics[tIndex]['subTopics'][sIndex]['title']}',
                                                    );
                                                  },
                                                  child: Text(
                                                    topics[tIndex]['subTopics'][sIndex]['title'] ??
                                                        '',
                                                    style: TextStyle(
                                                      color: context.textColor70,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                                trailing: _showResourcesAsList
                                                    ? (isTutor ? _buildAssignButtonOnly(topics[tIndex]['subTopics'][sIndex]) : const SizedBox.shrink())
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
    final List<dynamic> sets = item['practiceSets'] ?? [];
    final hasPractice = questions.isNotEmpty || sets.isNotEmpty;

    if (videos.isEmpty && slides.isEmpty && !hasPractice && !isTutor) {
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
          if (hasPractice)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: const Icon(
                Icons.assignment_turned_in_rounded,
                color: Color(0xFF10B981),
                size: 20,
              ),
              title: Text(
                sets.isNotEmpty
                    ? 'Practice Sets (${sets.length})'
                    : 'Practice Quiz (${questions.length} Qs)',
                style: TextStyle(color: context.textColor70, fontSize: 13),
              ),
              onTap: () => _takePracticeTest(item),
            ),
        ],
      ),
    );
  }

  Widget _buildAssignButtonOnly(Map<String, dynamic> item) {
    return IconButton(
      icon: const Icon(
        Icons.add_task_rounded,
        color: Color(0xFF3B82F6),
        size: 20,
      ),
      onPressed: () => _openAssignDialog(item),
      tooltip: 'Assign Resource',
    );
  }

  Widget _buildItemActions(Map<String, dynamic> item) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isTutor = auth.userRole?.toUpperCase() == 'TUTOR';

    final List<dynamic> videos = item['videos'] ?? [];
    final List<dynamic> slides = item['slides'] ?? [];
    final List<dynamic> questions = item['practiceQuestions'] ?? [];
    final List<dynamic> sets = item['practiceSets'] ?? [];
    final hasPractice = questions.isNotEmpty || sets.isNotEmpty;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildStatusBadge(item, compact: true),
        const SizedBox(width: 4),
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
        if (hasPractice)
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

  Map<String, int> _calculateSyllabusProgress() {
    int total = 0;
    int completed = 0;
    int inProgress = 0;

    void inspectNode(dynamic rawNode) {
      if (rawNode is! Map) return;
      total++;
      final status = (rawNode['status'] ?? 'not_started').toString();
      if (status == 'completed') {
        completed++;
      } else if (status == 'in_progress') {
        inProgress++;
      }

      if (rawNode['topics'] is List) {
        for (var t in rawNode['topics']) inspectNode(t);
      }
      if (rawNode['subTopics'] is List) {
        for (var s in rawNode['subTopics']) inspectNode(s);
      }
    }

    for (var chapter in _syllabus) inspectNode(chapter);

    final percentage = total > 0 ? ((completed / total) * 100).round() : 0;
    return {
      'total': total,
      'completed': completed,
      'inProgress': inProgress,
      'notStarted': total - completed - inProgress,
      'percentage': percentage,
    };
  }

  void _cycleNodeStatus(dynamic node) {
    if (node is! Map) return;
    final isTutor = Provider.of<AuthProvider>(context, listen: false)
            .userRole
            ?.toUpperCase() ==
        'TUTOR';
    if (!isTutor) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Syllabus progress is live-tracked and updated by your assigned Tutor.',
          ),
          backgroundColor: Colors.blueAccent,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final current = (node['status'] ?? 'not_started').toString();
    String nextStatus;
    if (current == 'not_started') {
      nextStatus = 'in_progress';
    } else if (current == 'in_progress') {
      nextStatus = 'completed';
    } else {
      nextStatus = 'not_started';
    }

    setState(() {
      node['status'] = nextStatus;
      if (nextStatus == 'completed') {
        node['completedAt'] = DateTime.now().toIso8601String();
      } else {
        node.remove('completedAt');
      }
    });

    final batchId = widget.batch['id'] ?? widget.batch['_id'];
    if (batchId != null) {
      ApiService.put('/batches/$batchId/syllabus', {'syllabus': _syllabus});
    }
  }

  Widget _buildStatusBadge(dynamic node, {bool compact = false}) {
    final status = (node['status'] ?? 'not_started').toString();
    Color bgColor;
    Color fgColor;
    String label;
    IconData icon;

    if (status == 'completed') {
      bgColor = const Color(0xFF10B981).withValues(alpha: 0.18);
      fgColor = const Color(0xFF10B981);
      label = compact ? 'Completed' : '✓ Completed';
      icon = Icons.check_circle_rounded;
    } else if (status == 'in_progress') {
      bgColor = const Color(0xFFF59E0B).withValues(alpha: 0.18);
      fgColor = const Color(0xFFF59E0B);
      label = compact ? 'In Progress' : '⏳ In Progress';
      icon = Icons.hourglass_top_rounded;
    } else {
      bgColor = context.textColor54.withValues(alpha: 0.12);
      fgColor = context.textColor54;
      label = compact ? 'Not Started' : '⚪ Not Started';
      icon = Icons.radio_button_unchecked_rounded;
    }

    return InkWell(
      onTap: () => _cycleNodeStatus(node),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: fgColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 12 : 14, color: fgColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: fgColor,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyllabusProgressHeader() {
    if (_syllabus.isEmpty) return const SizedBox.shrink();

    final stats = _calculateSyllabusProgress();
    final percentage = stats['percentage'] ?? 0;
    final completed = stats['completed'] ?? 0;
    final total = stats['total'] ?? 0;
    final inProgress = stats['inProgress'] ?? 0;
    final isTutor = Provider.of<AuthProvider>(context, listen: false)
            .userRole
            ?.toUpperCase() ==
        'TUTOR';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            blurRadius: 12,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_graph_rounded,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Syllabus Completion Progress',
                          style: TextStyle(
                            color: context.textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isTutor ? 'Tutor Mode' : 'Live Tracker',
                            style: const TextStyle(
                              color: Color(0xFF6366F1),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$completed of $total syllabus units completed ($inProgress in progress)',
                      style: TextStyle(
                        color: context.textColor60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF10B981)),
                ),
                child: Text(
                  '$percentage%',
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: total > 0 ? (completed / total) : 0.0,
              minHeight: 8,
              backgroundColor: context.textColor54.withValues(alpha: 0.2),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
            ),
          ),
        ],
      ),
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
    if (((item['practiceQuestions'] as List?)?.isNotEmpty ?? false) ||
        ((item['practiceSets'] as List?)?.isNotEmpty ?? false))
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
                              child: JyamitiLoader(
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
