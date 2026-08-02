import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../providers/theme_provider.dart';
import '../../../../services/api_service.dart';

class TutorManageAssignmentsScreen extends StatefulWidget {
  final bool isInline;
  const TutorManageAssignmentsScreen({super.key, this.isInline = false});

  @override
  State<TutorManageAssignmentsScreen> createState() => _TutorManageAssignmentsScreenState();
}

class _TutorManageAssignmentsScreenState extends State<TutorManageAssignmentsScreen> {
  bool _isLoading = true;
  List<dynamic> _assignments = [];

  @override
  void initState() {
    super.initState();
    _fetchAssignments();
  }

  Future<void> _fetchAssignments() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.getTutorAssignments();
      if (res.statusCode == 200) {
        if (mounted) {
          setState(() {
            _assignments = jsonDecode(res.body);
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load assignments')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateDueDate(Map<String, dynamic> assignment) async {
    final currentDueDate = DateTime.parse(assignment['dueDate']);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: currentDueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: context.isDark ? ThemeData.dark() : ThemeData.light(),
          child: child!,
        );
      },
    );

    if (picked != null && picked != currentDueDate) {
      try {
        final res = await ApiService.updateAssignmentDueDate(
          assignment['_id'],
          picked.toIso8601String(),
        );
        if (res.statusCode == 200) {
          _fetchAssignments();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Due date updated successfully'), backgroundColor: Colors.green),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to update due date'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _deleteAssignment(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text('Delete Assignment', style: TextStyle(color: context.textColor)),
        content: Text('Are you sure you want to delete this assignment? It will be removed from all assigned students.', style: TextStyle(color: context.textColor70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: context.textColor60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final res = await ApiService.deleteAssignment(id);
        if (res.statusCode == 200) {
          _fetchAssignments();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Assignment deleted successfully'), backgroundColor: Colors.green),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to delete assignment'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Widget _buildAssignmentCard(Map<String, dynamic> assignment) {
    final dueDate = DateTime.parse(assignment['dueDate']);
    final isOverdue = dueDate.isBefore(DateTime.now()) && assignment['status'] != 'completed';
    
    IconData typeIcon = Icons.assignment;
    Color typeColor = const Color(0xFF6366F1);
    
    if (assignment['itemType'] == 'video') {
      typeIcon = Icons.play_circle_fill_rounded;
      typeColor = Colors.redAccent;
    } else if (assignment['itemType'] == 'slide') {
      typeIcon = Icons.slideshow_rounded;
      typeColor = const Color(0xFFEC4899);
    } else if (assignment['itemType'] == 'practice_question') {
      typeIcon = Icons.assignment_turned_in_rounded;
      typeColor = const Color(0xFF10B981);
    }

    final studentInfo = assignment['student'] != null 
        ? 'Assigned to: ${assignment['student']['name']}'
        : 'Assigned to: Whole Batch (${assignment['batch']['name']})';

    return Card(
      color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isOverdue ? Colors.redAccent.withOpacity(0.5) : context.glassBorder,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(typeIcon, color: typeColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        assignment['itemTitle'] ?? 'Resource Assignment',
                        style: TextStyle(
                          color: context.textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        studentInfo,
                        style: TextStyle(color: context.textColor70, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.calendar_today_rounded, size: 14, color: isOverdue ? Colors.redAccent : context.textColor60),
                          const SizedBox(width: 4),
                          Text(
                            'Due: ${DateFormat('MMM dd, yyyy').format(dueDate)}',
                            style: TextStyle(
                              color: isOverdue ? Colors.redAccent : context.textColor60,
                              fontSize: 13,
                              fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (assignment['status'] == 'completed')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Completed', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _updateDueDate(assignment),
                  icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                  label: const Text('Edit Date'),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF6366F1)),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _deleteAssignment(assignment['_id']),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content = _isLoading
        ? const Center(child: JyamitiLoader(color: Color(0xFF6366F1)))
        : _assignments.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.assignment_turned_in, size: 64, color: context.textColor),
                    const SizedBox(height: 16),
                    Text(
                      'No assignments managed by you.',
                      style: TextStyle(color: context.textColor60, fontSize: 16),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: _assignments.length,
                itemBuilder: (context, index) {
                  return _buildAssignmentCard(_assignments[index]);
                },
              );

    if (widget.isInline) {
      return content;
    }

    return Scaffold(
      backgroundColor: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('Manage Assignments'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: context.textColor),
        titleTextStyle: TextStyle(
          color: context.textColor,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: content,
    );
  }
}
