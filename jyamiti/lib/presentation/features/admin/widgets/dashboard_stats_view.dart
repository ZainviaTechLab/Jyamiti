import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:jyamiti/providers/theme_provider.dart';

/// Rich, data-dense admin overview: KPIs, revenue (incl. aging), attendance,
/// an actionable "needs attention" queue, tutor performance, course/batch
/// capacity signals, and recent signups.
///
/// All input comes from `GET /api/stats/dashboard` as a loosely-typed map,
/// so every read below is defensive (`?? default`) against fields that may
/// not exist yet on an older backend build.
class DashboardStatsView extends StatelessWidget {
  final Map<String, dynamic> stats;

  const DashboardStatsView({super.key, required this.stats});

  static final NumberFormat _numberFmt = NumberFormat('#,##0');
  static final DateFormat _dateFmt = DateFormat('MMM d');
  static final DateFormat _dateTimeFmt = DateFormat('MMM d, h:mm a');

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  List<dynamic> _list(dynamic v) => v is List ? List<dynamic>.from(v) : <dynamic>[];
  num _num(dynamic v) => v is num ? v : 0;

  String _money(num v) => '\$${_numberFmt.format(v)}';

  DateTime? _date(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = _map(stats['totals']);
    final userBreakdown = _map(stats['userBreakdown']);
    final userGrowth = _map(stats['userGrowth']);
    final revenue = _map(stats['revenue']);
    final attendance = _map(stats['attendance']);
    final needsAttention = _map(stats['needsAttention']);
    final regTrends = _map(stats['registrationTrends']);
    final revenueTrend = _map(revenue['monthlyTrend']);
    final overdueAging = _list(revenue['overdueAging']);
    final batches = _map(stats['batches']);
    final topBatches = _list(batches['topByEnrollment']);
    final coursePopularity = _list(stats['coursePopularity']);
    final tutorPerformance = _list(stats['tutorPerformance']);
    final recentUsers = _list(stats['recentUsers']);

    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 900;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _sectionTitle(context, 'Overview'),
              const SizedBox(height: 16),
              _buildPrimaryStats(context, totals, userGrowth, screenWidth),
              const SizedBox(height: 16),
              isWide
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildUserCompositionDonut(context, totals)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildUserStatusDonut(context, userBreakdown)),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        _buildUserCompositionDonut(context, totals),
                        const SizedBox(height: 16),
                        _buildUserStatusDonut(context, userBreakdown),
                      ],
                    ),

              const SizedBox(height: 32),
              _sectionTitle(context, 'Revenue'),
              const SizedBox(height: 16),
              _buildRevenueStats(context, revenue, screenWidth),
              const SizedBox(height: 16),
              overdueAging.isEmpty
                  ? _buildRevenueSplitDonut(context, revenue)
                  : (isWide
                      ? IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildRevenueSplitDonut(context, revenue)),
                              const SizedBox(width: 16),
                              Expanded(flex: 2, child: _buildOverdueAgingCard(context, overdueAging)),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            _buildRevenueSplitDonut(context, revenue),
                            const SizedBox(height: 16),
                            _buildOverdueAgingCard(context, overdueAging),
                          ],
                        )),

              const SizedBox(height: 32),
              _sectionTitle(context, 'Trends'),
              const SizedBox(height: 16),
              isWide
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildRegistrationTrendCard(context, regTrends)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildRevenueTrendCard(context, revenueTrend)),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        _buildRegistrationTrendCard(context, regTrends),
                        const SizedBox(height: 16),
                        _buildRevenueTrendCard(context, revenueTrend),
                      ],
                    ),

              const SizedBox(height: 32),
              _sectionTitle(context, 'Attendance'),
              const SizedBox(height: 16),
              _buildAttendanceRow(context, attendance, screenWidth),

              const SizedBox(height: 32),
              _sectionTitle(context, 'Needs Attention'),
              const SizedBox(height: 16),
              _responsiveWrap(
                context,
                screenWidth,
                cols: screenWidth > 1100 ? 4 : (screenWidth > 700 ? 2 : 1),
                children: [
                  _buildLeaveRequestsCard(context, _map(needsAttention['pendingLeaveRequests'])),
                  _buildOverduePaymentsCard(context, _map(needsAttention['overduePayments'])),
                  _buildParentMeetingsCard(context, _map(needsAttention['upcomingParentMeetings'])),
                  _buildPendingGradingCard(context, _map(needsAttention['pendingGrading'])),
                ],
              ),

              const SizedBox(height: 32),
              _sectionTitle(context, 'Tutor Performance'),
              const SizedBox(height: 16),
              _buildTutorPerformanceCard(context, tutorPerformance),

              const SizedBox(height: 32),
              _sectionTitle(context, 'Courses & Batch Capacity'),
              const SizedBox(height: 16),
              isWide
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildCoursePopularityCard(context, coursePopularity)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildCapacityAlertsCard(context, batches)),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        _buildCoursePopularityCard(context, coursePopularity),
                        const SizedBox(height: 16),
                        _buildCapacityAlertsCard(context, batches),
                      ],
                    ),

              const SizedBox(height: 32),
              _sectionTitle(context, 'Top Batches & Signups'),
              const SizedBox(height: 16),
              isWide
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: _buildTopBatchesCard(context, topBatches)),
                          const SizedBox(width: 16),
                          Expanded(flex: 2, child: _buildRecentUsersCard(context, recentUsers)),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        _buildTopBatchesCard(context, topBatches),
                        const SizedBox(height: 16),
                        _buildRecentUsersCard(context, recentUsers),
                      ],
                    ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Section scaffolding
  // ---------------------------------------------------------------------

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(color: context.textColor, fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  Widget _glassCard(BuildContext context, {required Widget child, Color? accent}) {
    return Container(
      decoration: BoxDecoration(
        color: context.glassBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent?.withOpacity(0.3) ?? context.glassBorder),
        boxShadow: accent == null
            ? null
            : [BoxShadow(color: accent.withOpacity(0.08), blurRadius: 20, spreadRadius: -5)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );
  }

  /// Wraps [children] into a responsive grid without forcing a fixed aspect
  /// ratio, so each card's height can follow its (variable-length) content.
  Widget _responsiveWrap(
    BuildContext context,
    double screenWidth, {
    required int cols,
    required List<Widget> children,
  }) {
    const spacing = 16.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final safeCols = cols.clamp(1, children.isEmpty ? 1 : children.length);
        final cardWidth = (constraints.maxWidth - spacing * (safeCols - 1)) / safeCols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: children.map((c) => SizedBox(width: cardWidth, child: c)).toList(),
        );
      },
    );
  }

  /// A donut chart with an optional center label and a right-hand legend.
  /// Falls back to a neutral gray ring when every segment is zero, so the
  /// chart never renders blank on a fresh/empty dataset.
  Widget _donutCard(
    BuildContext context,
    String title, {
    required List<(String, num, Color)> segments,
    String? centerLabel,
    String? centerSubLabel,
    Color? accent,
    String? footer,
  }) {
    final total = segments.fold<num>(0, (a, s) => a + s.$2);
    final sections = total > 0
        ? segments
            .where((s) => s.$2 > 0)
            .map(
              (s) => PieChartSectionData(
                value: s.$2.toDouble(),
                color: s.$3,
                radius: 24,
                showTitle: false,
              ),
            )
            .toList()
        : [PieChartSectionData(value: 1, color: context.glassBorder, radius: 24, showTitle: false)];

    return _glassCard(
      context,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 116,
                height: 116,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(PieChartData(sectionsSpace: 2, centerSpaceRadius: 34, sections: sections)),
                    if (centerLabel != null)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            centerLabel,
                            style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          if (centerSubLabel != null)
                            Text(
                              centerSubLabel,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: context.textColor60, fontSize: 9),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: segments.map((s) {
                    final pct = total > 0 ? (s.$2 / total * 100) : 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.$1,
                              style: TextStyle(color: context.textColor70, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${_numberFmt.format(s.$2)} · ${pct.toStringAsFixed(0)}%',
                            style: TextStyle(color: context.textColor, fontWeight: FontWeight.w600, fontSize: 11.5),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          if (footer != null) ...[
            const SizedBox(height: 10),
            Divider(color: context.glassBorder, height: 1),
            const SizedBox(height: 8),
            Text(footer, style: TextStyle(color: context.textColor60, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  /// Compact vertical bar chart for comparing a short label list (tutors,
  /// courses, ...) by a single numeric value. Labels are truncated and
  /// tilted slightly so a handful of names fit without overlapping.
  Widget _compareBarChart(BuildContext context, List<(String, num)> items, Color color) {
    if (items.isEmpty) return const SizedBox.shrink();
    double maxY = 0;
    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < items.length; i++) {
      final value = items[i].$2.toDouble();
      if (value > maxY) maxY = value;
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(toY: value, color: color, width: 22, borderRadius: BorderRadius.circular(4)),
          ],
        ),
      );
    }
    return SizedBox(
      height: 190,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY + (maxY * 0.25) + 1,
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= items.length) return const Text('');
                  final label = items[i].$1;
                  final shortLabel = label.length > 10 ? '${label.substring(0, 10)}…' : label;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Transform.rotate(
                      angle: -0.5,
                      child: Text(shortLabel, style: TextStyle(color: context.textColor70, fontSize: 10)),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  if (value % 1 != 0) return const Text('');
                  return Text(value.toInt().toString(), style: TextStyle(color: context.textColor70, fontSize: 11));
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(color: context.glassBorder, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barGroups: barGroups,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Overview
  // ---------------------------------------------------------------------

  Widget _buildPrimaryStats(
    BuildContext context,
    Map<String, dynamic> totals,
    Map<String, dynamic> userGrowth,
    double screenWidth,
  ) {
    final growthPercent = _num(userGrowth['growthPercent']);
    final cols = screenWidth > 1100 ? 4 : (screenWidth > 700 ? 3 : (screenWidth > 480 ? 2 : 1));
    return _responsiveWrap(
      context,
      screenWidth,
      cols: cols,
      children: [
        _statCard(
          context,
          'TOTAL STUDENTS',
          _numberFmt.format(_num(totals['students'])),
          const Color(0xFF6366F1),
          Icons.people_alt_rounded,
          subtitle: userGrowth.isEmpty
              ? null
              : '${growthPercent >= 0 ? '+' : ''}${growthPercent.toStringAsFixed(1)}% this month',
          subtitleColor: growthPercent >= 0 ? const Color(0xFF10B981) : Colors.redAccent,
        ),
        _statCard(
          context,
          'TOTAL TUTORS',
          _numberFmt.format(_num(totals['tutors'])),
          const Color(0xFF10B981),
          Icons.person_rounded,
        ),
        _statCard(
          context,
          'TOTAL MENTORS',
          _numberFmt.format(_num(totals['mentors'])),
          const Color(0xFF14B8A6),
          Icons.supervisor_account_rounded,
        ),
        _statCard(
          context,
          'TOTAL COURSES',
          _numberFmt.format(_num(totals['courses'])),
          const Color(0xFFF59E0B),
          Icons.book_rounded,
        ),
        _statCard(
          context,
          'TOTAL BATCHES',
          _numberFmt.format(_num(totals['batches'])),
          const Color(0xFFEC4899),
          Icons.class_rounded,
        ),
        _statCard(
          context,
          'SESSIONS (7D)',
          _numberFmt.format(_num(totals['sessionsPastWeek'])),
          const Color(0xFF06B6D4),
          Icons.event_available_rounded,
          subtitle: 'past week',
        ),
        _statCard(
          context,
          'SESSIONS (NEXT 7D)',
          _numberFmt.format(_num(totals['sessionsNextWeek'])),
          const Color(0xFF8B5CF6),
          Icons.upcoming_rounded,
          subtitle: 'upcoming',
        ),
      ],
    );
  }

  /// Compact, content-sized KPI card: a small icon badge beside a
  /// label/value/subtitle stack. Deliberately does NOT stretch to fill a
  /// tall grid cell — it's meant to be dropped into [_responsiveWrap] so
  /// its height follows its content instead of an arbitrary aspect ratio.
  Widget _statCard(
    BuildContext context,
    String title,
    String value,
    Color color,
    IconData icon, {
    String? subtitle,
    Color? subtitleColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: context.glassBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 19),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: context.textColor60,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        value,
                        style: TextStyle(
                          color: context.textColor,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: subtitleColor ?? context.textColor60,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserCompositionDonut(BuildContext context, Map<String, dynamic> totals) {
    final students = _num(totals['students']);
    final tutors = _num(totals['tutors']);
    final mentors = _num(totals['mentors']);
    final total = students + tutors + mentors;
    return _donutCard(
      context,
      'User Composition',
      segments: [
        ('Students', students, const Color(0xFF6366F1)),
        ('Tutors', tutors, const Color(0xFF10B981)),
        ('Mentors', mentors, const Color(0xFF14B8A6)),
      ],
      centerLabel: _numberFmt.format(total),
      centerSubLabel: 'total users',
    );
  }

  Widget _buildUserStatusDonut(BuildContext context, Map<String, dynamic> userBreakdown) {
    final active = _num(userBreakdown['active']);
    final inactive = _num(userBreakdown['inactive']);
    final suspended = _num(userBreakdown['suspended']);
    final incomplete = _num(userBreakdown['incompleteProfile']);
    final total = active + inactive + suspended;
    return _donutCard(
      context,
      'User Status',
      segments: [
        ('Active', active, const Color(0xFF10B981)),
        ('Inactive', inactive, const Color(0xFF64748B)),
        ('Suspended', suspended, Colors.redAccent),
      ],
      centerLabel: total > 0 ? '${(active / total * 100).toStringAsFixed(0)}%' : '—',
      centerSubLabel: 'active',
      footer: incomplete > 0
          ? '${_numberFmt.format(incomplete)} user(s) also have an incomplete profile'
          : null,
    );
  }

  Widget _buildRevenueSplitDonut(BuildContext context, Map<String, dynamic> revenue) {
    final collected = _num(revenue['totalCollected']);
    final totalPending = _num(revenue['totalPending']);
    final overdue = _num(revenue['overdueAmount']);
    final pendingNotDue = totalPending - overdue;
    final collectionRate = _num(revenue['collectionRate']);
    return _donutCard(
      context,
      'Revenue Split',
      segments: [
        ('Collected', collected, const Color(0xFF10B981)),
        ('Pending (not due)', pendingNotDue < 0 ? 0 : pendingNotDue, const Color(0xFFF59E0B)),
        ('Overdue', overdue, Colors.redAccent),
      ],
      centerLabel: '${collectionRate.toStringAsFixed(0)}%',
      centerSubLabel: 'collected',
    );
  }

  // ---------------------------------------------------------------------
  // Revenue
  // ---------------------------------------------------------------------

  Widget _buildRevenueStats(BuildContext context, Map<String, dynamic> revenue, double screenWidth) {
    final collectionRate = _num(revenue['collectionRate']).toDouble();
    final cols = screenWidth > 1100 ? 4 : (screenWidth > 700 ? 2 : 1);
    return _responsiveWrap(
      context,
      screenWidth,
      cols: cols,
      children: [
        _statCard(
          context,
          'TOTAL COLLECTED',
          _money(_num(revenue['totalCollected'])),
          const Color(0xFF10B981),
          Icons.account_balance_wallet_rounded,
          subtitle: 'this month: ${_money(_num(revenue['thisMonthCollected']))}',
        ),
        _statCard(
          context,
          'PENDING DUES',
          _money(_num(revenue['totalPending'])),
          const Color(0xFFF59E0B),
          Icons.hourglass_bottom_rounded,
          subtitle: 'due this month: ${_money(_num(revenue['thisMonthDue']))}',
        ),
        _statCard(
          context,
          'OVERDUE',
          _money(_num(revenue['overdueAmount'])),
          Colors.redAccent,
          Icons.warning_amber_rounded,
          subtitle: '${_numberFmt.format(_num(revenue['overdueCount']))} payment(s)',
          subtitleColor: Colors.redAccent,
        ),
        _statCard(
          context,
          'COLLECTION RATE',
          '${collectionRate.toStringAsFixed(1)}%',
          const Color(0xFF6366F1),
          Icons.trending_up_rounded,
          subtitle: 'collected vs billed',
        ),
      ],
    );
  }

  Widget _buildOverdueAgingCard(BuildContext context, List<dynamic> aging) {
    final amounts = aging.map((raw) => _num(_map(raw)['amount'])).toList();
    final maxAmount = amounts.isEmpty ? 0 : amounts.reduce((a, b) => a > b ? a : b);
    const colors = [Color(0xFFF59E0B), Color(0xFFF97316), Color(0xFFEF4444), Color(0xFFB91C1C)];
    return _glassCard(
      context,
      accent: Colors.redAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overdue Payments Aging',
            style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 12),
          ...aging.asMap().entries.map((entry) {
            final i = entry.key;
            final a = _map(entry.value);
            final amount = _num(a['amount']);
            final count = _num(a['count']).toInt();
            final color = colors[i % colors.length];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(
                      a['label']?.toString() ?? '',
                      style: TextStyle(color: context.textColor70, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: maxAmount > 0 ? (amount / maxAmount).clamp(0, 1).toDouble() : 0,
                        minHeight: 10,
                        backgroundColor: context.glassBorder,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: Text(
                      '${_money(amount)} ($count)',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: context.textColor, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Trends
  // ---------------------------------------------------------------------

  Widget _buildRegistrationTrendCard(BuildContext context, Map<String, dynamic> regTrends) {
    return _glassCard(
      context,
      child: SizedBox(
        height: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Registration Trends',
              style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: regTrends.isEmpty
                  ? Center(
                      child: Text('No registration data available', style: TextStyle(color: context.textColor60)),
                    )
                  : _buildRegistrationGraph(context, regTrends),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegistrationGraph(BuildContext context, Map<String, dynamic> data) {
    final sortedKeys = data.keys.toList()..sort();
    final barGroups = <BarChartGroupData>[];
    double maxY = 0;

    for (int i = 0; i < sortedKeys.length; i++) {
      final entry = _map(data[sortedKeys[i]]);
      final value = _num(entry['student']).toDouble();
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
        maxY: maxY + (maxY * 0.2) + 1,
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                if (value.toInt() >= 0 && value.toInt() < sortedKeys.length) {
                  final parts = sortedKeys[value.toInt()].split('-');
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      parts.length > 1 ? parts[1] : sortedKeys[value.toInt()],
                      style: TextStyle(color: context.textColor70, fontSize: 12),
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
                if (value % 1 != 0) return const Text('');
                return Text(value.toInt().toString(), style: TextStyle(color: context.textColor70, fontSize: 12));
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 1,
          getDrawingHorizontalLine: (value) => FlLine(color: context.glassBorder, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        barGroups: barGroups,
      ),
    );
  }

  Widget _buildRevenueTrendCard(BuildContext context, Map<String, dynamic> revenueTrend) {
    return _glassCard(
      context,
      child: SizedBox(
        height: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Revenue Trend',
                  style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const Spacer(),
                _legendDot(context, 'Billed', const Color(0xFFF59E0B)),
                const SizedBox(width: 12),
                _legendDot(context, 'Collected', const Color(0xFF10B981)),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: revenueTrend.isEmpty
                  ? Center(child: Text('No revenue data available', style: TextStyle(color: context.textColor60)))
                  : _buildRevenueGraph(context, revenueTrend),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(BuildContext context, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: context.textColor60, fontSize: 11)),
      ],
    );
  }

  Widget _buildRevenueGraph(BuildContext context, Map<String, dynamic> data) {
    final sortedKeys = data.keys.toList()..sort();
    final barGroups = <BarChartGroupData>[];
    double maxY = 0;

    for (int i = 0; i < sortedKeys.length; i++) {
      final entry = _map(data[sortedKeys[i]]);
      final due = _num(entry['due']).toDouble();
      final collected = _num(entry['collected']).toDouble();
      if (due > maxY) maxY = due;
      if (collected > maxY) maxY = collected;
      barGroups.add(
        BarChartGroupData(
          x: i,
          barsSpace: 4,
          barRods: [
            BarChartRodData(toY: due, color: const Color(0xFFF59E0B), width: 8, borderRadius: BorderRadius.circular(3)),
            BarChartRodData(toY: collected, color: const Color(0xFF10B981), width: 8, borderRadius: BorderRadius.circular(3)),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY + (maxY * 0.2) + 1,
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                if (value.toInt() >= 0 && value.toInt() < sortedKeys.length) {
                  final parts = sortedKeys[value.toInt()].split('-');
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      parts.length > 1 ? parts[1] : sortedKeys[value.toInt()],
                      style: TextStyle(color: context.textColor70, fontSize: 12),
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
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const Text('');
                return Text(_numberFmt.format(value.toInt()), style: TextStyle(color: context.textColor70, fontSize: 10));
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(color: context.glassBorder, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        barGroups: barGroups,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Attendance
  // ---------------------------------------------------------------------

  Widget _buildAttendanceRow(BuildContext context, Map<String, dynamic> attendance, double screenWidth) {
    final last7 = _map(attendance['last7Days']);
    final last30 = _map(attendance['last30Days']);
    final children = [
      Expanded(child: _buildAttendanceCard(context, 'Last 7 Days', last7, const Color(0xFF6366F1))),
      const SizedBox(width: 16),
      Expanded(child: _buildAttendanceCard(context, 'Last 30 Days', last30, const Color(0xFF10B981))),
    ];
    return screenWidth > 600
        ? IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: children))
        : Column(
            children: [
              _buildAttendanceCard(context, 'Last 7 Days', last7, const Color(0xFF6366F1)),
              const SizedBox(height: 16),
              _buildAttendanceCard(context, 'Last 30 Days', last30, const Color(0xFF10B981)),
            ],
          );
  }

  Widget _buildAttendanceCard(BuildContext context, String label, Map<String, dynamic> data, Color color) {
    final rate = _num(data['rate']).toDouble();
    final present = _num(data['present']);
    final absent = _num(data['absent']);
    final leave = _num(data['leave']);
    return _donutCard(
      context,
      '$label Attendance',
      segments: [
        ('Present', present, const Color(0xFF10B981)),
        ('Absent', absent, Colors.redAccent),
        ('Leave', leave, const Color(0xFFF59E0B)),
      ],
      centerLabel: '${rate.toStringAsFixed(0)}%',
      centerSubLabel: 'present rate',
      accent: color,
    );
  }

  // ---------------------------------------------------------------------
  // Needs attention
  // ---------------------------------------------------------------------

  Widget _needsAttentionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required int count,
    required List<Widget> items,
    required String emptyText,
  }) {
    return _glassCard(
      context,
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(emptyText, style: TextStyle(color: context.textColor60, fontSize: 12)),
            )
          else
            ...items,
        ],
      ),
    );
  }

  Widget _attentionListItem(BuildContext context, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: context.textColor, fontSize: 12.5, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(color: context.textColor60, fontSize: 11.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveRequestsCard(BuildContext context, Map<String, dynamic> data) {
    final items = _list(data['items']);
    return _needsAttentionCard(
      context,
      title: 'Pending Leave Requests',
      icon: Icons.event_busy_rounded,
      color: const Color(0xFFF59E0B),
      count: _num(data['count']).toInt(),
      emptyText: 'No pending leave requests.',
      items: items.map((raw) {
        final it = _map(raw);
        return _attentionListItem(
          context,
          it['studentName']?.toString() ?? 'Unknown',
          [
            if ((it['batchName']?.toString() ?? '').isNotEmpty) it['batchName'],
            it['reason'],
          ].where((e) => e != null && e.toString().isNotEmpty).join(' · '),
        );
      }).toList(),
    );
  }

  Widget _buildOverduePaymentsCard(BuildContext context, Map<String, dynamic> data) {
    final items = _list(data['items']);
    return _needsAttentionCard(
      context,
      title: 'Overdue Payments',
      icon: Icons.money_off_rounded,
      color: Colors.redAccent,
      count: _num(data['count']).toInt(),
      emptyText: 'No overdue payments. 🎉',
      items: items.map((raw) {
        final it = _map(raw);
        final due = _date(it['dueDate']);
        return _attentionListItem(
          context,
          '${it['studentName'] ?? 'Unknown'}  ·  ${_money(_num(it['amountDue']))}',
          [
            if ((it['batchName']?.toString() ?? '').isNotEmpty) it['batchName'],
            if (due != null) 'due ${_dateFmt.format(due)}',
          ].where((e) => e != null && e.toString().isNotEmpty).join(' · '),
        );
      }).toList(),
    );
  }

  Widget _buildParentMeetingsCard(BuildContext context, Map<String, dynamic> data) {
    final items = _list(data['items']);
    return _needsAttentionCard(
      context,
      title: 'Upcoming Parent Meetings',
      icon: Icons.groups_rounded,
      color: const Color(0xFF6366F1),
      count: _num(data['count']).toInt(),
      emptyText: 'No parent meetings scheduled.',
      items: items.map((raw) {
        final it = _map(raw);
        final when = _date(it['scheduledAt']);
        return _attentionListItem(
          context,
          it['title']?.toString() ?? 'Meeting',
          [
            it['batchName'],
            it['hostName'] != null ? 'host: ${it['hostName']}' : null,
            if (when != null) _dateTimeFmt.format(when),
          ].where((e) => e != null && e.toString().isNotEmpty).join(' · '),
        );
      }).toList(),
    );
  }

  Widget _buildPendingGradingCard(BuildContext context, Map<String, dynamic> data) {
    final items = _list(data['items']);
    return _needsAttentionCard(
      context,
      title: 'Pending Exam Grading',
      icon: Icons.rate_review_rounded,
      color: const Color(0xFF8B5CF6),
      count: _num(data['count']).toInt(),
      emptyText: 'No submissions awaiting grading.',
      items: items.map((raw) {
        final it = _map(raw);
        final submitted = _date(it['submittedAt']);
        return _attentionListItem(
          context,
          it['examTitle']?.toString() ?? 'Exam',
          [
            it['studentName'],
            if (submitted != null) 'submitted ${_dateFmt.format(submitted)}',
          ].where((e) => e != null && e.toString().isNotEmpty).join(' · '),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------
  // Tutor performance
  // ---------------------------------------------------------------------

  Widget _buildTutorPerformanceCard(BuildContext context, List<dynamic> tutors) {
    return _glassCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Batches, Students, Attendance & Revenue by Tutor',
            style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 12),
          if (tutors.isNotEmpty) ...[
            Text(
              'STUDENTS PER TUTOR',
              style: TextStyle(color: context.textColor70, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            _compareBarChart(
              context,
              tutors.map((raw) {
                final t = _map(raw);
                final name = (t['tutorName']?.toString() ?? 'Unknown').split(' ').first;
                return (name, _num(t['studentCount']));
              }).toList(),
              const Color(0xFF6366F1),
            ),
            const SizedBox(height: 20),
          ],
          if (tutors.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text('No tutors assigned to batches yet.', style: TextStyle(color: context.textColor60, fontSize: 12)),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 42,
                dataRowMaxHeight: 48,
                columnSpacing: 28,
                dividerThickness: 0.5,
                headingTextStyle: TextStyle(color: context.textColor70, fontWeight: FontWeight.bold, fontSize: 12),
                dataTextStyle: TextStyle(color: context.textColor, fontSize: 12.5),
                columns: const [
                  DataColumn(label: Text('Tutor')),
                  DataColumn(label: Text('Batches'), numeric: true),
                  DataColumn(label: Text('Students'), numeric: true),
                  DataColumn(label: Text('Attendance (30d)'), numeric: true),
                  DataColumn(label: Text('Collected'), numeric: true),
                  DataColumn(label: Text('Pending'), numeric: true),
                ],
                rows: tutors.map((raw) {
                  final t = _map(raw);
                  final attendanceRate = t['attendanceRate'];
                  final rateColor = attendanceRate == null
                      ? context.textColor60
                      : (_num(attendanceRate) >= 80
                          ? const Color(0xFF10B981)
                          : (_num(attendanceRate) >= 60 ? const Color(0xFFF59E0B) : Colors.redAccent));
                  final pending = _num(t['revenuePending']);
                  return DataRow(
                    cells: [
                      DataCell(Text(t['tutorName']?.toString() ?? 'Unknown')),
                      DataCell(Text('${_num(t['batchCount']).toInt()}')),
                      DataCell(Text('${_num(t['studentCount']).toInt()}')),
                      DataCell(
                        Text(
                          attendanceRate == null ? '—' : '${_num(attendanceRate).toStringAsFixed(1)}%',
                          style: TextStyle(color: rateColor, fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(Text(_money(_num(t['revenueCollected'])))),
                      DataCell(
                        Text(
                          _money(pending),
                          style: TextStyle(
                            color: pending > 0 ? const Color(0xFFF59E0B) : context.textColor60,
                            fontWeight: pending > 0 ? FontWeight.w700 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Course popularity & batch capacity
  // ---------------------------------------------------------------------

  Widget _buildCoursePopularityCard(BuildContext context, List<dynamic> courses) {
    return _glassCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Course Popularity',
            style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 12),
          if (courses.isNotEmpty) ...[
            Text(
              'STUDENTS PER COURSE',
              style: TextStyle(color: context.textColor70, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            _compareBarChart(
              context,
              courses.map((raw) {
                final c = _map(raw);
                return (c['courseName']?.toString() ?? 'Course', _num(c['studentCount']));
              }).toList(),
              const Color(0xFFF59E0B),
            ),
            const SizedBox(height: 20),
          ],
          if (courses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text('No course data yet.', style: TextStyle(color: context.textColor60, fontSize: 12)),
            )
          else
            ...courses.map((raw) {
              final c = _map(raw);
              final fillRate = c['fillRate'];
              final studentCount = _num(c['studentCount']).toInt();
              final capacity = _num(c['capacity']).toInt();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c['courseName']?.toString() ?? 'Course',
                            style: TextStyle(color: context.textColor, fontWeight: FontWeight.w600, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_num(c['batchCount']).toInt()} batch(es)',
                            style: TextStyle(color: context.textColor60, fontSize: 11),
                          ),
                          if (fillRate != null) ...[
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: (_num(fillRate) / 100).clamp(0, 1).toDouble(),
                                minHeight: 5,
                                backgroundColor: context.glassBorder,
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      capacity > 0 ? '$studentCount / $capacity' : '$studentCount',
                      style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildCapacityAlertsCard(BuildContext context, Map<String, dynamic> batches) {
    final nearFull = _list(batches['nearFull']);
    final underEnrolled = _list(batches['underEnrolled']);
    return _glassCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Batch Capacity Alerts',
            style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 14),
          Text(
            'NEAR FULL (≥90%)',
            style: TextStyle(color: context.textColor70, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5),
          ),
          const SizedBox(height: 6),
          if (nearFull.isEmpty)
            Text('None right now.', style: TextStyle(color: context.textColor60, fontSize: 12))
          else
            ...nearFull.map((raw) => _capacityItem(context, _map(raw), const Color(0xFFEC4899))),
          const SizedBox(height: 16),
          Text(
            'UNDER-ENROLLED (≤30%)',
            style: TextStyle(color: context.textColor70, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5),
          ),
          const SizedBox(height: 6),
          if (underEnrolled.isEmpty)
            Text('None right now.', style: TextStyle(color: context.textColor60, fontSize: 12))
          else
            ...underEnrolled.map((raw) => _capacityItem(context, _map(raw), const Color(0xFF06B6D4))),
        ],
      ),
    );
  }

  Widget _capacityItem(BuildContext context, Map<String, dynamic> b, Color color) {
    final fillRatio = b['fillRatio'];
    final pct = fillRatio == null ? null : (_num(fillRatio) * 100);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${b['name'] ?? 'Batch'} · ${b['tutorName'] ?? 'Unassigned'}',
              style: TextStyle(color: context.textColor, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (pct != null)
            Text('${pct.toStringAsFixed(0)}%', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Top batches & recent users
  // ---------------------------------------------------------------------

  Widget _buildTopBatchesCard(BuildContext context, List<dynamic> topBatches) {
    return _glassCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top Batches by Enrollment',
            style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 12),
          if (topBatches.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text('No batches yet.', style: TextStyle(color: context.textColor60, fontSize: 12)),
            )
          else
            ...topBatches.map((raw) {
              final b = _map(raw);
              final studentCount = _num(b['studentCount']).toInt();
              final maxMembers = b['maxMembers'];
              final capacityText =
                  maxMembers is num && maxMembers > 0 ? '$studentCount / ${maxMembers.toInt()}' : '$studentCount';
              final fillRatio =
                  (maxMembers is num && maxMembers > 0) ? (studentCount / maxMembers).clamp(0.0, 1.0) : null;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b['name']?.toString() ?? 'Batch',
                            style: TextStyle(color: context.textColor, fontWeight: FontWeight.w600, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${b['courseName'] ?? ''} · ${b['tutorName'] ?? 'Unassigned'} · ${b['categoryName'] ?? ''}',
                            style: TextStyle(color: context.textColor60, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (fillRatio != null) ...[
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: fillRatio,
                                minHeight: 5,
                                backgroundColor: context.glassBorder,
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      capacityText,
                      style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRecentUsersCard(BuildContext context, List<dynamic> recentUsers) {
    return _glassCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Signups',
            style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 12),
          if (recentUsers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text('No recent signups.', style: TextStyle(color: context.textColor60, fontSize: 12)),
            )
          else
            ...recentUsers.map((raw) {
              final u = _map(raw);
              final role = u['role']?.toString() ?? '';
              final created = _date(u['createdAt']);
              final roleColor = switch (role) {
                'STUDENT' => const Color(0xFF6366F1),
                'TUTOR' => const Color(0xFF10B981),
                'MENTOR' => const Color(0xFF14B8A6),
                'ADMIN' => const Color(0xFFEC4899),
                _ => const Color(0xFF64748B),
              };
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: roleColor.withOpacity(0.2),
                      child: Text(
                        (u['name']?.toString().isNotEmpty ?? false) ? u['name'].toString()[0].toUpperCase() : '?',
                        style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            u['name']?.toString() ?? 'Unknown',
                            style: TextStyle(color: context.textColor, fontWeight: FontWeight.w600, fontSize: 12.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(role, style: TextStyle(color: roleColor, fontSize: 10.5, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    if (created != null)
                      Text(_dateFmt.format(created), style: TextStyle(color: context.textColor60, fontSize: 11)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
