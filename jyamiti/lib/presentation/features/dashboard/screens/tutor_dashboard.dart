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
import '../../exams/screens/assessment_question_management_screen.dart';
import '../../chat/screens/chat_list_screen.dart';
import '../../academic/screens/schedules_screen.dart';
import '../../academic/screens/tutor_tutorials_screen.dart';
import '../../academic/screens/student_learning_path_screen.dart';
import '../../academic/screens/tutor_manage_assignments_screen.dart';
import '../../academic/screens/batch_performances_screen.dart';
import '../../../widgets/writing_pad_widget.dart';

class TutorDashboard extends StatefulWidget {
  const TutorDashboard({super.key});

  @override
  State<TutorDashboard> createState() => _TutorDashboardState();
}

class _TutorDashboardState extends State<TutorDashboard> {
  // 0=Overview, 1=Schedules, 2=Question Bank, 3=Assessments, 4=Messages
  int _selectedSidebarTab = 0;
  Widget? _activeInlineSubScreen;

  static const Color _roleColor = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        Provider.of<AuthProvider>(context, listen: false).fetchProfile();
      }
    });
  }

  Future<void> _handleLogout(AuthProvider auth) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white.withValues(alpha: 0.9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: context.glassBorder),
          ),
          title: Text('Confirm Logout', style: TextStyle(color: context.textColor)),
          content: Text('Are you sure you want to sign out?', style: TextStyle(color: context.textColor70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: context.textColor60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Logout'),
            ),
          ],
        ),
      ),
    );
    if (confirm == true && mounted) auth.logout();
  }

  // ─── Sidebar Item ────────────────────────────────────────────────────────────
  Widget _buildSidebarItem(int index, String title, IconData icon) {
    final isSelected = _selectedSidebarTab == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 5.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Material(
            color: isSelected
                ? _roleColor.withValues(alpha: context.isDark ? 0.18 : 0.12)
                : Colors.transparent,
            child: InkWell(
              onTap: () => setState(() {
                _selectedSidebarTab = index;
                _activeInlineSubScreen = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? _roleColor.withValues(alpha: 0.4)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      color: isSelected ? _roleColor : context.textColor70,
                      size: 20,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      title,
                      style: TextStyle(
                        color: isSelected ? context.textColor : context.textColor70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarNavBtn(String title, IconData icon, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 5.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(icon, color: context.textColor70, size: 20),
                const SizedBox(width: 16),
                Text(
                  title,
                  style: TextStyle(
                    color: context.textColor70,
                    fontWeight: FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Right Content Area ──────────────────────────────────────────────────────
  Widget _buildRightContentArea(Map<String, dynamic>? profile) {
    final isLargeScreen = MediaQuery.of(context).size.width > 900;
    if (isLargeScreen && _activeInlineSubScreen != null) {
      return _activeInlineSubScreen!;
    }

    switch (_selectedSidebarTab) {
      case 0:
        return _buildOverviewTab(profile);
      case 1:
        return const SchedulesScreen(isInline: true);
      case 4:
        return const ChatListScreen(isInline: true);
      case 5:
        return const TutorManageAssignmentsScreen(isInline: true);
      default:
        return _buildOverviewTab(profile);
    }
  }

  // ─── Overview Tab ────────────────────────────────────────────────────────────
  Widget _buildOverviewTab(Map<String, dynamic>? profile) {
    final String name = profile?['name'] ?? 'Tutor';
    final batches = profile?['batches'] as List?;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome Card
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: context.isDark
                      ? Colors.black.withValues(alpha: 0.2)
                      : _roleColor.withValues(alpha: 0.06),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: context.isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: context.isDark
                          ? context.textColor.withValues(alpha: 0.08)
                          : _roleColor.withValues(alpha: 0.15),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _roleColor.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.school_rounded,
                          size: 32,
                          color: _roleColor,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome back,',
                              style: TextStyle(
                                fontSize: 14,
                                color: context.textColor.withValues(alpha: 0.7),
                              ),
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
                      // Quick stats badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _roleColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _roleColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.class_rounded, color: _roleColor, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '${batches?.length ?? 0} Batch${(batches?.length ?? 0) != 1 ? 'es' : ''}',
                              style: const TextStyle(
                                color: _roleColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
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

          const SizedBox(height: 28),

          // Quick Actions Grid
          Text(
            'Quick Actions',
            style: TextStyle(
              color: context.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ).animate().fade(delay: 150.ms).slideX(begin: -0.1, end: 0),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossCount = constraints.maxWidth > 600 ? 4 : 2;
              return GridView.count(
                crossAxisCount: crossCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  _buildQuickActionCard(
                    icon: Icons.library_books_rounded,
                    label: 'Question Bank',
                    color: const Color(0xFFF59E0B),
                    onTap: () {
                      final isLargeScreen = MediaQuery.of(context).size.width > 900;
                      if (isLargeScreen) {
                        setState(() {
                          _activeInlineSubScreen = QuestionBankScreen(
                            isInline: true,
                            onBack: () => setState(() => _activeInlineSubScreen = null),
                          );
                        });
                      } else {
                        Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const QuestionBankScreen()));
                      }
                    },
                  ),
                  _buildQuickActionCard(
                    icon: Icons.assessment_rounded,
                    label: 'Assessments',
                    color: const Color(0xFF8B5CF6),
                    onTap: () {
                      final isLargeScreen = MediaQuery.of(context).size.width > 900;
                      if (isLargeScreen) {
                        setState(() {
                          _activeInlineSubScreen = AssessmentQuestionManagementScreen(
                            isInline: true,
                            onBack: () => setState(() => _activeInlineSubScreen = null),
                          );
                        });
                      } else {
                        Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const AssessmentQuestionManagementScreen()));
                      }
                    },
                  ),
                  _buildQuickActionCard(
                    icon: Icons.calendar_month_rounded,
                    label: 'Schedules',
                    color: const Color(0xFF6366F1),
                    onTap: () => setState(() {
                      _selectedSidebarTab = 1;
                      _activeInlineSubScreen = null;
                    }),
                  ),
                  _buildQuickActionCard(
                    icon: Icons.assignment_rounded,
                    label: 'Assignments',
                    color: const Color(0xFF3B82F6),
                    onTap: () => setState(() {
                      _selectedSidebarTab = 5;
                      _activeInlineSubScreen = null;
                    }),
                  ),
                ],
              );
            },
          ).animate().fade(delay: 200.ms).slideY(begin: 0.1, end: 0),

          const SizedBox(height: 32),

          // My Batches Section
          Text(
            'My Batches',
            style: TextStyle(
              color: context.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ).animate().fade(delay: 300.ms).slideX(begin: -0.1, end: 0),
          const SizedBox(height: 16),

          if (profile == null)
            const Center(
              child: CircularProgressIndicator(color: _roleColor),
            )
          else if (batches == null || batches.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: context.isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.glassBorder),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.class_outlined, size: 48, color: context.textColor60),
                    const SizedBox(height: 12),
                    Text(
                      'No batches assigned yet.',
                      style: TextStyle(color: context.textColor60, fontSize: 15),
                    ),
                  ],
                ),
              ),
            )
          else
            ...batches.map((b) => _buildBatchCard(b)),
        ],
      ),
    );
  }

  // ─── Quick Action Card ───────────────────────────────────────────────────────
  Widget _buildQuickActionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.isDark
              ? color.withValues(alpha: 0.08)
              : color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: context.isDark ? 0.05 : 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: context.isDark ? color.withValues(alpha: 0.9) : color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Batch Card ──────────────────────────────────────────────────────────────
  Widget _buildBatchCard(Map<String, dynamic> b) {
    final students = b['students'] as List?;
    final isLargeScreen = MediaQuery.of(context).size.width > 900;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: context.isDark
            ? const Color(0xFF1E293B).withValues(alpha: 0.5)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: context.isDark
              ? context.textColor.withValues(alpha: 0.08)
              : _roleColor.withValues(alpha: 0.12),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: _roleColor.withValues(alpha: context.isDark ? 0.05 : 0.03),
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
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _roleColor.withValues(alpha: context.isDark ? 0.15 : 0.08),
                      Colors.transparent,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: context.isDark
                          ? context.glassBorder
                          : _roleColor.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _roleColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.class_rounded, color: _roleColor, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b['name'] ?? '',
                            style: TextStyle(
                              color: context.textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            b['course']?['name'] ?? '',
                            style: TextStyle(
                              color: _roleColor.withValues(alpha: 0.9),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: context.isDark ? 0.2 : 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            b['timePeriod'] ?? '',
                            style: const TextStyle(
                              color: Color(0xFF818CF8),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: context.isDark
                                ? Colors.white.withValues(alpha: 0.04)
                                : Colors.black.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: context.glassBorder),
                          ),
                          child: Text(
                            b['daysOfWeek'] ?? '',
                            style: TextStyle(color: context.textColor70, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Students + Actions Section
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (students != null && students.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Enrolled Students',
                            style: TextStyle(
                              color: context.textColor60,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _roleColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${students.length} Total',
                              style: const TextStyle(
                                color: _roleColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: students.take(8).map((s) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: context.isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.black.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: context.glassBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person_rounded, size: 11, color: context.textColor60),
                                const SizedBox(width: 5),
                                Text(
                                  s['name'] ?? '',
                                  style: TextStyle(color: context.textColor70, fontSize: 11),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                      if (students.length > 8) ...[
                        const SizedBox(height: 6),
                        Text(
                          '+ ${students.length - 8} more',
                          style: TextStyle(color: context.textColor60, fontSize: 11),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Divider(color: context.glassBorder, height: 1),
                      const SizedBox(height: 20),
                    ],

                    // Explore Syllabus Button
                    InkWell(
                      onTap: () {
                        final isLargeScreen = MediaQuery.of(context).size.width > 900;
                        if (isLargeScreen) {
                          setState(() {
                            _activeInlineSubScreen = StudentLearningPathScreen(
                              batch: b,
                              isInline: true,
                              onBack: () => setState(() => _activeInlineSubScreen = null),
                            );
                          });
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StudentLearningPathScreen(batch: b),
                            ),
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _roleColor,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: _roleColor.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.explore_rounded, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'Explore Syllabus',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Action Buttons
                    if (isLargeScreen)
                      Row(
                        children: [
                          Expanded(child: _buildActionBtn(
                            context,
                            icon: Icons.book_rounded,
                            label: 'Worksheets',
                            color: const Color(0xFF6366F1),
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => BatchWorksheetsScreen(batch: b))),
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: _buildActionBtn(
                            context,
                            icon: Icons.note_alt_rounded,
                            label: 'Notes',
                            color: const Color(0xFF8B5CF6),
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => BatchNotesScreen(batch: b))),
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: _buildActionBtn(
                            context,
                            icon: Icons.quiz_rounded,
                            label: 'Exams',
                            color: const Color(0xFF10B981),
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => ExamManagementScreen(batch: b))),
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: _buildActionBtn(
                            context,
                            icon: Icons.play_circle_fill_rounded,
                            label: 'Tutorials',
                            color: const Color(0xFFEC4899),
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => TutorTutorialsScreen(batch: b))),
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: _buildActionBtn(
                            context,
                            icon: Icons.analytics_rounded,
                            label: 'Performances',
                            color: const Color(0xFFF59E0B),
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => BatchPerformancesScreen(batch: b))),
                          )),
                        ],
                      )
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            _buildActionBtn(context, icon: Icons.book_rounded, label: 'Worksheets',
                                color: const Color(0xFF6366F1),
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => BatchWorksheetsScreen(batch: b)))),
                            const SizedBox(width: 10),
                            _buildActionBtn(context, icon: Icons.note_alt_rounded, label: 'Notes',
                                color: const Color(0xFF8B5CF6),
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => BatchNotesScreen(batch: b)))),
                            const SizedBox(width: 10),
                            _buildActionBtn(context, icon: Icons.quiz_rounded, label: 'Exams',
                                color: const Color(0xFF10B981),
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => ExamManagementScreen(batch: b)))),
                            const SizedBox(width: 10),
                            _buildActionBtn(context, icon: Icons.play_circle_fill_rounded, label: 'Tutorials',
                                color: const Color(0xFFEC4899),
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => TutorTutorialsScreen(batch: b)))),
                            const SizedBox(width: 10),
                            _buildActionBtn(context, icon: Icons.analytics_rounded, label: 'Performances',
                                color: const Color(0xFFF59E0B),
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => BatchPerformancesScreen(batch: b)))),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate()
        .fade(duration: 500.ms, delay: 200.ms)
        .slideY(begin: 0.1, end: 0);
  }

  Widget _buildActionBtn(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: context.isDark ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Main Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final profile = auth.profile;
    final isLargeScreen = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      extendBodyBehindAppBar: !isLargeScreen,
      floatingActionButton: const JyamitiPadFab(),
      appBar: isLargeScreen
          ? null
          : AppBar(
              title: const Text(
                'Tutor Dashboard',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ).animate().fade().slideY(begin: -0.2, end: 0),
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: IconThemeData(color: context.textColor),
              actions: [
                IconButton(
                  icon: Icon(Icons.chat_bubble_outline_rounded, color: context.textColor),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ChatListScreen())),
                ),
                IconButton(
                  icon: Icon(Icons.calendar_month_rounded, color: context.textColor),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SchedulesScreen())),
                ),
                IconButton(
                  icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                  onPressed: () => _handleLogout(auth),
                ),
              ],
            ),
      body: Stack(
        children: [
          // Background gradient — theme-aware
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: context.isDark
                    ? const [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)]
                    : const [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // ── Large Screen: Sidebar + Content ─────────────────────────────────
          if (isLargeScreen)
            SafeArea(
              child: Row(
                children: [
                  // Sidebar
                  Container(
                    width: 260,
                    decoration: BoxDecoration(
                      color: context.glassBg,
                      border: Border(
                        right: BorderSide(color: context.glassBorder),
                      ),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        // Logo / Brand Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _roleColor.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.school_rounded,
                                color: _roleColor,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Tutor Panel',
                              style: TextStyle(
                                color: context.textColor,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        _buildSidebarItem(0, 'Overview', Icons.dashboard_rounded),
                        _buildSidebarItem(1, 'Schedules', Icons.calendar_month_rounded),
                        _buildSidebarNavBtn('Question Bank', Icons.library_books_rounded, const Color(0xFFF59E0B), () {
                          final isLargeScreen = MediaQuery.of(context).size.width > 900;
                          if (isLargeScreen) {
                            setState(() {
                              _activeInlineSubScreen = QuestionBankScreen(
                                isInline: true,
                                onBack: () => setState(() => _activeInlineSubScreen = null),
                              );
                            });
                          } else {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const QuestionBankScreen()));
                          }
                        }),
                        _buildSidebarNavBtn('Assessments', Icons.assessment_rounded, const Color(0xFF8B5CF6), () {
                          final isLargeScreen = MediaQuery.of(context).size.width > 900;
                          if (isLargeScreen) {
                            setState(() {
                              _activeInlineSubScreen = AssessmentQuestionManagementScreen(
                                isInline: true,
                                onBack: () => setState(() => _activeInlineSubScreen = null),
                              );
                            });
                          } else {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const AssessmentQuestionManagementScreen()));
                          }
                        }),
                        _buildSidebarItem(5, 'Assignments', Icons.assignment_rounded),

                        const Spacer(),

                        _buildSidebarItem(4, 'Messages', Icons.chat_bubble_outline_rounded),

                        // Logout button
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _handleLogout(auth),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 12.0),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.logout_rounded,
                                          color: Colors.redAccent, size: 20),
                                      const SizedBox(width: 16),
                                      Text(
                                        'Sign Out',
                                        style: TextStyle(
                                          color: context.textColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),

                  // Main content
                  Expanded(child: _buildRightContentArea(profile)),
                ],
              ),
            )

          // ── Small Screen: Scrollable Column ─────────────────────────────────
          else
            SafeArea(
              child: _buildRightContentArea(profile),
            ),
        ],
      ),
    );
  }
}
