import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../domain/models/slide_deck_models.dart';
import '../../../../providers/theme_provider.dart';
import '../../../../services/slide_cache_service.dart';

class AdminSlideAnalyticsScreen extends StatefulWidget {
  final SlideDeck deck;

  const AdminSlideAnalyticsScreen({super.key, required this.deck});

  @override
  State<AdminSlideAnalyticsScreen> createState() =>
      _AdminSlideAnalyticsScreenState();
}

class _AdminSlideAnalyticsScreenState extends State<AdminSlideAnalyticsScreen> {
  List<SlideAnalyticsReport> _reports = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    final reports = await SlideCacheService.instance.getAnalyticsForDeck(
      widget.deck.id,
      widget.deck.title,
      widget.deck.slides.length,
    );
    setState(() {
      _reports = reports;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final totalSlides = widget.deck.slides.length;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Slide Analytics Dashboard')),
        body: const Center(child: JyamitiLoader()),
      );
    }

    double avgCompletion = 0;
    int totalTimeSec = 0;
    int totalQuizCorrect = 0;
    int totalQuizzes = 0;

    for (var r in _reports) {
      avgCompletion += r.completionPercent;
      totalTimeSec += r.totalTimeSpentSeconds;
      totalQuizCorrect += r.quizScore;
      totalQuizzes += r.totalQuizzes;
    }
    if (_reports.isNotEmpty) {
      avgCompletion /= _reports.length;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.deck.title} • Analytics'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Banner
                Text(
                  'Student Engagement & Time Analytics',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Real-time breakdown of time spent per slide, completion rates, and quiz performance.',
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 20),

                // Top KPI Summary Cards
                Row(
                  children: [
                    Expanded(
                      child: _buildKpiCard(
                        context,
                        'Students Tracked',
                        '${_reports.length}',
                        Icons.people_outline_rounded,
                        const Color(0xFF6366F1),
                        isDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildKpiCard(
                        context,
                        'Avg Completion',
                        '${(avgCompletion * 100).toStringAsFixed(1)}%',
                        Icons.donut_large_rounded,
                        const Color(0xFF10B981),
                        isDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildKpiCard(
                        context,
                        'Total Study Time',
                        '${(totalTimeSec / 60).toStringAsFixed(1)} mins',
                        Icons.timer_outlined,
                        const Color(0xFF0EA5E9),
                        isDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildKpiCard(
                        context,
                        'Quiz Accuracy',
                        totalQuizzes > 0
                            ? '${((totalQuizCorrect / totalQuizzes) * 100).toStringAsFixed(0)}%'
                            : 'N/A',
                        Icons.quiz_outlined,
                        const Color(0xFFF59E0B),
                        isDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // Slide Time Distribution Bar Chart
                Card(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.bar_chart_rounded, color: Color(0xFF6366F1)),
                            SizedBox(width: 8),
                            Text(
                              'Average Time Spent per Slide (Seconds)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 240,
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: _calculateMaxBarY(totalSlides),
                              barTouchData: BarTouchData(enabled: true),
                              titlesData: FlTitlesData(
                                show: true,
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (val, meta) {
                                      final idx = val.toInt();
                                      if (idx >= 0 && idx < totalSlides) {
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 6.0),
                                          child: Text(
                                            'Slide ${idx + 1}',
                                            style: const TextStyle(fontSize: 10),
                                          ),
                                        );
                                      }
                                      return const SizedBox();
                                    },
                                  ),
                                ),
                                leftTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: true, reservedSize: 32),
                                ),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              borderData: FlBorderData(show: false),
                              barGroups: List.generate(totalSlides, (slideIdx) {
                                double avgSec = 0;
                                int count = 0;
                                for (var r in _reports) {
                                  if (r.slideTimeSpent.containsKey(slideIdx)) {
                                    avgSec += r.slideTimeSpent[slideIdx]!;
                                    count++;
                                  }
                                }
                                if (count > 0) avgSec /= count;

                                return BarChartGroupData(
                                  x: slideIdx,
                                  barRods: [
                                    BarChartRodData(
                                      toY: avgSec > 0 ? avgSec : 10,
                                      color: const Color(0xFF6366F1),
                                      width: 18,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ],
                                );
                              }),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Student Engagement Roster Table
                Card(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Student Roster Progress Log',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Student Name')),
                              DataColumn(label: Text('Completion %')),
                              DataColumn(label: Text('Total Time')),
                              DataColumn(label: Text('Quiz Correct')),
                              DataColumn(label: Text('Last Active')),
                            ],
                            rows: _reports.map((r) {
                              return DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      r.studentName,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  DataCell(
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 60,
                                          child: LinearProgressIndicator(
                                            value: r.completionPercent,
                                            backgroundColor: Colors.grey.shade700,
                                            valueColor: const AlwaysStoppedAnimation(Color(0xFF10B981)),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text('${(r.completionPercent * 100).toStringAsFixed(0)}%'),
                                      ],
                                    ),
                                  ),
                                  DataCell(Text('${(r.totalTimeSpentSeconds / 60).toStringAsFixed(1)}m')),
                                  DataCell(Text('${r.quizScore} / ${r.totalQuizzes}')),
                                  DataCell(Text('${r.lastActive.hour}:${r.lastActive.minute.toString().padLeft(2, '0')}')),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ],
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

  double _calculateMaxBarY(int totalSlides) {
    double maxVal = 60;
    for (var r in _reports) {
      for (var val in r.slideTimeSpent.values) {
        if (val > maxVal) maxVal = val.toDouble();
      }
    }
    return maxVal + 20;
  }

  Widget _buildKpiCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
