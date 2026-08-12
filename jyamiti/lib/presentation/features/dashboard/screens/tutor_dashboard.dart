import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../../widgets/theme_reveal.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../academic/screens/batch_worksheets_screen.dart';
import '../../academic/screens/batch_notes_screen.dart';
import '../../exams/screens/exam_management_screen.dart';
import '../../chat/screens/chat_list_screen.dart';
import '../../academic/screens/schedules_screen.dart';
import '../../academic/screens/tutor_tutorials_screen.dart';
import '../../academic/screens/student_learning_path_screen.dart';
import '../../academic/screens/tutor_manage_assignments_screen.dart';
import '../../academic/screens/batch_performances_screen.dart';
import '../../mathpad/library/screens/mathpad_library_screen.dart';
import '../../slides/screens/slide_decks_manager_screen.dart';
import '../../../widgets/writing_pad_widget.dart';
import '../../competitions/screens/tutor_competition_host_screen.dart';
import '../../competitions/screens/tutor_arena_history_screen.dart';
import '../../meetings/screens/parent_meetings_dashboard_screen.dart';

class TutorDashboard extends StatefulWidget {
  const TutorDashboard({super.key});

  @override
  State<TutorDashboard> createState() => _TutorDashboardState();
}

class _TutorDashboardState extends State<TutorDashboard> {
  // 0=Overview, 1=Schedules, 2=Question Bank, 3=Assessments, 4=Messages
  int _selectedSidebarTab = 0;
  Widget? _activeInlineSubScreen;

