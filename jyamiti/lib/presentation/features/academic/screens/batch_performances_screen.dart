import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import '../../../../services/api_service.dart';

class BatchPerformancesScreen extends StatefulWidget {
  final Map<String, dynamic> batch;
  const BatchPerformancesScreen({super.key, required this.batch});

  @override
  State<BatchPerformancesScreen> createState() => _BatchPerformancesScreenState();
}

class _BatchPerformancesScreenState extends State<BatchPerformancesScreen> {
  bool _isLoading = true;
  List<dynamic> _students = [];
  List<dynamic> _assignments = [];
  List<Map<String, String>> _uniqueTasks = [];
  
  // Filter states
  String _searchQuery = '';
  String _selectedContentType = 'All'; // All, video, slide, practice_question

  @override
  void initState() {
    super.initState();
    _fetchPerformances();
  }

  Future<void> _fetchPerformances() async {
    setState(() => _isLoading = true);
    try {
      final batchId = widget.batch['_id'] ?? widget.batch['id'] ?? '';
      final res = await ApiService.getBatchPerformances(batchId);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawStudents = data['students'] as List? ?? [];
        final rawAssignments = data['assignments'] as List? ?? [];

        // Identify all unique tasks assigned in this batch
        final tasks = <Map<String, String>>[];
        final seenKeys = <String>{};

        for (var a in rawAssignments) {
          final title = a['itemTitle'] ?? '';
          final type = a['itemType'] ?? '';
          final key = '$title|$type';
          if (!seenKeys.contains(key)) {
            seenKeys.add(key);
            tasks.add({'title': title, 'type': type});
          }
        }

        setState(() {
          _students = rawStudents;
          _assignments = rawAssignments;
          _uniqueTasks = tasks;
        });
      }
    } catch (e) {
      debugPrint('Error fetching performances: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<dynamic> get _filteredStudents {
    if (_searchQuery.isEmpty) return _students;
    return _students.where((s) {
      final name = (s['name'] ?? '').toString().toLowerCase();
      final email = (s['email'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase()) || email.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  List<Map<String, String>> get _filteredTasks {
    if (_selectedContentType == 'All') return _uniqueTasks;
    return _uniqueTasks.where((t) => t['type'] == _selectedContentType).toList();
  }

  void _exportCSV() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📊 Exporting CSV format... (Feature mock)'),
        backgroundColor: Colors.indigo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          '${widget.batch['name'] ?? 'Batch'} Performances',
          style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: context.textColor),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchPerformances,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)))
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dashboard Title
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Assignment scores',
                            style: TextStyle(
                              color: context.textColor,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Track student progress and completion of assigned tasks.',
                            style: TextStyle(color: context.textColor60, fontSize: 13),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: const Color(0xFF6366F1),
                          side: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onPressed: _exportCSV,
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('Download CSV', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Filter Row
                  Row(
                    children: [
                      // Search Bar
                      Expanded(
                        flex: 2,
                        child: TextField(
                          onChanged: (val) => setState(() => _searchQuery = val),
                          style: TextStyle(color: context.textColor),
                          decoration: InputDecoration(
                            hintText: 'Search students...',
                            hintStyle: TextStyle(color: context.textColor60),
                            prefixIcon: Icon(Icons.search_rounded, color: context.textColor60, size: 20),
                            filled: true,
                            fillColor: cardColor,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: context.glassBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Dropdown filter content types
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedContentType,
                          dropdownColor: cardColor,
                          style: TextStyle(color: context.textColor),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: cardColor,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: context.glassBorder),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'All', child: Text('All content types')),
                            DropdownMenuItem(value: 'video', child: Text('Videos')),
                            DropdownMenuItem(value: 'slide', child: Text('Slides')),
                            DropdownMenuItem(value: 'practice_question', child: Text('Practice / Quizzes')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedContentType = val);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Performance Matrix Table
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: context.glassBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          )
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: _filteredStudents.isEmpty
                            ? Center(
                                child: Text(
                                  'No students found.',
                                  style: TextStyle(color: context.textColor60),
                                ),
                              )
                            : SingleChildScrollView(
                                scrollDirection: Axis.vertical,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columnSpacing: 28,
                                    headingRowColor: WidgetStateProperty.all(
                                      isDark ? Colors.white.withOpacity(0.02) : const Color(0xFFF1F5F9),
                                    ),
                                    border: TableBorder(
                                      horizontalInside: BorderSide(color: context.glassBorder, width: 0.5),
                                      verticalInside: BorderSide(color: context.glassBorder, width: 0.5),
                                    ),
                                    columns: [
                                      DataColumn(
                                        label: Text(
                                          'STUDENTS',
                                          style: TextStyle(
                                            color: context.textColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      ..._filteredTasks.map((t) {
                                        IconData typeIcon = Icons.assignment;
                                        Color typeColor = Colors.grey;
                                        if (t['type'] == 'video') {
                                          typeIcon = Icons.play_circle_fill_rounded;
                                          typeColor = Colors.redAccent;
                                        } else if (t['type'] == 'slide') {
                                          typeIcon = Icons.slideshow_rounded;
                                          typeColor = const Color(0xFFEC4899);
                                        } else if (t['type'] == 'practice_question') {
                                          typeIcon = Icons.assignment_turned_in_rounded;
                                          typeColor = const Color(0xFF10B981);
                                        }

                                        return DataColumn(
                                          label: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Icon(typeIcon, color: typeColor, size: 16),
                                              const SizedBox(height: 4),
                                              Container(
                                                constraints: const BoxConstraints(maxWidth: 130),
                                                child: Text(
                                                  t['title'] ?? '',
                                                  style: TextStyle(
                                                    color: context.textColor70,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 11,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                    ],
                                    rows: _filteredStudents.map((student) {
                                      return DataRow(
                                        cells: [
                                          // Student Name Cell
                                          DataCell(
                                            Text(
                                              student['name'] ?? 'Unknown Student',
                                              style: TextStyle(
                                                color: context.textColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          // Performance Matrix Cells
                                          ..._filteredTasks.map((task) {
                                            // Find student assignment matching task title & type safely
                                            final matchingAss = _assignments.firstWhere(
                                              (a) {
                                                final assStudent = a['student'];
                                                final assStudentId = assStudent is Map ? assStudent['_id'] : assStudent;
                                                final targetStudentId = student is Map ? student['_id'] : student;
                                                return assStudentId == targetStudentId &&
                                                    a['itemTitle'] == task['title'] &&
                                                    a['itemType'] == task['type'];
                                              },
                                              orElse: () => null,
                                            );

                                            if (matchingAss == null) {
                                              // Not assigned to this student
                                              return DataCell(
                                                Center(
                                                  child: Text(
                                                    '-',
                                                    style: TextStyle(color: context.textColor),
                                                  ),
                                                ),
                                              );
                                            }

                                            final isCompleted = matchingAss['status'] == 'completed';

                                            if (!isCompleted) {
                                              // Incomplete: Black box with light red color
                                              return DataCell(
                                                Center(
                                                  child: Container(
                                                    width: 32,
                                                    height: 32,
                                                    decoration: BoxDecoration(
                                                      color: Colors.black87,
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(
                                                        color: Colors.redAccent.withOpacity(0.6),
                                                        width: 1,
                                                      ),
                                                    ),
                                                    child: const Center(
                                                      child: Icon(
                                                        Icons.remove_rounded,
                                                        size: 14,
                                                        color: Colors.redAccent,
                                                      ),
                                                    ),
                                                  ).animate().fade(duration: 300.ms),
                                                ),
                                              );
                                            }

                                            // Completed: Type-specific representation
                                            Widget cellWidget;
                                            if (task['type'] == 'video') {
                                              // Video tick
                                              cellWidget = Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: Colors.blue.withOpacity(0.5)),
                                                ),
                                                child: const Icon(
                                                  Icons.check_rounded,
                                                  color: Colors.blue,
                                                  size: 16,
                                                ),
                                              );
                                            } else if (task['type'] == 'slide') {
                                              // Slide progress square
                                              cellWidget = Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  color: Colors.pink.withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: Colors.pink.withOpacity(0.5)),
                                                ),
                                                child: const Icon(
                                                  Icons.slideshow_rounded,
                                                  color: Colors.pink,
                                                  size: 16,
                                                ),
                                              );
                                            } else {
                                              // Quiz/Practice Question: Score percentage
                                              final score = matchingAss['score'];
                                              final total = matchingAss['totalQuestions'];
                                              
                                              int percentage = 100;
                                              if (score != null && total != null && total > 0) {
                                                percentage = ((score / total) * 100).round();
                                              }

                                              final color = percentage >= 80 ? Colors.green : Colors.orange;

                                              cellWidget = Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: color.withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: color.withOpacity(0.5)),
                                                ),
                                                child: Text(
                                                  '$percentage',
                                                  style: TextStyle(
                                                    color: color,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              );
                                            }

                                            return DataCell(
                                              Center(child: cellWidget),
                                            );
                                          }),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
