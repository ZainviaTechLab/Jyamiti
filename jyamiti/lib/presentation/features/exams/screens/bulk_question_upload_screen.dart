import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../providers/theme_provider.dart';
import 'package:flutter/services.dart';
import '../../../../services/api_service.dart';

class BulkQuestionUploadScreen extends StatefulWidget {
  final String courseId;
  final Map<String, dynamic>? course;
  
  const BulkQuestionUploadScreen({super.key, required this.courseId, this.course});

  @override
  State<BulkQuestionUploadScreen> createState() => _BulkQuestionUploadScreenState();
}

class _BulkQuestionUploadScreenState extends State<BulkQuestionUploadScreen> {
  final TextEditingController _inputController = TextEditingController();
  List<Map<String, dynamic>> _parsedQuestions = [];
  bool _isSaving = false;
  
  String? _selectedChapter;
  String? _selectedTopic;

  final String _sampleFormat = """
[TYPE] MCQ_SINGLE
[MARKS] 2
[QUESTION] What is 2 + 2?
[OPTION] 3
[OPTION] 4
[OPTION] 5
[OPTION] 6
[ANSWER] 4

---
[TYPE] TRUE_FALSE
[MARKS] 1
[QUESTION] A circle has 360 degrees.
[ANSWER] True

---
[TYPE] SHORT_ANSWER
[MARKS] 5
[QUESTION] Explain the process of photosynthesis in 2-3 sentences.
[ANSWER] Photosynthesis is the process...

---
[TYPE] MCQ_MULTI
[MARKS] 3
[QUESTION] Which of the following are planets?
[OPTION] Earth
[OPTION] Moon
[OPTION] Mars
[OPTION] Sun
[ANSWER] Earth
[ANSWER] Mars
""";

