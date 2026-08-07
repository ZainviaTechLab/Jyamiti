import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../providers/theme_provider.dart';
import '../../../../services/api_service.dart';
import 'question_form_screen.dart';
import 'bulk_question_upload_screen.dart';

class QuestionBankScreen extends StatefulWidget {
  final bool isInline;
  final VoidCallback? onBack;

  const QuestionBankScreen({super.key, this.isInline = false, this.onBack});

  @override
  State<QuestionBankScreen> createState() => _QuestionBankScreenState();
}

class _QuestionBankScreenState extends State<QuestionBankScreen> {
  List<dynamic> _courses = [];
  String? _selectedCourseId;
  String? _selectedChapterFilter;
  String? _selectedTopicFilter;
  String? _selectedSubTopicFilter;
  List<dynamic> _questions = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchCourses();
  }

  Future<void> _fetchCourses() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.get('/courses');
      if (res.statusCode == 200) {
        setState(() {
          _courses = jsonDecode(res.body);
          if (_courses.isNotEmpty) {
            _selectedCourseId = _courses[0]['id'] ?? _courses[0]['_id'];
            _fetchQuestions();
          } else {
            _isLoading = false;
          }
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchQuestions() async {
    if (_selectedCourseId == null) return;
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.get('/questions/course/$_selectedCourseId');
      if (res.statusCode == 200) {
        setState(() {
          _questions = jsonDecode(res.body);
        });
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _navigateToQuestionForm({Map<String, dynamic>? existingQuestion}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionFormScreen(
          courses: _courses,
          initialCourseId: _selectedCourseId,
          existingQuestion: existingQuestion,
        ),
      ),
    );

    if (result == true) {
      _fetchQuestions();
    }
  }


  Future<void> _deleteQuestion(String id) async {
    final res = await ApiService.delete('/questions/$id');
    if (res.statusCode == 200) {
      _fetchQuestions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text('Question Bank', style: TextStyle(color: context.textColor)),
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        iconTheme: IconThemeData(color: context.textColor),
        leading: widget.isInline
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        actions: [
          if (_selectedCourseId != null)
            IconButton(
              icon: Icon(Icons.file_upload, color: context.textColor),
              tooltip: 'Bulk Upload',
              onPressed: () async {
                final selectedCourse = _courses.firstWhere((c) => (c['id'] ?? c['_id']) == _selectedCourseId, orElse: () => null);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => BulkQuestionUploadScreen(
                    courseId: _selectedCourseId!,
                    course: selectedCourse,
                  )),
                );
                if (result == true) {
                  _fetchQuestions();
                }
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (_courses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<String>(
                value: _selectedCourseId,
                dropdownColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                style: TextStyle(color: context.textColor),
                decoration: InputDecoration(
                  labelText: 'Select Course', 
                  labelStyle: TextStyle(color: context.textColor70),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: context.textColor54.withOpacity(0.4))),
                ),
                items: _courses.map((c) => DropdownMenuItem<String>(
                  value: c['id'] ?? c['_id'],
                  child: Text(c['name']),
                )).toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedCourseId = v;
                    _selectedChapterFilter = null;
                    _selectedTopicFilter = null;
                    _selectedSubTopicFilter = null;
                  });
                  _fetchQuestions();
                },
              ),
            ),
          if (_selectedCourseId != null) ...[
            Builder(
              builder: (ctx) {
                final selectedCourse = _courses.firstWhere((c) => (c['id'] ?? c['_id']) == _selectedCourseId, orElse: () => null);
                final List<dynamic> syllabus = selectedCourse?['syllabus'] ?? [];
                
                return Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedChapterFilter,
                          dropdownColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                          style: TextStyle(color: context.textColor),
                          decoration: InputDecoration(
                            labelText: 'Filter by Chapter',
                            labelStyle: TextStyle(color: context.textColor70),
                            isDense: true,
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: context.textColor54.withOpacity(0.4))),
                          ),
                          items: [
                            const DropdownMenuItem<String>(value: null, child: Text('All Chapters')),
                            ...syllabus.map((ch) => DropdownMenuItem<String>(
                              value: ch['title'],
                              child: Text(ch['title']),
                            ))
                          ],
                          onChanged: (v) {
                            setState(() {
                              _selectedChapterFilter = v;
                              _selectedTopicFilter = null; // Reset topic when chapter changes
                              _selectedSubTopicFilter = null;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Builder(
                          builder: (ctx) {
                            final chapter = syllabus.firstWhere((ch) => ch['title'] == _selectedChapterFilter, orElse: () => null);
                            final List<dynamic> topics = chapter?['topics'] ?? [];
                            return DropdownButtonFormField<String>(
                              value: _selectedTopicFilter,
                              dropdownColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                              style: TextStyle(color: context.textColor),
                              decoration: InputDecoration(
                                labelText: 'Filter by Topic',
                                labelStyle: TextStyle(color: context.textColor70),
                                isDense: true,
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: context.textColor54.withOpacity(0.4))),
                              ),
                              items: [
                                const DropdownMenuItem<String>(value: null, child: Text('All Topics')),
                                if (_selectedChapterFilter != null)
                                  ...topics.map((t) => DropdownMenuItem<String>(
                                    value: t['title'],
                                    child: Text(t['title']),
                                  ))
                              ],
                              onChanged: _selectedChapterFilter == null ? null : (v) {
                                setState(() {
                                  _selectedTopicFilter = v;
                                  _selectedSubTopicFilter = null;
                                });
                              },
                            );
                          }
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Builder(
                          builder: (ctx) {
                            final chapter = syllabus.firstWhere((ch) => ch['title'] == _selectedChapterFilter, orElse: () => null);
                            final List<dynamic> topics = chapter?['topics'] ?? [];
                            final topic = topics.firstWhere((t) => t['title'] == _selectedTopicFilter, orElse: () => null);
                            final List<dynamic> subTopics = (topic?['subTopics'] as List?) ?? [];
                            return DropdownButtonFormField<String>(
                              value: _selectedSubTopicFilter,
                              dropdownColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                              style: TextStyle(color: context.textColor),
                              decoration: InputDecoration(
                                labelText: 'Filter by Subtopic',
                                labelStyle: TextStyle(color: context.textColor70),
                                isDense: true,
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: context.textColor54.withOpacity(0.4))),
                              ),
                              items: [
                                const DropdownMenuItem<String>(value: null, child: Text('All Subtopics')),
                                if (_selectedTopicFilter != null)
                                  ...subTopics.map((s) => DropdownMenuItem<String>(
                                    value: s['title'],
                                    child: Text(s['title']),
                                  ))
                              ],
                              onChanged: _selectedTopicFilter == null ? null : (v) {
                                setState(() {
                                  _selectedSubTopicFilter = v;
                                });
                              },
                            );
                          }
                        ),
                      ),
                    ],
                  ),
                );
              }
            )
          ],
          Expanded(
            child: _isLoading 
              ? const Center(child: JyamitiLoader(color: Color(0xFF6366F1)))
              : Builder(builder: (context) {
                  final filteredQuestions = _questions.where((q) {
                    if (_selectedChapterFilter != null && q['chapter'] != _selectedChapterFilter) return false;
                    if (_selectedTopicFilter != null && q['topic'] != _selectedTopicFilter) return false;
                    if (_selectedSubTopicFilter != null && q['subtopic'] != _selectedSubTopicFilter) return false;
                    return true;
                  }).toList();
                  
                  if (filteredQuestions.isEmpty) {
                    return Center(child: Text('No questions match the filters.', style: TextStyle(color: context.textColor70)));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredQuestions.length,
                    itemBuilder: (ctx, i) {
                      final q = filteredQuestions[i];
                    return Card(
                      color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                      child: ListTile(
                        title: Text(q['text'], style: TextStyle(color: context.textColor)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${q['type']} • ${q['marks']} marks', style: TextStyle(color: context.textColor60)),
                            if (q['chapter'] != null && q['chapter'].toString().isNotEmpty)
                              Text(
                                'Chapter: ${q['chapter']}'
                                '${q['topic'] != null && q['topic'].toString().isNotEmpty ? ' • Topic: ${q['topic']}' : ''}'
                                '${q['subtopic'] != null && q['subtopic'].toString().isNotEmpty ? ' • Subtopic: ${q['subtopic']}' : ''}',
                                style: const TextStyle(color: Color(0xFF8B5CF6), fontSize: 12),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit, color: context.textColor70),
                              onPressed: () => _navigateToQuestionForm(existingQuestion: q),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.redAccent),
                              onPressed: () => _deleteQuestion(q['_id']),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }),
          )
        ],
      ),
      floatingActionButton: _selectedCourseId != null ? FloatingActionButton(
        onPressed: _navigateToQuestionForm,
        backgroundColor: const Color(0xFF6366F1),
        child: Icon(Icons.add, color: context.textColor),
      ) : null,
    );
  }
}
