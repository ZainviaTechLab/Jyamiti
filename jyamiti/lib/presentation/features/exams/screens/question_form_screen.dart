import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'package:flutter/material.dart';
import '../../../../providers/theme_provider.dart';
import '../../../../services/api_service.dart';

class QuestionFormScreen extends StatefulWidget {
  final List<dynamic> courses;
  final String? initialCourseId;
  final Map<String, dynamic>? existingQuestion;

  const QuestionFormScreen({
    super.key,
    required this.courses,
    this.initialCourseId,
    this.existingQuestion,
  });

  @override
  State<QuestionFormScreen> createState() => _QuestionFormScreenState();
}

class _QuestionFormScreenState extends State<QuestionFormScreen> {
  late String _type;
  late TextEditingController _textCtrl;
  late TextEditingController _marksCtrl;
  late TextEditingController _shortAnswerCtrl;
  late List<TextEditingController> _optionsCtrls;
  late List<bool> _mcqCorrect;
  late bool _tfCorrect;

  String? _selectedCourseId;
  String? _selectedChapter;
  String? _selectedTopic;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final q = widget.existingQuestion;
    _type = q?['type'] ?? 'MCQ_SINGLE';
    _textCtrl = TextEditingController(text: q?['text'] ?? '');
    _marksCtrl = TextEditingController(text: q?['marks']?.toString() ?? '1');
    _shortAnswerCtrl = TextEditingController();

    if (_type == 'SHORT_ANSWER') {
      _shortAnswerCtrl.text = (q?['correctAnswers'] != null && q!['correctAnswers'].isNotEmpty) ? q['correctAnswers'][0] : '';
    }

    _optionsCtrls = [TextEditingController(), TextEditingController(), TextEditingController(), TextEditingController()];
    _mcqCorrect = [false, false, false, false];

    if (_type.startsWith('MCQ')) {
      final List<dynamic> options = q?['options'] ?? [];
      final List<dynamic> correctAnswers = q?['correctAnswers'] ?? [];
      for (int i = 0; i < 4 && i < options.length; i++) {
        _optionsCtrls[i].text = options[i];
        _mcqCorrect[i] = correctAnswers.contains(options[i]);
      }
    }

    _tfCorrect = true;
    if (_type == 'TRUE_FALSE') {
      _tfCorrect = (q?['correctAnswers'] != null && q!['correctAnswers'].isNotEmpty && q['correctAnswers'][0] == 'True');
    }

