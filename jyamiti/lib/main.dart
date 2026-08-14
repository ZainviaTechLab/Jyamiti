import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'presentation/features/auth/screens/login_screen.dart';
import 'presentation/features/auth/screens/splash_screen.dart';
import 'presentation/features/admin/screens/admin_stats_dashboard.dart';
import 'presentation/features/dashboard/screens/student_dashboard.dart';
import 'presentation/features/dashboard/screens/tutor_dashboard.dart';
import 'presentation/features/dashboard/screens/mentor_dashboard.dart';
import 'core/theme/app_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'presentation/features/chat/bloc/chat_bloc.dart';
import 'presentation/features/dashboard/bloc/student_dashboard/student_dashboard_bloc.dart';
import 'presentation/features/dashboard/bloc/student_performance/student_performance_bloc.dart';
import 'presentation/features/dashboard/bloc/student_payments/student_payments_bloc.dart';
import 'presentation/features/academic/bloc/schedules/schedules_bloc.dart';
import 'dart:io' show Platform;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:media_kit/media_kit.dart';
import 'services/api_service.dart';
import 'services/offline_sync_service.dart';
import 'presentation/widgets/theme_reveal.dart';
import 'presentation/features/mathpad/mathpad_shader_warmup.dart';
import 'presentation/features/mathpad/recording/mathpad_recording_service.dart';

void main() {
  // Must be set before `WidgetsFlutterBinding.ensureInitialized()` --
  // `PaintingBinding.initInstances()` (which that call triggers) is what
  // actually runs it. See `MathPadShaderWarmUp`'s doc comment for the real
  // jank this fixes (found via a live DevTools capture: a single frame
  // spending 461ms compiling shaders mid-drawing on a heavily-used page).
  PaintingBinding.shaderWarmUp = const MathPadShaderWarmUp();
  WidgetsFlutterBinding.ensureInitialized();
  // Must run once before any `media_kit` Player is created -- backs the
  // Math Pad Asset Library's video embeds (see `MediaEmbedWidget`).
  MediaKit.ensureInitialized();
  OfflineSyncService.instance.initAutoSync();
  OfflineSyncService.instance.syncPendingRequests();

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider<ChatBloc>(create: (context) => ChatBloc()),
        BlocProvider<StudentDashboardBloc>(create: (context) => StudentDashboardBloc()),
        BlocProvider<StudentPerformanceBloc>(create: (context) => StudentPerformanceBloc()),
        BlocProvider<StudentPaymentsBloc>(create: (context) => StudentPaymentsBloc()),
        BlocProvider<SchedulesBloc>(create: (context) => SchedulesBloc()),
      ],
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => MathPadRecordingService()),
        ],
        child: const LearningPlatformApp(),
      ),
    ),
  );
}

class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
      };
}

class LearningPlatformApp extends StatelessWidget {
  const LearningPlatformApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return MaterialApp(
      title: 'Jyamiti math learning',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      scrollBehavior: AppScrollBehavior(),
      builder: (context, child) {
        return ThemeReveal(child: child ?? const SizedBox.shrink());
      },
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.wait([
        Provider.of<AuthProvider>(context, listen: false).tryAutoLogin(),
        Future.delayed(const Duration(milliseconds: 2500)),
      ]).then((_) {
        if (mounted) {
          setState(() {
            _initialized = true;
          });
          _checkForUpdates();
        }
      });
    });
  }

  Future<void> _checkForUpdates() async {
    if (kIsWeb) return;
    try {
      if (Platform.isWindows) {
        final res = await ApiService.get('/updates/windows');
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final int latestBuild = data['latestBuildCode'] ?? 0;
          const int currentBuild = 6; 
          
          if (latestBuild > currentBuild) {
            _showUpdateDialog(
              data['latestVersion'] ?? '1.0.5',
              data['downloadUrl'] ?? '',
              data['releaseNotes'] ?? '',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking for updates: $e');
    }
  }

  void _showUpdateDialog(String version, String downloadUrl, String releaseNotes) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.system_update_rounded, color: Color(0xFF6366F1)),
            const SizedBox(width: 10),
            Text(
              'Update Available!',
              style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A new version (v$version) of Jyamiti is available.',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
            ),
            if (releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'What\'s New:',
                style: GoogleFonts.spaceGrotesk(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                releaseNotes,
                style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Later', style: TextStyle(color: Colors.white30)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              if (downloadUrl.isNotEmpty) {
                final url = Uri.parse(downloadUrl);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              }
            },
            child: const Text('Update Now', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (ctx, auth, _) {
        if (!_initialized) {
          return const SplashScreenContent();
        } else if (!auth.isAuthenticated) {
          return const LoginScreen();
        } else {
          if (auth.userRole == 'ADMIN') {
            return const AdminStatsDashboard();
          } else if (auth.userRole == 'TUTOR') {
            return const TutorDashboard();
          } else if (auth.userRole == 'MENTOR') {
            return const MentorDashboard();
          } else {
            return const StudentDashboard();
          }
        }
      },
    );
  }
}
