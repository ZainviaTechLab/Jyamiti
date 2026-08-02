import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../academic/screens/batch_worksheets_screen.dart';
import '../../academic/screens/batch_notes_screen.dart';
import '../../exams/screens/exam_management_screen.dart';
import '../../exams/screens/question_bank_screen.dart';
import '../../chat/screens/chat_list_screen.dart';
import '../../academic/screens/schedules_screen.dart';
import '../../academic/screens/tutor_tutorials_screen.dart';
import '../../../widgets/writing_pad_widget.dart';

class MentorDashboard extends StatefulWidget {
  const MentorDashboard({super.key});

  @override
  State<MentorDashboard> createState() => _MentorDashboardState();
}

class _MentorDashboardState extends State<MentorDashboard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        Provider.of<AuthProvider>(context, listen: false).fetchProfile();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final profile = auth.profile;
    final String name = auth.userName ?? 'Mentor';
    Color roleColor = Color(0xFF10B981);

    return Scaffold(
      extendBodyBehindAppBar: true,
      floatingActionButton: const JyamitiPadFab(),
      appBar: AppBar(
        title: const Text(
          'Mentor Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
        ).animate().fade().slideY(begin: -0.2, end: 0),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: context.textColor),
        actions: [
          IconButton(
            icon: Icon(Icons.chat_bubble_outline_rounded, color: context.textColor),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatListScreen())),
          ),
          IconButton(
            icon: Icon(Icons.calendar_month_rounded, color: context.textColor),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SchedulesScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            onPressed: () async {
              final bool? confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                  title:  Text('Confirm Logout', style: TextStyle(color: context.textColor)),
                  content: Text('Are you sure you want to sign out?', style: TextStyle(color: context.textColor70)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text('Cancel', style: TextStyle(color: context.textColor60)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text('Logout', style: TextStyle(color: context.textColor)),
                    ),
                  ],
                ),
              );
              
              if (confirm == true && mounted) {
                auth.logout();
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Futuristic Gradient Background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: context.isDark ? const [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)] : const [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          
          SafeArea(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Greeting Area with Glassmorphism
                  Container(
                    decoration: BoxDecoration(
                      color: context.glassBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: roleColor.withOpacity(0.3)),
                      boxShadow: [
                        BoxShadow(color: roleColor.withOpacity(0.1), blurRadius: 20, spreadRadius: -5),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: roleColor.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.school_rounded,
                                  size: 32,
                                  color: roleColor,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Welcome back,', style: TextStyle(color: context.textColor.withOpacity(0.7)),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: context.textColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ).animate().fade(duration: 400.ms).slideY(begin: 0.2, end: 0),
                  
                  const SizedBox(height: 32),

                  Text(
                    'My Class Schedules',
                    style: TextStyle(color: context.textColor, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  if (profile == null)
                    const Center(
                      child: JyamitiLoader(color: Color(0xFF6366F1)),
                    )
                  else ...[
                    if (profile['batches'] == null ||
                        (profile['batches'] as List).isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'No batches currently assigned to you.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.textColor60),
                        ),
                      )
                    else
                      ...((profile['batches'] as List).map(
                        (b) => _buildBatchCard(b, roleColor, context),
                      )),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      
    ],),
    );
  }

  Widget _buildBatchCard(Map<String, dynamic> b, Color roleColor, BuildContext context) {
    final students = b['students'] as List?;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.glassBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: roleColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(color: roleColor.withOpacity(0.1), blurRadius: 20, spreadRadius: -5),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        b['name'],
                        style: TextStyle(color: context.textColor, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: context.glassBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        b['timePeriod'],
                        style: const TextStyle(
                          color: Color(0xFF818CF8),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Course: ${b['course']['name']}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 13,
                  ),
                ),
                Divider(color: context.glassBorder, height: 24),
                Row(
                  children: [
                   Icon(
                      Icons.calendar_today_rounded,
                      size: 16,
                      color: context.textColor60,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      b['daysOfWeek'],
                      style: TextStyle(color: context.textColor70, fontSize: 14),
                    ),
                  ],
                ),
                
                if (students != null) ...[
                  Divider(color: context.glassBorder, height: 24),
                  Text(
                    'Students Enrolled (${students.length})',
                    style: TextStyle(color: context.textColor70,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  students.isEmpty
                      ? Text(
                          'No students in this batch',
                          style: TextStyle(color: context.textColor54.withOpacity(0.5), fontSize: 12),
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: students.map((s) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8, 
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: context.glassBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: context.glassBg,
                                ),
                              ),
                              child: Text(
                                s['name'],
                                style: TextStyle(color: context.textColor60,
                                  fontSize: 11,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                ],
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                        icon: const Icon(Icons.book, size: 16, color: Colors.white),
                        label: const Text('Worksheets', style: const TextStyle(color: Colors.white)),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BatchWorksheetsScreen(batch: b))),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
                        icon: const Icon(Icons.note_alt, size: 16, color: Colors.white),
                        label: const Text('Notes', style: const TextStyle(color: Colors.white)),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BatchNotesScreen(batch: b))),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                        icon: const Icon(Icons.quiz, size: 16, color: Colors.white),
                        label: const Text('Exams', style: const TextStyle(color: Colors.white)),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExamManagementScreen(batch: b))),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEC4899)),
                        icon: const Icon(Icons.play_circle_filled_rounded, size: 16, color: Colors.white),
                        label: const Text('Tutorials', style: const TextStyle(color: Colors.white)),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TutorTutorialsScreen(batch: b))),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
                        icon: const Icon(Icons.library_books, size: 16, color: Colors.white),
                        label: const Text('Question Bank', style: const TextStyle(color: Colors.white)),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuestionBankScreen())),
                      ),
                    ]
                  )
                )
              ],
            ),
          ),
        ),
      ),
    ).animate().fade(duration: 400.ms, delay: 200.ms).slideY(begin: 0.1, end: 0);
  }
}

