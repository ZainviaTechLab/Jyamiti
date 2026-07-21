import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:jyamiti/presentation/features/admin/bloc/batch_category/batch_category_bloc.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../providers/auth_provider.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../services/api_service.dart';
import '../bloc/batch/batch_bloc.dart';
import '../bloc/batch/batch_event.dart';
import '../screens/admin_batch_detail_screen.dart';
import '../bloc/batch/batch_state.dart';
import 'batch_categories_tab.dart';

// ==========================================
// BATCHES MANAGEMENT TAB
// ==========================================
class BatchesTab extends StatefulWidget {
  const BatchesTab({super.key});

  @override
  State<BatchesTab> createState() => _BatchesTabState();
}

class _BatchesTabState extends State<BatchesTab> {
  List<dynamic> _batches = [];
  List<dynamic> _courses = [];
  List<dynamic> _tutors = [];
  List<dynamic> _mentors = [];
  List<dynamic> _students = [];
  List<dynamic> _categories = [];
  bool _isLoading = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final cRes = await ApiService.get('/courses');
      final uRes = await ApiService.get('/users');
      final catRes = await ApiService.get('/batch-categories');

      if (cRes.statusCode == 200) _courses = jsonDecode(cRes.body);
      if (catRes.statusCode == 200) _categories = jsonDecode(catRes.body);
      if (uRes.statusCode == 200) {
        final allUsers = jsonDecode(uRes.body) as List;
        _tutors = allUsers.where((u) => u['role'] == 'TUTOR').toList();
        _mentors = allUsers.where((u) => u['role'] == 'MENTOR').toList();
        _students = allUsers.where((u) => u['role'] == 'STUDENT').toList();
      }

      if (mounted) context.read<BatchBloc>().add(FetchBatches());
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _triggerRefresh() {
    context.read<BatchBloc>().add(FetchBatches());
  }

  void _createBatch(
    String name,
    String categoryId,
    String courseId,
    String tutorId,
    List<String> mentorIds,
    List<String> days,
    String timePeriod,
    String classLink,
    String? startDate,
  ) {
    context.read<BatchBloc>().add(
      CreateBatch({
        'name': name,
        'categoryId': categoryId,
        'courseId': courseId,
        'tutorId': tutorId,
        'mentorIds': mentorIds,
        'daysOfWeek': days,
        'timePeriod': timePeriod,
        'classLink': classLink,
        if (startDate != null) 'startDate': startDate,
      }),
    );
  }

  void _deleteBatch(String id) {
    context.read<BatchBloc>().add(DeleteBatch(id));
  }