  void _showSampleFormatDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
             Text('Sample Format', style: TextStyle(color: context.textColor, fontSize: 18)),
            IconButton(
              icon: const Icon(Icons.copy, color: Color(0xFF6366F1), size: 20),
              tooltip: 'Copy Format',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _sampleFormat));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sample format copied to clipboard!')),
                );
              },
            ),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.textColor54.withOpacity(0.4)),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              _sampleFormat,
              style: TextStyle(color: context.textColor70, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: TextStyle(color: context.textColor70)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Format'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _sampleFormat));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sample format copied to clipboard!')),
              );
              Navigator.pop(ctx);
            },
          )
        ],
      ),
    );
  }

  void _parseText() {
    final text = _inputController.text;
    List<Map<String, dynamic>> parsed = [];
    List<String> chunks = text.split('---');
    
    for (String chunk in chunks) {
      if (chunk.trim().isEmpty) continue;
      
      Map<String, dynamic> q = {
        'course': widget.courseId,
        'type': 'SHORT_ANSWER',
        'chapter': _selectedChapter ?? '',
        'topic': _selectedTopic ?? '',
        'marks': 1,
        'text': '',
        'options': [],
        'correctAnswers': [],
      };
      
      RegExp tagExp = RegExp(r'\[([A-Z_]+)\]([\s\S]*?)(?=\n\[|$)', multiLine: true);
      Iterable<RegExpMatch> matches = tagExp.allMatches(chunk);
      
      for (final match in matches) {
        String tag = match.group(1) ?? '';
        String content = (match.group(2) ?? '').trim();
        
        switch (tag) {
          case 'TYPE':
            q['type'] = content;
            break;
          case 'MARKS':
            q['marks'] = int.tryParse(content) ?? 1;
            break;
          case 'QUESTION':
            q['text'] = content;
            break;
          case 'OPTION':
            (q['options'] as List).add(content);
            break;
          case 'ANSWER':
            (q['correctAnswers'] as List).add(content);
            break;
        }
      }
      
      if (q['text'].toString().isNotEmpty) {
        parsed.add(q);
      }
    }
    
    setState(() {
      _parsedQuestions = parsed;
    });

    if (parsed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not parse any questions. Check format.'), backgroundColor: Colors.orange),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Parsed ${parsed.length} questions successfully!'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _submitQuestions() async {
    if (_parsedQuestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No questions to upload!')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final res = await ApiService.post('/questions/bulk', {'questions': _parsedQuestions});
      
      if (res.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Questions uploaded successfully!'), backgroundColor: Colors.green),
          );
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to upload: ${jsonDecode(res.body)['message'] ?? 'Error'}'), backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error connecting to server')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text('Bulk Upload Questions', style: TextStyle(color: context.textColor)),
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        iconTheme: IconThemeData(color: context.textColor),
        actions: [
          TextButton.icon(
            icon: Icon(Icons.help_outline, color: context.textColor),
            label: Text('Format', style: TextStyle(color: context.textColor)),
            onPressed: _showSampleFormatDialog,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.course != null) ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedChapter,
                      dropdownColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                      style: TextStyle(color: context.textColor),
                      decoration: InputDecoration(
                        labelText: 'Chapter',
                        labelStyle: TextStyle(color: context.textColor70),
                        isDense: true,
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: context.textColor54.withOpacity(0.4))),
                      ),
                      items: (widget.course!['syllabus'] as List<dynamic>?)?.map((ch) => DropdownMenuItem<String>(
                        value: ch['title'],
                        child: Text(ch['title']),
                      )).toList() ?? [],
                      onChanged: (v) {
                        setState(() {
                          _selectedChapter = v;
                          _selectedTopic = null;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Builder(
                      builder: (ctx) {
                        final syllabus = (widget.course!['syllabus'] as List<dynamic>?) ?? [];
                        final chapter = syllabus.firstWhere((ch) => ch['title'] == _selectedChapter, orElse: () => null);
                        final topics = (chapter?['topics'] as List<dynamic>?) ?? [];
                        return DropdownButtonFormField<String>(
                          value: _selectedTopic,
                          dropdownColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                          style: TextStyle(color: context.textColor),
                          decoration: InputDecoration(
                            labelText: 'Topic (Optional)',
                            labelStyle: TextStyle(color: context.textColor70),
                            isDense: true,
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: context.textColor54.withOpacity(0.4))),
                          ),
                          items: _selectedChapter == null ? [] : topics.map((t) => DropdownMenuItem<String>(
                            value: t['title'],
                            child: Text(t['title']),
                          )).toList(),
                          onChanged: _selectedChapter == null ? null : (v) {
                            setState(() {
                              _selectedTopic = v;
                            });
                          },
                        );
                      }
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
             Text(
              'Paste your formatted questions below. Separate questions with "---".',
              style: TextStyle(color: context.textColor70, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Expanded(
              flex: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.textColor54.withOpacity(0.4)),
                ),
                child: TextField(
                  controller: _inputController,
                  maxLines: null,
                  expands: true,
                  style: TextStyle(color: context.textColor, fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.all(16),
                    border: InputBorder.none,
                    hintText: '[TYPE] MCQ_SINGLE\n[QUESTION] Example question...\n...',
                    hintStyle: TextStyle(color: Colors.white38),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _parseText,
              icon: const Icon(Icons.preview),
              label: const Text('Parse & Preview'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 16),
            if (_parsedQuestions.isNotEmpty) ...[
              Divider(color: context.textColor54.withOpacity(0.4)),
              const SizedBox(height: 8),
              Text(
                'Preview (${_parsedQuestions.length} Questions)',
                style: TextStyle(color: context.textColor, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                flex: 1,
                child: ListView.builder(
                  itemCount: _parsedQuestions.length,
                  itemBuilder: (ctx, i) {
                    final q = _parsedQuestions[i];
                    return Card(
                      color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${q['type']} • ${q['marks']} marks', style: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold, fontSize: 12)),
                                if (q['chapter'] != '') Text('Ch: ${q['chapter']}', style: TextStyle(color: context.textColor54, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(q['text'], style: TextStyle(color: context.textColor, fontSize: 15)),
                            if ((q['options'] as List).isNotEmpty) ...[
                              const SizedBox(height: 6),
                              ...((q['options'] as List).map((opt) => Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text('○ $opt', style: TextStyle(color: context.textColor70)),
                              )))
                            ],
                            if ((q['correctAnswers'] as List).isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text('Answer: ${(q['correctAnswers'] as List).join(", ")}', style: const TextStyle(color: Colors.greenAccent, fontSize: 13)),
                            ]
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _submitQuestions,
                icon: _isSaving ?  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: context.textColor)) : const Icon(Icons.cloud_upload),
                label: Text(_isSaving ? 'Uploading...' : 'Save All to Question Bank'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
