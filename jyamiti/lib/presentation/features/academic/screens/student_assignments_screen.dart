import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/api_service.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../providers/theme_provider.dart';
import '../../exams/screens/assessment_taking_screen.dart';
import 'student_tutorials_screen.dart';
import 'package:intl/intl.dart';

import 'video_player_screen.dart';

class StudentAssignmentsScreen extends StatefulWidget {
  final bool isInline;
  const StudentAssignmentsScreen({super.key, this.isInline = false});

  @override
  State<StudentAssignmentsScreen> createState() => _StudentAssignmentsScreenState();
}

class _StudentAssignmentsScreenState extends State<StudentAssignmentsScreen> {
  bool _isLoading = true;
  List<dynamic> _assignments = [];

  @override
  void initState() {
    super.initState();
    _fetchAssignments();
  }

  Future<void> _fetchAssignments() async {
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final res = await ApiService.getStudentAssignments(auth.userId ?? '');
      if (res.statusCode == 200) {
        setState(() {
          _assignments = jsonDecode(res.body);
        });
      }
    } catch (e) {
      debugPrint('Error fetching assignments: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String? _extractYoutubeId(String url) {
    final RegExp regExp = RegExp(
      r'^.*(youtu.be\/|v\/|u\/\w\/|embed\/|watch\?v=|\&v=)([^#\&\?]*).*',
      caseSensitive: false,
      multiLine: false,
    );
    final match = regExp.firstMatch(url);
    if (match != null && match.group(2)!.length == 11) {
      return match.group(2);
    }
    return null;
  }

  void _handleStartAssignment(Map<String, dynamic> assignment) {
    final itemData = assignment['itemData'] ?? {};
    final type = assignment['itemType'];

    if (type == 'video') {
      final List<dynamic> videos = itemData['videos'] ?? [];
      if (videos.isEmpty) return;
      final video = videos[0];
      final url = video['url'] ?? '';
      final videoId = _extractYoutubeId(url);
      if (videoId == null) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(
            title: video['title'] ?? assignment['itemTitle'] ?? '',
            videoId: videoId,
            assignmentId: assignment['_id'],
            onCompleted: () {
              _fetchAssignments();
            },
          ),
        ),
      );
    } else if (type == 'slide') {
      final List<dynamic> slides = itemData['slides'] ?? [];
      if (slides.isEmpty) return;

      showDialog(
        context: context,
        builder: (ctx) {
          int currentSlide = 0;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Dialog(
                backgroundColor: context.isDark ? const Color(0xFF0F172A) : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.9,
                  height: MediaQuery.of(context).size.height * 0.7,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              assignment['itemTitle'] ?? '',
                              style: TextStyle(color: context.textColor, fontSize: 18, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: context.textColor60),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: PageView.builder(
                          itemCount: slides.length,
                          onPageChanged: (idx) {
                            setDialogState(() => currentSlide = idx);
                          },
                          itemBuilder: (context, idx) {
                            final slide = slides[idx];
                            final img = slide['image'] ?? '';
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  slide['title'] ?? '',
                                  style: TextStyle(color: context.textColor, fontSize: 20, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                if (img.isNotEmpty) ...[
                                  Expanded(
                                    flex: 3,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Image.network(
                                        'https://api.jyamitimath.com/$img',
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 60),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                Expanded(
                                  flex: 2,
                                  child: SingleChildScrollView(
                                    child: Text(
                                      slide['content'] ?? '',
                                      style: TextStyle(color: context.textColor70, fontSize: 16, height: 1.5),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ],
                            ).animate().fade(duration: 300.ms).slideX(begin: 0.1, end: 0);
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Slide ${currentSlide + 1} of ${slides.length}',
                            style: TextStyle(color: context.textColor60, fontWeight: FontWeight.bold),
                          ),
                          if (currentSlide + 1 == slides.length)
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                              onPressed: () async {
                                Navigator.pop(ctx);
                                try {
                                  final res = await ApiService.completeAssignment(assignment['_id']);
                                  if (res.statusCode == 200) {
                                    _fetchAssignments();
                                  }
                                } catch (e) {
                                  debugPrint('Error completing slides assignment: $e');
                                }
                              },
                              child: const Text('Complete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            )
                          else
                            const Icon(Icons.swipe, size: 18, color: Color(0xFF6366F1)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } else if (type == 'practice_question') {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final isTeacher = auth.userRole?.toUpperCase() == 'TUTOR' || auth.userRole?.toUpperCase() == 'ADMIN' || auth.userRole?.toUpperCase() == 'MENTOR';
      
      final List<dynamic> sets = itemData['practiceSets'] ?? [];
      final List<dynamic> rawQuestions = [];
      if (sets.isNotEmpty) {
        for (var s in sets) {
          rawQuestions.addAll(s['questions'] ?? []);
        }
      } else {
        rawQuestions.addAll(itemData['practiceQuestions'] ?? []);
      }
      
      final List<dynamic> questions = isTeacher
          ? rawQuestions
          : rawQuestions.where((q) => q['isClasswork'] != true && q['category'] != 'classwork').toList();
      if (questions.isEmpty) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AssessmentTakingScreen(
            practiceQuestions: questions,
            assignmentId: assignment['_id'],
            onCompleted: () {
              _fetchAssignments();
            },
          ),
        ),
      );
    }
  }

  Widget _buildAssignmentCard(Map<String, dynamic> assignment) {
    final dueDate = DateTime.parse(assignment['dueDate']);
    final isOverdue = dueDate.isBefore(DateTime.now()) && assignment['status'] != 'completed';
    
    IconData typeIcon;
    Color typeColor;
    
    switch (assignment['itemType']) {
      case 'video':
        typeIcon = Icons.play_circle_fill_rounded;
        typeColor = Colors.redAccent;
        break;
      case 'slide':
        typeIcon = Icons.slideshow_rounded;
        typeColor = const Color(0xFFEC4899);
        break;
      case 'practice_question':
        typeIcon = Icons.assignment_turned_in_rounded;
        typeColor = const Color(0xFF10B981);
        break;
      default:
        typeIcon = Icons.menu_book_rounded;
        typeColor = const Color(0xFF3B82F6);
    }

    return Card(
      color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isOverdue ? Colors.redAccent.withValues(alpha: 0.5) : context.glassBorder,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(typeIcon, color: typeColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assignment['itemTitle'] ?? 'Resource Assignment',
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 14, color: isOverdue ? Colors.redAccent : context.textColor60),
                      const SizedBox(width: 4),
                      Text(
                        'Due: ${DateFormat('MMM dd, yyyy').format(dueDate)}',
                        style: TextStyle(
                          color: isOverdue ? Colors.redAccent : context.textColor60,
                          fontSize: 13,
                          fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (assignment['status'] == 'completed')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Completed', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
              )
            else
              ElevatedButton(
                onPressed: () {
                  // DEBUG: print full assignment to console
                  debugPrint('=== START TAPPED ===');
                  debugPrint('itemType: ${assignment['itemType']}');
                  debugPrint('itemData: ${assignment['itemData']}');
                  debugPrint('itemData keys: ${(assignment['itemData'] as Map?)?.keys.toList()}');
                  debugPrint('Full assignment: $assignment');

                  if (assignment['itemData'] == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('This resource was assigned before instant-start was available. Please navigate to Learning Path.')),
                    );
                    return;
                  }
                  _handleStartAssignment(assignment);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Start'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.isInline ? Colors.transparent : (context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
      appBar: widget.isInline
          ? null
          : AppBar(
              title: const Text('My Assignments', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
      body: _isLoading
          ? const Center(child: JyamitiLoader())
          : _assignments.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.assignment_turned_in, size: 64, color: context.textColor.withValues(alpha: 0.2)),
                      const SizedBox(height: 16),
                      Text('No assignments yet!', style: TextStyle(color: context.textColor60, fontSize: 16)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchAssignments,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: _assignments.length,
                    itemBuilder: (context, index) {
                      return _buildAssignmentCard(_assignments[index])
                          .animate()
                          .fade(delay: (index * 50).ms)
                          .slideX(begin: 0.05, end: 0);
                    },
                  ),
                ),
    );
  }
}
