import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/theme_provider.dart';
import '../../../widgets/ask_jyammy_dialog.dart';
import '../../../widgets/writing_pad_widget.dart';
import '../../academic/screens/batch_worksheets_screen.dart';
import '../../academic/screens/batch_notes_screen.dart';
import '../../exams/screens/exam_management_screen.dart';
import '../../academic/screens/schedules_screen.dart';
import '../../academic/screens/student_tutorials_screen.dart';
import '../../academic/screens/student_learning_path_screen.dart';
import '../../academic/screens/student_assignments_screen.dart';
import 'student_performance_screen.dart';
import 'student_payments_screen.dart';
import 'student_settings_screen.dart';
import 'student_detailed_attendance_screen.dart';
import '../../meetings/screens/parent_meetings_dashboard_screen.dart';
import '../../meetings/screens/parent_meeting_room_screen.dart';
import '../../../../services/parent_meeting_service.dart';
import '../../../../services/class_meeting_service.dart';
import '../../../../services/class_meeting_socket_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/student_dashboard/student_dashboard_bloc.dart';
import '../bloc/student_dashboard/student_dashboard_event.dart';
import '../bloc/student_dashboard/student_dashboard_state.dart';
import '../../../../services/api_service.dart';
import '../../chat/screens/chat_list_screen.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  int _selectedSidebarTab =
      0; // 0 = Overview, 1 = Schedules, 2 = Messages, 3 = Performance, 4 = Payments, 5 = Settings
  Widget? _activeInlineSubScreen;

  // "Start Class"'s student-side counterpart -- see
  // `_buildStudentJoinClassCard`. Loaded once on mount (catches a class
  // that was already live before this screen opened) and kept live via
  // `ClassMeetingSocketService` (catches one starting/ending while the
  // student is already looking at the dashboard).
  Map<String, dynamic>? _liveClassMeeting;

  @override
  void initState() {
    super.initState();
    context.read<StudentDashboardBloc>().add(FetchStudentDashboardSummary());
    Future.microtask(() {
      if (mounted) {
        Provider.of<AuthProvider>(context, listen: false).fetchProfile();
      }
    });
    _loadLiveClassMeeting();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.userId != null) {
      ClassMeetingSocketService.instance.connect(auth.userId!);
    }
    ClassMeetingSocketService.instance.onClassStarted = (meeting) {
      if (mounted) setState(() => _liveClassMeeting = meeting);
    };
    ClassMeetingSocketService.instance.onClassEnded = (meetingId) {
      if (mounted &&
          _liveClassMeeting != null &&
          _liveClassMeeting!['_id'].toString() == meetingId) {
        setState(() => _liveClassMeeting = null);
      }
    };
  }

  Future<void> _loadLiveClassMeeting() async {
    try {
      final meetings = await ClassMeetingService.getMyLiveMeetings();
      if (mounted && meetings.isNotEmpty) {
        setState(() => _liveClassMeeting = meetings.first);
      }
    } catch (_) {
      // Silent -- this is a best-effort live banner, not core dashboard
      // data; a failed check here shouldn't block/error the rest of the
      // dashboard.
    }
  }

  @override
  void dispose() {
    ClassMeetingSocketService.instance.disconnect();
    super.dispose();
  }

  Future<void> _handleLogout(AuthProvider auth) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: context.isDark
              ? const Color(0xFF1E293B)
              : Colors.white.withOpacity(0.8),
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
                backgroundColor: Colors.redAccent.withOpacity(0.8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Logout', style: TextStyle(color: context.textColor)),
            ),
          ],
        ),
      ),
    );

    if (confirm == true && mounted) {
      auth.logout();
    }
  }

  Widget _buildSidebarItem(int index, String title, IconData icon) {
    final isSelected = _selectedSidebarTab == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Material(
            color: isSelected
                ? const Color(0xFF6366F1).withOpacity(0.2)
                : Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedSidebarTab = index;
                  _activeInlineSubScreen = null;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF6366F1).withOpacity(0.5)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      color: isSelected
                          ? const Color(0xFF818CF8)
                          : context.textColor70,
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

  Widget _buildRightContentArea(
    Map<String, dynamic>? profile,
    AuthProvider auth,
  ) {
    final isLargeScreen = MediaQuery.of(context).size.width > 900;
    if (isLargeScreen && _activeInlineSubScreen != null) {
      return _activeInlineSubScreen!;
    }

    switch (_selectedSidebarTab) {
      case 0:
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: context.isDark
                          ? Colors.black.withOpacity(0.2)
                          : const Color(0xFF3B82F6).withOpacity(0.06),
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
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: context.isDark
                            ? Colors.white.withOpacity(0.03)
                            : Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: context.isDark
                              ? context.textColor.withOpacity(0.08)
                              : const Color(0xFF8B5CF6).withOpacity(0.15),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6).withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.school_rounded,
                              size: 32,
                              color: Color(0xFF3B82F6),
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
                                    color: context.textColor.withOpacity(0.7),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  auth.userName ?? 'Student',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: context.textColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          BlocBuilder<
                            StudentDashboardBloc,
                            StudentDashboardState
                          >(
                            builder: (context, state) {
                              if (state is StudentDashboardLoading ||
                                  state is StudentDashboardInitial) {
                                return const SizedBox.shrink();
                              }
                              String totalSweets = '0';
                              if (state is StudentDashboardLoaded) {
                                totalSweets =
                                    state.summaryData['totalSweets']
                                        ?.toString() ??
                                    '0';
                              }
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFF59E0B,
                                  ).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(
                                      0xFFF59E0B,
                                    ).withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      '🍬',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      totalSweets,
                                      style: TextStyle(
                                        color: context.textColor,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ).animate().fade(duration: 400.ms).slideY(begin: 0.2, end: 0),

              const SizedBox(height: 24),
              _buildStudentDashboard(profile, context),
            ],
          ),
        );
      case 1:
        return const SchedulesScreen(isInline: true);
      case 2:
        return const ChatListScreen(isInline: true);
      case 3:
        return const StudentPerformanceScreen(isInline: true);
      case 4:
        return const StudentPaymentsScreen(isInline: true);
      case 5:
        return const StudentSettingsScreen(isInline: true);
      case 6:
        final batches = profile?['batches'] as List?;
        if (batches == null || batches.isEmpty) {
          return const Center(child: Text('No batches assigned.'));
        }
        return StudentLearningPathScreen(batch: batches[0], isInline: true);
      case 7:
        return const StudentAssignmentsScreen(isInline: true);
      case 9:
        return ParentMeetingsDashboardScreen(
          isInline: true,
          onBack: () => setState(() => _selectedSidebarTab = 0),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final profile = auth.profile;
    final isLargeScreen = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      extendBodyBehindAppBar: true,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'ask_jyammy_fab',
        onPressed: () => AskJyammyDialog.show(context),
        backgroundColor: const Color(0xFF6366F1),
        elevation: 8,
        icon: Image.asset(
          'assets/image/Jyammy.png',
          width: 24,
          height: 24,
          fit: BoxFit.contain,
        ),
        label: const Text(
          'Ask Jyammy',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
      appBar: isLargeScreen
          ? null
          : AppBar(
              title: const Text(
                'Dashboard',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ).animate().fade().slideY(begin: -0.2, end: 0),
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: IconThemeData(color: context.textColor),
              actions: [
                // IconButton(
                //   icon: Image.asset('assets/image/Jyammy.png', width: 24, height: 24, fit: BoxFit.contain),
                //   tooltip: 'Ask Jyammy AI',
                //   onPressed: () => AskJyammyDialog.show(context),
                // ),
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
                  icon: Icon(Icons.settings_rounded, color: context.textColor),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StudentSettingsScreen(),
                    ),
                  ),
                ),
              ],
            ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: context.isDark
                    ? [
                        const Color(0xFF0F172A),
                        const Color(0xFF1E1B4B),
                        const Color(0xFF0F172A),
                      ]
                    : [
                        const Color(0xFFF1F5F9),
                        const Color(0xFFE2E8F0),
                        const Color(0xFFF1F5F9),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          if (isLargeScreen)
            SafeArea(
              child: Row(
                children: [
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.school_rounded,
                                color: Color(0xFF818CF8),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Jyamiti Student',
                              style: TextStyle(
                                color: context.textColor,
                                fontSize: 18,
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
                          6,
                          'Learning Path',
                          Icons.auto_stories_rounded,
                        ),
                        _buildSidebarItem(
                          7,
                          'Assignments',
                          Icons.assignment_rounded,
                        ),
                        _buildSidebarItem(
                          9,
                          'Parent Meetings',
                          Icons.video_call_rounded,
                        ),
                        _buildSidebarItem(
                          3,
                          'Performance',
                          Icons.bar_chart_rounded,
                        ),
                        _buildSidebarItem(4, 'Payments', Icons.payment_rounded),
                        _buildSidebarItem(
                          5,
                          'Settings',
                          Icons.settings_rounded,
                        ),

                        const Spacer(),

                        _buildSidebarItem(
                          2,
                          'Messages',
                          Icons.chat_bubble_outline_rounded,
                        ),

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

                  Expanded(child: _buildRightContentArea(profile, auth)),
                ],
              ),
            )
          else
            SafeArea(
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20.0,
                      vertical: 24.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: context.isDark
                                        ? Colors.black.withOpacity(0.2)
                                        : const Color(
                                            0xFF3B82F6,
                                          ).withOpacity(0.06),
                                    blurRadius: 30,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 16,
                                    sigmaY: 16,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(16.0),
                                    decoration: BoxDecoration(
                                      color: context.isDark
                                          ? Colors.white.withOpacity(0.03)
                                          : Colors.white.withOpacity(0.95),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: context.isDark
                                            ? context.textColor.withOpacity(
                                                0.08,
                                              )
                                            : const Color(
                                                0xFF8B5CF6,
                                              ).withOpacity(0.15),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF3B82F6,
                                            ).withOpacity(0.2),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.school_rounded,
                                            size: 32,
                                            color: Color(0xFF3B82F6),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Welcome back,',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: context.textColor
                                                      .withOpacity(0.7),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                auth.userName ?? 'Student',
                                                style: TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.bold,
                                                  color: context.textColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        BlocBuilder<
                                          StudentDashboardBloc,
                                          StudentDashboardState
                                        >(
                                          builder: (context, state) {
                                            if (state
                                                    is StudentDashboardLoading ||
                                                state
                                                    is StudentDashboardInitial) {
                                              return const SizedBox.shrink();
                                            }
                                            String totalSweets = '0';
                                            if (state
                                                is StudentDashboardLoaded) {
                                              totalSweets =
                                                  state
                                                      .summaryData['totalSweets']
                                                      ?.toString() ??
                                                  '0';
                                            }
                                            return Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(
                                                  0xFFF59E0B,
                                                ).withOpacity(0.2),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFFF59E0B,
                                                  ).withOpacity(0.3),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Text(
                                                    '🍬',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    totalSweets,
                                                    style: TextStyle(
                                                      color: context.textColor,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .animate()
                            .fade(duration: 400.ms)
                            .slideY(begin: 0.2, end: 0),

                        const SizedBox(height: 10),
                        _buildStudentDashboard(profile, context),
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

  Widget _buildStudentDashboard(
    Map<String, dynamic>? profile,
    BuildContext context,
  ) {
    if (profile == null) {
      return Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Attendance Pie Chart
        BlocBuilder<StudentDashboardBloc, StudentDashboardState>(
          builder: (context, state) {
            if (state is StudentDashboardLoading ||
                state is StudentDashboardInitial) {
              return Container(
                height: 220,
                decoration: BoxDecoration(
                  color: context.glassBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: context.glassBorder),
                ),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF10B981)),
                ),
              );
            }

            Map<String, dynamic> data = {};
            if (state is StudentDashboardLoaded) {
              data = state.summaryData;
            } else if (state is StudentDashboardError) {
              return Center(
                child: Text(state.message, style: TextStyle(color: Colors.red)),
              );
            }

            final present = data['present']?.toString() ?? '0';
            final absent = data['absent']?.toString() ?? '0';
            final leave = data['leave']?.toString() ?? '0';
            final percentageNum = data['percentage']?.toDouble() ?? 0.0;
            final streak = data['streak']?.toString() ?? '0';

            final percentageStr = '${percentageNum.toStringAsFixed(1)}%';

            return Column(
                  children: [
                    _buildStudentJoinClassCard(context),
                    _buildStudentParentMeetingsCard(context),
                    ActiveAssignmentsPreview(
                      onNavigateToAssignments: () {
                        // Force navigation to assignments tab
                        setState(() {
                          _selectedSidebarTab = 7;
                          _activeInlineSubScreen = null;
                        });
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Attendance Overview',
                          style: TextStyle(
                            color: context.textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    StudentDetailedAttendanceScreen(
                                      summaryData: data,
                                    ),
                              ),
                            );
                          },
                          child: Text(
                            'Details',
                            style: TextStyle(
                              color: Color(0xFF818CF8),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: context.isDark
                                ? Colors.black.withOpacity(0.2)
                                : const Color(0xFF6366F1).withOpacity(0.06),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: context.isDark
                                  ? Colors.white.withOpacity(0.03)
                                  : Colors.white.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: context.isDark
                                    ? context.textColor.withOpacity(0.08)
                                    : Colors.white.withOpacity(0.6),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Percentage Circle
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      width: 100,
                                      height: 100,
                                      child: CircularProgressIndicator(
                                        value: percentageNum / 100.0,
                                        strokeWidth: 10,
                                        backgroundColor: context.glassBorder,
                                        valueColor:
                                            const AlwaysStoppedAnimation<Color>(
                                              Color(0xFF10B981),
                                            ),
                                        strokeCap: StrokeCap.round,
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          percentageStr,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF10B981),
                                          ),
                                        ),
                                        Text(
                                          'Attendance',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: context.textColor
                                                .withOpacity(0.7),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 32),

                                // Stats
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildStatRow(
                                        'Present',
                                        present,
                                        const Color(0xFF10B981),
                                      ),
                                      _buildStatRow(
                                        'Absent',
                                        absent,
                                        Colors.redAccent,
                                      ),
                                      _buildStatRow(
                                        'Leave',
                                        leave,
                                        const Color(0xFFF59E0B),
                                      ),
                                      const SizedBox(height: 12),
                                      // Streak Chip
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF10B981,
                                          ).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: const Color(
                                              0xFF10B981,
                                            ).withOpacity(0.3),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons
                                                  .local_fire_department_rounded,
                                              color: Color(0xFF10B981),
                                              size: 16,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '$streak days streak',
                                              style: TextStyle(
                                                color: context.textColor,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
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
                      ),
                    ),
                  ],
                )
                .animate()
                .fade(duration: 400.ms, delay: 100.ms)
                .slideY(begin: 0.1, end: 0);
          },
        ),
        const SizedBox(height: 12),

        // Quick Actions Grid
        Text(
          'Quick Actions',
          style: TextStyle(
            color: context.textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 16),
        Builder(
          builder: (context) {
            final screenWidth = MediaQuery.of(context).size.width;
            final crossAxisCount = screenWidth > 900
                ? 6
                : (screenWidth > 600 ? 4 : 3);
            final childAspectRatio = screenWidth > 900 ? 1.05 : 0.9;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: childAspectRatio,
              children: [
                _buildGridAction(
                  context,
                  'Worksheets',
                  Icons.book_rounded,
                  const Color(0xFF6366F1),
                  () => _handleGridNavigation(context, profile, 'Worksheets'),
                ),
                _buildGridAction(
                  context,
                  'Notes',
                  Icons.note_alt_rounded,
                  const Color(0xFF8B5CF6),
                  () => _handleGridNavigation(context, profile, 'notes'),
                ),
                _buildGridAction(
                  context,
                  'Exams',
                  Icons.quiz_rounded,
                  const Color(0xFF10B981),
                  () => _handleGridNavigation(context, profile, 'exams'),
                ),

                _buildGridAction(
                  context,
                  'Tutorials',
                  Icons.play_circle_filled_rounded,
                  const Color(0xFFEC4899),
                  () => _handleGridNavigation(context, profile, 'tutorials'),
                ),
                _buildGridAction(
                  context,
                  'Assignments',
                  Icons.assignment_rounded,
                  const Color(0xFF3B82F6),
                  () {
                    if (MediaQuery.of(context).size.width > 900) {
                      setState(() => _selectedSidebarTab = 7);
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const StudentAssignmentsScreen(),
                        ),
                      );
                    }
                  },
                ),
                _buildGridAction(
                  context,
                  'Learning Path',
                  Icons.auto_stories_rounded,
                  const Color(0xFF8B5CF6),
                  () =>
                      _handleGridNavigation(context, profile, 'learning_path'),
                ),
                _buildGridAction(
                  context,
                  'Performance',
                  Icons.bar_chart_rounded,
                  const Color.fromARGB(255, 243, 39, 29),
                  () {
                    if (MediaQuery.of(context).size.width > 900) {
                      setState(() => _selectedSidebarTab = 3);
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const StudentPerformanceScreen(),
                        ),
                      );
                    }
                  },
                ),
                _buildGridAction(
                  context,
                  'Payments',
                  Icons.payment_rounded,
                  const Color(0xFFF59E0B),
                  () {
                    if (MediaQuery.of(context).size.width > 900) {
                      setState(() => _selectedSidebarTab = 4);
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const StudentPaymentsScreen(),
                        ),
                      );
                    }
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              color: context.textColor70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: context.textColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridAction(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    final isDark = context.isDark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(isDark ? 0.08 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.02)
                  : Colors.white.withOpacity(0.75),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? color.withOpacity(0.2)
                    : color.withOpacity(0.35),
                width: 1.2,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).animate().fade(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }

  void _handleGridNavigation(
    BuildContext context,
    Map<String, dynamic> profile,
    String action,
  ) {
    final batches = profile['batches'] as List?;
    if (batches == null || batches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are not assigned to any batches.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (batches.length == 1) {
      _navigateToScreen(context, action, batches[0]);
    } else {
      // Show bottom sheet to select batch
      showModalBottomSheet(
        context: context,
        backgroundColor: context.isDark
            ? const Color(0xFF1E293B)
            : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) {
          return Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Batch',
                  style: TextStyle(
                    color: context.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 16),
                ...batches.map(
                  (b) => ListTile(
                    title: Text(
                      b['name'],
                      style: TextStyle(color: context.textColor),
                    ),
                    subtitle: Text(
                      b['course']['name'],
                      style: TextStyle(color: context.textColor60),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: context.textColor54,
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _navigateToScreen(context, action, b);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  void _navigateToScreen(BuildContext context, String action, dynamic batch) {
    final isLargeScreen = MediaQuery.of(context).size.width > 900;
    if (isLargeScreen) {
      setState(() {
        if (action == 'Worksheets') {
          _activeInlineSubScreen = BatchWorksheetsScreen(
            batch: batch,
            isInline: true,
            onBack: () => setState(() => _activeInlineSubScreen = null),
          );
        } else if (action == 'notes') {
          _activeInlineSubScreen = BatchNotesScreen(
            batch: batch,
            isInline: true,
            onBack: () => setState(() => _activeInlineSubScreen = null),
          );
        } else if (action == 'exams') {
          _activeInlineSubScreen = ExamManagementScreen(
            batch: batch,
            isInline: true,
            onBack: () => setState(() => _activeInlineSubScreen = null),
          );
        } else if (action == 'tutorials') {
          _activeInlineSubScreen = StudentTutorialsScreen(
            batch: batch,
            isInline: true,
            onBack: () => setState(() => _activeInlineSubScreen = null),
          );
        } else if (action == 'learning_path') {
          _activeInlineSubScreen = StudentLearningPathScreen(
            batch: batch,
            isInline: true,
            onBack: () => setState(() => _activeInlineSubScreen = null),
          );
        }
      });
    } else {
      if (action == 'Worksheets') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BatchWorksheetsScreen(batch: batch),
          ),
        );
      } else if (action == 'notes') {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BatchNotesScreen(batch: batch)),
        );
      } else if (action == 'exams') {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ExamManagementScreen(batch: batch)),
        );
      } else if (action == 'tutorials') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentTutorialsScreen(batch: batch),
          ),
        );
      } else if (action == 'learning_path') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentLearningPathScreen(batch: batch),
          ),
        );
      }
    }
  }

  /// "Start Class"'s student-side banner -- same visual shape as
  /// `_buildStudentParentMeetingsCard` below, but driven by
  /// `_liveClassMeeting` (loaded once + kept live via
  /// `ClassMeetingSocketService`, see `initState`) instead of a
  /// `FutureBuilder` re-polled only on rebuild, since a class starting
  /// needs to show up the INSTANT the tutor starts it, not just next
  /// time this widget happens to rebuild.
  Widget _buildStudentJoinClassCard(BuildContext context) {
    final m = _liveClassMeeting;
    if (m == null) return const SizedBox.shrink();

    final title = m['title'] ?? 'Live Class';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.redAccent, width: 2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.school_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.toString(),
                        style: TextStyle(
                          color: context.textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '🔴 CLASS LIVE NOW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Tutor: ${m['hostName'] ?? 'Tutor'} • ${m['batchName'] ?? 'Batch'}',
                  style: TextStyle(color: context.textColor70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.login_rounded, size: 16),
            label: const Text(
              'Join Class',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ParentMeetingRoomScreen(
                    meeting: Map<String, dynamic>.from(m),
                    isHost: false,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStudentParentMeetingsCard(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: ParentMeetingService.getMyMeetings(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final meetings = snapshot.data!;
        final activeMeetings = meetings
            .where((m) => m['status'] == 'live' || m['status'] == 'scheduled')
            .toList();

        if (activeMeetings.isEmpty) return const SizedBox.shrink();

        final m = activeMeetings.first as Map;
        final title = m['title'] ?? 'Parent Meeting';
        final status = (m['status'] ?? 'scheduled').toString();
        final isLive = status == 'live';

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isLive
                ? Colors.redAccent.withValues(alpha: 0.12)
                : const Color(0xFF6366F1).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isLive ? Colors.redAccent : const Color(0xFF6366F1),
              width: isLive ? 2 : 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isLive ? Colors.redAccent : const Color(0xFF6366F1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.video_call_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title.toString(),
                            style: TextStyle(
                              color: context.textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isLive
                                ? Colors.redAccent
                                : const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isLive ? '🔴 LIVE NOW' : '📅 SCHEDULED',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Host: ${m['hostName'] ?? 'Tutor'} • ${m['batchName'] ?? 'Batch'}',
                      style: TextStyle(
                        color: context.textColor70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isLive ? Colors.redAccent : const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.login_rounded, size: 16),
                label: const Text(
                  'Join Meeting',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ParentMeetingRoomScreen(
                        meeting: Map<String, dynamic>.from(m),
                        isHost: false,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class ActiveAssignmentsPreview extends StatefulWidget {
  final VoidCallback onNavigateToAssignments;

  const ActiveAssignmentsPreview({
    super.key,
    required this.onNavigateToAssignments,
  });

  @override
  State<ActiveAssignmentsPreview> createState() =>
      _ActiveAssignmentsPreviewState();
}

class _ActiveAssignmentsPreviewState extends State<ActiveAssignmentsPreview> {
  bool _isLoading = true;
  List<dynamic> _assignments = [];

  @override
  void initState() {
    super.initState();
    _fetchAssignments();
  }

  Future<void> _fetchAssignments() async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final res = await ApiService.getStudentAssignments(auth.userId ?? '');
      if (res.statusCode == 200) {
        final List<dynamic> allAssignments = jsonDecode(res.body);
        final pending = allAssignments
            .where((a) => a['status'] != 'completed')
            .toList();
        if (mounted) {
          setState(() {
            _assignments = pending.take(2).toList();
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 100,
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          color: context.glassBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.glassBorder),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF6366F1)),
        ),
      );
    }

    if (_assignments.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF6366F1).withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Active Assignments',
                style: TextStyle(
                  color: context.textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: widget.onNavigateToAssignments,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6366F1),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'View All',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._assignments.map((assignment) {
            IconData icon = Icons.assignment;
            Color color = const Color(0xFF6366F1);
            if (assignment['itemType'] == 'video') {
              icon = Icons.play_circle_fill_rounded;
              color = Colors.redAccent;
            } else if (assignment['itemType'] == 'slide') {
              icon = Icons.slideshow_rounded;
              color = const Color(0xFFEC4899);
            } else if (assignment['itemType'] == 'practice_question') {
              icon = Icons.assignment_turned_in_rounded;
              color = const Color(0xFF10B981);
            }

            return InkWell(
              onTap: widget.onNavigateToAssignments,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.isDark
                      ? Colors.white.withOpacity(0.03)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.glassBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        assignment['itemTitle'] ?? 'Resource Assignment',
                        style: TextStyle(
                          color: context.textColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
