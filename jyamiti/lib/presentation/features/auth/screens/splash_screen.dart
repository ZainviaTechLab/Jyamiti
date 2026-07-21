import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../providers/theme_provider.dart';

class SplashScreenContent extends StatelessWidget {
  const SplashScreenContent({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0E15) : const Color(0xFFF1F5F9),
      body: Stack(
        children: [
          // Futuristic background ambient glow
          Positioned(
            top: -150,
            left: -150,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF4F46E5).withOpacity(isDark ? 0.15 : 0.08),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -150,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF818CF8).withOpacity(isDark ? 0.12 : 0.08),
                ),
              ),
            ),
          ),
          
          // Central content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Glowing animated logo container
                Hero(
                  tag: 'app_logo',
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(isDark ? 0.3 : 0.15),
                          blurRadius: 40,
                          spreadRadius: 2,
                        ),
                      ],
                      border: Border.all(
                        color: const Color(0xFF6366F1).withOpacity(isDark ? 0.5 : 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: Image.asset(
                        'assets/image/logo.png',
                        width: 130,
                        height: 130,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                )
                .animate()
                .fadeIn(duration: 800.ms, curve: Curves.easeOut)
                .scale(duration: 800.ms, begin: const Offset(0.8, 0.8), curve: Curves.easeOutBack),
                
                const SizedBox(height: 32),
                
                // App Title
                Text(
                  'JYAMITI',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: context.textColor,
                    letterSpacing: 8,
                    shadows: [
                      Shadow(
                        color: const Color(0xFF6366F1).withOpacity(isDark ? 0.8 : 0.4),
                        blurRadius: 15,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                )
                .animate()
                .fadeIn(delay: 300.ms, duration: 800.ms)
                .slideY(delay: 300.ms, duration: 800.ms, begin: 0.2, end: 0),
                
                const SizedBox(height: 8),
                
                // Subtitle
                Text(
                  'Interactive Mathematics Learning',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: context.textColor70,
                    letterSpacing: 2,
                  ),
                )
                .animate()
                .fadeIn(delay: 500.ms, duration: 800.ms),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