    _selectedCourseId = q?['course'] ?? widget.initialCourseId;
    _selectedChapter = q?['chapter'];
    _selectedTopic = q?['topic'];
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _marksCtrl.dispose();
    _shortAnswerCtrl.dispose();
    for (var ctrl in _optionsCtrls) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _saveQuestion() async {
    setState(() => _isLoading = true);

    List<String> options = [];
    List<String> correctAnswers = [];

    if (_type.startsWith('MCQ')) {
      for (int i = 0; i < 4; i++) {
        if (_optionsCtrls[i].text.isNotEmpty) {
          options.add(_optionsCtrls[i].text);
          if (_mcqCorrect[i]) correctAnswers.add(_optionsCtrls[i].text);
        }
      }
    } else if (_type == 'TRUE_FALSE') {
      options = ['True', 'False'];
      correctAnswers = [_tfCorrect ? 'True' : 'False'];
    } else if (_type == 'SHORT_ANSWER') {
      if (_shortAnswerCtrl.text.isNotEmpty) {
        correctAnswers = [_shortAnswerCtrl.text.trim()];
      }
    }

    final reqBody = {
      'course': _selectedCourseId,
      if (_selectedChapter != null) 'chapter': _selectedChapter,
      if (_selectedTopic != null) 'topic': _selectedTopic,
      'type': _type,
      'text': _textCtrl.text,
      'options': options,
      'correctAnswers': correctAnswers,
      'marks': int.tryParse(_marksCtrl.text) ?? 1
    };

    try {
      if (widget.existingQuestion != null) {
        final res = await ApiService.put('/questions/${widget.existingQuestion!['_id']}', reqBody);
        if (res.statusCode == 200) {
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update question')));
        }
      } else {
        final res = await ApiService.post('/questions', reqBody);
        if (res.statusCode == 201) {
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to create question')));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error saving question')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCourse = widget.courses.firstWhere((c) => (c['id'] ?? c['_id']) == _selectedCourseId, orElse: () => null);
    final List<dynamic> syllabus = selectedCourse?['syllabus'] ?? [];

    return Scaffold(
      backgroundColor: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(widget.existingQuestion != null ? 'Edit Question' : 'Add Question', style: TextStyle(color: context.textColor)),
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        iconTheme: IconThemeData(color: context.textColor),
        actions: [
          if (_isLoading)
            Center(child: Padding(padding: const EdgeInsets.all(16.0), child: SizedBox(width: 20, height: 20, child: JyamitiLoader(color: context.textColor, strokeWidth: 2))))
          else
            TextButton(
              onPressed: _saveQuestion,
              child: const Text('Save', style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold, fontSize: 16)),
            )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: _type,
              dropdownColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              style: TextStyle(color: context.textColor),
              items: const [
                DropdownMenuItem(value: 'MCQ_SINGLE', child: Text('Single Choice MCQ')),
                DropdownMenuItem(value: 'MCQ_MULTI', child: Text('Multi Choice MCQ')),
                DropdownMenuItem(value: 'TRUE_FALSE', child: Text('True / False')),
                DropdownMenuItem(value: 'SHORT_ANSWER', child: Text('Short Answer')),
              ],
              onChanged: (v) => setState(() => _type = v!),
              decoration: InputDecoration(labelText: 'Question Type', labelStyle: TextStyle(color: context.textColor70), filled: true, fillColor: context.isDark ? const Color(0xFF1E293B) : Colors.white, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: syllabus.any((ch) => ch['title'] == _selectedChapter) ? _selectedChapter : null,
              dropdownColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              style: TextStyle(color: context.textColor),
              decoration: InputDecoration(labelText: 'Chapter (Optional)', labelStyle: TextStyle(color: context.textColor70), filled: true, fillColor: context.isDark ? const Color(0xFF1E293B) : Colors.white, border: const OutlineInputBorder()),
              items: syllabus.isEmpty 
                ? [const DropdownMenuItem<String>(value: null, child: Text('No chapters (Add Syllabus first)'))]
                : syllabus.map((ch) => DropdownMenuItem<String>(
                    value: ch['title'],
                    child: Text(ch['title']),
                  )).toList(),
              onChanged: syllabus.isEmpty ? null : (v) => setState(() {
                _selectedChapter = v;
                _selectedTopic = null;
              }),
            ),
            const SizedBox(height: 16),
            if (_selectedChapter != null && syllabus.any((ch) => ch['title'] == _selectedChapter)) ...[
              Builder(
                builder: (ctx) {
                  final chapter = syllabus.firstWhere((ch) => ch['title'] == _selectedChapter, orElse: () => null);
                  final List<dynamic> topics = chapter?['topics'] ?? [];
                  return DropdownButtonFormField<String>(
                    value: topics.any((t) => t['title'] == _selectedTopic) ? _selectedTopic : null,
                    dropdownColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                    style: TextStyle(color: context.textColor),
                    decoration: InputDecoration(labelText: 'Topic (Optional)', labelStyle: TextStyle(color: context.textColor70), filled: true, fillColor: context.isDark ? const Color(0xFF1E293B) : Colors.white, border: const OutlineInputBorder()),
                    items: topics.isEmpty
                      ? [const DropdownMenuItem<String>(value: null, child: Text('No topics available'))]
                      : topics.map((t) => DropdownMenuItem<String>(
                          value: t['title'],
                          child: Text(t['title']),
                        )).toList(),
                    onChanged: topics.isEmpty ? null : (v) => setState(() => _selectedTopic = v),
                  );
                }
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _textCtrl,
              style: TextStyle(color: context.textColor),
              decoration: InputDecoration(labelText: 'Question Text', labelStyle: TextStyle(color: context.textColor70), filled: true, fillColor: context.isDark ? const Color(0xFF1E293B) : Colors.white, border: const OutlineInputBorder()),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _marksCtrl,
              style: TextStyle(color: context.textColor),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Marks', labelStyle: TextStyle(color: context.textColor70), filled: true, fillColor: context.isDark ? const Color(0xFF1E293B) : Colors.white, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            if (_type == 'MCQ_SINGLE' || _type == 'MCQ_MULTI') ...[
              Text('Options & Correct Answer:', style: TextStyle(color: context.textColor70, fontSize: 16)),
              const SizedBox(height: 8),
              ...List.generate(4, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  children: [
                    Checkbox(
                      value: _mcqCorrect[i],
                      checkColor: Colors.white,
                      activeColor: const Color(0xFF6366F1),
                      onChanged: (v) {
                        setState(() {
                          if (_type == 'MCQ_SINGLE') {
                            for(int j=0; j<4; j++) _mcqCorrect[j] = false;
                          }
                          _mcqCorrect[i] = v ?? false;
                        });
                      },
                    ),
                    Expanded(
                      child: TextField(
                        controller: _optionsCtrls[i],
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(hintText: 'Option ${i+1}', hintStyle: TextStyle(color: context.textColor54.withOpacity(0.5)), filled: true, fillColor: context.isDark ? const Color(0xFF1E293B) : Colors.white, border: const OutlineInputBorder()),
                      ),
                    )
                  ],
                ),
              ))
            ] else if (_type == 'TRUE_FALSE') ...[
              Text('Correct Answer:', style: TextStyle(color: context.textColor70, fontSize: 16)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(color: context.isDark ? const Color(0xFF1E293B) : Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade800)),
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Radio<bool>(value: true, groupValue: _tfCorrect, activeColor: const Color(0xFF6366F1), onChanged: (v) => setState(() => _tfCorrect = v!)),
                    Text('True', style: TextStyle(color: context.textColor, fontSize: 16)),
                    const SizedBox(width: 24),
                    Radio<bool>(value: false, groupValue: _tfCorrect, activeColor: const Color(0xFF6366F1), onChanged: (v) => setState(() => _tfCorrect = v!)),
                    Text('False', style: TextStyle(color: context.textColor, fontSize: 16)),
                  ],
                ),
              )
            ] else if (_type == 'SHORT_ANSWER') ...[
              TextField(
                controller: _shortAnswerCtrl,
                style: TextStyle(color: context.textColor),
                decoration: InputDecoration(labelText: 'Correct Answer (Exact Match)', labelStyle: TextStyle(color: context.textColor70), filled: true, fillColor: context.isDark ? const Color(0xFF1E293B) : Colors.white, border: const OutlineInputBorder()),
              )
            ]
          ],
        ),
      ),
    );
  }
}
