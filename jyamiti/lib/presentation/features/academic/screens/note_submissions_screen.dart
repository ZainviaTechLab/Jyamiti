import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import '../../../../services/api_service.dart';
import '../../academic/screens/file_viewer_screen.dart';

class NoteSubmissionsScreen extends StatefulWidget {
  final Map<String, dynamic> note;
  const NoteSubmissionsScreen({super.key, required this.note});

  @override
  State<NoteSubmissionsScreen> createState() => _NoteSubmissionsScreenState();
}

class _NoteSubmissionsScreenState extends State<NoteSubmissionsScreen> {
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
      final res = await ApiService.get('/notes/${widget.note['_id']}/submissions');
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

  void _showReviewDialog(Map<String, dynamic> submission) {
    final criteria = List<String>.from(widget.note['criteria'] ?? []);
    
    // Map to hold Y/N selection for each criteria
    final Map<String, String> criteriaSelections = {};
    for (var c in criteria) {
      criteriaSelections[c] = submission['criteriaValues']?[c] ?? 'N';
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              title: Text('Review: ${submission['student']['name']}', style: TextStyle(color: context.textColor)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () {
                        final url = '${ApiService.serverBaseUrl}/${submission['fileUrl']}';
                        final filename = submission['fileUrl'].split('/').last;
                        Navigator.push(context, MaterialPageRoute(builder: (_) => FileViewerScreen(url: url, filename: filename)));
                      },
                      child: Text('File: ${submission['fileUrl'].split('/').last}', style: const TextStyle(color: Colors.blueAccent, decoration: TextDecoration.underline)),
                    ),
                    const SizedBox(height: 16),
                    Text('Criteria Review (Y/N):', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...criteria.map((c) => Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        children: [
                          Expanded(child: Text(c, style: TextStyle(color: context.textColor70))),
                          DropdownButton<String>(
                            value: criteriaSelections[c],
                            dropdownColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                            style: TextStyle(color: context.textColor),
                            items: const [
                              DropdownMenuItem(value: 'Y', child: Text('Yes (Y)', style: TextStyle(color: Colors.greenAccent))),
                              DropdownMenuItem(value: 'N', child: Text('No (N)', style: TextStyle(color: Colors.redAccent))),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() {
                                  criteriaSelections[c] = val;
                                });
                              }
                            },
                          )
                        ],
                      ),
                    )),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: context.textColor60))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                  onPressed: () async {
                    final res = await ApiService.put('/notes/${widget.note['_id']}/submissions/${submission['_id']}/review', {
                      'criteriaValues': criteriaSelections,
                    });
                    
                    if (res.statusCode == 200) {
                      Navigator.pop(ctx);
                      _fetchSubmissions();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save review')));
                    }
                  },
                  child: Text('Save Review', style: TextStyle(color: context.textColor)),
                )
              ],
            );
          }
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
                final isReviewed = s['status'] == 'REVIEWED';
                return Card(
                  color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(s['student']['name'], style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold)),
                    subtitle: Text(isReviewed ? 'Reviewed' : 'Needs Review', style: TextStyle(color: isReviewed ? Colors.greenAccent : Colors.orangeAccent)),
                    trailing: Icon(Icons.grading, color: context.textColor70),
                    onTap: () => _showReviewDialog(s),
                  ),
                );
              },
            ),
    );
  }
}
