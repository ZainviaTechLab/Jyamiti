import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:jyamiti/providers/auth_provider.dart';
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
import '../../slides/screens/slide_decks_manager_screen.dart';

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
          backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white.withValues(alpha: 0.8),
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
              child: Text(
                'Logout',
                style: TextStyle(color: context.textColor),
              ),
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
                      color: isSelected ? const Color(0xFF818CF8) : context.textColor70,
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

  Widget _buildRightContentArea() {
    switch (_selectedSidebarTab) {
      case 0:
        return BlocBuilder<AdminStatsBloc, AdminStatsState>(
          builder: (context, state) {
            if (state is AdminStatsLoading || state is AdminStatsInitial) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)));
            }
            if (state is AdminStatsError) {
              return Center(child: Text(state.message, style: const TextStyle(color: Colors.redAccent)));
            }
            if (state is AdminStatsLoaded) {
              final _stats = state.stats;
              final totals = _stats['totals'];
              final Map<String, dynamic> regTrends = _stats['registrationTrends'] ?? {};
              return Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        // Totals Cards
                        GridView.count(
                          crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.3,
                          children: [
                            _buildStatCard('TOTAL STUDENTS', totals['students'] ?? 0, const Color(0xFF6366F1), Icons.people_alt_rounded),
                            _buildStatCard('TOTAL TUTORS', totals['tutors'] ?? 0, const Color(0xFF10B981), Icons.person_rounded),
                            _buildStatCard('TOTAL COURSES', totals['courses'] ?? 0, const Color(0xFFF59E0B), Icons.book_rounded),
                            _buildStatCard('TOTAL BATCHES', totals['batches'] ?? 0, const Color(0xFFEC4899), Icons.class_rounded),
                          ],
                        ),
                        const SizedBox(height: 32),
                        // Charts / Graphs
                        Text(
                          'Registration Trends',
                          style: TextStyle(color: context.textColor, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          height: 300,
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: context.glassBg,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: context.glassBorder),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: regTrends.isEmpty
                                ? const Center(child: Text('No registration data available'))
                                : _buildRegistrationGraph(regTrends),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        );
      case 1:
        return const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: UsersTab(),
          ),
        );
      case 2:
        return const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: CoursesTab(),
          ),
        );
      case 3:
        return const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: BatchesTab(),
          ),
        );
      case 4:
        return const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: DesktopUploadTab(),
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
        BlocProvider<AdminStatsBloc>(create: (context) => AdminStatsBloc()..add(FetchAdminStats())),
        BlocProvider<UserBloc>(create: (context) => UserBloc()),
        BlocProvider<CourseBloc>(create: (context) => CourseBloc()),
        BlocProvider<BatchCategoryBloc>(create: (context) => BatchCategoryBloc()),
        BlocProvider<BatchBloc>(create: (context) => BatchBloc()),
      ],
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: isLargeScreen
            ? null
            : AppBar(
                title: const Text(
                  'Admin Dashboard',
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
                backgroundColor: Colors.transparent,
                elevation: 0,
                actions: [
                  IconButton(
                    icon: Icon(
                      context.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                      color: context.textColor,
                    ),
                    tooltip: 'Toggle Theme',
                    onPressed: () {
                      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
                      themeProvider.toggleTheme(!themeProvider.isDarkMode);
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.chat_bubble_outline_rounded, color: context.textColor),
                    tooltip: 'Messages',
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatListScreen())),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
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
                      ? context.isDark ? const [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)] : const [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)]
                      : const [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)],
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
                      child: Column(
                        children: [
                          const SizedBox(height: 24),
                          // App logo / Name
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.2),
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
                          _buildSidebarItem(0, 'Dashboard Stats', Icons.analytics_rounded),
                          _buildSidebarItem(1, 'Users', Icons.people_alt_rounded),
                          _buildSidebarItem(2, 'Courses', Icons.menu_book_rounded),
                          _buildSidebarItem(3, 'Batches', Icons.class_rounded),
                          _buildSidebarItem(4, 'Desktop Upload', Icons.system_update_rounded),
                          
                           const Spacer(),
                           
                           // Theme toggle link
                           Padding(
                             padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                             child: ClipRRect(
                               borderRadius: BorderRadius.circular(12),
                               child: Material(
                                 color: Colors.transparent,
                                 child: InkWell(
                                   onTap: () {
                                     final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
                                     themeProvider.toggleTheme(!themeProvider.isDarkMode);
                                   },
                                   child: Container(
                                     padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                     child: Row(
                                       children: [
                                         Icon(
                                           context.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                                           color: context.textColor70,
                                           size: 20,
                                         ),
                                         const SizedBox(width: 16),
                                         Text(
                                           context.isDark ? 'Light Theme' : 'Dark Theme',
                                           style: TextStyle(color: context.textColor70, fontSize: 14),
                                         ),
                                       ],
                                     ),
                                   ),
                                 ),
                               ),
                             ),
                           ),
                           
                           // Chat / Messages link
                           Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatListScreen())),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                    child: Row(
                                      children: [
                                        Icon(Icons.chat_bubble_outline_rounded, color: context.textColor70, size: 20),
                                        const SizedBox(width: 16),
                                        Text('Messages', style: TextStyle(color: context.textColor70, fontSize: 14)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          
                          // Sign Out Button
                          Padding(
                            padding: EdgeInsets.all(16.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _handleLogout(auth),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
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
                    
                    // Right Content Area
                    Expanded(
                      child: _buildRightContentArea(),
                    ),
                  ],
                ),
              )
            else
              SafeArea(
                child: BlocBuilder<AdminStatsBloc, AdminStatsState>(
                  builder: (context, state) {
                    if (state is AdminStatsLoading || state is AdminStatsInitial) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)));
                    }
                    if (state is AdminStatsError) {
                      return Center(child: Text(state.message, style: const TextStyle(color: Colors.redAccent)));
                    }
                    if (state is AdminStatsLoaded) {
                      final _stats = state.stats;
                      final totals = _stats['totals'];
                      final Map<String, dynamic> regTrends = _stats['registrationTrends'] ?? {};
                      return Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 1000),
                          child: SingleChildScrollView(
                            padding: EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 16),
                                // Totals Cards
                                GridView.count(
                                  crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  childAspectRatio: 1.3,
                                  children: [
                                    _buildStatCard('TOTAL STUDENTS', totals['students'] ?? 0, const Color(0xFF6366F1), Icons.people_alt_rounded),
                                    _buildStatCard('TOTAL TUTORS', totals['tutors'] ?? 0, const Color(0xFF10B981), Icons.person_rounded),
                                    _buildStatCard('TOTAL COURSES', totals['courses'] ?? 0, const Color(0xFFF59E0B), Icons.book_rounded),
                                    _buildStatCard('TOTAL BATCHES', totals['batches'] ?? 0, const Color(0xFFEC4899), Icons.class_rounded),
                                  ],
                                ),
                                const SizedBox(height: 32),
                                // Charts / Graphs
                                Text(
                                  'Registration Trends',
                                  style: TextStyle(color: context.textColor, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  height: 300,
                                  padding: EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: context.glassBg,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: context.glassBorder),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(24),
                                    child: regTrends.isEmpty
                                        ? const Center(child: Text('No registration data available'))
                                        : _buildRegistrationGraph(regTrends),
                                  ),
                                ),
                                const SizedBox(height: 40),
                                // Navigation Button
                                Center(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(color: const Color(0xFF6366F1).withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10)),
                                      ],
                                    ),
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF6366F1),
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        elevation: 0,
                                      ),
                                      icon: const Icon(Icons.dashboard_customize_rounded, size: 24),
                                      label: const Text('ENTER ADMIN CONSOLE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                                      onPressed: () {
                                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminConsoleScreen()));
                                      },
                                    ),
                                  ).animate().fade(duration: 600.ms, delay: 600.ms).slideY(begin: 0.3, end: 0),
                                ),
                                const SizedBox(height: 40),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, int count, Color color, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: context.glassBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: -5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color.withOpacity(0.8), size: 28),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: context.textColor,
                      shadows: [Shadow(color: color, blurRadius: 10)],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    style: TextStyle(
                      color: context.textColor70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRegistrationGraph(Map<String, dynamic> data) {
    final sortedKeys = data.keys.toList()..sort();
    final barGroups = <BarChartGroupData>[];
    double maxY = 0;

    for (int i = 0; i < sortedKeys.length; i++) {
      final value = data[sortedKeys[i]]['student'].toDouble();
      if (value > maxY) maxY = value;
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: value,
              color: const Color(0xFF6366F1),
              width: 16,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY + (maxY * 0.2) + 1, // Add some top padding
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                if (value.toInt() >= 0 && value.toInt() < sortedKeys.length) {
                  return Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text(
                      sortedKeys[value.toInt()].split('-')[1], // Month only
                      style: TextStyle(color: context.textColor70,
                        fontSize: 12,
                      ),
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                if (value % 1 != 0) return const Text(''); // Only show integers
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(color: context.textColor70, fontSize: 12),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 1,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: context.glassBorder, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        barGroups: barGroups,
      ),
    );
  }
}