  void _confirmDelete(
    BuildContext context,
    String itemName,
    VoidCallback onConfirm,
  ) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Text(
            'Delete $itemName?',
            style: TextStyle(color: context.textColor),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Please type "$itemName" to confirm deletion.',
                style: TextStyle(color: context.textColor70),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                style: TextStyle(color: context.textColor),
                decoration: InputDecoration(
                  labelText: 'Confirm Name',
                  labelStyle: TextStyle(color: context.textColor54),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: context.glassBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.redAccent),
                  ),
                ),
              ),
            ],
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
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () {
                if (controller.text.trim() == itemName) {
                  Navigator.pop(ctx);
                  onConfirm();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Name does not match!'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              child: Text(
                'Delete',
                style: TextStyle(color: context.textColor),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editBatchDetails(
    String id,
    String categoryId,
    String tutorId,
    List<String> mentorIds,
    List<String> days,
    String timePeriod,
    String classLink,
    String? startDate,
  ) async {
    try {
      final response = await ApiService.put('/batches/$id', {
        'categoryId': categoryId,
        'tutorId': tutorId,
        'mentorIds': mentorIds,
        'daysOfWeek': days,
        'timePeriod': timePeriod,
        'classLink': classLink,
        if (startDate != null) 'startDate': startDate,
      });
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Batch details updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchData();
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Error updating schedule'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  Future<void> _addStudentsToBatch(
    String batchId,
    List<String> studentIds,
  ) async {
    try {
      final response = await ApiService.post('/batches/$batchId/students', {
        'studentIds': studentIds,
      });

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Students added to batch successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchData();
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Error adding students'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  Future<void> _removeStudentFromBatch(String batchId, String studentId) async {
    try {
      final response = await ApiService.delete(
        '/batches/$batchId/students/$studentId',
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Student removed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchData();
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  Future<void> _moveStudentToBatch(String sourceBatchId, String targetBatchId, String studentId) async {
    setState(() => _isLoading = true);
    try {
      final deleteResponse = await ApiService.delete('/batches/$sourceBatchId/students/$studentId');
      if (deleteResponse.statusCode == 200) {
        final addResponse = await ApiService.post('/batches/$targetBatchId/students', {
          'studentIds': [studentId],
        });
        if (addResponse.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Student moved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchData();
        } else {
          final data = jsonDecode(addResponse.body);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Error adding student to target batch'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } else {
        final data = jsonDecode(deleteResponse.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Error removing student from current batch'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error moving student: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showChangeBatchDialog(Map<String, dynamic> currentBatch, Map<String, dynamic> student) {
    final otherBatches = _batches.where((b) {
      final bid = b['id'] ?? b['_id'];
      final curid = currentBatch['id'] ?? currentBatch['_id'];
      return bid != curid;
    }).toList();

    if (otherBatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No other batches available to move this student to.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AlertDialog(
            backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            title: Text(
              'Move ${student['name']}',
              style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold),
            ),
            content: Container(
              width: 400,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select target batch to transfer this student to:',
                    style: TextStyle(color: context.textColor70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: otherBatches.length,
                      itemBuilder: (c, idx) {
                        final batch = otherBatches[idx];
                        final categoryName = batch['category']?['name'] ?? 'General';
                        final courseName = batch['course']?['name'] ?? 'Unknown Course';
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: context.isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.02),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: context.textColor.withOpacity(0.05)),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            title: Text(
                              batch['name'] ?? '',
                              style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            subtitle: Text(
                              '$courseName • $categoryName',
                              style: TextStyle(color: context.textColor60, fontSize: 12),
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () {
                              Navigator.pop(ctx);
                              Navigator.pop(context);
                              _moveStudentToBatch(
                                currentBatch['id'] ?? currentBatch['_id'],
                                batch['id'] ?? batch['_id'],
                                student['id'] ?? student['_id'],
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
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
            ],
          ),
        );
      },
    );
  }

  void _showAddBatchDialog() {
    if (_courses.isEmpty || _tutors.isEmpty || _categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please add at least one course, one category, and one tutor first.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final linkController = TextEditingController();

    TimeOfDay? startTime = const TimeOfDay(hour: 10, minute: 0);
    TimeOfDay? endTime = const TimeOfDay(hour: 12, minute: 0);
    DateTime? startDate = DateTime.now();

    String _formatTimePeriod(TimeOfDay start, TimeOfDay end) {
      String formatTime(TimeOfDay t) {
        final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
        final minute = t.minute.toString().padLeft(2, '0');
        final period = t.period == DayPeriod.am ? 'AM' : 'PM';
        return '${hour.toString().padLeft(2, '0')}:$minute $period';
      }

      return '${formatTime(start)} - ${formatTime(end)}';
    }

    String? selectedCourse = _courses.isNotEmpty ? _courses[0]['id'] : null;
    String? selectedCategory = _categories.isNotEmpty
        ? _categories[0]['id']
        : null;
    String? selectedTutor = _tutors.isNotEmpty ? _tutors[0]['id'] : null;
    List<String> selectedMentors = [];
    List<String> selectedDays = [];

    final weekDays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              title: Text(
                'Create New Batch',
                style: TextStyle(color: context.textColor),
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: nameController,
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Batch Name',
                          labelStyle: TextStyle(color: context.textColor70),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCourse,
                        dropdownColor: const Color(0xFF1E293B),
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Course',
                          labelStyle: TextStyle(color: context.textColor70),
                        ),
                        items: _courses.map<DropdownMenuItem<String>>((c) {
                          return DropdownMenuItem(
                            value: c['id'],
                            child: Text(c['name']),
                          );
                        }).toList(),
                        onChanged: (v) =>
                            setDialogState(() => selectedCourse = v!),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCategory,
                        dropdownColor: const Color(0xFF1E293B),
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Category',
                          labelStyle: TextStyle(color: context.textColor70),
                        ),
                        items: _categories.map<DropdownMenuItem<String>>((c) {
                          return DropdownMenuItem(
                            value: c['id'],
                            child: Text(c['name']),
                          );
                        }).toList(),
                        onChanged: (v) =>
                            setDialogState(() => selectedCategory = v!),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedTutor,
                        dropdownColor: const Color(0xFF1E293B),
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Lead Tutor',
                          labelStyle: TextStyle(color: context.textColor70),
                        ),
                        items: _tutors.map<DropdownMenuItem<String>>((t) {
                          return DropdownMenuItem(
                            value: t['id'],
                            child: Text(t['name']),
                          );
                        }).toList(),
                        onChanged: (v) =>
                            setDialogState(() => selectedTutor = v!),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Select Mentors:',
                        style: TextStyle(
                          color: context.textColor70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ..._mentors.map((m) {
                        final isChecked = selectedMentors.contains(m['id']);
                        return CheckboxListTile(
                          title: Text(
                            m['name'],
                            style: TextStyle(color: context.textColor),
                          ),
                          activeColor: const Color(0xFF6366F1),
                          checkColor: Colors.white,
                          value: isChecked,
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                selectedMentors.add(m['id']);
                              } else {
                                selectedMentors.remove(m['id']);
                              }
                            });
                          },
                        );
                      }),
                      const SizedBox(height: 16),
                      Text(
                        'Select Days of Week:',
                        style: TextStyle(
                          color: context.textColor70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: weekDays.map((day) {
                          final isSelected = selectedDays.contains(day);
                          return FilterChip(
                            label: Text(day.substring(0, 3)),
                            selected: isSelected,
                            selectedColor: const Color(0xFF6366F1),
                            checkmarkColor: Colors.white,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : (context.isDark ? Colors.white70 : Colors.black87),
                            ),
                            backgroundColor: context.isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                            onSelected: (val) {
                              setDialogState(() {
                                if (val) {
                                  selectedDays.add(day);
                                } else {
                                  selectedDays.remove(day);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Start Date:',
                        style: TextStyle(
                          color: context.textColor70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              startDate == null
                                  ? 'No date selected'
                                  : startDate!.toLocal().toString().split(
                                      ' ',
                                    )[0],
                              style: TextStyle(color: context.textColor),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: startDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (d != null)
                                setDialogState(() => startDate = d);
                            },
                            child: const Text(
                              'Pick Date',
                              style: TextStyle(color: Color(0xFF818CF8)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Class Time Period:',
                        style: TextStyle(
                          color: context.textColor70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: context.isDark ? const Color(0xFF334155) : Colors.grey[200],
                              ),
                              icon: Icon(
                                Icons.access_time,
                                size: 16,
                                color: context.textColor,
                              ),
                              label: Text(
                                startTime != null
                                    ? startTime!.format(context)
                                    : 'Start Time',
                                style: TextStyle(color: context.textColor),
                              ),
                              onPressed: () async {
                                final t = await showTimePicker(
                                  context: context,
                                  initialTime: startTime ?? TimeOfDay.now(),
                                );
                                if (t != null)
                                  setDialogState(() => startTime = t);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: context.isDark ? const Color(0xFF334155) : Colors.grey[200],
                              ),
                              icon: Icon(
                                Icons.access_time,
                                size: 16,
                                color: context.textColor,
                              ),
                              label: Text(
                                endTime != null
                                    ? endTime!.format(context)
                                    : 'End Time',
                                style: TextStyle(color: context.textColor),
                              ),
                              onPressed: () async {
                                final t = await showTimePicker(
                                  context: context,
                                  initialTime: endTime ?? TimeOfDay.now(),
                                );
                                if (t != null)
                                  setDialogState(() => endTime = t);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: linkController,
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Class Link (URL)',
                          labelStyle: TextStyle(color: context.textColor70),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Required' : null,
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
                  onPressed: () {
                    if (formKey.currentState!.validate() &&
                        selectedDays.isNotEmpty &&
                        startTime != null &&
                        endTime != null &&
                        startDate != null) {
                      _createBatch(
                        nameController.text.trim(),
                        selectedCategory!,
                        selectedCourse!,
                        selectedTutor!,
                        selectedMentors,
                        selectedDays,
                        _formatTimePeriod(startTime!, endTime!),
                        linkController.text.trim(),
                        startDate!.toIso8601String(),
                      );
                      Navigator.pop(ctx);
                    } else if (selectedDays.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Please select at least one day for classes.',
                          ),
                        ),
                      );
                    }
                  },
                  child: Text(
                    'Create',
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

  void _showEditBatchDetailsDialog(Map<String, dynamic> batch) {
    final formKey = GlobalKey<FormState>();
    final linkController = TextEditingController(
      text: batch['classLink'] ?? '',
    );

    TimeOfDay _parseTime(String t) {
      final parts = t.split(':');
      final hourStr = parts[0];
      final minStr = parts[1].substring(0, 2);
      final period = parts[1].substring(3).trim();
      int hour = int.parse(hourStr);
      if (period.toUpperCase() == 'PM' && hour != 12) hour += 12;
      if (period.toUpperCase() == 'AM' && hour == 12) hour = 0;
      return TimeOfDay(hour: hour, minute: int.parse(minStr));
    }

    TimeOfDay? startTime;
    TimeOfDay? endTime;
    if (batch['timePeriod'] != null) {
      final parts = batch['timePeriod'].toString().split('-');
      if (parts.length == 2) {
        try {
          startTime = _parseTime(parts[0].trim());
          endTime = _parseTime(parts[1].trim());
        } catch (e) {
          startTime = const TimeOfDay(hour: 10, minute: 0);
          endTime = const TimeOfDay(hour: 12, minute: 0);
        }
      }
    }

    DateTime? startDate;
    if (batch['startDate'] != null) {
      startDate = DateTime.tryParse(batch['startDate']);
    }

    String _formatTimePeriod(TimeOfDay start, TimeOfDay end) {
      String formatTime(TimeOfDay t) {
        final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
        final minute = t.minute.toString().padLeft(2, '0');
        final period = t.period == DayPeriod.am ? 'AM' : 'PM';
        return '${hour.toString().padLeft(2, '0')}:$minute $period';
      }

      return '${formatTime(start)} - ${formatTime(end)}';
    }

    // Parse existing days
    List<String> selectedDays = [];
    if (batch['daysOfWeek'] != null &&
        batch['daysOfWeek'].toString().isNotEmpty) {
      selectedDays = batch['daysOfWeek']
          .toString()
          .split(',')
          .map((e) => e.trim())
          .toList();
    }
    final weekDays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    // Existing tutor
    String? selectedTutor;
    final existingTutorId = batch['tutor']?['id'] ?? batch['tutor']?['_id'];
    if (existingTutorId != null &&
        _tutors.any((t) => t['id'] == existingTutorId)) {
      selectedTutor = existingTutorId;
    } else if (_tutors.isNotEmpty) {
      selectedTutor = _tutors[0]['id'];
    }

    // Existing mentors
    List<String> selectedMentors = [];
    if (batch['mentors'] != null) {
      for (var m in batch['mentors']) {
        selectedMentors.add((m['id'] ?? m['_id']).toString());
      }
    }

    String? selectedCategory;
    final existingCategoryId =
        batch['category']?['id'] ?? batch['category']?['_id'];
    if (existingCategoryId != null &&
        _categories.any((c) => c['id'] == existingCategoryId)) {
      selectedCategory = existingCategoryId;
    } else if (_categories.isNotEmpty) {
      selectedCategory = _categories[0]['id'];
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              title: Text(
                'Edit Batch Details',
                style: TextStyle(color: context.textColor),
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_categories.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          initialValue: selectedCategory,
                          dropdownColor: const Color(0xFF1E293B),
                          style: TextStyle(color: context.textColor),
                          decoration: InputDecoration(
                            labelText: 'Category',
                            labelStyle: TextStyle(color: context.textColor70),
                          ),
                          items: _categories.map<DropdownMenuItem<String>>((c) {
                            return DropdownMenuItem(
                              value: c['id'],
                              child: Text(c['name']),
                            );
                          }).toList(),
                          onChanged: (v) =>
                              setDialogState(() => selectedCategory = v),
                        ),
                        const SizedBox(height: 16),
                      ],
                      DropdownButtonFormField<String>(
                        initialValue: selectedTutor,
                        dropdownColor: const Color(0xFF1E293B),
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Lead Tutor',
                          labelStyle: TextStyle(color: context.textColor70),
                        ),
                        items: _tutors.map<DropdownMenuItem<String>>((t) {
                          return DropdownMenuItem(
                            value: t['id'],
                            child: Text(t['name']),
                          );
                        }).toList(),
                        onChanged: (v) =>
                            setDialogState(() => selectedTutor = v),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Select Mentors:',
                        style: TextStyle(
                          color: context.textColor70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ..._mentors.map((m) {
                        final isChecked = selectedMentors.contains(m['id']);
                        return CheckboxListTile(
                          title: Text(
                            m['name'],
                            style: TextStyle(color: context.textColor),
                          ),
                          activeColor: const Color(0xFF6366F1),
                          checkColor: Colors.white,
                          value: isChecked,
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                selectedMentors.add(m['id']);
                              } else {
                                selectedMentors.remove(m['id']);
                              }
                            });
                          },
                        );
                      }),
                      const SizedBox(height: 16),
                      Text(
                        'Select Days of Week:',
                        style: TextStyle(
                          color: context.textColor70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: weekDays.map((day) {
                          final isSelected = selectedDays.contains(day);
                          return FilterChip(
                            label: Text(day.substring(0, 3)),
                            selected: isSelected,
                            selectedColor: const Color(0xFF6366F1),
                            checkmarkColor: Colors.white,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : (context.isDark ? Colors.white70 : Colors.black87),
                            ),
                            backgroundColor: context.isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                            onSelected: (val) {
                              setDialogState(() {
                                if (val) {
                                  selectedDays.add(day);
                                } else {
                                  selectedDays.remove(day);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Start Date:',
                        style: TextStyle(
                          color: context.textColor70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              startDate == null
                                  ? 'No date selected'
                                  : startDate!.toLocal().toString().split(
                                      ' ',
                                    )[0],
                              style: TextStyle(color: context.textColor),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: startDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (d != null)
                                setDialogState(() => startDate = d);
                            },
                            child: const Text(
                              'Pick Date',
                              style: TextStyle(color: Color(0xFF818CF8)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Class Time Period:',
                        style: TextStyle(
                          color: context.textColor70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: context.isDark ? const Color(0xFF334155) : Colors.grey[200],
                              ),
                              icon: Icon(
                                Icons.access_time,
                                size: 16,
                                color: context.textColor,
                              ),
                              label: Text(
                                startTime != null
                                    ? startTime!.format(context)
                                    : 'Start Time',
                                style: TextStyle(color: context.textColor),
                              ),
                              onPressed: () async {
                                final t = await showTimePicker(
                                  context: context,
                                  initialTime: startTime ?? TimeOfDay.now(),
                                );
                                if (t != null)
                                  setDialogState(() => startTime = t);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: context.isDark ? const Color(0xFF334155) : Colors.grey[200],
                              ),
                              icon: Icon(
                                Icons.access_time,
                                size: 16,
                                color: context.textColor,
                              ),
                              label: Text(
                                endTime != null
                                    ? endTime!.format(context)
                                    : 'End Time',
                                style: TextStyle(color: context.textColor),
                              ),
                              onPressed: () async {
                                final t = await showTimePicker(
                                  context: context,
                                  initialTime: endTime ?? TimeOfDay.now(),
                                );
                                if (t != null)
                                  setDialogState(() => endTime = t);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: linkController,
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Class Link (URL)',
                          labelStyle: TextStyle(color: context.textColor70),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Required' : null,
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
                  onPressed: () {
                    if (formKey.currentState!.validate() &&
                        selectedDays.isNotEmpty &&
                        selectedTutor != null &&
                        selectedCategory != null &&
                        startTime != null &&
                        endTime != null &&
                        startDate != null) {
                      _editBatchDetails(
                        batch['id'],
                        selectedCategory!,
                        selectedTutor!,
                        selectedMentors,
                        selectedDays,
                        _formatTimePeriod(startTime!, endTime!),
                        linkController.text.trim(),
                        startDate!.toIso8601String(),
                      );
                      Navigator.pop(ctx);
                    } else if (selectedDays.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select at least one day.'),
                        ),
                      );
                    }
                  },
                  child: Text(
                    'Save',
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

  void _showAddStudentsDialog(Map<String, dynamic> batch) {
    if (_students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No students registered yet to enroll.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final allEnrolledStudentIds = <String>{};
    for (var b in _batches) {
      if (b['students'] != null) {
        for (var s in b['students']) {
          allEnrolledStudentIds.add((s['id'] ?? s['_id']).toString());
        }
      }
    }

    final enrollableStudents = _students
        .where(
          (s) =>
              !allEnrolledStudentIds.contains((s['id'] ?? s['_id']).toString()),
        )
        .toList();

    if (enrollableStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All registered students are already in this batch.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    List<String> studentsToEnroll = [];
    String searchQuery = '';
    final searchCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredStudents = enrollableStudents.where((s) {
              final name = (s['name'] ?? '').toString().toLowerCase();
              return name.contains(searchQuery.toLowerCase());
            }).toList();

            return AlertDialog(
              backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              title: Text(
                'Enroll in ${batch['name']}',
                style: TextStyle(color: context.textColor),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchCtrl,
                      style: TextStyle(color: context.textColor),
                      decoration: InputDecoration(
                        labelText: 'Search Students',
                        labelStyle: TextStyle(color: context.textColor70),
                        prefixIcon: Icon(Icons.search, color: context.textColor70),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: context.glassBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF6366F1)),
                        ),
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          searchQuery = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredStudents.length,
                        itemBuilder: (c, i) {
                          final s = filteredStudents[i];
                          final isChecked = studentsToEnroll.contains(s['id']);
                          return CheckboxListTile(
                            title: Text(
                              s['name'],
                              style: TextStyle(color: context.textColor),
                            ),
                            subtitle: Text(
                              s['email'],
                              style: TextStyle(color: context.textColor60),
                            ),
                            activeColor: const Color(0xFF6366F1),
                            value: isChecked,
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == true) {
                                  studentsToEnroll.add(s['id']);
                                } else {
                                  studentsToEnroll.remove(s['id']);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
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
                  onPressed: () {
                    if (studentsToEnroll.isNotEmpty) {
                      _addStudentsToBatch(batch['id'], studentsToEnroll);
                      Navigator.pop(ctx);
                    }
                  },
                  child: Text(
                    'Add',
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

  void _showBatchDetails(Map<String, dynamic> batch) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final enrolledStudents = batch['students'] as List;

        return Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                batch['name'],
                style: TextStyle(color: context.textColor, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              if (batch['category'] != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    '${batch['category']['name']} (Max: ${batch['category']['maxMembers']} | Fees: ${batch['category']['fees']})',
                    style: const TextStyle(
                      color: Color(0xFF8B5CF6),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Course: ${batch['course']['name']}',
                style: const TextStyle(
                  color: Color(0xFF818CF8),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Divider(color: context.glassBorder, height: 24),
              Text(
                'Schedule: ${batch['daysOfWeek']} | ${batch['timePeriod']}',
                style: TextStyle(color: context.textColor70),
              ),
              const SizedBox(height: 8),
              Text(
                'Lead Tutor: ${batch['tutor']['name']} (${batch['tutor']['email']})',
                style: TextStyle(color: context.textColor70),
              ),
              if (batch['mentors'] != null &&
                  (batch['mentors'] as List).isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Mentors: ${(batch['mentors'] as List).map((m) => m['name'] ?? '').join(', ')}',
                  style: TextStyle(color: context.textColor70),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Enrolled Students (${enrolledStudents.length})',
                    style: TextStyle(color: context.textColor, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showAddStudentsDialog(batch);
                    },
                    icon: const Icon(
                      Icons.person_add_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Add Student',
                      style: TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: enrolledStudents.isEmpty
                    ? Center(
                        child: Text(
                          'No students enrolled yet',
                          style: TextStyle(color: context.textColor60),
                        ),
                      )
                    : ListView.builder(
                        itemCount: enrolledStudents.length,
                        itemBuilder: (c, idx) {
                          final st = enrolledStudents[idx];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: context.isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                              child: Icon(
                                Icons.person_rounded,
                                color: context.textColor,
                              ),
                            ),
                            title: Text(
                              st['name'],
                              style: TextStyle(
                                color: context.textColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              st['email'],
                              style: TextStyle(color: context.textColor60),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Change Batch',
                                  icon: const Icon(
                                    Icons.swap_horiz_rounded,
                                    color: Color(0xFF6366F1),
                                  ),
                                  onPressed: () {
                                    _showChangeBatchDialog(batch, st);
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Remove from Batch',
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () {
                                    _removeStudentFromBatch(
                                      batch['id'] ?? batch['_id'],
                                      st['id'] ?? st['_id'],
                                    );
                                    Navigator.pop(ctx);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BatchBloc, BatchState>(
      listener: (context, state) {
        if (state is BatchLoaded) {
          setState(() {
            _batches = state.batches;
          });
        } else if (state is BatchOperationSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.green,
            ),
          );
          _triggerRefresh();
        } else if (state is BatchOperationFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      },
      builder: (context, state) {
        bool isBlocLoading = state is BatchLoading || state is BatchInitial;
        List<dynamic> batches = [];
        if (state is BatchLoaded) {
          batches = state.batches;
          _batches = state.batches;
        }

        if (_isLoading || isBlocLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF6366F1)),
          );
        }

        final filteredBatches = _searchQuery.isEmpty
            ? batches
            : batches.where((b) {
                final name = (b['name'] ?? '').toString().toLowerCase();
                final course = (b['course']?['name'] ?? '')
                    .toString()
                    .toLowerCase();
                final category = (b['category']?['name'] ?? '')
                    .toString()
                    .toLowerCase();
                final tutor = (b['tutor']?['name'] ?? '')
                    .toString()
                    .toLowerCase();

                bool mentorMatch = false;
                if (b['mentors'] != null) {
                  for (var m in b['mentors']) {
                    if ((m['name'] ?? '').toString().toLowerCase().contains(
                      _searchQuery,
                    )) {
                      mentorMatch = true;
                      break;
                    }
                  }
                }

                return name.contains(_searchQuery) ||
                    course.contains(_searchQuery) ||
                    category.contains(_searchQuery) ||
                    tutor.contains(_searchQuery) ||
                    mentorMatch;
              }).toList();

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: batches.isEmpty
              ? Center(
                  child: Text(
                    'No batches created yet',
                    style: TextStyle(color: context.textColor70),
                  ),
                )
              : filteredBatches.isEmpty
              ? Center(
                  child: Text(
                    'No matching batches found',
                    style: TextStyle(color: context.textColor70),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.only(
                    top: 24,
                    left: 16,
                    right: 16,
                    bottom: 100,
                  ),
                  itemCount: filteredBatches.length,
                  itemBuilder: (ctx, idx) {
                    final batch = filteredBatches[idx];
                    final animationDelay = (idx % 10) * 50;

                    return Container(
                          margin: EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: context.glassBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(
                                0xFF10B981,
                              ).withValues(alpha: 0.3),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF10B981,
                                ).withValues(alpha: 0.05),
                                blurRadius: 10,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: ListTile(
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                onTap: () => _showBatchDetails(batch),
                                onLongPress: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          AdminBatchDetailScreen(batch: batch),
                                    ),
                                  );
                                },
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        batch['name'],
                                        style: TextStyle(
                                          color: context.textColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (batch['category'] != null)
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF6366F1,
                                          ).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: const Color(
                                              0xFF6366F1,
                                            ).withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: Text(
                                          batch['category']['name'] ??
                                              'Category',
                                          style: const TextStyle(
                                            color: Color(0xFF8B5CF6),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: EdgeInsets.only(top: 8.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Course: ${batch['course']['name']}',
                                        style: const TextStyle(
                                          color: Color(0xFF10B981),
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Days: ${batch['daysOfWeek']}',
                                        style: TextStyle(color: context.textColor70,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        'Time: ${batch['timePeriod']}',
                                        style: TextStyle(color: context.textColor70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                isThreeLine: true,
                                trailing: PopupMenuButton<String>(
                                  icon: Icon(
                                    Icons.more_vert,
                                    color: context.textColor70,
                                  ),
                                  color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: context.glassBorder,
                                    ),
                                  ),
                                  elevation: 8,
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _showEditBatchDetailsDialog(batch);
                                    } else if (value == 'add') {
                                      _showAddStudentsDialog(batch);
                                    } else if (value == 'delete') {
                                      _confirmDelete(
                                        context,
                                        batch['name'],
                                        () => _deleteBatch(batch['id']),
                                      );
                                    }
                                  },
                                  itemBuilder: (BuildContext context) =>
                                      <PopupMenuEntry<String>>[
                                        const PopupMenuItem<String>(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.edit,
                                                color: Colors.blueAccent,
                                                size: 20,
                                              ),
                                              SizedBox(width: 12),
                                              Text(
                                                'Edit Details',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem<String>(
                                          value: 'add',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.person_add_rounded,
                                                color: Color(0xFF818CF8),
                                                size: 20,
                                              ),
                                              SizedBox(width: 12),
                                              Text(
                                                'Add Students',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem<String>(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.delete_outline_rounded,
                                                color: Colors.redAccent,
                                                size: 20,
                                              ),
                                              SizedBox(width: 12),
                                              Text(
                                                'Delete Batch',
                                                style: TextStyle(
                                                  color: Colors.redAccent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                ),
                              ),
                            ),
                          ),
                        )
                        .animate()
                        .fade(duration: 400.ms, delay: animationDelay.ms)
                        .slideX(begin: 0.1, end: 0);
                  },
                ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
          floatingActionButton: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FloatingActionButton(
                  heroTag: 'categories_btn',
                  backgroundColor: const Color(0xFF8B5CF6),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BlocProvider.value(
                          value: context.read<BatchCategoryBloc>(),
                          child: const BatchCategoriesTab(),
                        ),
                      ),
                    ).then((_) => _fetchData()); // Refresh categories on back
                  },
                  child: const Icon(
                    Icons.category_rounded,
                    color: Colors.white,
                  ),
                ).animate().scale(delay: 500.ms),
                const SizedBox(width: 12),
                Expanded(
                  child:
                      BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 12,
                          sigmaY: 12,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          child: TextField(
                            controller: _searchController,
                            style: TextStyle(
                              color: context.textColor,
                              fontSize: 15,
                              letterSpacing: 1.0,
                              fontWeight: FontWeight.w500,
                            ),
                            cursorColor: const Color(0xFF8B5CF6),
                            textAlignVertical: TextAlignVertical.center,
                            decoration: InputDecoration(
                              hintText: 'Type to search...',
                              hintStyle: TextStyle(
                                color: context.textColor54,
                                fontSize: 14,
                                letterSpacing: 1.0,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 18,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: context.isDark ? const Color(0xFF8B5CF6) : Colors.grey[600],
                                size: 20,
                              ),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.clear_rounded,
                                        color: context.isDark ? Colors.white60 : Colors.grey[600],
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {
                                          _searchQuery = '';
                                        });
                                      },
                                    )
                                  : null,
                            ),
                            onChanged: (val) {
                              setState(() {
                                _searchQuery = val.toLowerCase();
                              });
                            },
                          ),
                        ),
                      )
                          .animate()
                          .fade(duration: 600.ms, delay: 500.ms)
                          .slideY(begin: 0.2, end: 0)
                          .shimmer(duration: 2000.ms, color: context.glassBorder),
                ),
                const SizedBox(width: 12),
                FloatingActionButton(
                  heroTag: 'add_batch_btn',
                  backgroundColor: const Color(0xFF6366F1),
                  onPressed: _showAddBatchDialog,
                  child: const Icon(Icons.add_rounded, color: Colors.white),
                ).animate().scale(delay: 500.ms),
              ],
            ),
          ),
        );
      },
    );
  }
}
