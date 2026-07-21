import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../widgets/users_tab.dart';
import '../widgets/courses_tab.dart';
import '../widgets/batches_tab.dart';
import '../widgets/desktop_upload_tab.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/user/user_bloc.dart';
import '../bloc/course/course_bloc.dart';
import '../bloc/batch/batch_bloc.dart';
import '../bloc/batch_category/batch_category_bloc.dart';

class AdminConsoleScreen extends StatefulWidget {
  const AdminConsoleScreen({super.key});

  @override
  State<AdminConsoleScreen> createState() => _AdminConsoleScreenState();
}

class _AdminConsoleScreenState extends State<AdminConsoleScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<UserBloc>(create: (context) => UserBloc()),
        BlocProvider<CourseBloc>(create: (context) => CourseBloc()),
        BlocProvider<BatchCategoryBloc>(create: (context) => BatchCategoryBloc()),
        BlocProvider<BatchBloc>(create: (context) => BatchBloc()),
      ],
      child: Scaffold(
        extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'ADMIN CONSOLE',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, color: context.textColor, fontSize: 18),
        ).animate().fade().slideY(begin: -0.2, end: 0),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: context.textColor),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              height: 55,
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF1E293B) : Colors.white.withOpacity(0.6),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: context.glassBorder),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10)),
                ],
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.5), blurRadius: 15, spreadRadius: -2),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: context.textColor,
                unselectedLabelColor: context.textColor60,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
                tabs: const [
                  Tab(icon: Icon(Icons.people_alt_rounded, size: 18), iconMargin: EdgeInsets.only(bottom: 2), text: 'Users'),
                  Tab(icon: Icon(Icons.menu_book_rounded, size: 18), iconMargin: EdgeInsets.only(bottom: 2), text: 'Courses'),
                  Tab(icon: Icon(Icons.class_rounded, size: 18), iconMargin: EdgeInsets.only(bottom: 2), text: 'Batches'),
                  Tab(icon: Icon(Icons.system_update_rounded, size: 18), iconMargin: EdgeInsets.only(bottom: 2), text: 'Updates'),
                ],
              ),
            ).animate().fade(delay: 200.ms).scale(begin: const Offset(0.9, 0.9)),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: context.isDark ? const [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)] : const [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: SafeArea(
          child: TabBarView(
            controller: _tabController,
            children: const [
              UsersTab(),
              CoursesTab(),
              BatchesTab(),
              Padding(
                padding: EdgeInsets.all(16.0),
                child: DesktopUploadTab(),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
