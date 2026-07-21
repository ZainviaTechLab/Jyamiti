import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../academic/screens/batch_worksheets_screen.dart';
import '../../academic/screens/batch_notes_screen.dart';
import '../../exams/screens/exam_management_screen.dart';
import '../../academic/screens/tutor_tutorials_screen.dart';
import '../../academic/screens/schedules_screen.dart';

class AdminBatchDetailScreen extends StatelessWidget {
  final Map<String, dynamic> batch;

  const AdminBatchDetailScreen({super.key, required this.batch});

  @override
  Widget build(BuildContext context) {
    const Color themeColor = Color(0xFF6366F1);
    final students = batch['students'] as List?;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          batch['name'] ?? 'Batch Details',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            color: context.textColor,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: context.textColor),
      ),
      body: Stack(
        children: [
          // Futuristic Gradient Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0F172A),
                  Color(0xFF1E1B4B),
                  Color(0xFF0F172A),
                ],
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
                  padding: EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 24.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Main Info Card
                  _buildMainInfoCard(context, themeColor),
                  const SizedBox(height: 32),

                  // Quick Actions Grid
                  Text(
                    'Management Actions',
                    style: TextStyle(color: context.textColor, fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ).animate().fade().slideX(begin: -0.1, end: 0),
                  const SizedBox(height: 16),

                  _buildActionGrid(context),

                  const SizedBox(height: 32),

                  // Students List section if any
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Enrolled Students',
                        style: TextStyle(color: context.textColor, fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        '${students?.length ?? 0} Total',
                        style: const TextStyle(
                          color: themeColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ).animate().fade().slideX(begin: -0.1, end: 0),
                  const SizedBox(height: 16),

                  if (students == null || students.isEmpty)
                    Center(
                      child: Text(
                        'No students enrolled in this batch.',
                        style: TextStyle(color: context.textColor54, fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 12,
                      children: students.map((s) {
                        return Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: context.glassBorder,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: context.glassBorder,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_rounded,
                                size: 16,
                                color: context.textColor70,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                s['name'] ?? '',
                                style: TextStyle(color: context.textColor, fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ).animate().fade().scale(delay: 200.ms);
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
        ],
      ),
    );
  }

  Widget _buildMainInfoCard(BuildContext context, Color themeColor) {
    return Container(
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF1E293B) : Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: themeColor.withValues(alpha: 0.1),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      themeColor.withValues(alpha: 0.2),
                      Colors.transparent,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: context.glassBorder,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: themeColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.class_rounded,
                            color: themeColor,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                batch['course']?['name'] ?? 'Unknown Course',
                                style: TextStyle(color: context.textColor, fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (batch['category'] != null)
                                Padding(
                                  padding: EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    '${batch['category']['name']}',
                                    style: TextStyle(
                                      color: themeColor.withValues(alpha: 0.9),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    _buildInfoRow(
                      context,
                      Icons.calendar_month_rounded,
                      'Schedule',
                      '${batch['daysOfWeek']} | ${batch['timePeriod']}',
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(color: context.glassBorder, height: 1),
                    ),
                    _buildInfoRow(
                      context,
                      Icons.person,
                      'Lead Tutor',
                      batch['tutor']?['name'] ?? 'Unassigned',
                    ),
                    if (batch['mentors'] != null &&
                        (batch['mentors'] as List).isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(color: context.glassBorder, height: 1),
                      ),
                      _buildInfoRow(
                        context,
                        Icons.people_alt_rounded,
                        'Mentors',
                        (batch['mentors'] as List)
                            .map((m) => m['name'])
                            .join(', '),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fade(duration: 500.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String title, String value) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.glassBorder,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: context.textColor70),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(color: context.textColor54, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(color: context.textColor, fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionGrid(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 600 ? 4 : 2;
    final childAspectRatio = screenWidth > 600 ? 2.5 : 1.5;
    return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: childAspectRatio,
          children: [
            _buildActionTile(
              context,
              icon: Icons.calendar_month_rounded,
              title: 'Sessions',
              color: const Color(0xFF6366F1), // Indigo
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SchedulesScreen()),
              ),
            ),
            _buildActionTile(
              context,
              icon: Icons.book_rounded,
              title: 'Worksheets',
              color: const Color(0xFFF59E0B), // Amber
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BatchWorksheetsScreen(batch: batch),
                ),
              ),
            ),
            _buildActionTile(
              context,
              icon: Icons.note_alt_rounded,
              title: 'Notes',
              color: const Color(0xFF8B5CF6), // Violet
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BatchNotesScreen(batch: batch),
                ),
              ),
            ),
            _buildActionTile(
              context,
              icon: Icons.quiz_rounded,
              title: 'Exams',
              color: const Color(0xFF10B981), // Emerald
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExamManagementScreen(batch: batch),
                ),
              ),
            ),
            _buildActionTile(
              context,
              icon: Icons.play_circle_fill_rounded,
              title: 'Tutorials',
              color: const Color(0xFFEC4899), // Pink
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TutorTutorialsScreen(batch: batch),
                ),
              ),
            ),
          ],
        )
        .animate()
        .fade(duration: 400.ms, delay: 200.ms)
        .slideY(begin: 0.1, end: 0);
  }

  Widget _buildActionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.05),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

