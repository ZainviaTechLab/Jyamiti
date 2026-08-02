import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/api_service.dart';
import 'session_notes_screen.dart';

class BatchNotesScreen extends StatefulWidget {
  final Map<String, dynamic> batch;
  final bool isInline;
  final VoidCallback? onBack;
  const BatchNotesScreen({super.key, required this.batch, this.isInline = false, this.onBack});

  @override
  State<BatchNotesScreen> createState() => _BatchNotesScreenState();
}

class _BatchNotesScreenState extends State<BatchNotesScreen> {
  List<dynamic> _teacherNotes = [];
  List<dynamic> _studentSubmissions = [];
  List<String> _sessionDates = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchNotes();
  }

  Future<void> _fetchNotes() async {
    setState(() => _isLoading = true);
    try {
      final batchId = widget.batch['id'] ?? widget.batch['_id'];
      final resNotes = await ApiService.get('/notes/batch/$batchId/all');
      final resSchedules = await ApiService.get('/schedules/batch/$batchId/past');
      
      if (resNotes.statusCode == 200 && resSchedules.statusCode == 200) {
        final notesData = jsonDecode(resNotes.body);
        final schedulesData = jsonDecode(resSchedules.body);
        
        setState(() {
          _teacherNotes = notesData['teacherNotes'] ?? [];
          _studentSubmissions = notesData['studentSubmissions'] ?? [];
          
          final Set<String> dates = {};
          
          // Add dates from past schedules
          if (schedulesData is List) {
            for (var s in schedulesData) {
              if (s['date'] != null) {
                dates.add(DateTime.parse(s['date']).toIso8601String().split('T')[0]);
              }
            }
          }

          // Fallback: add dates from any existing notes
          for (var n in _teacherNotes) {
            dates.add(DateTime.parse(n['sessionDate']).toIso8601String().split('T')[0]);
          }
          for (var s in _studentSubmissions) {
            dates.add(DateTime.parse(s['sessionDate']).toIso8601String().split('T')[0]);
          }
          _sessionDates = dates.toList()..sort((a, b) => b.compareTo(a));
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      setState(() => _isLoading = false);
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
        title: Text('Notes: ${widget.batch['name']}', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, letterSpacing: 1)),
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
              : _sessionDates.isEmpty
                ? Center(child: Text('No sessions with notes found', style: TextStyle(color: context.textColor70)))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _sessionDates.length,
                    itemBuilder: (ctx, i) {
                      final dateStr = _sessionDates[i];
                      
                      final sessionTeacherNotes = _teacherNotes.where((n) => DateTime.parse(n['sessionDate']).toIso8601String().split('T')[0] == dateStr);
                      final sessionStudentNotes = _studentSubmissions.where((s) => DateTime.parse(s['sessionDate']).toIso8601String().split('T')[0] == dateStr);
                      
                      final bool teacherUploaded = sessionTeacherNotes.isNotEmpty;
                      
                      Widget subtitleWidget;
                      if (role == 'STUDENT') {
                        final String myNoteStatus = sessionStudentNotes.isEmpty ? 'Not Uploaded' : (sessionStudentNotes.first['status'] == 'REVIEWED' ? 'Checked' : 'Pending');
                        subtitleWidget = Text('Teacher Note: ${teacherUploaded ? "Available" : "Not Uploaded"} | My Note: $myNoteStatus', style: TextStyle(color: context.textColor60));
                      } else {
                        int checkedCount = 0;
                        int pendingCount = 0;
                        for (var s in sessionStudentNotes) {
                          if (s['status'] == 'REVIEWED') checkedCount++;
                          else pendingCount++;
                        }
                        subtitleWidget = Text('Teacher Note: ${teacherUploaded ? "Uploaded" : "Pending"} | Checked: $checkedCount | Pending: $pendingCount', style: TextStyle(color: context.textColor60));
                      }

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
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => SessionNotesScreen(
                                    batchId: widget.batch['id'] ?? widget.batch['_id'],
                                    batchName: widget.batch['name'],
                                    sessionDate: dateStr,
                                    teacherNotes: _teacherNotes.where((n) => DateTime.parse(n['sessionDate']).toIso8601String().split('T')[0] == dateStr).toList(),
                                    studentSubmissions: _studentSubmissions.where((s) => DateTime.parse(s['sessionDate']).toIso8601String().split('T')[0] == dateStr).toList(),
                                    onRefresh: _fetchNotes,
                                  )));
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF8B5CF6).withOpacity(0.2),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.menu_book_rounded, color: Color(0xFF8B5CF6), size: 24),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Session: $dateStr', 
                                              style: TextStyle(color: context.textColor, fontSize: 16, fontWeight: FontWeight.bold)
                                            ),
                                            const SizedBox(height: 6),
                                            subtitleWidget,
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.arrow_forward_ios_rounded, size: 16, color: context.textColor54.withOpacity(0.5)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ).animate().fade(duration: 400.ms, delay: (i * 100).ms).slideX(begin: 0.1, end: 0);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
