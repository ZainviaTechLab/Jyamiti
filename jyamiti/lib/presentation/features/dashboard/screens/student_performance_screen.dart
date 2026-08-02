import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../providers/theme_provider.dart';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/student_performance/student_performance_bloc.dart';
import '../bloc/student_performance/student_performance_event.dart';
import '../bloc/student_performance/student_performance_state.dart';

class StudentPerformanceScreen extends StatefulWidget {
  final bool isInline;
  const StudentPerformanceScreen({super.key, this.isInline = false});

  @override
  State<StudentPerformanceScreen> createState() => _StudentPerformanceScreenState();
}

class _StudentPerformanceScreenState extends State<StudentPerformanceScreen> {
  @override
  void initState() {
    super.initState();
    context.read<StudentPerformanceBloc>().add(FetchStudentPerformance());
  }

  Color getPerformanceColor(double score) {
    if (score >= 85) return Colors.green;
    if (score >= 70) return Colors.blue;
    if (score >= 50) return Colors.orange;
    if (score >= 35) return Colors.orangeAccent;
    return Colors.red;
  }

  IconData getPerformanceIcon(double score) {
    if (score >= 85) return Icons.emoji_events;
    if (score >= 70) return Icons.thumb_up;
    if (score >= 50) return Icons.check_circle;
    if (score >= 35) return Icons.warning;
    return Icons.error;
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: widget.isInline
          ? null
          : AppBar(
              title: Text('My Performance', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, letterSpacing: 1)),
              backgroundColor: Colors.transparent,
              flexibleSpace: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    color: context.isDark ? const Color(0xFF0F172A).withOpacity(0.6) : Colors.white.withOpacity(0.6),
                  ),
                ),
              ),
              iconTheme: IconThemeData(color: context.textColor),
              elevation: 0,
            ),
      body: Stack(
        children: [
          if (!widget.isInline)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: context.isDark ? [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)] : [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          SafeArea(
            child: BlocBuilder<StudentPerformanceBloc, StudentPerformanceState>(
              builder: (context, state) {
                if (state is StudentPerformanceLoading || state is StudentPerformanceInitial) {
                  return Center(child: JyamitiLoader(color: Color(0xFF6366F1)));
                } else if (state is StudentPerformanceError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          state.message,
                          style: TextStyle(color: Colors.redAccent, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 20),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                          onPressed: () {
                            context.read<StudentPerformanceBloc>().add(FetchStudentPerformance());
                          },
                          child: const Text('Retry', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                } else if (state is StudentPerformanceLoaded) {
                  final performanceData = state.performanceData;
                  final subjectsList = performanceData['subjects'] as List?;
                  
                  if (subjectsList == null || subjectsList.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.book_outlined, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No performance data available',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Take some exams to see your performance',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ).animate().fade(duration: 600.ms),
                    );
                  }
                  
                  return _buildPerformanceContent(performanceData);
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceContent(Map<String, dynamic> performanceData) {
    final subjects =
        (performanceData['subjects'] as List?)?.cast<Map<String, dynamic>>() ??
        [];
    final overall = performanceData['overall'] as Map<String, dynamic>? ?? {};
    final summary = performanceData['summary'] as Map<String, dynamic>? ?? {};

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Student Info Card
          Container(
            decoration: BoxDecoration(
              color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(20),
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
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Performance Overview',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textColor),
                      ),
                      SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem(
                            'Total Exams',
                            '${summary['total_exams'] ?? overall['total_exams'] ?? 0}',
                          ),
                          _buildStatItem(
                            'Chapters',
                            '${summary['subjects_count'] ?? overall['total_subjects'] ?? 0}',
                          ),
                          _buildStatItem(
                            'Avg Score',
                            '${(overall['average_score'] ?? overall['score_percentage'] ?? summary['average_performance'] ?? summary['overall_performance'] ?? 0).toStringAsFixed(1)}%',
                          ),
                        ],
                      ),
                      SizedBox(height: 20),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: LinearProgressIndicator(
                          value: summary['overall_performance'] / 100,
                          backgroundColor: context.isDark ? Colors.white10 : Colors.black12,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            getPerformanceColor(summary['overall_performance']),
                          ),
                          minHeight: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ).animate().fade(duration: 400.ms).slideY(begin: 0.1, end: 0),

          SizedBox(height: 20),

          // Overall Performance
          Container(
            decoration: BoxDecoration(
              color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(20),
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
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Overall Performance',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textColor),
                      ),
                      SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildOverallStat(
                            'Performance',
                            overall['performance_rating'] ??
                                summary['performance_rating'] ??
                                'Not Rated',
                            getPerformanceColor(
                              overall['average_score'] ??
                                  overall['score_percentage'] ??
                                  0,
                            ),
                          ),
                          _buildOverallStat(
                            'Average Score',
                            '${(overall['average_score'] ?? overall['score_percentage'] ?? summary['average_performance'] ?? summary['overall_performance'] ?? 0).toStringAsFixed(1)}%',
                            const Color(0xFF3B82F6),
                          ),
                          _buildOverallStat(
                            'Total Marks',
                            '${overall['marks_obtained'] ?? 0}/${overall['total_marks'] ?? 0}',
                            const Color(0xFF10B981),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ).animate().fade(duration: 400.ms, delay: 100.ms).slideY(begin: 0.1, end: 0),

          SizedBox(height: 20),
          _buildPerformanceChart(subjects),
          SizedBox(height: 20),
          
          Text(
            'Chapter-wise Performance',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textColor),
          ),
          SizedBox(height: 12),

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: subjects.length,
            itemBuilder: (context, index) {
              final subject = subjects[index];
              return _buildSubjectCard(subject);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String title, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF6366F1),
          ),
        ),
        Text(title, style: TextStyle(fontSize: 12, color: context.textColor70)),
      ],
    );
  }

  Widget _buildOverallStat(String title, String value, Color color) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            getPerformanceIcon(double.tryParse(value.replaceAll('%', '')) ?? 0),
            color: color,
            size: 24,
          ),
        ),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(title, style: TextStyle(fontSize: 12, color: context.textColor70)),
      ],
    );
  }

  Widget _buildPerformanceChart(List<Map<String, dynamic>> subjects) {
    return Container(
      decoration: BoxDecoration(
        color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
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
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chapter-wise Combined Performance',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF818CF8),
                  ),
                ),
                SizedBox(height: 24),
                SizedBox(
                  height: 300,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: 100,
                      minY: 0,
                      barTouchData: BarTouchData(enabled: true),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index >= 0 && index < subjects.length) {
                                final subject = subjects[index];
                                final displayName =
                                    subject['subject_display'] ??
                                    subject['subject'];
                                final shortName = displayName.length > 8
                                    ? '${displayName.substring(0, 8)}...'
                                    : displayName;
                                return Padding(
                                  padding: EdgeInsets.only(top: 12.0),
                                  child: RotatedBox(
                                    quarterTurns: 1,
                                    child: Text(
                                      shortName,
                                      style: TextStyle(fontSize: 11, color: context.textColor70, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                );
                              }
                              return Text('');
                            },
                            reservedSize: 60,
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                '${value.toInt()}%',
                                style: TextStyle(fontSize: 11, color: context.textColor70, fontWeight: FontWeight.bold),
                              );
                            },
                            reservedSize: 40,
                          ),
                        ),
                        rightTitles: const AxisTitles(),
                        topTitles: const AxisTitles(),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 20,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(color: context.isDark ? Colors.white10 : Colors.black12, strokeWidth: 1);
                        },
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: subjects.asMap().entries.map((entry) {
                        final index = entry.key;
                        final subject = entry.value;
                        return BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: (subject['combined_score'] ?? 0).toDouble(),
                              color: getPerformanceColor(
                                subject['combined_score']?.toDouble() ?? 0.0,
                              ),
                              width: 20,
                              borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: 100,
                                color: context.glassBg,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fade(duration: 400.ms, delay: 200.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildSubjectCard(Map<String, dynamic> subject) {
    final score =
        subject['combined_score'] ??
        subject['average_score'] ??
        subject['score_percentage'] ??
        0;
    final color = getPerformanceColor(score.toDouble());
    final weakestChapters =
        subject['weakest_chapters'] as List<Map<String, dynamic>>? ?? [];

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
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
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        subject['subject_display'] ?? subject['subject'],
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textColor),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withOpacity(0.3)),
                      ),
                      child: Text(
                        '${score.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LinearProgressIndicator(
                    value: score / 100,
                    backgroundColor: context.isDark ? Colors.white10 : Colors.black12,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 8,
                  ),
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Exams: ${subject['total_exams'] ?? subject['exams_taken'] ?? 0}',
                      style: TextStyle(fontSize: 13, color: context.textColor70, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Marks: ${subject['marks_obtained']}/${subject['total_marks']}',
                      style: TextStyle(fontSize: 13, color: context.textColor70, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      subject['performance_rating'] ?? 'Not Rated',
                      style: TextStyle(
                        fontSize: 13,
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color.withOpacity(0.2),
                      foregroundColor: color,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: color.withOpacity(0.3)),
                      ),
                    ),
                    icon: Icon(Icons.list_alt_rounded, size: 20),
                    label: Text('Topic-wise Performance', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      _showTopicWiseDialog(context, subject);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fade(duration: 400.ms, delay: 300.ms).slideY(begin: 0.1, end: 0);
  }

  void _showTopicWiseDialog(BuildContext context, Map<String, dynamic> subject) {
    final topics = subject['topics'] as List<Map<String, dynamic>>? ?? [];
    
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Text(
            '${subject['subject_display']} - Topics',
            style: TextStyle(color: context.textColor, fontSize: 18),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: topics.isEmpty
                ? Text('No topic data available', style: TextStyle(color: context.textColor70))
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: topics.length,
                    separatorBuilder: (ctx, index) => Divider(color: Colors.white10),
                    itemBuilder: (ctx, index) {
                      final topic = topics[index];
                      final score = topic['score_percentage'] ?? 0.0;
                      final tColor = getPerformanceColor(score);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(topic['topic'], style: TextStyle(color: context.textColor)),
                        subtitle: Text(
                          'Marks: ${topic['marks_obtained']}/${topic['total_marks']}',
                          style: TextStyle(color: context.textColor54, fontSize: 12),
                        ),
                        trailing: Container(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: tColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${score.toStringAsFixed(1)}%',
                            style: TextStyle(color: tColor, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close', style: TextStyle(color: context.textColor70)),
            ),
          ],
        );
      },
    );
  }
}

