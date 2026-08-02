import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../providers/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../providers/auth_provider.dart';
import '../../auth/screens/forgot_password_screen.dart';
import '../../exams/screens/assessment_taking_screen.dart';
import '../widgets/Particles.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _errorMessage;
  bool _assessmentCompleted = false;

  @override
  void initState() {
    super.initState();
    _checkAssessmentStatus();
  }

  Future<void> _checkAssessmentStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _assessmentCompleted =
            prefs.getBool('is_assessment_test_completed') ?? false;
      });
    } catch (e) {
      debugPrint('Error reading assessment status: $e');
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _errorMessage = null);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final error = await authProvider.login(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (error != null) {
      setState(() => _errorMessage = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = Provider.of<AuthProvider>(context).isLoading;
    final isLargeScreen = MediaQuery.of(context).size.width > 900;

    Widget buildBrandInfo() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(
            child: RotatingParticles(
              particleCount: 8,
              radius: 68,
              duration: const Duration(seconds: 7),
              child: Hero(
                tag: 'app_logo',
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // border: Border.all(
                    //   color: const Color.fromARGB(
                    //     255,
                    //     223,
                    //     223,
                    //     230,
                    //   ).withOpacity(0.4),
                    //   width: 1.2,
                    // ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: Image.asset(
                      'assets/image/logo.png',
                      width: 90,
                      height: 90,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          Text(
                'Welcome Back',
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: context.textColor,
                  letterSpacing: -0.5,
                ),
              )
              .animate()
              .fadeIn(delay: 150.ms, duration: 600.ms)
              .slideY(delay: 150.ms, duration: 600.ms, begin: 0.1, end: 0),

          const SizedBox(height: 8),

          Text(
            'Sign in to access your dashboard',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: context.textColor.withOpacity(0.6),
            ),
          ).animate().fadeIn(delay: 250.ms, duration: 600.ms),
        ],
      );
    }

    Widget buildFormInputs() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withOpacity(0.25)),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ).animate().shake(duration: 400.ms),
            const SizedBox(height: 16),
          ],

          TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                style: TextStyle(color: context.textColor),
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  labelStyle: TextStyle(
                    color: context.textColor.withOpacity(0.5),
                  ),
                  prefixIcon: Icon(
                    Icons.email_outlined,
                    color: context.textColor.withOpacity(0.5),
                  ),
                  filled: true,
                  fillColor: context.isDark
                      ? context.textColor.withOpacity(0.02)
                      : const Color(0xFFF8FAFC),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: context.isDark
                          ? context.textColor.withOpacity(0.08)
                          : const Color(0xFFE2E8F0),
                      width: 1.0,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Color(0xFF6366F1),
                      width: 1.5,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: Colors.redAccent.withOpacity(0.5),
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Colors.redAccent,
                      width: 1.5,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your email';
                  }
                  if (!RegExp(
                    r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                  ).hasMatch(value)) {
                    return 'Please enter a valid email address';
                  }
                  return null;
                },
              )
              .animate()
              .fadeIn(delay: 350.ms, duration: 600.ms)
              .slideY(delay: 350.ms, duration: 600.ms, begin: 0.08, end: 0),

          const SizedBox(height: 20),

          TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                style: TextStyle(color: context.textColor),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(
                    color: context.textColor.withOpacity(0.5),
                  ),
                  prefixIcon: Icon(
                    Icons.lock_outline_rounded,
                    color: context.textColor.withOpacity(0.5),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: context.textColor.withOpacity(0.5),
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  filled: true,
                  fillColor: context.isDark
                      ? context.textColor.withOpacity(0.02)
                      : const Color(0xFFF8FAFC),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: context.isDark
                          ? context.textColor.withOpacity(0.08)
                          : const Color(0xFFE2E8F0),
                      width: 1.0,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Color(0xFF6366F1),
                      width: 1.5,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: Colors.redAccent.withOpacity(0.5),
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Colors.redAccent,
                      width: 1.5,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your password';
                  }
                  return null;
                },
              )
              .animate()
              .fadeIn(delay: 450.ms, duration: 600.ms)
              .slideY(delay: 450.ms, duration: 600.ms, begin: 0.08, end: 0),

          const SizedBox(height: 12),

          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ForgotPasswordScreen(),
                  ),
                );
              },
              child: Text(
                'Forgot Password?',
                style: GoogleFonts.outfit(
                  color: context.isDark
                      ? const Color(0xFF818CF8)
                      : const Color(0xFF4F46E5),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ).animate().fadeIn(delay: 500.ms, duration: 600.ms),

          const SizedBox(height: 24),

          Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: isLoading
                        ? [
                            const Color(0xFF6366F1).withOpacity(0.5),
                            const Color(0xFF818CF8).withOpacity(0.5),
                          ]
                        : [const Color(0xFF4F46E5), const Color(0xFF6366F1)],
                  ),
                  boxShadow: [
                    if (!isLoading)
                      BoxShadow(
                        color: const Color(
                          0xFF6366F1,
                        ).withOpacity(context.isDark ? 0.3 : 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: JyamitiLoader(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Sign In',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              )
              .animate()
              .fadeIn(delay: 550.ms, duration: 600.ms)
              .scale(
                delay: 550.ms,
                duration: 600.ms,
                begin: const Offset(0.95, 0.95),
                curve: Curves.easeOutBack,
              ),

          if (!_assessmentCompleted) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Divider(color: context.textColor54.withOpacity(0.4)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'New Student?',
                    style: GoogleFonts.outfit(
                      color: context.textColor54,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(color: context.textColor54.withOpacity(0.4)),
                ),
              ],
            ).animate().fadeIn(delay: 600.ms),
            const SizedBox(height: 16),
            OutlinedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AssessmentTakingScreen(),
                      ),
                    );
                    if (result == true) {
                      _checkAssessmentStatus();
                    }
                  },
                  icon: const Icon(Icons.quiz_outlined, size: 18),
                  label: Text(
                    'Start Assessment Test',
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.isDark
                        ? const Color(0xFF818CF8)
                        : const Color(0xFF4F46E5),
                    side: BorderSide(
                      color: context.isDark
                          ? const Color(0xFF6366F1).withOpacity(0.6)
                          : const Color(0xFF6366F1).withOpacity(0.4),
                      width: 1.2,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                )
                .animate()
                .fadeIn(delay: 650.ms)
                .scale(delay: 650.ms, begin: const Offset(0.95, 0.95)),
          ],
        ],
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: context.isDark
                    ? [
                        const Color(0xFF0D0E15),
                        const Color(0xFF1E1B4B),
                        const Color(0xFF080710),
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

          Positioned(
            top: -150,
            right: -100,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF4F46E5).withOpacity(0.12),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            left: -100,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF818CF8).withOpacity(0.1),
                ),
              ),
            ),
          ),

          Center(
            child:
                SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24.0,
                        vertical: 32.0,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isLargeScreen) ...[
                            Column(
                              children: [
                                ShaderMask(
                                  shaderCallback: (bounds) =>
                                      const LinearGradient(
                                        colors: [
                                          Color(0xFF6366F1),
                                          Color(0xFF8B5CF6),
                                          Color(0xFFA78BFA),
                                          Color(0xFFC4B5FD),
                                        ],
                                        stops: [0.0, 0.3, 0.7, 1.0],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ).createShader(bounds),
                                  child: Text(
                                    'JYAMITI MATH LEARNING',
                                    style: GoogleFonts.outfit(
                                      fontSize: 42,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 1.2,
                                      height: 1.1,
                                      shadows: [
                                        Shadow(
                                          blurRadius: 30,
                                          color: const Color(
                                            0xFF6366F1,
                                          ).withOpacity(0.15),
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        context.isDark
                                            ? Colors.white.withOpacity(0.05)
                                            : const Color(
                                                0xFF6366F1,
                                              ).withOpacity(0.05),
                                        context.isDark
                                            ? Colors.white.withOpacity(0.02)
                                            : const Color(
                                                0xFFA78BFA,
                                              ).withOpacity(0.05),
                                      ],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                    borderRadius: BorderRadius.circular(100),
                                    border: Border.all(
                                      color: context.isDark
                                          ? Colors.white.withOpacity(0.06)
                                          : const Color(
                                              0xFF6366F1,
                                            ).withOpacity(0.08),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    'Your intelligent platform for mathematical excellence',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.outfit(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: context.isDark
                                          ? Colors.white.withOpacity(0.7)
                                          : const Color(0xFF4B5563),
                                      letterSpacing: 0.5,
                                      height: 1.6,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFF6366F1),
                                          boxShadow: [
                                            BoxShadow(
                                              blurRadius: 8,
                                              color: const Color(
                                                0xFF6366F1,
                                              ).withOpacity(0.3),
                                              spreadRadius: 2,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Powered by AI',
                                        style: GoogleFonts.outfit(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: context.isDark
                                              ? Colors.white.withOpacity(0.35)
                                              : const Color(
                                                  0xFF6366F1,
                                                ).withOpacity(0.5),
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 36),
                          ],
                          Container(
                            constraints: BoxConstraints(
                              maxWidth: isLargeScreen ? 850 : 400,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: context.isDark
                                      ? Colors.black.withOpacity(0.4)
                                      : const Color(
                                          0xFF4F46E5,
                                        ).withOpacity(0.08),
                                  blurRadius: 40,
                                  offset: const Offset(0, 20),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 16,
                                  sigmaY: 16,
                                ),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isLargeScreen ? 48.0 : 32.0,
                                    vertical: 32.0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.isDark
                                        ? Colors.white.withOpacity(0.03)
                                        : Colors.white.withOpacity(0.95),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: context.isDark
                                          ? context.textColor.withOpacity(0.08)
                                          : const Color(
                                              0xFF8B5CF6,
                                            ).withOpacity(0.15),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Form(
                                    key: _formKey,
                                    child: isLargeScreen
                                        ? Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Expanded(
                                                flex: 5,
                                                child: buildBrandInfo(),
                                              ),
                                              Container(
                                                width: 1.5,
                                                height: 350,
                                                color: context.isDark
                                                    ? Colors.white.withOpacity(
                                                        0.08,
                                                      )
                                                    : Colors.black.withOpacity(
                                                        0.08,
                                                      ),
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 32,
                                                    ),
                                              ),
                                              Expanded(
                                                flex: 6,
                                                child: buildFormInputs(),
                                              ),
                                            ],
                                          )
                                        : Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              buildBrandInfo(),
                                              const SizedBox(height: 32),
                                              buildFormInputs(),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 800.ms, curve: Curves.easeOut)
                    .slideY(
                      duration: 800.ms,
                      begin: 0.1,
                      end: 0,
                      curve: Curves.easeOutCubic,
                    ),
          ),
        ],
      ),
    );
  }
}
