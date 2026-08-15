import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../providers/theme_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/api_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/schedules/schedules_bloc.dart';
import '../bloc/schedules/schedules_event.dart';
import '../bloc/schedules/schedules_state.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'live_meet_screen.dart';

class SchedulesScreen extends StatefulWidget {
  final bool isInline;
  const SchedulesScreen({super.key, this.isInline = false});

  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen> {
  @override
  void initState() {
    super.initState();
    context.read<SchedulesBloc>().add(FetchSchedules());
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<void> _applyForLeave(String scheduleId) async {
    final reasonController = TextEditingController();
    final bool? submit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text(
          'Apply for Leave',
          style: TextStyle(color: context.textColor),
        ),
        content: TextField(
          controller: reasonController,
          style: TextStyle(color: context.textColor),
          decoration: InputDecoration(
            labelText: 'Reason for leave',
            labelStyle: TextStyle(color: context.textColor54),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: context.textColor54.withOpacity(0.4)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF6366F1)),
            ),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: context.textColor60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Submit', style: TextStyle(color: context.textColor)),
          ),
        ],
      ),
    );

    if (submit == true && reasonController.text.trim().isNotEmpty) {
      context.read<SchedulesBloc>().add(
        SubmitLeaveRequest(
          scheduleId: scheduleId,
          reason: reasonController.text.trim(),
        ),
      );
    }
  }

  void _handleLeaveRequest(String scheduleId, String leaveId, String status) {
    context.read<SchedulesBloc>().add(
      UpdateLeaveRequestStatus(
        scheduleId: scheduleId,
        leaveId: leaveId,
        status: status,
      ),
    );
  }

  Future<void> _markAttendance(
    String scheduleId,
    List<dynamic> attendances,
  ) async {
    final scheduleAttendances = attendances
        .where((a) => a['schedule'] == scheduleId && a['status'] != 'Leave')
        .toList();
    if (scheduleAttendances.isEmpty) {
      _showError('No students found for this schedule (or all are on leave)');
      return;
    }

    final Map<String, String> updatedStatuses = {};
    final Map<String, bool> updatedLates = {};
    final Map<String, int> updatedSweets = {};

    for (var a in scheduleAttendances) {
      final sid = a['student']['_id'];
      // Map Pending/null to Absent by default, keep Present as Present
      updatedStatuses[sid] = (a['status'] == 'Present') ? 'Present' : 'Absent';
      updatedLates[sid] = a['isLate'] ?? false;
      updatedSweets[sid] = a['sweets'] ?? 0;
    }

    final bool? submit = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AlertDialog(
                backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white.withOpacity(0.8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: context.glassBorder),
                ),
                title: Text(
                  'Mark Attendance',
                  style: TextStyle(
                    color: context.textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: scheduleAttendances.length,
                    itemBuilder: (context, index) {
                      final studentName =
                          scheduleAttendances[index]['student']['name'];
                      final studentId =
                          scheduleAttendances[index]['student']['_id'];
                      final currentStatus = updatedStatuses[studentId];
                      final isLate = updatedLates[studentId] ?? false;
                      final sweets = updatedSweets[studentId] ?? 0;
                      final isPresent = currentStatus == 'Present';

                      return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: context.glassBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isPresent
                                    ? const Color(0xFF10B981).withOpacity(0.3)
                                    : context.glassBg,
                              ),
                            ),
                            child: Column(
                              children: [
                                ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  title: Text(
                                    studentName,
                                    style: TextStyle(
                                      color: context.textColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    isPresent ? 'Present' : 'Absent',
                                    style: TextStyle(
                                      color: isPresent
                                          ? const Color(0xFF10B981)
                                          : Colors.redAccent.withOpacity(0.8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  trailing: Switch(
                                    value: isPresent,
                                    activeColor: const Color(0xFF10B981),
                                    inactiveThumbColor: Colors.white54,
                                    inactiveTrackColor: context.glassBorder,
                                    onChanged: (val) {
                                      setDialogState(() {
                                        updatedStatuses[studentId] = val
                                            ? 'Present'
                                            : 'Absent';
                                      });
                                    },
                                  ),
                                ),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  height: isPresent ? 50 : 0,
                                  curve: Curves.easeOutCubic,
                                  clipBehavior: Clip.hardEdge,
                                  decoration: const BoxDecoration(),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0,
                                    ),
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: isLate,
                                          onChanged: (val) {
                                            setDialogState(() {
                                              updatedLates[studentId] =
                                                  val ?? false;
                                            });
                                          },
                                          activeColor: const Color(0xFFF59E0B),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          'Late',
                                          style: TextStyle(
                                            color: context.textColor70,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          'Sweets: ',
                                          style: TextStyle(
                                            color: context.textColor70,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Row(
                                          children: List.generate(3, (i) {
                                            final isActive = i < sweets;
                                            return GestureDetector(
                                              onTap: () {
                                                setDialogState(() {
                                                  if (sweets == i + 1) {
                                                    updatedSweets[studentId] =
                                                        0;
                                                  } else {
                                                    updatedSweets[studentId] =
                                                        i + 1;
                                                  }
                                                });
                                              },
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 2.0,
                                                    ),
                                                child: Opacity(
                                                  opacity: isActive ? 1.0 : 0.3,
                                                  child: const Text(
                                                    '🍬',
                                                    style: TextStyle(
                                                      fontSize: 18,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                          .animate()
                          .fade(delay: (index * 50).ms)
                          .slideX(
                            begin: 0.1,
                            end: 0,
                            curve: Curves.easeOutQuad,
                          );
                    },
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: context.textColor60),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(
                      'Save Attendance',
                      style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ).animate().scale(begin: const Offset(0.9, 0.9)).fade(),
            );
          },
        );
      },
    );

    if (submit == true) {
      final List<Map<String, dynamic>> dataToSubmit = updatedStatuses.entries
          .map((e) {
            final sid = e.key;
            return {
              'studentId': sid,
              'status': e.value,
              'isLate': updatedLates[sid] ?? false,
              'sweets': updatedSweets[sid] ?? 0,
            };
          })
          .toList();

      context.read<SchedulesBloc>().add(
        MarkAttendance(scheduleId: scheduleId, attendanceData: dataToSubmit),
      );
    }
  }

  void _showUploadNoteDialog(String batchId, String sessionDate) {
    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String? selectedFileName;
    List<int>? selectedFileBytes;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.glassBg,
              title: Text(
                'Upload Session Note',
                style: TextStyle(color: context.textColor),
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: titleCtrl,
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Title',
                          labelStyle: TextStyle(color: context.textColor54),
                        ),
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      TextFormField(
                        controller: descCtrl,
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Description',
                          labelStyle: TextStyle(color: context.textColor54),
                        ),
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedFileName == null
                                  ? 'No file selected'
                                  : selectedFileName!,
                              style: TextStyle(color: context.textColor54),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              FilePickerResult? result =
                                  await FilePicker.pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: [
                                      'pdf',
                                      'jpg',
                                      'jpeg',
                                      'png',
                                    ],
                                    withData: true,
                                  );
                              if (result != null &&
                                  result.files.single.bytes != null) {
                                setDialogState(() {
                                  selectedFileName = result.files.single.name;
                                  selectedFileBytes = result.files.single.bytes;
                                });
                              }
                            },
                            child: const Text(
                              'Pick File',
                              style: TextStyle(color: Color(0xFF818CF8)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: context.textColor60),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                  ),
                  onPressed: () async {
                    if (formKey.currentState!.validate() &&
                        selectedFileBytes != null) {
                      context.read<SchedulesBloc>().add(
                        SubmitNoteUpload(
                          batchId: batchId,
                          sessionId: sessionDate,
                          title: titleCtrl.text,
                          description: descCtrl.text,
                          fileBytes: selectedFileBytes!,
                          fileName: selectedFileName!,
                        ),
                      );
                      Navigator.pop(ctx);
                    } else if (selectedFileBytes == null) {
                      _showError('Please select a file');
                    }
                  },
                  child: Text(
                    'Upload',
                    style: TextStyle(color: context.textColor),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showLeaveRequests(String scheduleId, List<dynamic> allLeaveRequests) {
    final requests = allLeaveRequests
        .where((l) => l['schedule'] == scheduleId && l['status'] == 'Pending')
        .toList();
    if (requests.isEmpty) {
      _showSuccess('No pending leave requests for this schedule');
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text(
          'Pending Leave Requests',
          style: TextStyle(color: context.textColor),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final req = requests[index];
              return Card(
                color: context.isDark ? const Color(0xFF0F172A) : Colors.white,
                child: ListTile(
                  title: Text(
                    req['student']['name'],
                    style: TextStyle(color: context.textColor),
                  ),
                  subtitle: Text(
                    req['reason'],
                    style: TextStyle(color: context.textColor54),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.check, color: Colors.green),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _handleLeaveRequest(
                            scheduleId,
                            req['_id'],
                            'Approved',
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.redAccent),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _handleLeaveRequest(
                            scheduleId,
                            req['_id'],
                            'Rejected',
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: TextStyle(color: context.textColor60)),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      _showError('Could not launch $urlString');
    }
  }

  Future<void> _editClassLink(String batchId, String currentLink) async {
    final linkController = TextEditingController(text: currentLink);
    final bool? submit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text(
          'Edit Class Link',
          style: TextStyle(color: context.textColor),
        ),
        content: TextField(
          controller: linkController,
          style: TextStyle(color: context.textColor),
          decoration: InputDecoration(
            labelText: 'Meeting URL',
            labelStyle: TextStyle(color: context.textColor54),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: context.textColor54.withOpacity(0.4)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF6366F1)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: context.textColor60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Save', style: TextStyle(color: context.textColor)),
          ),
        ],
      ),
    );

    if (submit == true) {
      context.read<SchedulesBloc>().add(
        UpdateClassLink(batchId: batchId, link: linkController.text.trim()),
      );
    }
  }

  void _showCancelDialog(String scheduleId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text(
          'Cancel Session',
          style: TextStyle(color: context.textColor),
        ),
        content: Text(
          'Are you sure you want to cancel this session? This action cannot be undone.',
          style: TextStyle(color: context.textColor70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('No', style: TextStyle(color: context.textColor60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<SchedulesBloc>().add(
                CancelSchedule(scheduleId: scheduleId),
              );
            },
            child: Text(
              'Yes, Cancel',
              style: TextStyle(color: context.textColor),
            ),
          ),
        ],
      ),
    );
  }

  void _showPostponeDialog(String scheduleId) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF6366F1),
              onPrimary: Colors.white,
              surface: Color(0xFF1E293B),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      context.read<SchedulesBloc>().add(
        PostponeSchedule(
          scheduleId: scheduleId,
          newDate: picked.toIso8601String(),
        ),
      );
    }
  }

  Widget _buildScheduleList(
    List<dynamic> list,
    List<dynamic> allAttendances,
    List<dynamic> allLeaveRequests,
    List<dynamic> allNoteSubmissions,
    String role,
    bool isToday, {
    bool isPast = false,
  }) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          'No schedules found',
          style: TextStyle(color: context.textColor54),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final schedule = list[index];
        final date = DateTime.parse(schedule['date']).toLocal();
        final isStudent = role == 'STUDENT';

        bool hasUploadedNote = false;
        if (isStudent && isPast) {
          for (var sub in allNoteSubmissions) {
            if (sub['batch'] == schedule['batch']['_id'] &&
                sub['sessionDate'].toString().split('T')[0] ==
                    schedule['date'].toString().split('T')[0]) {
              hasUploadedNote = true;
              break;
            }
          }
        }

        Map<String, dynamic>? userLeaveReq;
        if (isStudent) {
          try {
            userLeaveReq = allLeaveRequests.firstWhere(
              (l) => l['schedule'] == schedule['_id'],
            );
          } catch (e) {
            userLeaveReq = null;
          }
        }

        return Container(
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: context.glassBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.glassBorder),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.1),
                    blurRadius: 20,
                    spreadRadius: -5,
                  ),
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
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    DateFormat(
                                      'EEEE, MMM d, yyyy',
                                    ).format(date),
                                    style: TextStyle(
                                      color: schedule['isCancelled'] == true
                                          ? Colors.redAccent
                                          : context.textColor,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      decoration:
                                          schedule['isCancelled'] == true
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  if (schedule['isCancelled'] == true) ...[
                                    SizedBox(width: 8),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent.withOpacity(
                                          0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'CANCELLED',
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF6366F1,
                                ).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(
                                    0xFF6366F1,
                                  ).withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                '${schedule['startTime']} - ${schedule['endTime']}',
                                style: TextStyle(
                                  color: Color(0xFF818CF8),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (!isStudent &&
                                schedule['isCancelled'] != true) ...[
                              SizedBox(width: 4),
                              PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.more_vert_rounded,
                                  color: context.textColor70,
                                ),
                                color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'cancel',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.cancel_rounded,
                                          color: Colors.redAccent,
                                          size: 20,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Cancel Session',
                                          style: TextStyle(
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'postpone',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.edit_calendar_rounded,
                                          color: Colors.orangeAccent,
                                          size: 20,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Postpone',
                                          style: TextStyle(
                                            color: Colors.orangeAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                onSelected: (val) {
                                  if (val == 'cancel') {
                                    _showCancelDialog(schedule['_id']);
                                  } else if (val == 'postpone') {
                                    _showPostponeDialog(schedule['_id']);
                                  }
                                },
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: 12),
                        if (!isStudent) ...[
                          Text(
                            'Batch: ${schedule['batch']['name']}',
                            style: TextStyle(
                              color: context.textColor.withOpacity(0.8),
                              fontSize: 15,
                            ),
                          ),
                          SizedBox(height: 8),
                        ],
                        if (isToday &&
                            ((schedule['batch']['classLink'] != null &&
                                    schedule['batch']['classLink']
                                        .toString()
                                        .isNotEmpty) ||
                                schedule['batch']['meetType'] == 'JITSI_MEET')) ...[
                          Divider(color: context.glassBorder, height: 24),
                          ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF8B5CF6),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  elevation: 8,
                                  shadowColor: const Color(
                                    0xFF8B5CF6,
                                  ).withOpacity(0.5),
                                ),
                                icon: Icon(
                                  Icons.video_camera_front,
                                  size: 20,
                                  color: Colors.white,
                                ),
                                label: Text(
                                  'Join Live Session',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onPressed: () {
                                  final batch = schedule['batch'];
                                  final meetType = batch['meetType'] ?? 'CUSTOM';
                                  if (meetType == 'JITSI_MEET') {
                                    var domain = (batch['jitsiServer'] ?? 'meet.jit.si').toString().trim();
                                    domain = domain.replaceAll(RegExp(r'^https?://'), '');
                                    if (domain.endsWith('/')) {
                                      domain = domain.substring(0, domain.length - 1);
                                    }
                                    if (domain.isEmpty) domain = 'meet.jit.si';
                                    
                                    final batchName = batch['name'] ?? 'Class';
                                    final batchId = batch['id'] ?? batch['_id'] ?? 'meet';
                                    final cleanRoomName = 'jyamiti_$batchId';
                                    final meetUrl = 'https://$domain/$cleanRoomName';

                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => LiveMeetScreen(
                                          meetingUrl: meetUrl,
                                          batchName: batchName,
                                        ),
                                      ),
                                    );
                                  } else {
                                    _launchUrl(batch['classLink'] ?? '');
                                  }
                                },
                              )
                              .animate(
                                onPlay: (controller) =>
                                    controller.repeat(reverse: true),
                              )
                              .shimmer(
                                duration: 2000.ms,
                                color: context.textColor54.withOpacity(0.4),
                              ),
                        ],
                        SizedBox(height: 16),
                        if (isStudent) ...[
                          if (isPast && !hasUploadedNote)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(
                                    0xFF6366F1,
                                  ).withOpacity(0.2),
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(
                                      color: const Color(
                                        0xFF6366F1,
                                      ).withOpacity(0.5),
                                    ),
                                  ),
                                ),
                                icon: Icon(
                                  Icons.upload_file_rounded,
                                  size: 16,
                                  color: Color(0xFF818CF8),
                                ),
                                label: Text(
                                  'Upload Note',
                                  style: TextStyle(
                                    color: Color(0xFF818CF8),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onPressed: () => _showUploadNoteDialog(
                                  schedule['batch']['_id'],
                                  schedule['date'],
                                ),
                              ),
                            )
                          else if (isPast && hasUploadedNote)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.green.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_circle_rounded,
                                      size: 16,
                                      color: Colors.green,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Note Uploaded',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          if (userLeaveReq != null)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: userLeaveReq['status'] == 'Approved'
                                    ? Colors.green.withOpacity(0.1)
                                    : userLeaveReq['status'] == 'Rejected'
                                    ? Colors.redAccent.withOpacity(0.1)
                                    : Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: userLeaveReq['status'] == 'Approved'
                                      ? Colors.green.withOpacity(0.3)
                                      : userLeaveReq['status'] == 'Rejected'
                                      ? Colors.redAccent.withOpacity(0.3)
                                      : Colors.orange.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    userLeaveReq['status'] == 'Approved'
                                        ? Icons.check_circle_rounded
                                        : userLeaveReq['status'] == 'Rejected'
                                        ? Icons.cancel_rounded
                                        : Icons.pending_actions_rounded,
                                    size: 16,
                                    color: userLeaveReq['status'] == 'Approved'
                                        ? Colors.green
                                        : userLeaveReq['status'] == 'Rejected'
                                        ? Colors.redAccent
                                        : Colors.orange,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Leave: ${userLeaveReq['status']}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color:
                                          userLeaveReq['status'] == 'Approved'
                                          ? Colors.green
                                          : userLeaveReq['status'] == 'Rejected'
                                          ? Colors.redAccent
                                          : Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (!isPast)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3B82F6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: Icon(
                                Icons.event_busy,
                                size: 16,
                                color: Colors.white,
                              ),
                              label: Text(
                                'Apply for Leave',
                                style: TextStyle(color: Colors.white),
                              ),
                              onPressed: () => _applyForLeave(schedule['_id']),
                            ),
                        ] else ...[
                          Divider(color: context.glassBorder, height: 24),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              if ((isToday || isPast) &&
                                  schedule['isCancelled'] != true)
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(
                                      0xFF10B981,
                                    ).withOpacity(0.2),
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                        color: const Color(
                                          0xFF10B981,
                                        ).withOpacity(0.5),
                                      ),
                                    ),
                                  ),
                                  icon: Icon(
                                    Icons.checklist_rtl_rounded,
                                    size: 18,
                                    color: Color(0xFF10B981),
                                  ),
                                  label: Text(
                                    'Mark Attendance',
                                    style: TextStyle(
                                      color: Color(0xFF10B981),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () => _markAttendance(
                                    schedule['_id'],
                                    allAttendances,
                                  ),
                                ),
                              if (role == 'MENTOR' || role == 'ADMIN')
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(
                                      0xFFF59E0B,
                                    ).withOpacity(0.2),
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                        color: const Color(
                                          0xFFF59E0B,
                                        ).withOpacity(0.5),
                                      ),
                                    ),
                                  ),
                                  icon: Icon(
                                    Icons.mark_email_unread_rounded,
                                    size: 18,
                                    color: Color(0xFFF59E0B),
                                  ),
                                  label: Text(
                                    'Leave Requests',
                                    style: TextStyle(
                                      color: Color(0xFFF59E0B),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () => _showLeaveRequests(
                                    schedule['_id'],
                                    allLeaveRequests,
                                  ),
                                ),
                              if (isToday &&
                                  (role == 'TUTOR' ||
                                      role == 'MENTOR' ||
                                      role == 'ADMIN') &&
                                  schedule['batch']['meetType'] != 'JITSI_MEET')
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(
                                      0xFF6366F1,
                                    ).withOpacity(0.2),
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                        color: const Color(
                                          0xFF6366F1,
                                        ).withOpacity(0.5),
                                      ),
                                    ),
                                  ),
                                  icon: Icon(
                                    Icons.edit_rounded,
                                    size: 18,
                                    color: Color(0xFF818CF8),
                                  ),
                                  label: Text(
                                    'Edit Link',
                                    style: TextStyle(
                                      color: Color(0xFF818CF8),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () => _editClassLink(
                                    schedule['batch']['_id'],
                                    schedule['batch']['classLink'] ?? '',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            )
            .animate()
            .fade(duration: 400.ms, delay: (index * 100).ms)
            .slideY(begin: 0.1, end: 0);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = Provider.of<AuthProvider>(context).userRole ?? 'STUDENT';

    return BlocConsumer<SchedulesBloc, SchedulesState>(
      listener: (context, state) {
        if (state is SchedulesActionSuccess) {
          _showSuccess(state.message);
        } else if (state is SchedulesActionError) {
          _showError(state.message);
        }
      },
      buildWhen: (previous, current) {
        return current is! SchedulesActionSuccess &&
            current is! SchedulesActionError;
      },
      builder: (context, state) {
        if (state is SchedulesLoading || state is SchedulesInitial) {
          return Scaffold(
            backgroundColor: widget.isInline ? Colors.transparent : (context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
            body: Center(
              child: JyamitiLoader(color: Color(0xFF6366F1)),
            ),
          );
        } else if (state is SchedulesError) {
          return Scaffold(
            backgroundColor: widget.isInline ? Colors.transparent : (context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.message,
                    style: TextStyle(color: context.textColor70),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        context.read<SchedulesBloc>().add(FetchSchedules()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        } else if (state is SchedulesLoaded) {
          final _schedules = state.schedules;
          final _attendances = state.attendances;
          final _leaveRequests = state.leaveRequests;
          final _noteSubmissions = state.noteSubmissions;

          final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
          final todaySchedules = _schedules.where((s) {
            final date = DateTime.parse(s['date']).toLocal();
            return DateFormat('yyyy-MM-dd').format(date) == todayStr;
          }).toList();

          final upcomingSchedules = _schedules.where((s) {
            final date = DateTime.parse(s['date']).toLocal();
            return DateFormat('yyyy-MM-dd').format(date).compareTo(todayStr) >
                0;
          }).toList();
          final recentSchedules =
              _schedules.where((s) {
                final date = DateTime.parse(s['date']).toLocal();
                return DateFormat(
                      'yyyy-MM-dd',
                    ).format(date).compareTo(todayStr) <
                    0;
              }).toList()..sort(
                (a, b) => DateTime.parse(
                  b['date'],
                ).compareTo(DateTime.parse(a['date'])),
              );

          return DefaultTabController(
            length: 3,
            child: Scaffold(
              extendBodyBehindAppBar: true,
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                automaticallyImplyLeading: !widget.isInline,
                title: widget.isInline
                    ? null
                    : Text(
                        'Schedules & Attendance',
                        style: TextStyle(
                          color: context.textColor,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                backgroundColor: Colors.transparent,
                flexibleSpace: widget.isInline
                    ? null
                    : ClipRRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            color: context.isDark
                                ? const Color(0xFF0F172A).withOpacity(0.6)
                                : Colors.white.withOpacity(0.6),
                          ),
                        ),
                      ),
                iconTheme: IconThemeData(color: context.textColor),
                elevation: 0,
                bottom: TabBar(
                  indicatorColor: const Color(0xFF6366F1),
                  indicatorWeight: 3,
                  labelColor: context.textColor,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                  unselectedLabelColor: context.textColor.withOpacity(0.6),
                  tabs: const [
                    Tab(text: "Today"),
                    Tab(text: "Upcoming"),
                    Tab(text: "Recent"),
                  ],
                ),
              ),
              body: Stack(
                children: [
                  if (!widget.isInline)
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: context.isDark
                              ? [
                                  Color(0xFF0F172A),
                                  Color(0xFF1E1B4B),
                                  Color(0xFF0F172A),
                                ]
                              : [
                                  Color(0xFFF1F5F9),
                                  Color(0xFFE2E8F0),
                                  Color(0xFFF1F5F9),
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  SafeArea(
                    child: TabBarView(
                      children: [
                        _buildScheduleList(
                          todaySchedules,
                          _attendances,
                          _leaveRequests,
                          _noteSubmissions,
                          role,
                          true,
                        ),
                        _buildScheduleList(
                          upcomingSchedules,
                          _attendances,
                          _leaveRequests,
                          _noteSubmissions,
                          role,
                          false,
                        ),
                        _buildScheduleList(
                          recentSchedules,
                          _attendances,
                          _leaveRequests,
                          _noteSubmissions,
                          role,
                          false,
                          isPast: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
