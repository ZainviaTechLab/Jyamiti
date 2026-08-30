import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:jyamiti/providers/auth_provider.dart';
import '../../../widgets/theme_reveal.dart';
import '../bloc/admin_stats/admin_stats_bloc.dart';
import '../bloc/admin_stats/admin_stats_event.dart';
import '../bloc/admin_stats/admin_stats_state.dart';
import 'package:provider/provider.dart';
import 'admin_console_screen.dart';
import '../../chat/screens/chat_list_screen.dart';
import '../bloc/user/user_bloc.dart';
import '../bloc/course/course_bloc.dart';
import '../bloc/batch/batch_bloc.dart';
import '../bloc/batch_category/batch_category_bloc.dart';
import '../widgets/users_tab.dart';
import '../widgets/courses_tab.dart';
import '../widgets/batches_tab.dart';
import '../widgets/desktop_upload_tab.dart';
import '../widgets/dashboard_stats_view.dart';
import '../../exams/screens/question_bank_screen.dart';
import '../../exams/screens/assessment_question_management_screen.dart';

class AdminStatsDashboard extends StatefulWidget {
  const AdminStatsDashboard({super.key});

  @override
  State<AdminStatsDashboard> createState() => _AdminStatsDashboardState();
}

class _AdminStatsDashboardState extends State<AdminStatsDashboard> {
  int _selectedSidebarTab = 0; // 0 = Stats, 1 = Users, 2 = Courses, 3 = Batches

