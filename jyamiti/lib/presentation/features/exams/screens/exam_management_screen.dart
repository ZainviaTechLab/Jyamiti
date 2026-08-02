import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../providers/theme_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/api_service.dart';
import '../../exams/screens/exam_taking_screen.dart';
import '../../exams/screens/exam_results_screen.dart';

class ExamManagementScreen extends StatefulWidget {
  final Map<String, dynamic> batch;
  final bool isInline;
  final VoidCallback? onBack;
  const ExamManagementScreen({super.key, required this.batch, this.isInline = false, this.onBack});

  @override
  State<ExamManagementScreen> createState() => _ExamManagementScreenState();
}

class _ExamManagementScreenState extends State<ExamManagementScreen> {
  List<dynamic> _exams = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchExams();
  }

  Future<void> _fetchExams() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.get('/exams/batch/${widget.batch['_id'] ?? widget.batch['id']}');
      if (res.statusCode == 200) {
        setState(() {
          _exams = jsonDecode(res.body);
        });
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showCreateExamDialog() async {
    final courseId = widget.batch['course']['_id'] ?? widget.batch['course'];
    
    showDialog(context: context, builder: (_) => const Center(child: JyamitiLoader()));
    final qRes = await ApiService.get('/questions/course/$courseId');
    Navigator.pop(context);

    if (qRes.statusCode != 200) return;
    final List<dynamic> questions = jsonDecode(qRes.body);
    final List<String> selectedQuestionIds = [];

    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final durationCtrl = TextEditingController(text: '15');

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              title: Text('Create Exam', style: TextStyle(color: context.textColor)),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      style: TextStyle(color: context.textColor),
                      decoration:  InputDecoration(labelText: 'Title', labelStyle: TextStyle(color: context.textColor70)),
                    ),
                    TextField(
                      controller: descCtrl,
                      style: TextStyle(color: context.textColor),
                      decoration:  InputDecoration(labelText: 'Description', labelStyle: TextStyle(color: context.textColor70)),
                    ),
                    TextField(
                      controller: durationCtrl,
                      style: TextStyle(color: context.textColor),
                      keyboardType: TextInputType.number,
                      decoration:  InputDecoration(labelText: 'Duration (minutes)', labelStyle: TextStyle(color: context.textColor70)),
                    ),
                     SizedBox(height: 16),
                    Text('Select Questions:', style: TextStyle(color: context.textColor70, fontWeight: FontWeight.bold)),
                     SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: questions.length,
                        itemBuilder: (ctx, i) {
                          final q = questions[i];
                          final isSelected = selectedQuestionIds.contains(q['_id']);
                          return CheckboxListTile(
                            value: isSelected,
                            title: Text(q['text'], style: TextStyle(color: context.textColor, fontSize: 14)),
                            subtitle: Text('${q['type']} • ${q['marks']} marks', style: TextStyle(color: context.textColor54, fontSize: 12)),
                            activeColor: const Color(0xFF6366F1),
                            checkColor: Colors.white,
                            onChanged: (v) {
                              setDialogState(() {
                                if (v == true) selectedQuestionIds.add(q['_id']);
                                else selectedQuestionIds.remove(q['_id']);
                              });
                            },
                          );
                        },
                      ),
                    )
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: context.textColor60))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                  onPressed: () async {
                    if (titleCtrl.text.isEmpty || selectedQuestionIds.isEmpty) return;

                    final reqBody = {
                      'title': titleCtrl.text,
                      'description': descCtrl.text,
                      'batch': widget.batch['_id'] ?? widget.batch['id'],
                      'duration': int.tryParse(durationCtrl.text) ?? 15,
                      'questions': selectedQuestionIds
                    };

                    final res = await ApiService.post('/exams', reqBody);
                    if (res.statusCode == 201) {
                      Navigator.pop(ctx);
                      _fetchExams();
                    }
                  },
                  child: Text('Create', style: TextStyle(color: context.textColor)),
                )
              ],
            );
          }
        );
      }
    );
  }

  void _showEditExamDialog(Map<String, dynamic> exam) async {
    final courseId = widget.batch['course']['_id'] ?? widget.batch['course'];
    
    showDialog(context: context, builder: (_) => const Center(child: JyamitiLoader()));
    final qRes = await ApiService.get('/questions/course/$courseId');
    Navigator.pop(context);

    if (qRes.statusCode != 200) return;
    final List<dynamic> questions = jsonDecode(qRes.body);
    final List<String> selectedQuestionIds = (exam['questions'] as List?)?.map((q) => q['_id'].toString()).toList() ?? [];

    final titleCtrl = TextEditingController(text: exam['title']);
    final descCtrl = TextEditingController(text: exam['description']);
    final durationCtrl = TextEditingController(text: exam['duration']?.toString() ?? '15');

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              title: Text('Edit Exam', style: TextStyle(color: context.textColor)),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      style: TextStyle(color: context.textColor),
                      decoration:  InputDecoration(labelText: 'Title', labelStyle: TextStyle(color: context.textColor70)),
                    ),
                    TextField(
                      controller: descCtrl,
                      style: TextStyle(color: context.textColor),
                      decoration:  InputDecoration(labelText: 'Description', labelStyle: TextStyle(color: context.textColor70)),
                    ),
                    TextField(
                      controller: durationCtrl,
                      style: TextStyle(color: context.textColor),
                      keyboardType: TextInputType.number,
                      decoration:  InputDecoration(labelText: 'Duration (minutes)', labelStyle: TextStyle(color: context.textColor70)),
                    ),
                     SizedBox(height: 16),
                    Text('Select Questions:', style: TextStyle(color: context.textColor70, fontWeight: FontWeight.bold)),
                     SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: questions.length,
                        itemBuilder: (ctx, i) {
                          final q = questions[i];
                          final isSelected = selectedQuestionIds.contains(q['_id']);
                          return CheckboxListTile(
                            value: isSelected,
                            title: Text(q['text'], style: TextStyle(color: context.textColor, fontSize: 14)),
                            subtitle: Text('${q['type']} • ${q['marks']} marks', style: TextStyle(color: context.textColor54, fontSize: 12)),
                            activeColor: const Color(0xFF6366F1),
                            checkColor: Colors.white,
                            onChanged: (v) {
                              setDialogState(() {
                                if (v == true) selectedQuestionIds.add(q['_id']);
                                else selectedQuestionIds.remove(q['_id']);
                              });
                            },
                          );
                        },
                      ),
                    )
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: context.textColor60))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  onPressed: () async {
                    if (titleCtrl.text.isEmpty || selectedQuestionIds.isEmpty) return;

                    final reqBody = {
                      'title': titleCtrl.text,
                      'description': descCtrl.text,
                      'duration': int.tryParse(durationCtrl.text) ?? 15,
                      'questions': selectedQuestionIds
                    };

                    final res = await ApiService.put('/exams/${exam['_id']}', reqBody);
                    if (res.statusCode == 200) {
                      Navigator.pop(ctx);
                      _fetchExams();
                    }
                  },
                  child: Text('Save Changes', style: TextStyle(color: context.textColor)),
                )
              ],
            );
          }
        );
      }
    );
  }

  void _handleExamTap(Map<String, dynamic> exam, String role) {
    if (role == 'STUDENT') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ExamTakingScreen(examId: exam['_id'])));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ExamResultsScreen(exam: exam)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = Provider.of<AuthProvider>(context, listen: false).userRole;
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isInline,
        leading: widget.isInline && widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onBack,
              )
            : null,
        title: Text('Exams: ${widget.batch['name']}', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, letterSpacing: 1)),
        backgroundColor: Colors.transparent,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: context.isDark ? const Color(0xFF0F172A) : Colors.white.withOpacity(0.6),
            ),
          ),
        ),
        iconTheme: IconThemeData(color: context.textColor),
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Futuristic Gradient Background
          Container(
            decoration: widget.isInline
                ? null
                : BoxDecoration(
                    gradient: LinearGradient(
                      colors: context.isDark
                          ? const [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)]
                          : const [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
          ),
          SafeArea(
            child: _isLoading 
              ? const Center(child: JyamitiLoader(color: Color(0xFF6366F1)))
              : _exams.isEmpty
                ? Center(child: Text('No exams scheduled', style: TextStyle(color: context.textColor70)))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _exams.length,
                    itemBuilder: (ctx, i) {
                      final e = _exams[i];
                      final subjectName = (widget.batch['course'] is Map) ? widget.batch['course']['name'] : widget.batch['name'];
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: context.glassBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: context.glassBorder),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.1), blurRadius: 20, spreadRadius: -5),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withOpacity(0.2),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.quiz_rounded, color: Color(0xFF10B981), size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          e['title'] ?? 'Unknown Title',
                                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textColor),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      const Icon(Icons.book_rounded, size: 16, color: Color(0xFF818CF8)),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text("Subject: ${subjectName ?? '-'}", style: TextStyle(color: context.textColor70, fontSize: 14))),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.timer_rounded, size: 16, color: Colors.orangeAccent),
                                      const SizedBox(width: 8),
                                      Text("Duration: ${e['duration'] ?? '-'} mins", style: TextStyle(color: context.textColor70, fontSize: 14)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.help_outline_rounded, size: 16, color: Colors.lightBlueAccent),
                                      const SizedBox(width: 8),
                                      Text("Questions: ${e['questions']?.length ?? 0}", style: TextStyle(color: context.textColor70, fontSize: 14)),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: (role == 'STUDENT' && e['hasSubmitted'] == true)
                                        ? Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF10B981).withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF10B981)),
                                                SizedBox(width: 8),
                                                Text('Completed', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                                              ],
                                            ),
                                          )
                                        : Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (role == 'TUTOR')
                                                Padding(
                                                  padding: const EdgeInsets.only(right: 8.0),
                                                  child: ElevatedButton.icon(
                                                    onPressed: () => _showEditExamDialog(e),
                                                    icon: Icon(Icons.edit_rounded, size: 20, color: context.textColor),
                                                    label: Text('Edit', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold)),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: const Color(0xFF10B981),
                                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                                      elevation: 8,
                                                      shadowColor: const Color(0xFF10B981).withOpacity(0.5),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(12),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ElevatedButton.icon(
                                                onPressed: () => _handleExamTap(e, role!),
                                                icon: Icon(role == 'STUDENT' ? Icons.play_arrow_rounded : Icons.analytics_rounded, size: 20, color: context.textColor),
                                                label: Text(role == 'STUDENT' ? 'Start Exam' : 'View Results', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold)),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF6366F1),
                                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                                  elevation: 8,
                                                  shadowColor: const Color(0xFF6366F1).withOpacity(0.5),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
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
                      ).animate().fade(duration: 400.ms, delay: (i * 100).ms).slideY(begin: 0.1, end: 0);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: role == 'TUTOR' ? FloatingActionButton(
        onPressed: _showCreateExamDialog,
        backgroundColor: const Color(0xFF6366F1),
        elevation: 8,
        child: Icon(Icons.add_rounded, color: context.textColor, size: 28),
      ).animate().scale(delay: 500.ms) : null,
    );
  }
}
