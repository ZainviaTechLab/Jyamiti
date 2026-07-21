import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/provider.dart';
import '../../../../providers/theme_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

class StudentDetailedAttendanceScreen extends StatefulWidget {
  final Map<String, dynamic> summaryData;
  const StudentDetailedAttendanceScreen({super.key, required this.summaryData});

  @override
  State<StudentDetailedAttendanceScreen> createState() => _StudentDetailedAttendanceScreenState();
}

class _StudentDetailedAttendanceScreenState extends State<StudentDetailedAttendanceScreen> {
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    final present = widget.summaryData['present']?.toString() ?? '0';
    final absent = widget.summaryData['absent']?.toString() ?? '0';
    final leave = widget.summaryData['leave']?.toString() ?? '0';
    final total = widget.summaryData['total']?.toString() ?? '0';
    final percentageNum = widget.summaryData['percentage']?.toDouble() ?? 0.0;

    final List<Map<String, dynamic>> recentAttendance = 
        (widget.summaryData['recentAttendance'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];

    final List<Map<String, dynamic>> monthlyTrend = 
        (widget.summaryData['monthlyTrend'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Detailed Attendance',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
        ).animate().fade().slideY(begin: -0.2, end: 0),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: context.textColor),
      ),
      body: Stack(
        children: [
          // Futuristic Gradient Background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: context.isDark 
                    ? [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)]
                    : [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current Month Summary
                  _buildGlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Current Month Overview',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: context.textColor,
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getColorForPercentage(percentageNum).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _getColorForPercentage(percentageNum).withOpacity(0.5)),
                              ),
                              child: Text(
                                '${percentageNum.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  color: _getColorForPercentage(percentageNum),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatCircle('Present', present, const Color(0xFF10B981)),
                            _buildStatCircle('Absent', absent, Colors.redAccent),
                            _buildStatCircle('Leave', leave, const Color(0xFFF59E0B)),
                            _buildStatCircle('Total', total, const Color(0xFF3B82F6)),
                          ],
                        ),
                      ],
                    ),
                  ).animate().fade(duration: 400.ms).slideY(begin: 0.1, end: 0),
                  SizedBox(height: 24),

                  // Recent Attendance
                  Text(
                    'Recent Sessions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textColor),
                  ).animate().fade(delay: 100.ms),
                  SizedBox(height: 12),
                  _buildGlassCard(
                    padding: EdgeInsets.all(12),
                    child: _buildRecentAttendanceList(recentAttendance, context),
                  ).animate().fade(delay: 150.ms).slideY(begin: 0.1, end: 0),
                  SizedBox(height: 24),

                  // Monthly Trend
                  Text(
                    'Monthly Trend',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textColor),
                  ).animate().fade(delay: 200.ms),
                  SizedBox(height: 12),
                  _buildMonthlyTrend(monthlyTrend).animate().fade(delay: 250.ms).slideX(begin: 0.1, end: 0),
                  
                  SizedBox(height: 24),
                  
                  // View All Sessions Button
                  _buildGlassCard(
                    padding: EdgeInsets.zero,
                    child: InkWell(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session Dashboard coming soon!')));
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'View Session Attendance',
                              style: TextStyle(
                                color: Color(0xFF818CF8),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios_rounded, color: const Color(0xFF818CF8).withOpacity(0.7), size: 18),
                          ],
                        ),
                      ),
                    ),
                  ).animate().fade(delay: 300.ms).slideY(begin: 0.1, end: 0),
                  
                  SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getColorForPercentage(double percentage) {
    if (percentage >= 75) return const Color(0xFF10B981);
    if (percentage >= 60) return const Color(0xFFF59E0B);
    return Colors.redAccent;
  }

  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(20)}) {
    return Container(
      decoration: BoxDecoration(
        color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.isDark ? context.glassBorder : Colors.white.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: context.isDark ? Colors.black.withOpacity(0.2) : const Color(0xFF6366F1).withOpacity(0.06),
            blurRadius: 30,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildStatCircle(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.5), width: 2),
          ),
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: context.textColor70,
          ),
        ),
      ],
    );
  }

  Widget _buildRecentAttendanceList(List<Map<String, dynamic>> recent, BuildContext context) {
    if (recent.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No recent attendance records',
            style: TextStyle(color: context.textColor54, fontStyle: FontStyle.italic),
          ),
        ),
      );
    }

    return Column(
      children: recent.map((attendance) {
        final bool isPresent = attendance['status'] == 'present';
        final Color statusColor = isPresent ? const Color(0xFF10B981) : Colors.redAccent;
        final String remarks = attendance['remarks'] ?? '';
        final int sweets = attendance['sweets'] ?? 0;

        return Container(
          margin: EdgeInsets.only(bottom: 8),
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.isDark ? context.glassBorder : Colors.white.withOpacity(0.75)),
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: statusColor.withOpacity(0.5), blurRadius: 4)],
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attendance['date'],
                      style: TextStyle(fontWeight: FontWeight.w600, color: context.textColor),
                    ),
                    if (remarks.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(
                          remarks,
                          style: TextStyle(fontSize: 12, color: context.textColor54),
                        ),
                      ),
                  ],
                ),
              ),
              if (isPresent && sweets > 0)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: List.generate(sweets, (index) => Text('🍬', style: TextStyle(fontSize: 14))),
                  ),
                ),
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isPresent ? 'Present' : 'Absent',
                  style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMonthlyTrend(List<Map<String, dynamic>> trend) {
    if (trend.isEmpty) {
      return Text(
        'No trend data available',
        style: TextStyle(color: context.textColor54, fontStyle: FontStyle.italic),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: trend.map((month) {
          final double percentage = (month['percentage'] as num?)?.toDouble() ?? 0.0;
          final Color pColor = _getColorForPercentage(percentage);

          return Container(
            width: 100,
            margin: EdgeInsets.only(right: 16),
            child: _buildGlassCard(
              padding: EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Column(
                children: [
                  Text(
                    month['month'],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: context.textColor70,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '${percentage.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: pColor,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '${month['present']}/${month['total']}',
                    style: TextStyle(fontSize: 12, color: context.textColor54),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
