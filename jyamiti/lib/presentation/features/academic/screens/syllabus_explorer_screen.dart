import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:jyamiti/presentation/widgets/inline_youtube_player.dart';
import '../../exams/screens/assessment_taking_screen.dart';
import '../../../../domain/models/slide_deck_models.dart';
import '../../slides/screens/student_slide_viewer_screen.dart';
import '../../admin/screens/course_syllabus_screen.dart';

class ResourceItem {
  final String type; // 'video' | 'slide' | 'quiz'
  final String title;
  final dynamic rawData;

  ResourceItem({
    required this.type,
    required this.title,
    required this.rawData,
  });
}

class SyllabusExplorerScreen extends StatefulWidget {
  final Map<String, dynamic> batch;
  final Map<String, dynamic> categoryItem;
  final String itemType;
  final String breadcrumbText;

  const SyllabusExplorerScreen({
    super.key,
    required this.batch,
    required this.categoryItem,
    required this.itemType,
    required this.breadcrumbText,
  });

  @override
  State<SyllabusExplorerScreen> createState() => _SyllabusExplorerScreenState();
}

class _SyllabusExplorerScreenState extends State<SyllabusExplorerScreen> {
  final List<ResourceItem> _resources = [];
  ResourceItem? _selectedResource;

  @override
  void initState() {
    super.initState();
    _collectResources();
    if (_resources.isNotEmpty) {
      _selectResource(_resources.first);
    }
  }

  void _collectResources() {
    _resources.clear();
    _collectFromItem(widget.categoryItem);
  }

  void _collectFromItem(Map<String, dynamic> item) {
    // Collect directly from this item
    final List<dynamic> videos = item['videos'] ?? [];
    for (var v in videos) {
      _resources.add(ResourceItem(
        type: 'video',
        title: v['title'] ?? 'Video Lecture',
        rawData: v,
      ));
    }

    final List<dynamic> slides = item['slides'] ?? [];
    if (slides.isNotEmpty) {
      _resources.add(ResourceItem(
        type: 'slide',
        title: '${item['title'] ?? 'Lesson'} - Slide Deck',
        rawData: slides,
      ));
    }

    final List<dynamic> sets = item['practiceSets'] ?? [];
    if (sets.isNotEmpty) {
      for (var s in sets) {
        final List<dynamic> questions = s['questions'] ?? [];
        if (questions.isNotEmpty) {
          _resources.add(ResourceItem(
            type: 'quiz',
            title: '${s['title'] ?? 'Practice Set'}',
            rawData: questions,
          ));
        }
      }
    } else {
      final List<dynamic> questions = item['practiceQuestions'] ?? [];
      if (questions.isNotEmpty) {
        _resources.add(ResourceItem(
          type: 'quiz',
          title: '${item['title'] ?? 'Lesson'} - Practice Quiz',
          rawData: questions,
        ));
      }
    }

    // Recursively collect from child topics
    if (item['topics'] != null) {
      for (var topic in item['topics']) {
        _collectFromItem(topic);
      }
    }

    // Recursively collect from child sub-topics
    if (item['subTopics'] != null) {
      for (var sub in item['subTopics']) {
        _collectFromItem(sub);
      }
    }
  }

