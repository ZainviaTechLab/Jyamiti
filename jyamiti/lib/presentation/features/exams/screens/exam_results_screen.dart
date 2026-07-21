import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../providers/theme_provider.dart';
import '../../../../services/api_service.dart';

class ExamResultsScreen extends StatefulWidget {
  final Map<String, dynamic> exam;
  const ExamResultsScreen({super.key, required this.exam});

  @override
  State<ExamResultsScreen> createState() => _ExamResultsScreenState();
}

class _ExamResultsScreenState extends State<ExamResultsScreen> {
  List<dynamic> _submissions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchSubmissions();
  }

  Future<void> _fetchSubmissions() async {
    try {
      final res = await ApiService.get('/exams/${widget.exam['_id'] ?? widget.exam['id']}/submissions');
      if (res.statusCode == 200) {
        setState(() {
          _submissions = jsonDecode(res.body);
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _showGradeDialog(Map<String, dynamic> submission) {
    final answers = submission['answers'] as List<dynamic>;
    final shortAnswers = answers.where((a) => a['textAnswer'] != null && a['textAnswer'] != '').toList();
    
    if (shortAnswers.isEmpty && submission['status'] == 'GRADED') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This submission is fully auto-graded.')));
      return;
    }

    final Map<String, TextEditingController> gradeCtrls = {};
    for (var a in answers) {
      if (a['textAnswer'] != null) {
        gradeCtrls[a['questionId']] = TextEditingController(text: a['marksObtained']?.toString() ?? '0');
      }
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Text('Grade: ${submission['student']['name']}', style: TextStyle(color: context.textColor)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Auto-Graded Score: ${submission['totalScore']}', style: const TextStyle(color: Colors.greenAccent)),
                const SizedBox(height: 16),
                if (shortAnswers.isEmpty)
                  Text('No short answers to grade.', style: TextStyle(color: context.textColor70))
                else
                  ...shortAnswers.map((a) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                           Text('Answer:', style: TextStyle(color: context.textColor54)),
                          Text(a['textAnswer'], style: TextStyle(color: context.textColor)),
                           SizedBox(height: 8),
                          Row(
                            children: [
                               Text('Marks:', style: TextStyle(color: context.textColor70)),
                              SizedBox(width: 8),
                              SizedBox(
                                width: 60,
                                child: TextField(
                                  controller: gradeCtrls[a['questionId']],
                                  keyboardType: TextInputType.number,
                                  style: TextStyle(color: context.textColor),
                                ),
                              )
                            ],
                          )
                        ],
                      ),
                    );
                  })
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: context.textColor60))),
            if (shortAnswers.isNotEmpty)
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                onPressed: () async {
                  Map<String, num> grades = {};
                  for (var k in gradeCtrls.keys) {
                    grades[k] = num.tryParse(gradeCtrls[k]!.text) ?? 0;
                  }
                  
                  final res = await ApiService.put('/exams/${widget.exam['_id'] ?? widget.exam['id']}/grade/${submission['_id']}', {
                    'grades': grades
                  });
                  if (res.statusCode == 200) {
                    Navigator.pop(ctx);
                    _fetchSubmissions();
                  }
                },
                child: Text('Save Grades', style: TextStyle(color: context.textColor)),
              )
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text('Results: ${widget.exam['title']}', style: TextStyle(color: context.textColor)),
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        iconTheme: IconThemeData(color: context.textColor),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
        : _submissions.isEmpty
          ? Center(child: Text('No submissions yet', style: TextStyle(color: context.textColor70)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _submissions.length,
              itemBuilder: (ctx, i) {
                final s = _submissions[i];
                final isGraded = s['status'] == 'GRADED';
                return Card(
                  color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(s['student']['name'], style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold)),
                    subtitle: Text(isGraded ? 'Score: ${s['totalScore']}' : 'Pending Review', style: TextStyle(color: isGraded ? Colors.greenAccent : Colors.orangeAccent)),
                    trailing: Icon(Icons.grading, color: context.textColor70),
                    onTap: () => _showGradeDialog(s),
                  ),
                );
              },
            ),
    );
  }
}
