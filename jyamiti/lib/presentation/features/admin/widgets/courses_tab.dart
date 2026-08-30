import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';

import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../providers/auth_provider.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/course/course_bloc.dart';
import '../bloc/course/course_event.dart';
import '../bloc/course/course_state.dart';
import '../screens/course_syllabus_screen.dart';
import '../../academic/screens/student_learning_path_screen.dart';

// ==========================================
// COURSES MANAGEMENT TAB
// ==========================================
class CoursesTab extends StatefulWidget {
  const CoursesTab({super.key});

  @override
  State<CoursesTab> createState() => _CoursesTabState();
}

class _CoursesTabState extends State<CoursesTab> {
  String? _selectedCourseId;
  String? _selectedCourseName;
  String? _exploreCourseId;
  String? _exploreCourseName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CourseBloc>().add(FetchCourses());
    });
  }

  void _triggerRefresh() {
    context.read<CourseBloc>().add(FetchCourses());
  }

  void _createCourse(String name, String desc, String grade, String subject) {
    context.read<CourseBloc>().add(
      CreateCourse(
        title: name,
        description: desc,
        grade: grade,
        subject: subject,
      ),
    );
  }

  void _deleteCourse(String id) {
    context.read<CourseBloc>().add(DeleteCourse(id));
  }

  void _updateCourse(
    String id,
    String name,
    String desc,
    String grade,
    String subject,
  ) {
    context.read<CourseBloc>().add(
      UpdateCourse(
        id: id,
        title: name,
        description: desc,
        grade: grade,
        subject: subject,
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    String itemName,
    VoidCallback onConfirm,
  ) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AlertDialog(
            backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white.withOpacity(0.8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            title: Text(
              'Delete $itemName?',
              style: TextStyle(color: context.textColor),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Please type "$itemName" to confirm deletion.',
                  style: TextStyle(color: context.textColor70),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  style: TextStyle(color: context.textColor),
                  decoration: InputDecoration(
                    labelText: 'Confirm Name',
                    labelStyle: TextStyle(color: context.textColor54),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: context.glassBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.redAccent),
                    ),
                  ),
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
                  backgroundColor: Colors.redAccent.withOpacity(0.8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  if (controller.text.trim() == itemName) {
                    Navigator.pop(ctx);
                    onConfirm();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Name does not match!'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                },
                child: const Text('Delete'),
              ),
            ],
          ).animate().fade().scale(begin: const Offset(0.9, 0.9)),
        );
      },
    );
  }

  void _showAddCourseDialog() {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final gradeController = TextEditingController();
    final subjectController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AlertDialog(
            backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white.withOpacity(0.8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            title: Text(
              'Add New Course',
              style: TextStyle(color: context.textColor),
            ),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    style: TextStyle(color: context.textColor),
                    decoration: InputDecoration(
                      labelText: 'Course Name (e.g. Class 10 Math)',
                      labelStyle: TextStyle(color: context.textColor70),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: gradeController,
                          style: TextStyle(color: context.textColor),
                          decoration: InputDecoration(
                            labelText: 'Grade/Class',
                            labelStyle: TextStyle(color: context.textColor70),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: subjectController,
                          style: TextStyle(color: context.textColor),
                          decoration: InputDecoration(
                            labelText: 'Subject',
                            labelStyle: TextStyle(color: context.textColor70),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descController,
                    style: TextStyle(color: context.textColor),
                    decoration: InputDecoration(
                      labelText: 'Description',
                      labelStyle: TextStyle(color: context.textColor70),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1).withOpacity(0.8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    _createCourse(
                      nameController.text.trim(),
                      descController.text.trim(),
                      gradeController.text.trim(),
                      subjectController.text.trim(),
                    );
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Create'),
              ),
            ],
          ).animate().fade().scale(begin: const Offset(0.9, 0.9)),
        );
      },
    );
  }

  void _showEditCourseDialog(Map<String, dynamic> course) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: course['name']);
    final descController = TextEditingController(text: course['description']);
    final gradeController = TextEditingController(text: course['grade']);
    final subjectController = TextEditingController(text: course['subject']);

    showDialog(
      context: context,
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AlertDialog(
            backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white.withOpacity(0.8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            title: Text(
              'Edit Course',
              style: TextStyle(color: context.textColor),
            ),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    style: TextStyle(color: context.textColor),
                    decoration: InputDecoration(
                      labelText: 'Course Name (e.g. Class 10 Math)',
                      labelStyle: TextStyle(color: context.textColor70),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: gradeController,
                          style: TextStyle(color: context.textColor),
                          decoration: InputDecoration(
                            labelText: 'Grade/Class',
                            labelStyle: TextStyle(color: context.textColor70),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: subjectController,
                          style: TextStyle(color: context.textColor),
                          decoration: InputDecoration(
                            labelText: 'Subject',
                            labelStyle: TextStyle(color: context.textColor70),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descController,
                    style: TextStyle(color: context.textColor),
                    decoration: InputDecoration(
                      labelText: 'Description',
                      labelStyle: TextStyle(color: context.textColor70),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:  Text(
                  'Cancel',
                  style: TextStyle(color: context.textColor60),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1).withOpacity(0.8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    _updateCourse(
                      course['id'],
                      nameController.text.trim(),
                      descController.text.trim(),
                      gradeController.text.trim(),
                      subjectController.text.trim(),
                    );
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ).animate().fade().scale(begin: const Offset(0.9, 0.9)),
        );
      },
    );
  }

  void _showCourseDetails(Map<String, dynamic> course) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;
    int chaptersCount = (course['syllabus'] as List?)?.length ?? 0;
    int topicsCount = 0;
    int subTopicsCount = 0;
    int videosCount = 0;
    int slidesCount = 0;
    int questionsCount = 0;

    int getQuestionsCount(Map<dynamic, dynamic> it) {
      int count = 0;
      final sets = it['practiceSets'] as List?;
      if (sets != null && sets.isNotEmpty) {
        for (var s in sets) {
          if (s is Map) {
            count += (s['questions'] as List?)?.length ?? 0;
          }
        }
      } else {
        count += (it['practiceQuestions'] as List?)?.length ?? 0;
      }
      return count;
    }

    if (course['syllabus'] != null) {
      for (var ch in course['syllabus']) {
        videosCount += (ch['videos'] as List?)?.length ?? 0;
        slidesCount += (ch['slides'] as List?)?.length ?? 0;
        questionsCount += getQuestionsCount(ch);
        
        final topics = ch['topics'] as List?;
        if (topics != null) {
          topicsCount += topics.length;
          for (var tp in topics) {
            videosCount += (tp['videos'] as List?)?.length ?? 0;
            slidesCount += (tp['slides'] as List?)?.length ?? 0;
            questionsCount += getQuestionsCount(tp);
            
            final subTopics = tp['subTopics'] as List?;
            if (subTopics != null) {
              subTopicsCount += subTopics.length;
              for (var stp in subTopics) {
                videosCount += (stp['videos'] as List?)?.length ?? 0;
                slidesCount += (stp['slides'] as List?)?.length ?? 0;
                questionsCount += getQuestionsCount(stp);
              }
            }
          }
        }
      }
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Dialog(
            backgroundColor: context.isDark ? const Color(0xFF0F172A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: context.isDark 
                    ? const Color(0xFF8B5CF6).withOpacity(0.3) 
                    : const Color(0xFF8B5CF6).withOpacity(0.15)
              ),
            ),
            child: Container(
              width: isDesktop ? 700 : (screenWidth > 600 ? 550 : screenWidth * 0.95),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (course['grade'] != null && course['grade'].isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6).withOpacity(context.isDark ? 0.15 : 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(context.isDark ? 0.3 : 0.2)),
                                ),
                                child: Text(
                                  'Grade ${course['grade']} • ${course['subject'] ?? ''}',
                                  style: TextStyle(
                                    color: context.isDark ? const Color(0xFFD8B4FE) : const Color(0xFF6D28D9),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              course['name'] ?? '',
                              style: TextStyle(color: context.textColor, fontSize: 20, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: context.textColor60),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Description
                  if (course['description'] != null && course['description'].isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.01),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.textColor.withOpacity(0.05)),
                      ),
                      child: Text(
                        course['description'],
                        style: TextStyle(color: context.textColor70, fontSize: 13, height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Stats dashboard grid (2x3)
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Course Overview',
                            style: TextStyle(color: context.textColor, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: isDesktop ? 3 : 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: isDesktop ? 2.5 : 2.2,
                            children: [
                              _buildStatCard('Chapters', chaptersCount.toString(), Icons.menu_book, const Color(0xFF8B5CF6)),
                              _buildStatCard('Topics / Subtopics', '$topicsCount / $subTopicsCount', Icons.topic, const Color(0xFF3B82F6)),
                              _buildStatCard('Attached Videos', videosCount.toString(), Icons.play_circle_fill_rounded, Colors.redAccent),
                              _buildStatCard('Slides', slidesCount.toString(), Icons.slideshow_rounded, const Color(0xFFEC4899)),
                              _buildStatCard('Practice Quizzes', questionsCount.toString(), Icons.assignment_turned_in_rounded, const Color(0xFF10B981)),
                              _buildStatCard('Batches Assigned', (course['batchCount'] ?? 0).toString(), Icons.school_rounded, const Color(0xFFF59E0B)),
                            ],
                          ),
                          const SizedBox(height: 20),
                          
                          // Read-only syllabus overview tree
                          if (course['syllabus'] != null && (course['syllabus'] as List).isNotEmpty) ...[
                            Text(
                              'Syllabus Structure',
                              style: TextStyle(color: context.textColor, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.isDark ? Colors.white.withOpacity(0.01) : Colors.black.withOpacity(0.01),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: context.textColor.withOpacity(0.05)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var ch in course['syllabus']) ...[
                                    Row(
                                      children: [
                                        const Icon(Icons.bookmark, color: Color(0xFF8B5CF6), size: 14),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            ch['title'] ?? '',
                                            style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ),
                                        _buildInlineResourceBadges(ch),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    for (var tp in (ch['topics'] ?? [])) ...[
                                      Padding(
                                        padding: const EdgeInsets.only(left: 16.0, bottom: 4),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.topic, color: Color(0xFF3B82F6), size: 12),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                tp['title'] ?? '',
                                                style: TextStyle(color: context.textColor70, fontSize: 12, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            _buildInlineResourceBadges(tp),
                                          ],
                                        ),
                                      ),
                                      for (var stp in (tp['subTopics'] ?? [])) ...[
                                        Padding(
                                          padding: const EdgeInsets.only(left: 32.0, bottom: 4),
                                          child: Row(
                                            children: [
                                              Icon(Icons.subdirectory_arrow_right, color: context.textColor54.withOpacity(0.5), size: 10),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  stp['title'] ?? '',
                                                  style: TextStyle(color: context.textColor60, fontSize: 11),
                                                ),
                                              ),
                                              _buildInlineResourceBadges(stp),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                    const SizedBox(height: 8),
                                  ]
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Actions
                  if (isDesktop)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              setState(() {
                                _selectedCourseId = course['id'];
                                _selectedCourseName = course['name'];
                              });
                            },
                            icon: const Icon(Icons.edit_note_rounded, size: 18),
                            label: const Text('Manage Syllabus'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              setState(() {
                                _exploreCourseId = course['id'];
                                _exploreCourseName = course['name'];
                              });
                            },
                            icon: const Icon(Icons.explore_rounded, size: 18),
                            label: const Text('Explore Syllabus'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showEditCourseDialog(course);
                          },
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Edit Info'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.textColor70,
                            side: BorderSide(color: context.textColor.withOpacity(0.15)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BlocProvider.value(
                                  value: context.read<CourseBloc>(),
                                  child: CourseSyllabusScreen(
                                    courseId: course['id'],
                                    courseName: course['name'],
                                  ),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.edit_note_rounded, size: 18),
                          label: const Text('Manage Syllabus'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StudentLearningPathScreen(
                                  batch: {
                                    'course': {'id': course['id']},
                                    'name': course['name'],
                                  },
                                  isInline: false,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.explore_rounded, size: 18),
                          label: const Text('Explore Syllabus'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showEditCourseDialog(course);
                          },
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Edit Info'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.textColor70,
                            side: BorderSide(color: context.textColor.withOpacity(0.15)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInlineResourceBadges(Map<String, dynamic> item) {
    final int videos = (item['videos'] as List?)?.length ?? 0;
    final int slides = (item['slides'] as List?)?.length ?? 0;
    int practice = 0;
    final List? sets = item['practiceSets'] as List?;
    if (sets != null && sets.isNotEmpty) {
      for (var s in sets) {
        if (s is Map) {
          practice += (s['questions'] as List?)?.length ?? 0;
        }
      }
    } else {
      practice = (item['practiceQuestions'] as List?)?.length ?? 0;
    }
 
    if (videos == 0 && slides == 0 && practice == 0) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 8),
        if (videos > 0) ...[
          Icon(Icons.play_circle_fill_rounded, size: 10, color: Colors.redAccent.withOpacity(0.8)),
          const SizedBox(width: 2),
          Text(videos.toString(), style: TextStyle(fontSize: 9, color: context.textColor60, fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
        ],
        if (slides > 0) ...[
          Icon(Icons.slideshow_rounded, size: 10, color: const Color(0xFFEC4899).withOpacity(0.8)),
          const SizedBox(width: 2),
          Text(slides.toString(), style: TextStyle(fontSize: 9, color: context.textColor60, fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
        ],
        if (practice > 0) ...[
          Icon(Icons.assignment_turned_in_rounded, size: 10, color: const Color(0xFF10B981).withOpacity(0.8)),
          const SizedBox(width: 2),
          Text(practice.toString(), style: TextStyle(fontSize: 9, color: context.textColor60, fontWeight: FontWeight.bold)),
        ],
      ],
    );
  }

  Widget _buildCourseCard(Map<String, dynamic> course, int idx) {
    final grade = course['grade'];
    final subject = course['subject'];
    final hasBadge = grade != null &&
        grade.toString().isNotEmpty &&
        subject != null &&
        subject.toString().isNotEmpty;
    final description = (course['description'] ?? '').toString();
    final animationDelay = (idx % 10) * 50;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: context.glassBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.3)),
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
                child: InkWell(
                  onTap: () => _showCourseDetails(course),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 44, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course['name'] ?? '',
                          style: TextStyle(
                            color: context.textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        if (hasBadge)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withOpacity(context.isDark ? 0.15 : 0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF8B5CF6).withOpacity(context.isDark ? 0.3 : 0.2),
                              ),
                            ),
                            child: Text(
                              '$grade • $subject',
                              style: TextStyle(
                                color: context.isDark ? const Color(0xFFD8B4FE) : const Color(0xFF6D28D9),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Text(
                            description.isEmpty ? 'No description' : description,
                            style: TextStyle(color: context.textColor60, fontSize: 12.5, height: 1.35),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ).animate().fade(duration: 400.ms, delay: animationDelay.ms).slideY(begin: 0.05, end: 0),
        Positioned(
          top: 6,
          right: 6,
          child: _AnimatedCourseActions(
            onManage: () {
              final isLargeScreen = MediaQuery.of(context).size.width > 900;
              if (isLargeScreen) {
                setState(() {
                  _selectedCourseId = course['id'];
                  _selectedCourseName = course['name'];
                });
              } else {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (ctx, animation, secondaryAnimation) => BlocProvider.value(
                      value: context.read<CourseBloc>(),
                      child: CourseSyllabusScreen(
                        courseId: course['id'],
                        courseName: course['name'],
                      ),
                    ),
                    transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                  ),
                );
              }
            },
            onEdit: () => _showEditCourseDialog(course),
            onDelete: () => _confirmDelete(
              context,
              course['name'],
              () => _deleteCourse(course['id']),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.01),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.textColor.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  label,
                  style: TextStyle(color: context.textColor60, fontSize: 9),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CourseBloc, CourseState>(
      listener: (context, state) {
        if (state is CourseOperationSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.green,
            ),
          );
          _triggerRefresh();
        } else if (state is CourseOperationFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      },
      builder: (context, state) {
        final isLargeScreen = MediaQuery.of(context).size.width > 900;
        if (isLargeScreen && _selectedCourseId != null) {
          return CourseSyllabusScreen(
            courseId: _selectedCourseId!,
            courseName: _selectedCourseName!,
            onBack: () {
              setState(() {
                _selectedCourseId = null;
                _selectedCourseName = null;
              });
            },
          );
        }

        if (isLargeScreen && _exploreCourseId != null) {
          return StudentLearningPathScreen(
            batch: {
              'course': {'id': _exploreCourseId},
              'name': _exploreCourseName,
            },
            isInline: true,
            onBack: () {
              setState(() {
                _exploreCourseId = null;
                _exploreCourseName = null;
              });
            },
          );
        }

        bool isLoading = state is CourseLoading || state is CourseInitial;
        List<dynamic> courses = [];
        if (state is CourseLoaded) {
          courses = state.courses;
        }

        if (isLoading) {
          return const Center(
            child: JyamitiLoader(color: Color(0xFF6366F1)),
          );
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: courses.isEmpty
              ? Center(
                  child: Text(
                    'No courses added yet',
                    style: TextStyle(color: context.textColor70),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final crossAxisCount = width > 1300
                        ? 4
                        : (width > 950 ? 3 : (width > 620 ? 2 : 1));
                    return GridView.builder(
                      padding: EdgeInsets.only(
                        top: 24,
                        left: 16,
                        right: 16,
                        bottom: 100,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        mainAxisExtent: 156,
                      ),
                      itemCount: courses.length,
                      itemBuilder: (ctx, idx) =>
                          _buildCourseCard(courses[idx], idx),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: const Color(0xFF6366F1),
            onPressed: _showAddCourseDialog,
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: const Text(
              'Add Course',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ).animate().scale(delay: 500.ms),
        );
      },
    );
  }
}

class _AnimatedCourseActions extends StatefulWidget {
  final VoidCallback onManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AnimatedCourseActions({
    required this.onManage,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_AnimatedCourseActions> createState() => _AnimatedCourseActionsState();
}

class _AnimatedCourseActionsState extends State<_AnimatedCourseActions> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: _isExpanded
                ? (context.isDark
                    ? const Color(0xFF1E293B).withValues(alpha: 0.65)
                    : Colors.white.withValues(alpha: 0.65))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(30),
            border: _isExpanded
                ? Border.all(color: context.glassBorder)
                : null,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: _isExpanded ? 4 : 0,
            vertical: 0,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isExpanded) ...[
                IconButton(
                  icon: const Icon(Icons.menu_book, color: Color(0xFF10B981)),
                  tooltip: 'Manage Syllabus',
                  onPressed: () {
                    setState(() => _isExpanded = false);
                    widget.onManage();
                  },
                ).animate().fade().scale(),
                IconButton(
                  icon: const Icon(
                    Icons.edit_rounded,
                    color: Color(0xFF818CF8),
                  ),
                  tooltip: 'Edit Course',
                  onPressed: () {
                    setState(() => _isExpanded = false);
                    widget.onEdit();
                  },
                ).animate().fade().scale(),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                  ),
                  tooltip: 'Delete',
                  onPressed: () {
                    setState(() => _isExpanded = false);
                    widget.onDelete();
                  },
                ).animate().fade().scale(),
              ],
              IconButton(
                icon: Icon(
                  _isExpanded ? Icons.close_rounded : Icons.more_vert_rounded,
                  color: context.textColor70,
                ),
                onPressed: () {
                  setState(() => _isExpanded = !_isExpanded);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