  static const Color _roleColor = Color(0xFFF43F5E);

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
          backgroundColor: context.isDark
              ? const Color(0xFF1E293B)
              : Colors.white.withValues(alpha: 0.9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: context.glassBorder),
          ),
          title: Text(
            'Confirm Logout',
            style: TextStyle(color: context.textColor),
          ),
          content: Text(
            'Are you sure you want to sign out?',
            style: TextStyle(color: context.textColor70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(color: context.textColor60),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
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
                        color: isSelected
                            ? context.textColor
                            : context.textColor70,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
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

  Widget _buildSidebarNavBtn(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 5.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
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
      case 7:
        return _buildSavedNotesTab();
      case 8:
        return TutorArenaHistoryScreen(
          batches: profile?['batches'] as List?,
          isInline: true,
        );
      case 9:
        return ParentMeetingsDashboardScreen(
          batches: profile?['batches'] as List?,
          isInline: true,
        );
      case 10:
        if (kIsWeb) {
          return _buildMathPadWebFallback();
        }
        return MathPadLibraryScreen(
          batches: profile?['batches'] as List?,
          isInline: true,
        );
      default:
        return _buildOverviewTab(profile);
    }
  }

  Widget _buildMathPadWebFallback() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: context.isDark
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.glassBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.desktop_windows_rounded,
              size: 48,
              color: context.textColor60,
            ),
            const SizedBox(height: 12),
            Text(
              "Math Pad Library isn't available on the web version yet.\n"
              'Please use the Windows/macOS/Linux desktop app or the Android/iOS app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textColor60, fontSize: 15),
            ),
          ],
        ),
      ),
    );
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _roleColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _roleColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.class_rounded,
                              color: _roleColor,
                              size: 16,
                            ),
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
            const Center(child: JyamitiLoader(color: _roleColor))
          else if (batches == null || batches.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: context.isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.glassBorder),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.class_outlined,
                      size: 48,
                      color: context.textColor60,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No batches assigned yet.',
                      style: TextStyle(
                        color: context.textColor60,
                        fontSize: 15,
                      ),
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
                color: Colors.black.withValues(
                  alpha: context.isDark ? 0.3 : 0.05,
                ),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: _roleColor.withValues(
                  alpha: context.isDark ? 0.05 : 0.03,
                ),
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
                          _roleColor.withValues(
                            alpha: context.isDark ? 0.15 : 0.08,
                          ),
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
                          child: const Icon(
                            Icons.class_rounded,
                            color: _roleColor,
                            size: 26,
                          ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF6366F1,
                                ).withValues(alpha: context.isDark ? 0.2 : 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(
                                    0xFF6366F1,
                                  ).withValues(alpha: 0.3),
                                ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: context.isDark
                                    ? Colors.white.withValues(alpha: 0.04)
                                    : Colors.black.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: context.glassBorder),
                              ),
                              child: Text(
                                b['daysOfWeek'] ?? '',
                                style: TextStyle(
                                  color: context.textColor70,
                                  fontSize: 11,
                                ),
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: context.isDark
                                      ? Colors.white.withValues(alpha: 0.04)
                                      : Colors.black.withValues(alpha: 0.03),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: context.glassBorder,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.person_rounded,
                                      size: 11,
                                      color: context.textColor60,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      s['name'] ?? '',
                                      style: TextStyle(
                                        color: context.textColor70,
                                        fontSize: 11,
                                      ),
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
                              style: TextStyle(
                                color: context.textColor60,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          Divider(color: context.glassBorder, height: 1),
                          const SizedBox(height: 20),
                        ],

                        // Explore Syllabus Button
                        InkWell(
                          onTap: () {
                            final isLargeScreen =
                                MediaQuery.of(context).size.width > 900;
                            if (isLargeScreen) {
                              setState(() {
                                _activeInlineSubScreen =
                                    StudentLearningPathScreen(
                                      batch: b,
                                      isInline: true,
                                      onBack: () => setState(
                                        () => _activeInlineSubScreen = null,
                                      ),
                                    );
                              });
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      StudentLearningPathScreen(batch: b),
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
                                const Icon(
                                  Icons.explore_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
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
                              Expanded(
                                child: _buildActionBtn(
                                  context,
                                  icon: Icons.sports_esports_rounded,
                                  label: 'Arena',
                                  color: const Color(0xFF10B981),
                                  onTap: () {
                                    final isLargeScreen =
                                        MediaQuery.of(context).size.width > 900;
                                    if (isLargeScreen) {
                                      setState(() {
                                        _activeInlineSubScreen =
                                            TutorCompetitionHostScreen(
                                              batch: b,
                                              isInline: true,
                                              onBack: () => setState(
                                                () => _activeInlineSubScreen =
                                                    null,
                                              ),
                                            );
                                      });
                                    } else {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              TutorCompetitionHostScreen(
                                                batch: b,
                                              ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildActionBtn(
                                  context,
                                  icon: Icons.book_rounded,
                                  label: 'Worksheets',
                                  color: const Color(0xFF6366F1),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          BatchWorksheetsScreen(batch: b),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildActionBtn(
                                  context,
                                  icon: Icons.note_alt_rounded,
                                  label: 'Notes',
                                  color: const Color(0xFF8B5CF6),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          BatchNotesScreen(batch: b),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildActionBtn(
                                  context,
                                  icon: Icons.quiz_rounded,
                                  label: 'Exams',
                                  color: const Color(0xFF10B981),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ExamManagementScreen(batch: b),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildActionBtn(
                                  context,
                                  icon: Icons.play_circle_fill_rounded,
                                  label: 'Tutorials',
                                  color: const Color(0xFFEC4899),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          TutorTutorialsScreen(batch: b),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildActionBtn(
                                  context,
                                  icon: Icons.analytics_rounded,
                                  label: 'Performances',
                                  color: const Color(0xFFF59E0B),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          BatchPerformancesScreen(batch: b),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildActionBtn(
                                  context,
                                  icon: Icons.slideshow_rounded,
                                  label: 'Slides',
                                  color: const Color(0xFF0EA5E9),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const SlideDecksManagerScreen(
                                            isTutor: true,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [
                                _buildActionBtn(
                                  context,
                                  icon: Icons.sports_esports_rounded,
                                  label: 'Arena',
                                  color: const Color(0xFF10B981),
                                  onTap: () {
                                    final isLargeScreen =
                                        MediaQuery.of(context).size.width > 900;
                                    if (isLargeScreen) {
                                      setState(() {
                                        _activeInlineSubScreen =
                                            TutorCompetitionHostScreen(
                                              batch: b,
                                              isInline: true,
                                              onBack: () => setState(
                                                () => _activeInlineSubScreen =
                                                    null,
                                              ),
                                            );
                                      });
                                    } else {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              TutorCompetitionHostScreen(
                                                batch: b,
                                              ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(width: 10),
                                _buildActionBtn(
                                  context,
                                  icon: Icons.book_rounded,
                                  label: 'Worksheets',
                                  color: const Color(0xFF6366F1),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          BatchWorksheetsScreen(batch: b),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _buildActionBtn(
                                  context,
                                  icon: Icons.note_alt_rounded,
                                  label: 'Notes',
                                  color: const Color(0xFF8B5CF6),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          BatchNotesScreen(batch: b),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _buildActionBtn(
                                  context,
                                  icon: Icons.quiz_rounded,
                                  label: 'Exams',
                                  color: const Color(0xFF10B981),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ExamManagementScreen(batch: b),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _buildActionBtn(
                                  context,
                                  icon: Icons.play_circle_fill_rounded,
                                  label: 'Tutorials',
                                  color: const Color(0xFFEC4899),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          TutorTutorialsScreen(batch: b),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _buildActionBtn(
                                  context,
                                  icon: Icons.analytics_rounded,
                                  label: 'Performances',
                                  color: const Color(0xFFF59E0B),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          BatchPerformancesScreen(batch: b),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _buildActionBtn(
                                  context,
                                  icon: Icons.slideshow_rounded,
                                  label: 'Slides',
                                  color: const Color(0xFF0EA5E9),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const SlideDecksManagerScreen(
                                            isTutor: true,
                                          ),
                                    ),
                                  ),
                                ),
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
        )
        .animate()
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
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
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
      floatingActionButton: JyamitiPadFab(
        enableSaveNotes: true,
        onPressed: () {
          setState(() {
            _selectedSidebarTab = 10;
            _activeInlineSubScreen = null;
          });
        },
      ),
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
                Builder(
                  builder: (iconContext) => IconButton(
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      transitionBuilder: (child, animation) {
                        return RotationTransition(
                          turns: animation,
                          child: ScaleTransition(
                            scale: animation,
                            child: child,
                          ),
                        );
                      },
                      child: Icon(
                        context.isDark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        key: ValueKey<bool>(context.isDark),
                        color: context.textColor,
                      ),
                    ),
                    tooltip: 'Toggle Theme',
                    onPressed: () {
                      final themeProvider = Provider.of<ThemeProvider>(
                        context,
                        listen: false,
                      );
                      ThemeReveal.animate(iconContext, () {
                        themeProvider.toggleTheme(!themeProvider.isDarkMode);
                      });
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: context.textColor,
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ChatListScreen()),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.calendar_month_rounded,
                    color: context.textColor,
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SchedulesScreen()),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.logout_rounded,
                    color: Colors.redAccent,
                  ),
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

                        _buildSidebarItem(
                          0,
                          'Overview',
                          Icons.dashboard_rounded,
                        ),
                        _buildSidebarItem(
                          1,
                          'Schedules',
                          Icons.calendar_month_rounded,
                        ),
                        _buildSidebarItem(
                          5,
                          'Assignments',
                          Icons.assignment_rounded,
                        ),
                        _buildSidebarItem(
                          8,
                          'Arena History',
                          Icons.emoji_events_rounded,
                        ),
                        _buildSidebarItem(
                          9,
                          'Parent Meetings',
                          Icons.video_call_rounded,
                        ),
                        _buildSidebarItem(
                          7,
                          'My Notes',
                          Icons.note_alt_rounded,
                        ),


                        const Spacer(),

                        // Theme toggle link
                        Builder(
                          builder: (inkContext) => Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 6.0,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    final themeProvider =
                                        Provider.of<ThemeProvider>(
                                          context,
                                          listen: false,
                                        );
                                    ThemeReveal.animate(inkContext, () {
                                      themeProvider.toggleTheme(
                                        !themeProvider.isDarkMode,
                                      );
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0,
                                      vertical: 12.0,
                                    ),
                                    child: Row(
                                      children: [
                                        AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 500,
                                          ),
                                          transitionBuilder:
                                              (child, animation) {
                                                return RotationTransition(
                                                  turns: animation,
                                                  child: ScaleTransition(
                                                    scale: animation,
                                                    child: child,
                                                  ),
                                                );
                                              },
                                          child: Icon(
                                            context.isDark
                                                ? Icons.light_mode_rounded
                                                : Icons.dark_mode_rounded,
                                            key: ValueKey<bool>(context.isDark),
                                            color: context.textColor70,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Text(
                                          context.isDark
                                              ? 'Light Theme'
                                              : 'Dark Theme',
                                          style: TextStyle(
                                            color: context.textColor70,
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
                        ),

                        _buildSidebarItem(
                          4,
                          'Messages',
                          Icons.chat_bubble_outline_rounded,
                        ),

                        // Logout button
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 6.0,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _handleLogout(auth),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                    vertical: 12.0,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.logout_rounded,
                                        color: Colors.redAccent,
                                        size: 20,
                                      ),
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
            SafeArea(child: _buildRightContentArea(profile)),
        ],
      ),
    );
  }

  Widget _buildSavedNotesTab() {
    return FutureBuilder<List<dynamic>>(
      future: _loadSavedNotes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: JyamitiLoader());
        }
        final notes = snapshot.data ?? [];
        if (notes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.note_alt_rounded,
                    size: 64,
                    color: Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'No Saved Notes Yet',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: context.textColor,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'Draw anything on JyamitiPad and save it to access your personal notebook here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: context.textColor70),
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My Personal Notes',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: context.textColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Quickly open and edit your JyamitiPad sketch notes',
                  style: TextStyle(fontSize: 13, color: context.textColor70),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView.builder(
                    itemCount: notes.length,
                    itemBuilder: (context, index) {
                      final note = notes[index];
                      final timestamp = note['timestamp'] != null
                          ? DateTime.parse(note['timestamp']).toLocal()
                          : DateTime.now();
                      final formattedDate =
                          '${timestamp.day}/${timestamp.month}/${timestamp.year} at ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: context.isDark
                              ? context.glassBg
                              : Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: context.isDark
                                ? context.glassBorder
                                : Colors.black.withValues(alpha: 0.1),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF6366F1,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.gesture_rounded,
                              color: Color(0xFF6366F1),
                              size: 22,
                            ),
                          ),
                          title: Text(
                            note['title'] ?? 'Untitled Sketch',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: context.textColor,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              'Last edited: $formattedDate',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.textColor60,
                              ),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.open_in_new_rounded,
                                  color: Color(0xFF10B981),
                                ),
                                tooltip: 'Open and Edit Note',
                                onPressed: () => _openNoteInPad(note),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.redAccent,
                                ),
                                tooltip: 'Delete Note',
                                onPressed: () => _deleteNote(note['id']),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<dynamic>> _loadSavedNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final savedNotesStr = prefs.getString('jyamiti_my_notes') ?? '[]';
    return jsonDecode(savedNotesStr);
  }

  void _openNoteInPad(Map<String, dynamic> note) {
    final List<dynamic> linesList = note['lines'] ?? [];
    final List<DrawnLine> parsedLines = linesList.map((l) {
      final pointsList = (l['points'] as List).map((p) {
        return StrokePoint(
          Offset((p['dx'] as num).toDouble(), (p['dy'] as num).toDouble()),
        );
      }).toList();
      return DrawnLine(
        points: pointsList,
        color: Color(l['color'] as int),
        strokeWidth: (l['strokeWidth'] as num).toDouble(),
        isEraser: l['isEraser'] ?? false,
        isShape: l['isShape'] ?? false,
      );
    }).toList();

    JyamitiPadFullScreenPage.open(
      context,
      initialLines: parsedLines,
      enableSaveNotes: true,
      noteId: note['id'],
      noteTitle: note['title'],
    );
  }

  Future<void> _deleteNote(String noteId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Text(
            'Delete Note',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to delete this note? This action cannot be undone.',
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              child: const Text(
                'Delete',
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

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      final savedNotesStr = prefs.getString('jyamiti_my_notes') ?? '[]';
      final List<dynamic> savedNotes = jsonDecode(savedNotesStr);
      savedNotes.removeWhere((n) => n['id'] == noteId);
      await prefs.setString('jyamiti_my_notes', jsonEncode(savedNotes));
      setState(() {});
    }
  }
}
