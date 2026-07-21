import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../services/api_service.dart';
import '../../../../providers/theme_provider.dart';
import 'assessment_question_form_screen.dart';
import 'assessment_taking_screen.dart';

class AssessmentQuestionManagementScreen extends StatefulWidget {
  final bool isInline;
  final VoidCallback? onBack;

  const AssessmentQuestionManagementScreen({super.key, this.isInline = false, this.onBack});

  @override
  State<AssessmentQuestionManagementScreen> createState() => _AssessmentQuestionManagementScreenState();
}

class _AssessmentQuestionManagementScreenState extends State<AssessmentQuestionManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Questions tab states
  int _selectedGrade = 1;
  List<dynamic> _questions = [];
  bool _isLoadingQuestions = false;

  // Submissions tab states
  List<dynamic> _submissions = [];
  bool _isLoadingSubmissions = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _fetchQuestions();
    _fetchSubmissions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Fetch questions for selected grade
  Future<void> _fetchQuestions() async {
    setState(() => _isLoadingQuestions = true);
    try {
      final res = await ApiService.get('/assessment-questions/grade/$_selectedGrade');
      if (res.statusCode == 200) {
        setState(() {
          _questions = jsonDecode(res.body);
        });
      }
    } catch (e) {
      debugPrint('Error fetching questions: $e');
    } finally {
      setState(() => _isLoadingQuestions = false);
    }
  }

  // Fetch all student submissions
  Future<void> _fetchSubmissions() async {
    setState(() => _isLoadingSubmissions = true);
    try {
      final res = await ApiService.get('/assessment-submissions');
      if (res.statusCode == 200) {
        setState(() {
          _submissions = jsonDecode(res.body);
        });
      }
    } catch (e) {
      debugPrint('Error fetching submissions: $e');
    } finally {
      setState(() => _isLoadingSubmissions = false);
    }
  }

  // Navigate to create/edit form screen
  void _navigateToQuestionForm({Map<String, dynamic>? existingQuestion}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssessmentQuestionFormScreen(
          initialGrade: _selectedGrade,
          existingQuestion: existingQuestion,
        ),
      ),
    );

    if (result == true) {
      _fetchQuestions();
    }
  }

  // Delete question
  Future<void> _deleteQuestion(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text('Confirm Delete', style: TextStyle(color: ctx.textColor)),
        content: Text('Are you sure you want to delete this assessment question?', style: TextStyle(color: ctx.textColor70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: ctx.textColor54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: TextStyle(color: context.textColor)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final res = await ApiService.delete('/assessment-questions/$id');
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Question deleted successfully'), backgroundColor: Colors.green),
        );
        _fetchQuestions();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete question'), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error deleting question'), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(
          'Assessments Manager',
          style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold),
        ),
        leading: widget.isInline
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 1,
        shadowColor: isDark ? Colors.transparent : Colors.black12,
        iconTheme: IconThemeData(color: context.textColor),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF6366F1),
          labelColor: context.textColor,
          unselectedLabelColor: context.textColor60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.quiz_rounded), text: 'Questions'),
            Tab(icon: Icon(Icons.analytics_rounded), text: 'Submissions'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildQuestionsTab(),
          _buildSubmissionsTab(),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: () => _navigateToQuestionForm(),
              backgroundColor: const Color(0xFF6366F1),
              child:  Icon(Icons.add, color: context.textColor),
            )
          : null,
    );
  }

  // Tab 1: Questions list & Grade selector
  Widget _buildQuestionsTab() {
    return Column(
      children: [
        // Grade selector header
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: DropdownButtonFormField<int>(
            value: _selectedGrade,
            dropdownColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
            style: TextStyle(color: context.textColor),
            decoration: InputDecoration(
              labelText: 'Select Grade to Manage',
              labelStyle: TextStyle(color: context.textColor70),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: context.isDark ? context.glassBorder : Colors.black26)),
              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF6366F1))),
              filled: true,
              fillColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
            ),
            items: List.generate(12, (index) {
              final grade = index + 1;
              return DropdownMenuItem<int>(
                value: grade,
                child: Text('Grade $grade', style: TextStyle(color: context.textColor)),
              );
            }),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _selectedGrade = val;
                });
                _fetchQuestions();
              }
            },
          ),
        ),

        // List body
        Expanded(
          child: _isLoadingQuestions
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
              : RefreshIndicator(
                  onRefresh: _fetchQuestions,
                  color: const Color(0xFF6366F1),
                  child: _questions.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                            Center(
                              child: Text(
                                'No questions in this grade.\nTap the + button to add one!',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: context.textColor60, fontSize: 15, height: 1.5),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _questions.length,
                          itemBuilder: (ctx, idx) {
                            final q = _questions[idx];
                            return Card(
                              color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                              margin: const EdgeInsets.only(bottom: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: ExpansionTile(
                                collapsedIconColor: context.textColor54,
                                iconColor: const Color(0xFF6366F1),
                                title: Text(
                                  q['text'] ?? '',
                                  style: GoogleFonts.outfit(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF6366F1).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          q['type'] ?? '',
                                          style: const TextStyle(color: Color(0xFF818CF8), fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Marks: ${q['marks'] ?? 1}',
                                        style: TextStyle(color: context.textColor54, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Image details
                                        if (q['questionImage'] != null && q['questionImage'].toString().isNotEmpty) ...[
                                          Row(
                                            children: [
                                              const Icon(Icons.image, color: Color(0xFF8B5CF6), size: 16),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  'Has SVG/Image: ${q['isSvg'] == true ? "SVG" : "Standard Image"}',
                                                  style: TextStyle(color: context.textColor60, fontSize: 13),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                        ],

                                        // Options
                                        if (q['options'] != null && (q['options'] as List).isNotEmpty) ...[
                                          Text('Options:', style: TextStyle(color: context.textColor70, fontWeight: FontWeight.bold, fontSize: 13)),
                                          const SizedBox(height: 6),
                                          ...((q['options'] as List).asMap().entries.map((entry) {
                                            final int oIdx = entry.key;
                                            final dynamic o = entry.value;
                                            final List<dynamic> correct = q['correctAnswers'] ?? [];
                                            final bool isCorrect = correct.map((e) => e.toString()).contains(oIdx.toString());

                                            return Padding(
                                              padding: const EdgeInsets.only(bottom: 6.0),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    isCorrect ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                                                    color: isCorrect ? Colors.green : context.textColor54,
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      o['text'] ?? 'Option ${oIdx + 1}',
                                                      style: TextStyle(color: isCorrect ? Colors.green : context.textColor70, fontSize: 14),
                                                    ),
                                                  ),
                                                  if (o['imageUrl'] != null && o['imageUrl'].toString().isNotEmpty)
                                                    Text(' (SVG/Image)', style: TextStyle(color: context.textColor54, fontSize: 12)),
                                                ],
                                              ),
                                            );
                                          })),
                                          const SizedBox(height: 12),
                                        ],

                                        // Short answers details
                                        if (q['type'] == 'SHORT_ANSWER') ...[
                                          RichText(
                                            text: TextSpan(
                                              style: TextStyle(fontSize: 13, color: context.textColor70),
                                              children: [
                                                const TextSpan(text: 'Correct Answers: '),
                                                TextSpan(
                                                  text: (q['correctAnswers'] as List).join(' / '),
                                                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                        ],

                                        // Action buttons
                                        Divider(color: context.isDark ? context.glassBorder : Colors.black12),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            TextButton.icon(
                                              icon: const Icon(Icons.play_arrow_rounded, size: 16, color: Color(0xFF818CF8)),
                                              label: const Text('Try', style: TextStyle(color: Color(0xFF818CF8))),
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => AssessmentTakingScreen(trySingleQuestion: q),
                                                  ),
                                                );
                                              },
                                            ),
                                            const SizedBox(width: 8),
                                            TextButton.icon(
                                              icon: Icon(Icons.edit, size: 16, color: context.textColor70),
                                              label: Text('Edit', style: TextStyle(color: context.textColor70)),
                                              onPressed: () => _navigateToQuestionForm(existingQuestion: q),
                                            ),
                                            const SizedBox(width: 8),
                                            TextButton.icon(
                                              icon: const Icon(Icons.delete, size: 16, color: Colors.redAccent),
                                              label: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                                              onPressed: () => _deleteQuestion(q['_id']),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  )
                                ],
                              ),
                            );
                          },
                        ),
                ),
        ),
      ],
    );
    
  }

  // Tab 2: Submissions log
  Widget _buildSubmissionsTab() {
    return _isLoadingSubmissions
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
        : RefreshIndicator(
            onRefresh: _fetchSubmissions,
            color: const Color(0xFF6366F1),
            child: _submissions.isEmpty
                ? Center(
                    child: Text(
                      'No assessment results submitted yet.',
                      style: TextStyle(color: context.textColor60),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _submissions.length,
                    itemBuilder: (ctx, idx) {
                      final s = _submissions[idx];
                      final score = s['score'] ?? 0;
                      final total = s['totalQuestions'] ?? 0;
                      final pct = total > 0 ? (score / total) * 100 : 0.0;
                      
                      // Formatting timestamp
                      String timeStr = '';
                      if (s['createdAt'] != null) {
                        try {
                          final parsed = DateTime.parse(s['createdAt']).toLocal();
                          timeStr = '${parsed.day}/${parsed.month}/${parsed.year} at ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
                        } catch (_) {}
                      }

                      return Card(
                        color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: pct >= 80 
                                ? Colors.green.withOpacity(0.2) 
                                : pct >= 50 
                                    ? const Color(0xFF6366F1).withOpacity(0.2) 
                                    : Colors.orange.withOpacity(0.2),
                            child: Text(
                              'G${s['grade']}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: pct >= 80 
                                    ? Colors.green 
                                    : pct >= 50 
                                        ? const Color(0xFF818CF8) 
                                        : Colors.orange,
                              ),
                            ),
                          ),
                          title: Text(
                            s['name'] ?? '',
                            style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('WhatsApp: ${s['whatsappNumber'] ?? ""}', style: TextStyle(color: context.textColor54, fontSize: 13)),
                              if (timeStr.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(timeStr, style: TextStyle(color: context.textColor54.withOpacity(0.6), fontSize: 11)),
                              ]
                            ],
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: pct >= 80 
                                  ? Colors.green.withOpacity(0.12) 
                                  : pct >= 50 
                                      ? const Color(0xFF6366F1).withOpacity(0.12) 
                                      : Colors.orange.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: pct >= 80 
                                    ? Colors.green.withOpacity(0.3) 
                                    : pct >= 50 
                                        ? const Color(0xFF6366F1).withOpacity(0.3) 
                                        : Colors.orange.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              '$score/$total',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: pct >= 80 
                                    ? Colors.green 
                                    : pct >= 50 
                                        ? const Color(0xFF818CF8) 
                                        : Colors.orange,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          );
  }
}
