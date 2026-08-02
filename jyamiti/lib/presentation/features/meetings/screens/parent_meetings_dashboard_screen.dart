import 'package:flutter/material.dart';
import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/parent_meeting_service.dart';
import 'parent_meeting_room_screen.dart';

class ParentMeetingsDashboardScreen extends StatefulWidget {
  final List<dynamic>? batches;
  final bool isInline;
  final VoidCallback? onBack;

  const ParentMeetingsDashboardScreen({
    super.key,
    this.batches,
    this.isInline = false,
    this.onBack,
  });

  @override
  State<ParentMeetingsDashboardScreen> createState() =>
      _ParentMeetingsDashboardScreenState();
}

class _ParentMeetingsDashboardScreenState
    extends State<ParentMeetingsDashboardScreen> {
  bool _isLoading = true;
  List<dynamic> _meetings = [];
  String _selectedFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadMeetings();
  }

  Future<void> _loadMeetings() async {
    setState(() => _isLoading = true);
    try {
      final loaded = await ParentMeetingService.getMyMeetings();
      setState(() {
        _meetings = loaded;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _meetings = [];
        _isLoading = false;
      });
    }
  }

  void _showScheduleMeetingDialog() {
    final tutorBatches = widget.batches ?? [];
    if (tutorBatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No batches assigned. Please contact administrator.')),
      );
      return;
    }

    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String selectedBatchId = (tutorBatches.first['id'] ?? tutorBatches.first['_id']).toString();
    DateTime selectedDateTime = DateTime.now().add(const Duration(hours: 1));
    int durationMinutes = 45;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor:
                context.isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: context.glassBorder),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.video_call_rounded,
                    color: Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Schedule Parent Meeting',
                  style: TextStyle(
                    color: context.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Meeting Title
                    Text('Meeting Title *',
                        style: TextStyle(
                            color: context.textColor70,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleCtrl,
                      style: TextStyle(color: context.textColor),
                      decoration: InputDecoration(
                        hintText: 'e.g. Q3 Progress & Academic Review',
                        hintStyle: TextStyle(color: context.textColor60),
                        filled: true,
                        fillColor: context.isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.grey.withValues(alpha: 0.1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Target Batch Dropdown
                    Text('Select Target Batch *',
                        style: TextStyle(
                            color: context.textColor70,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: context.isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedBatchId,
                          isExpanded: true,
                          dropdownColor: context.isDark
                              ? const Color(0xFF1E293B)
                              : Colors.white,
                          items: tutorBatches.map((b) {
                            final id = (b['id'] ?? b['_id']).toString();
                            final name = (b['name'] ?? 'Batch').toString();
                            return DropdownMenuItem(
                              value: id,
                              child: Text(name,
                                  style: TextStyle(color: context.textColor)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => selectedBatchId = val);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Scheduled Date & Time Picker
                    Text('Date & Time *',
                        style: TextStyle(
                            color: context.textColor70,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDateTime,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 90)),
                        );
                        if (date != null && mounted) {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(selectedDateTime),
                          );
                          if (time != null) {
                            setDialogState(() {
                              selectedDateTime = DateTime(
                                date.year,
                                date.month,
                                date.day,
                                time.hour,
                                time.minute,
                              );
                            });
                          }
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: context.isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month_rounded,
                                color: Color(0xFF6366F1), size: 18),
                            const SizedBox(width: 10),
                            Text(
                              '${selectedDateTime.day}/${selectedDateTime.month}/${selectedDateTime.year} at ${selectedDateTime.hour.toString().padLeft(2, '0')}:${selectedDateTime.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                  color: context.textColor,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Description / Agenda
                    Text('Agenda / Notes (Optional)',
                        style: TextStyle(
                            color: context.textColor70,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      style: TextStyle(color: context.textColor),
                      decoration: InputDecoration(
                        hintText: 'Discussion topics, student performance...',
                        hintStyle: TextStyle(color: context.textColor60),
                        filled: true,
                        fillColor: context.isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.grey.withValues(alpha: 0.1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: TextStyle(color: context.textColor60)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Schedule Meeting'),
                onPressed: () async {
                  if (titleCtrl.text.trim().isEmpty) return;
                  try {
                    await ParentMeetingService.createMeeting(
                      title: titleCtrl.text.trim(),
                      description: descCtrl.text.trim(),
                      batchId: selectedBatchId,
                      scheduledAt: selectedDateTime.toIso8601String(),
                      durationMinutes: durationMinutes,
                    );
                    if (mounted) {
                      Navigator.pop(ctx);
                      _loadMeetings();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Parent Meeting scheduled successfully!')),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: ${e.toString()}')),
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final role = auth.userRole ?? 'STUDENT';
    final isHostRole = role == 'TUTOR' || role == 'ADMIN';

    final filteredMeetings = _meetings.where((m) {
      final status = (m['status'] ?? 'scheduled').toString();
      if (_selectedFilter == 'LIVE') return status == 'live';
      if (_selectedFilter == 'SCHEDULED') return status == 'scheduled';
      if (_selectedFilter == 'ENDED') return status == 'ended';
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.isInline
          ? null
          : AppBar(
              title: const Text(
                'Parent Meetings',
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
                      'Live Parent Meetings',
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isHostRole
                          ? 'Schedule and host live video conferences with parents and students.'
                          : 'Join scheduled video calls with your batch tutor.',
                      style: TextStyle(
                        color: context.textColor60,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                if (isHostRole)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text(
                      'Schedule Meeting',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _showScheduleMeetingDialog,
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // Status Filter Tabs
            Row(
              children: [
                _buildFilterChip('ALL', 'All Meetings'),
                const SizedBox(width: 8),
                _buildFilterChip('LIVE', '🔴 Live Now'),
                const SizedBox(width: 8),
                _buildFilterChip('SCHEDULED', '📅 Scheduled'),
                const SizedBox(width: 8),
                _buildFilterChip('ENDED', '🏁 Completed'),
              ],
            ),
            const SizedBox(height: 20),

            // Content Body
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: JyamitiLoader(color: Color(0xFF6366F1)),
                    )
                  : filteredMeetings.isEmpty
                      ? _buildEmptyState(isHostRole)
                      : ListView.builder(
                          itemCount: filteredMeetings.length,
                          itemBuilder: (context, index) {
                            final m = filteredMeetings[index];
                            return _buildMeetingCard(m, isHostRole);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedFilter == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : context.textColor70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF6366F1),
      backgroundColor: context.isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.grey.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (_) => setState(() => _selectedFilter = key),
    );
  }

  Widget _buildEmptyState(bool isHostRole) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: context.isDark
              ? context.glassBg
              : Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFF6366F1).withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.video_camera_front_rounded,
                color: Color(0xFF6366F1),
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Parent Meetings Found',
              style: TextStyle(
                color: context.textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isHostRole
                  ? 'Click "Schedule Meeting" above to set up a new video conference for parents.'
                  : 'There are currently no scheduled parent meetings for your batch.',
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

  Widget _buildMeetingCard(dynamic m, bool isHostRole) {
    if (m is! Map) return const SizedBox.shrink();

    final title = m['title'] ?? 'Parent Meeting';
    final description = m['description'] ?? '';
    final batchName = m['batchName'] ?? 'Batch';
    final hostName = m['hostName'] ?? 'Tutor';
    final status = (m['status'] ?? 'scheduled').toString();
    final isLive = status == 'live';
    final isEnded = status == 'ended';

    final scheduledAt = m['scheduledAt'] != null
        ? DateTime.tryParse(m['scheduledAt'].toString())
        : null;

    final dateStr = scheduledAt != null
        ? '${scheduledAt.day}/${scheduledAt.month}/${scheduledAt.year} at ${scheduledAt.hour.toString().padLeft(2, '0')}:${scheduledAt.minute.toString().padLeft(2, '0')}'
        : 'Scheduled';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLive
              ? Colors.redAccent
              : const Color(0xFF6366F1).withValues(alpha: 0.3),
          width: isLive ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isLive
                ? Colors.redAccent.withValues(alpha: 0.15)
                : const Color(0xFF6366F1).withValues(alpha: 0.05),
            blurRadius: 16,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isLive
                        ? Colors.redAccent.withValues(alpha: 0.15)
                        : const Color(0xFF6366F1).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.video_call_rounded,
                    color: isLive ? Colors.redAccent : const Color(0xFF6366F1),
                    size: 26,
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
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isLive
                                  ? Colors.redAccent.withValues(alpha: 0.15)
                                  : isEnded
                                      ? context.textColor54.withValues(alpha: 0.15)
                                      : const Color(0xFF10B981)
                                          .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isLive
                                  ? '🔴 LIVE NOW'
                                  : isEnded
                                      ? '🏁 COMPLETED'
                                      : '📅 SCHEDULED',
                              style: TextStyle(
                                color: isLive
                                    ? Colors.redAccent
                                    : isEnded
                                        ? context.textColor60
                                        : const Color(0xFF10B981),
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
                                color: context.textColor60, fontSize: 12),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.person_rounded,
                              size: 13, color: context.textColor60),
                          const SizedBox(width: 4),
                          Text(
                            'Host: $hostName',
                            style: TextStyle(
                                color: context.textColor60, fontSize: 12),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.access_time_rounded,
                              size: 13, color: context.textColor60),
                          const SizedBox(width: 4),
                          Text(
                            dateStr,
                            style: TextStyle(
                                color: context.textColor60, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (description.toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                description.toString(),
                style: TextStyle(
                  color: context.textColor70,
                  fontSize: 13,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isHostRole) ...[
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.redAccent, size: 20),
                    tooltip: 'Delete Meeting',
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Meeting?'),
                          content: const Text(
                              'Are you sure you want to cancel and delete this meeting?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('No'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && m['_id'] != null) {
                        await ParentMeetingService.deleteMeeting(
                            m['_id'].toString());
                        _loadMeetings();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                ],

                if (!isEnded)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLive ? Colors.redAccent : const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: isLive ? 4 : 1,
                    ),
                    icon: Icon(
                      isHostRole
                          ? Icons.video_call_rounded
                          : Icons.login_rounded,
                      size: 18,
                    ),
                    label: Text(
                      isHostRole
                          ? (isLive ? 'Return to Host Call' : 'Start Meeting as Host')
                          : 'Join Parent Meeting',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ParentMeetingRoomScreen(
                            meeting: Map<String, dynamic>.from(m as Map),
                            isHost: isHostRole,
                          ),
                        ),
                      ).then((_) => _loadMeetings());
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
