import 'package:flutter/material.dart';
import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../services/competition_service.dart';

class CompetitionAnalyticsDashboardScreen extends StatefulWidget {
  final String competitionId;
  final bool isInline;
  final VoidCallback? onBack;

  const CompetitionAnalyticsDashboardScreen({
    super.key,
    required this.competitionId,
    this.isInline = false,
    this.onBack,
  });

  @override
  State<CompetitionAnalyticsDashboardScreen> createState() =>
      _CompetitionAnalyticsDashboardScreenState();
}

class _CompetitionAnalyticsDashboardScreenState
    extends State<CompetitionAnalyticsDashboardScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _analyticsData;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
      final data =
          await CompetitionService.getCompetitionAnalytics(widget.competitionId);
      setState(() {
        _analyticsData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: context.textColor60,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: context.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicMasteryCard(Map<String, dynamic> topicData) {
    final String topic = topicData['topic'] ?? 'Topic';
    final int accuracyPct = topicData['accuracyPct'] ?? 0;
    final String masteryLevel = topicData['masteryLevel'] ?? 'MODERATE';
    final double avgTimeSec = (topicData['avgTimeSec'] ?? 0).toDouble();

    Color statusColor;
    IconData statusIcon;
    if (masteryLevel == 'STRONG') {
      statusColor = const Color(0xFF10B981);
      statusIcon = Icons.check_circle_rounded;
    } else if (masteryLevel == 'MODERATE') {
      statusColor = const Color(0xFFF59E0B);
      statusIcon = Icons.info_rounded;
    } else {
      statusColor = Colors.redAccent;
      statusIcon = Icons.warning_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      topic,
                      style: TextStyle(
                        color: context.textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        masteryLevel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: accuracyPct / 100,
                    backgroundColor: context.isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                    color: statusColor,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Accuracy: $accuracyPct%',
                      style: TextStyle(
                        color: context.textColor70,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      'Avg Speed: ${avgTimeSec}s / q',
                      style: TextStyle(
                        color: context.textColor60,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'COMPETITION ANALYTICS',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
        leading: widget.isInline
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onBack ?? () => Navigator.maybePop(context),
                tooltip: 'Back',
              )
            : null,
        backgroundColor:
            context.isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 1,
        iconTheme: IconThemeData(color: context.textColor),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadAnalytics,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: JyamitiLoader(color: Color(0xFF6366F1)))
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 48, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage,
                          style: TextStyle(color: context.textColor),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadAnalytics,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1).withOpacity(0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'ROOM: ${_analyticsData!['roomCode']}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ),
                                Text(
                                  _analyticsData!['batchName'] ?? 'Batch',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _analyticsData!['title'] ?? 'Batch Competition',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Host: ${_analyticsData!['tutorName'] ?? 'Tutor'}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ).animate().fade().scale(begin: const Offset(0.95, 0.95)),

                      const SizedBox(height: 20),

                      // Metrics Overview Grid
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              label: 'Participants',
                              value:
                                  '${_analyticsData!['totalParticipants']}',
                              icon: Icons.people_alt_rounded,
                              color: const Color(0xFF6366F1),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricCard(
                              label: 'Rounds',
                              value: '${_analyticsData!['totalRounds']}',
                              icon: Icons.repeat_rounded,
                              color: const Color(0xFF8B5CF6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              label: 'Batch Accuracy',
                              value:
                                  '${_analyticsData!['overallAccuracyPct']}%',
                              icon: Icons.bar_chart_rounded,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Weak & Strong Points Analysis Section
                      Text(
                        '💡 Weak & Strong Points Analysis',
                        style: TextStyle(
                          color: context.textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...((_analyticsData!['topicPerformance'] as List? ?? [])
                          .map((topicData) =>
                              _buildTopicMasteryCard(topicData as Map<String, dynamic>))),

                      const SizedBox(height: 24),

                      // Leaderboard Ranking Table
                      Text(
                        '🏆 Final Competition Leaderboard',
                        style: TextStyle(
                          color: context.textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: context.isDark
                              ? const Color(0xFF1E293B)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.glassBorder),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: (_analyticsData!['leaderboard'] as List? ?? [])
                              .length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final p = _analyticsData!['leaderboard'][idx];
                            final int rank = idx + 1;
                            Color badgeColor;
                            if (rank == 1) {
                              badgeColor = const Color(0xFFFFD700);
                            } else if (rank == 2) {
                              badgeColor = const Color(0xFFC0C0C0);
                            } else if (rank == 3) {
                              badgeColor = const Color(0xFFCD7F32);
                            } else {
                              badgeColor = context.textColor54;
                            }

                            final String pName = p['userId'] != null
                                ? (p['userId']['name'] ?? p['name'])
                                : (p['name'] ?? 'Student');

                            return ListTile(
                              leading: Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: badgeColor.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '#$rank',
                                  style: TextStyle(
                                    color: badgeColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              title: Text(
                                pName,
                                style: TextStyle(
                                  color: context.textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                '${p['responseHistory']?.length ?? 0} Rounds Played',
                                style: TextStyle(
                                  color: context.textColor60,
                                  fontSize: 11,
                                ),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF6366F1).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${p['totalScore']} pts',
                                  style: const TextStyle(
                                    color: Color(0xFF6366F1),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