  void _selectResource(ResourceItem resource) {
    setState(() {
      _selectedResource = resource;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  SlideDeck _buildSlideDeck(List<dynamic> slidesData) {
    final first = slidesData.first;
    if (first is Map<String, dynamic> && first.containsKey('slides')) {
      return SlideDeck.fromMap(first);
    }
    final String topicTitle = widget.categoryItem['title'] ?? 'Lesson Slides';
    final String courseName =
        widget.batch['courseTitle'] ?? widget.batch['name'] ?? 'Mathematics';
    return SlideDeck(
      id: 'deck_${widget.categoryItem['title'].hashCode}',
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

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      extendBodyBehindAppBar: false,
      backgroundColor: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          widget.categoryItem['title'] ?? 'Category Explorer',
          style: TextStyle(
            color: context.textColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 1,
        iconTheme: IconThemeData(color: context.textColor),
        actions: [
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
        ],
      ),
      body: Row(
        children: [
          // Left Sidebar (Resources List)
          Container(
            width: isLargeScreen ? 340 : 260,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: context.isDark 
                      ? Colors.white12 
                      : Colors.black12,
                ),
              ),
              color: context.isDark ? const Color(0xFF111827) : Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Breadcrumbs Header
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.breadcrumbText.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF6366F1),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Category Contents',
                        style: TextStyle(
                          color: context.textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _resources.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              'No lessons or resources available in this category.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: context.textColor54,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _resources.length,
                          itemBuilder: (context, index) {
                            final res = _resources[index];
                            final isSelected = _selectedResource == res;

                            IconData icon;
                            Color iconColor;
                            if (res.type == 'video') {
                              icon = Icons.play_circle_fill_rounded;
                              iconColor = Colors.redAccent;
                            } else if (res.type == 'slide') {
                              icon = Icons.slideshow_rounded;
                              iconColor = const Color(0xFFEC4899);
                            } else {
                              icon = Icons.assignment_turned_in_rounded;
                              iconColor = const Color(0xFF10B981);
                            }

                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF6366F1).withOpacity(0.12)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                dense: true,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                leading: Icon(icon, color: iconColor, size: 22),
                                title: Text(
                                  res.title,
                                  style: TextStyle(
                                    color: isSelected
                                        ? const Color(0xFF6366F1)
                                        : context.textColor,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                ),
                                onTap: () => _selectResource(res),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // Right Panel (Preview / Player Area)
          Expanded(
            child: _selectedResource == null
                ? Center(
                    child: Text(
                      'Select a resource on the left to start learning.',
                      style: TextStyle(color: context.textColor60),
                    ),
                  )
                : Container(
                    color: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedResource!.title,
                          style: TextStyle(
                            color: context.textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Card(
                            elevation: 2,
                            color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: _buildSelectedContent(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedContent() {
    if (_selectedResource!.type == 'video') {
      final videoUrl = _selectedResource!.rawData['url'] ?? '';
      final videoId = YoutubePlayerController.convertUrlToId(videoUrl) ?? '';
      return Column(
        children: [
          Expanded(
            child: InlineYoutubePlayer(
              videoId: videoId,
              videoUrl: videoUrl,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            color: context.isDark ? const Color(0xFF111827) : const Color(0xFFF1F5F9),
            child: Text(
              _selectedResource!.rawData['description'] ?? 'Watch this video lesson to learn about this topic.',
              style: TextStyle(color: context.textColor70, fontSize: 13),
            ),
          ),
        ],
      );
    } else if (_selectedResource!.type == 'slide') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.slideshow_rounded,
                size: 80,
                color: Color(0xFFEC4899),
              ),
              const SizedBox(height: 16),
              Text(
                'Learning Slide Presentation',
                style: TextStyle(
                  color: context.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Explore slides filled with visual concepts, images, and interactive drawings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textColor60, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEC4899),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                label: const Text('Open Presentation Mode', style: TextStyle(color: Colors.white)),
                onPressed: () {
                  final deck = _buildSlideDeck(_selectedResource!.rawData);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StudentSlideViewerScreen(deck: deck),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    } else if (_selectedResource!.type == 'quiz') {
      final questions = _selectedResource!.rawData as List;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.assignment_turned_in_rounded,
                size: 80,
                color: Color(0xFF10B981),
              ),
              const SizedBox(height: 16),
              Text(
                'Interactive Practice Quiz',
                style: TextStyle(
                  color: context.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Test your understanding with ${questions.length} practice questions.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textColor60, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.assignment_rounded, color: Colors.white),
                label: const Text('Start Quiz', style: TextStyle(color: Colors.white)),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AssessmentTakingScreen(practiceQuestions: questions),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
