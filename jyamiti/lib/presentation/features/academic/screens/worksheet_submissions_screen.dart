import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import '../../../../services/api_service.dart';
import '../../academic/screens/file_viewer_screen.dart';
import 'pdf_annotation_screen.dart';

class WorksheetSubmissionsScreen extends StatefulWidget {
  final Map<String, dynamic> Worksheet;
  const WorksheetSubmissionsScreen({super.key, required this.Worksheet});

  @override
  State<WorksheetSubmissionsScreen> createState() => _WorksheetSubmissionsScreenState();
}

class _WorksheetSubmissionsScreenState extends State<WorksheetSubmissionsScreen> {
  List<dynamic> _submissions = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchSubmissions();
  }

  Future<void> _fetchSubmissions() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.get('/Worksheets/${widget.Worksheet['_id']}/submissions');
      if (res.statusCode == 200) {
        setState(() {
          _submissions = jsonDecode(res.body);
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showGradeDialog(Map<String, dynamic> submission) {
    final maxScore = widget.Worksheet['maxScore'] ?? 100;
    
    final scoreCtrl = TextEditingController(text: submission['totalScore']?.toString() ?? '0');
    final remarkCtrl = TextEditingController(text: submission['remark'] ?? '');

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
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          final url = submission['annotatedFileUrl'] != null 
                              ? '${ApiService.serverBaseUrl}/${submission['annotatedFileUrl']}'
                              : '${ApiService.serverBaseUrl}/${submission['fileUrl']}';
                          final filename = submission['fileUrl'].split('/').last;
                          Navigator.push(context, MaterialPageRoute(builder: (_) => FileViewerScreen(url: url, filename: filename)));
                        },
                        child: Text(
                          'File: ${submission['fileUrl'].split('/').last}', 
                          style: const TextStyle(color: Colors.blueAccent, decoration: TextDecoration.underline)
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), padding: const EdgeInsets.symmetric(horizontal: 12)),
                      icon: Icon(Icons.draw, size: 16, color: context.textColor),
                      label: Text('Annotate', style: TextStyle(color: context.textColor)),
                      onPressed: () async {
                        final url = submission['annotatedFileUrl'] != null 
                            ? '${ApiService.serverBaseUrl}/${submission['annotatedFileUrl']}'
                            : '${ApiService.serverBaseUrl}/${submission['fileUrl']}';
                        final filename = submission['fileUrl'].split('/').last;
                        
                        final result = await Navigator.push(
                          context, 
                          MaterialPageRoute(builder: (_) => PdfAnnotationScreen(
                            url: url, 
                            filename: filename, 
                            WorksheetId: widget.Worksheet['_id'], 
                            submissionId: submission['_id']
                          ))
                        );
                        
                        if (result == true) {
                          _fetchSubmissions(); // Refresh if saved
                        }
                      },
                    ),
                  ],
                ),
                if (submission['annotatedFileUrl'] != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 4.0),
                    child: Text('✓ Annotated PDF exists', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                  ),
                const SizedBox(height: 16),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Text('Total Score:', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold))),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: scoreCtrl,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: '/$maxScore',
                          hintStyle: TextStyle(color: context.textColor54.withOpacity(0.5)),
                        ),
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: remarkCtrl,
                  style: TextStyle(color: context.textColor),
                  decoration: InputDecoration(labelText: 'Overall Remark', labelStyle: TextStyle(color: context.textColor70)),
                  maxLines: 3,
                )
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: context.textColor60))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
              onPressed: () async {
                final total = num.tryParse(scoreCtrl.text) ?? 0;
                
                final res = await ApiService.put('/Worksheets/${widget.Worksheet['_id']}/submissions/${submission['_id']}/grade', {
                  'totalScore': total,
                  'remark': remarkCtrl.text
                });
                
                if (res.statusCode == 200) {
                  Navigator.pop(ctx);
                  _fetchSubmissions();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save grade')));
                }
              },
              child: Text('Save Grade', style: TextStyle(color: context.textColor)),
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
        title: Text('Submissions', style: TextStyle(color: context.textColor)),
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        iconTheme: IconThemeData(color: context.textColor),
      ),
      body: _isLoading 
        ? const Center(child: JyamitiLoader(color: Color(0xFF6366F1)))
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
                    subtitle: Text(isGraded ? 'Score: ${s['totalScore']}' : 'Needs Grading', style: TextStyle(color: isGraded ? Colors.greenAccent : Colors.orangeAccent)),
                    trailing: Icon(Icons.grading, color: context.textColor70),
                    onTap: () => _showGradeDialog(s),
                  ),
                );
              },
            ),
    );
  }
}

