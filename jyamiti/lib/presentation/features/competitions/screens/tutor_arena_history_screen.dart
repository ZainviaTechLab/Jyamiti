import 'package:flutter/material.dart';
import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/competition_service.dart';
import '../../../../services/api_service.dart';
import 'competition_analytics_dashboard_screen.dart';

class TutorArenaHistoryScreen extends StatefulWidget {
  final List<dynamic>? batches;
  final bool isInline;
  final VoidCallback? onBack;

  const TutorArenaHistoryScreen({
    super.key,
    this.batches,
    this.isInline = false,
    this.onBack,
  });

  @override
  State<TutorArenaHistoryScreen> createState() =>
      _TutorArenaHistoryScreenState();
}

class _TutorArenaHistoryScreenState extends State<TutorArenaHistoryScreen> {
  bool _isLoading = true;
  String? _selectedBatchId;
  List<dynamic> _competitions = [];
  Widget? _selectedAnalyticsWidget;

  @override
  void initState() {
    super.initState();
    _loadCompetitions();
  }

  Future<void> _loadCompetitions() async {
    setState(() => _isLoading = true);
    try {
      final List<dynamic> loaded = [];
      final tutorBatches = widget.batches ?? [];

      if (_selectedBatchId != null && _selectedBatchId != 'ALL') {
        final comps =
            await CompetitionService.getBatchCompetitions(_selectedBatchId!);
        loaded.addAll(comps);
      } else {
        for (var b in tutorBatches) {
          final bId = b['id'] ?? b['_id'];
          if (bId != null) {
            try {
              final comps = await CompetitionService.getBatchCompetitions(bId.toString());
              for (var c in comps) {
                if (c is Map) {
                  c['batchName'] = b['name'];
                }
              }
              loaded.addAll(comps);
            } catch (_) {}
          }
        }
      }

      // If empty or offline, fallback fetch from user hosted competitions endpoint
      if (loaded.isEmpty) {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final userId = auth.userId;
        if (userId != null) {
          final res = await ApiService.get('/competitions/tutor/$userId');
          if (res.statusCode == 200) {
            final List<dynamic> resData = (res.body.isNotEmpty)
                ? (res.body.startsWith('[') ? (res.body as dynamic) : [])
                : [];
            loaded.addAll(resData);
          }
        }
      }

      setState(() {
        _competitions = loaded;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _competitions = [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedAnalyticsWidget != null) {
      return _selectedAnalyticsWidget!;
    }

    final tutorBatches = widget.batches ?? [];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.isInline
          ? null
          : AppBar(
              title: const Text(
                'Arena Competition History',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: widget.onBack != null
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: widget.onBack,
                    )
                  : null,
            ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live Arena History & Results',
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Review past live competitions, leaderboard results, and batch performance metrics.',
                      style: TextStyle(
                        color: context.textColor60,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                // Batch Filter Dropdown
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.isDark
                        ? const Color(0xFF1E293B)
                        : Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedBatchId ?? 'ALL',
                      dropdownColor: context.isDark
                          ? const Color(0xFF1E293B)
                          : Colors.white,
                      icon: const Icon(
                        Icons.filter_list_rounded,
                        color: Color(0xFFF59E0B),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'ALL',
                          child: Text(
                            'All Assigned Batches',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        ...tutorBatches.map((b) {
                          final id = (b['id'] ?? b['_id']).toString();
                          final name = (b['name'] ?? 'Batch').toString();
                          return DropdownMenuItem(
                            value: id,
                            child: Text(name),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedBatchId = val;
                        });
                        _loadCompetitions();
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Content List / Loader / Empty state
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: JyamitiLoader(color: Color(0xFFF59E0B)),
                    )
                  : _competitions.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          itemCount: _competitions.length,
                          itemBuilder: (context, index) {
                            final comp = _competitions[index];
                            return _buildArenaHistoryCard(comp);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: context.isDark
              ? context.glassBg
              : Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                color: Color(0xFFF59E0B),
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Arena Competitions Conducted Yet',
              style: TextStyle(
                color: context.textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Once you host a Live Arena Competition for your batch, all session history, leaderboard rankings, and performance analytics will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.textColor60,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ).animate().fade().scale(delay: 100.ms),
    );
  }

  Widget _buildArenaHistoryCard(dynamic comp) {
    if (comp is! Map) return const SizedBox.shrink();

    final roomCode = comp['roomCode'] ?? comp['code'] ?? 'ARENA';
    final title = comp['title'] ?? comp['topicTitle'] ?? 'Live Arena Competition';
    final batchName = comp['batchName'] ?? comp['batch']?['name'] ?? 'Assigned Batch';
    final status = (comp['status'] ?? 'completed').toString();
    final participants = (comp['participants'] as List?) ?? [];
    final compId = (comp['id'] ?? comp['_id'] ?? roomCode).toString();
    final createdAt = comp['createdAt'] != null
        ? DateTime.tryParse(comp['createdAt'].toString())
        : null;
    final dateStr = createdAt != null
        ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
        : 'Recent Session';

    // Sort top 3 participants
    final List<dynamic> sortedPlayers = List.from(participants);
    sortedPlayers.sort((a, b) =>
        ((b['score'] ?? 0) as num).compareTo((a['score'] ?? 0) as num));

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.06),
            blurRadius: 16,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Title, Batch, Date
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: Color(0xFFF59E0B),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title.toString(),
                              style: TextStyle(
                                color: context.textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              roomCode.toString(),
                              style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.group_rounded,
                              size: 13, color: context.textColor60),
                          const SizedBox(width: 4),
                          Text(
                            batchName.toString(),
                            style: TextStyle(
                              color: context.textColor60,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.calendar_today_rounded,
                              size: 12, color: context.textColor60),
                          const SizedBox(width: 4),
                          Text(
                            dateStr,
                            style: TextStyle(
                              color: context.textColor60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (sortedPlayers.isNotEmpty) ...[
              const SizedBox(height: 16),
              Divider(color: context.glassBorder, height: 1),
              const SizedBox(height: 14),

              // Leaderboard Top 3 Podium Preview
              Text(
                'Top Performers (${participants.length} Participants)',
                style: TextStyle(
                  color: context.textColor70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (int i = 0; i < sortedPlayers.length && i < 3; i++) ...[
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: i == 0
                              ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                              : context.isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.black.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: i == 0
                                ? const Color(0xFFF59E0B)
                                : context.glassBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              i == 0
                                  ? '🥇'
                                  : i == 1
                                      ? '🥈'
                                      : '🥉',
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (sortedPlayers[i]['name'] ?? 'Student')
                                        .toString(),
                                    style: TextStyle(
                                      color: context.textColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${sortedPlayers[i]['score'] ?? 0} pts',
                                    style: const TextStyle(
                                      color: Color(0xFF10B981),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (i < 2 && i < sortedPlayers.length - 1)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
            ],

            const SizedBox(height: 16),

            // Action Buttons Row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF59E0B),
                    side: const BorderSide(color: Color(0xFFF59E0B)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.analytics_rounded, size: 16),
                  label: const Text('View Full Analytics'),
                  onPressed: () {
                    setState(() {
                      _selectedAnalyticsWidget =
                          CompetitionAnalyticsDashboardScreen(
                        competitionId: compId,
                        isInline: widget.isInline,
                        onBack: () {
                          setState(() {
                            _selectedAnalyticsWidget = null;
                          });
                        },
                      );
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