  Future<void> _handleLogout(AuthProvider auth) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: context.isDark
              ? const Color(0xFF1E293B)
              : Colors.white.withValues(alpha: 0.8),
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
      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Material(
            color: isSelected
                ? const Color(0xFF6366F1).withValues(alpha: 0.2)
                : Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedSidebarTab = index;
                });
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF6366F1).withValues(alpha: 0.5)
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

  Widget _buildRightContentArea() {
    switch (_selectedSidebarTab) {
      case 0:
        return BlocBuilder<AdminStatsBloc, AdminStatsState>(
          builder: (context, state) {
            if (state is AdminStatsLoading || state is AdminStatsInitial) {
              return const Center(
                child: JyamitiLoader(color: Color(0xFF6366F1)),
              );
            }
            if (state is AdminStatsError) {
              return Center(
                child: Text(
                  state.message,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              );
            }
            if (state is AdminStatsLoaded) {
              return RefreshIndicator(
                onRefresh: () async {
                  context.read<AdminStatsBloc>().add(FetchAdminStats());
                },
                child: DashboardStatsView(stats: state.stats),
              );
            }
            return const SizedBox.shrink();
          },
        );
      case 1:
        return const SafeArea(
          child: Padding(padding: EdgeInsets.all(24.0), child: UsersTab()),
        );
      case 2:
        return const SafeArea(
          child: Padding(padding: EdgeInsets.all(24.0), child: CoursesTab()),
        );
      case 3:
        return const SafeArea(
          child: Padding(padding: EdgeInsets.all(24.0), child: BatchesTab()),
        );
      case 4:
        return const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: DesktopUploadTab(),
          ),
        );
      case 5:
        return const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: QuestionBankScreen(isInline: true),
          ),
        );
      case 6:
        return const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: AssessmentQuestionManagementScreen(isInline: true),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth > 900;

    return MultiBlocProvider(
      providers: [
        BlocProvider<AdminStatsBloc>(
          create: (context) => AdminStatsBloc()..add(FetchAdminStats()),
        ),
        BlocProvider<UserBloc>(create: (context) => UserBloc()),
        BlocProvider<CourseBloc>(create: (context) => CourseBloc()),
        BlocProvider<BatchCategoryBloc>(
          create: (context) => BatchCategoryBloc(),
        ),
        BlocProvider<BatchBloc>(create: (context) => BatchBloc()),
      ],
      child: Scaffold(
        extendBodyBehindAppBar: true,
        drawer: isLargeScreen
            ? null
            : Drawer(
                child: Container(
                  color: context.isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF8FAFC),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      DrawerHeader(
                        decoration: BoxDecoration(
                          color: context.isDark
                              ? const Color(0xFF1E1B4B)
                              : const Color(0xFFEEF2F6),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Color(0xFF6366F1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.shield_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Admin Menu',
                              style: TextStyle(
                                color: context.textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.analytics_rounded,
                          color: Color(0xFF6366F1),
                        ),
                        title: Text(
                          'Dashboard Stats',
                          style: TextStyle(color: context.textColor),
                        ),
                        selected: _selectedSidebarTab == 0,
                        onTap: () {
                          Navigator.pop(context);
                          setState(() {
                            _selectedSidebarTab = 0;
                          });
                        },
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.library_books_rounded,
                          color: Color(0xFFF59E0B),
                        ),
                        title: Text(
                          'Question Bank',
                          style: TextStyle(color: context.textColor),
                        ),
                        selected: _selectedSidebarTab == 5,
                        onTap: () {
                          Navigator.pop(context);
                          setState(() {
                            _selectedSidebarTab = 5;
                          });
                        },
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.assessment_rounded,
                          color: Color(0xFF8B5CF6),
                        ),
                        title: Text(
                          'Assessment Question',
                          style: TextStyle(color: context.textColor),
                        ),
                        selected: _selectedSidebarTab == 6,
                        onTap: () {
                          Navigator.pop(context);
                          setState(() {
                            _selectedSidebarTab = 6;
                          });
                        },
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.admin_panel_settings_rounded,
                          color: Color(0xFF10B981),
                        ),
                        title: Text(
                          'Admin Console',
                          style: TextStyle(color: context.textColor),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminConsoleScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(),
                      ListTile(
                        leading: const Icon(
                          Icons.people_alt_rounded,
                          color: Color(0xFF6366F1),
                        ),
                        title: Text(
                          'Users',
                          style: TextStyle(color: context.textColor),
                        ),
                        selected: _selectedSidebarTab == 1,
                        onTap: () {
                          Navigator.pop(context);
                          setState(() {
                            _selectedSidebarTab = 1;
                          });
                        },
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.menu_book_rounded,
                          color: Color(0xFFF59E0B),
                        ),
                        title: Text(
                          'Courses',
                          style: TextStyle(color: context.textColor),
                        ),
                        selected: _selectedSidebarTab == 2,
                        onTap: () {
                          Navigator.pop(context);
                          setState(() {
                            _selectedSidebarTab = 2;
                          });
                        },
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.class_rounded,
                          color: Color(0xFF8B5CF6),
                        ),
                        title: Text(
                          'Batches',
                          style: TextStyle(color: context.textColor),
                        ),
                        selected: _selectedSidebarTab == 3,
                        onTap: () {
                          Navigator.pop(context);
                          setState(() {
                            _selectedSidebarTab = 3;
                          });
                        },
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.system_update_rounded,
                          color: Color(0xFFEC4899),
                        ),
                        title: Text(
                          'Desktop Upload',
                          style: TextStyle(color: context.textColor),
                        ),
                        selected: _selectedSidebarTab == 4,
                        onTap: () {
                          Navigator.pop(context);
                          setState(() {
                            _selectedSidebarTab = 4;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
        appBar: isLargeScreen
            ? null
            : AppBar(
                title: const Text(
                  'Admin Dashboard',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
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
                    tooltip: 'Messages',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ChatListScreen()),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: Colors.redAccent,
                    ),
                    tooltip: 'Sign Out',
                    onPressed: () => _handleLogout(auth),
                  ),
                ],
              ),
        body: Stack(
          children: [
            // Futuristic Gradient Background
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: context.isDark
                      ? context.isDark
                            ? const [
                                Color(0xFF0F172A),
                                Color(0xFF1E1B4B),
                                Color(0xFF0F172A),
                              ]
                            : const [
                                Color(0xFFF1F5F9),
                                Color(0xFFE2E8F0),
                                Color(0xFFF1F5F9),
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
            if (isLargeScreen)
              SafeArea(
                child: Row(
                  children: [
                    // Left Sidebar Pane
                    Container(
                      width: 260,
                      decoration: BoxDecoration(
                        color: context.glassBg,
                        border: Border(
                          right: BorderSide(color: context.glassBorder),
                        ),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight,
                              ),
                              child: IntrinsicHeight(
                                child: Column(
                                  children: [
                                    const SizedBox(height: 24),
                                    // App logo / Name
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF6366F1,
                                            ).withValues(alpha: 0.2),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.admin_panel_settings_rounded,
                                            color: Color(0xFF818CF8),
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Jyamiti Admin',
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

                                    // Menu items
                                    _buildSidebarItem(
                                      0,
                                      'Dashboard Stats',
                                      Icons.analytics_rounded,
                                    ),
                                    _buildSidebarItem(
                                      1,
                                      'Users',
                                      Icons.people_alt_rounded,
                                    ),
                                    _buildSidebarItem(
                                      2,
                                      'Courses',
                                      Icons.menu_book_rounded,
                                    ),
                                    _buildSidebarItem(3, 'Batches', Icons.class_rounded),
                                    _buildSidebarItem(
                                      4,
                                      'Desktop Upload',
                                      Icons.system_update_rounded,
                                    ),
                                    _buildSidebarItem(
                                      5,
                                      'Question Bank',
                                      Icons.library_books_rounded,
                                    ),
                                    _buildSidebarItem(
                                      6,
                                      'Assessments',
                                      Icons.assessment_rounded,
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

                                    // Chat / Messages link
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
                                            onTap: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => const ChatListScreen(),
                                              ),
                                            ),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 16.0,
                                                vertical: 12.0,
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.chat_bubble_outline_rounded,
                                                    color: context.textColor70,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 16),
                                                  Text(
                                                    'Messages',
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

                                    // Sign Out Button
                                    Padding(
                                      padding: const EdgeInsets.all(16.0),
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
                            ),
                          );
                        },
                      ),
                    ),

                    // Right Content Area
                    Expanded(child: _buildRightContentArea()),
                  ],
                ),
              )
            else
              SafeArea(child: _buildRightContentArea()),
          ],
        ),
      ),
    );
  }

}
