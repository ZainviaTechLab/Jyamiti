import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'video_player_screen.dart';
import '../../../../services/api_service.dart';

class TutorTutorialsScreen extends StatefulWidget {
  final Map<String, dynamic> batch;

  const TutorTutorialsScreen({super.key, required this.batch});

  @override
  State<TutorTutorialsScreen> createState() => _TutorTutorialsScreenState();
}

class _TutorTutorialsScreenState extends State<TutorTutorialsScreen> {
  bool _isLoading = true;
  List<dynamic> _tutorials = [];
  List<String> _chapters = [];
  List<String> _sessionDates = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await Future.wait([_fetchTutorials(), _fetchChapters(), _fetchSessions()]);
    setState(() => _isLoading = false);
  }

  Future<void> _fetchTutorials() async {
    try {
      final batchId = widget.batch['id'] ?? widget.batch['_id'];
      final res = await ApiService.get('/tutorials/batch/$batchId');
      if (res.statusCode == 200) {
        _tutorials = jsonDecode(res.body);
      }
    } catch (e) {
      debugPrint('Error fetching tutorials: $e');
    }
  }

  Future<void> _fetchChapters() async {
    try {
      final courseId =
          widget.batch['course']?['id'] ?? widget.batch['course']?['_id'];
      if (courseId == null) return;
      final res = await ApiService.get('/courses');
      if (res.statusCode == 200) {
        final List courses = jsonDecode(res.body);
        final course = courses.firstWhere(
          (c) => c['id'] == courseId || c['_id'] == courseId,
          orElse: () => null,
        );
        if (course != null && course['syllabus'] != null) {
          _chapters = (course['syllabus'] as List)
              .map((s) => s['title'].toString())
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Error fetching chapters: $e');
    }
  }

  Future<void> _fetchSessions() async {
    try {
      final res = await ApiService.get('/schedules/my-schedules');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List schedules = data['schedules'] ?? [];
        final batchId = widget.batch['id'] ?? widget.batch['_id'];
        final filtered = schedules.where((s) {
          final schedBatchId = s['batch']?['_id'] ?? s['batch'];
          return schedBatchId == batchId;
        }).toList();
        _sessionDates =
            filtered
                .map((s) {
                  final date =
                      DateTime.tryParse(s['date'] ?? '') ?? DateTime.now();
                  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                })
                .toSet()
                .toList()
              ..sort();
      }
    } catch (e) {
      debugPrint('Error fetching sessions: $e');
    }
  }

  Future<void> _deleteTutorial(String id) async {
    final res = await ApiService.delete('/tutorials/$id');
    if (res.statusCode == 200) {
      await _fetchTutorials();
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tutorial deleted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _showAddTutorialSheet() {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String? selectedSession;
    String? selectedChapter;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                  top: 24,
                  left: 20,
                  right: 20,
                ),
                decoration: BoxDecoration(
                  color: context.isDark ? const Color(0xFF1E293B) : Colors.white.withOpacity(0.95),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  border: Border.all(color: context.glassBorder),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: context.textColor54.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Upload Tutorial',
                        style: TextStyle(color: context.textColor, fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildField(titleCtrl, 'Title', Icons.title_rounded),
                      const SizedBox(height: 14),
                      _buildField(
                        urlCtrl,
                        'Video URL (YouTube / Drive)',
                        Icons.link_rounded,
                      ),
                      const SizedBox(height: 14),
                      _buildDropdown(
                        label: 'Session Date',
                        icon: Icons.calendar_today_rounded,
                        value: selectedSession,
                        items: _sessionDates,
                        onChanged: (v) => setSheet(() => selectedSession = v),
                      ),
                      const SizedBox(height: 14),
                      _buildDropdown(
                        label: 'Chapter',
                        icon: Icons.menu_book_rounded,
                        value: selectedChapter,
                        items: _chapters,
                        onChanged: (v) => setSheet(() => selectedChapter = v),
                      ),
                      const SizedBox(height: 14),
                      _buildField(
                        descCtrl,
                        'Description (optional)',
                        Icons.notes_rounded,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: Icon(
                            Icons.upload_rounded,
                            color: context.textColor,
                          ),
                          label: Text(
                            'Upload Tutorial',
                            style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          onPressed: () async {
                            if (titleCtrl.text.trim().isEmpty ||
                                urlCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Title and Video URL are required',
                                  ),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }
                            Navigator.pop(ctx);
                            final res = await ApiService.post('/tutorials', {
                              'batchId':
                                  widget.batch['id'] ?? widget.batch['_id'],
                              'title': titleCtrl.text.trim(),
                              'videoUrl': urlCtrl.text.trim(),
                              'sessionDate': selectedSession ?? '',
                              'chapter': selectedChapter ?? '',
                              'description': descCtrl.text.trim(),
                            });
                            if (res.statusCode == 201) {
                              await _fetchTutorials();
                              setState(() {});
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Tutorial uploaded!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } else {
                              final body = jsonDecode(res.body);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(body['message'] ?? 'Error'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: TextStyle(color: context.textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.textColor54),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        filled: true,
        fillColor: context.glassBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF6366F1)),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      dropdownColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
      style: TextStyle(color: context.textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.textColor54),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        filled: true,
        fillColor: context.glassBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF6366F1)),
        ),
      ),
      hint: Text(
        'Select $label',
        style: const TextStyle(color: Colors.white38),
      ),
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: onChanged,
    );
  }

  String? _extractYoutubeId(String url) {
    final regExp = RegExp(
      r'(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?)\/|.*[?&]v=)|youtu\.be\/)([^"&?\/\s]{11})',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(url);
    return match?.group(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Tutorials — ${widget.batch['name']}',
          style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white.withOpacity(0.85),
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        iconTheme: IconThemeData(color: context.textColor),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF6366F1),
        onPressed: _showAddTutorialSheet,
        icon: Icon(Icons.add_rounded, color: context.textColor),
        label: Text(
          'Add Tutorial',
          style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold),
        ),
      ).animate().scale(delay: 400.ms),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF6366F1)),
              )
            : _tutorials.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.video_library_rounded,
                      color: context.textColor54.withOpacity(0.4),
                      size: 80,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No tutorials uploaded yet.',
                      style: TextStyle(color: context.textColor54, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap "Add Tutorial" to get started.',
                      style: TextStyle(color: context.textColor54.withOpacity(0.5)),
                    ),
                  ],
                ).animate().fade(duration: 600.ms),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(
                  top: 100,
                  left: 16,
                  right: 16,
                  bottom: 100,
                ),
                itemCount: _tutorials.length,
                itemBuilder: (ctx, idx) {
                  final t = _tutorials[idx];
                  final videoId = _extractYoutubeId(t['videoUrl'] ?? '');
                  final delay = (idx % 10) * 60;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: context.glassBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF6366F1).withOpacity(0.3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.08),
                          blurRadius: 15,
                        ),
                      ],
                    ),
                    child:
                        ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () async {
                                    if (videoId != null) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => VideoPlayerScreen(
                                            videoId: videoId,
                                            title: t['title'] ?? 'Video',
                                          ),
                                        ),
                                      );
                                    } else {
                                      final uri = Uri.tryParse(
                                        t['videoUrl'] ?? '',
                                      );
                                      if (uri != null)
                                        await launchUrl(
                                          uri,
                                          mode: LaunchMode.externalApplication,
                                        );
                                    }
                                  },
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Thumbnail
                                      if (videoId != null)
                                        Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  const BorderRadius.vertical(
                                                    top: Radius.circular(20),
                                                  ),
                                              child: Image.network(
                                                'https://img.youtube.com/vi/$videoId/mqdefault.jpg',
                                                width: double.infinity,
                                                height: 180,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    Container(
                                                      height: 180,
                                                      color: const Color(
                                                        0xFF1E293B,
                                                      ),
                                                      child: Icon(
                                                        Icons
                                                            .video_library_rounded,
                                                        color: context.textColor54.withOpacity(0.5),
                                                        size: 60,
                                                      ),
                                                    ),
                                              ),
                                            ),
                                            Container(
                                              width: 56,
                                              height: 56,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.black.withOpacity(
                                                  0.6,
                                                ),
                                                border: Border.all(
                                                  color: context.textColor54.withOpacity(0.4),
                                                ),
                                              ),
                                              child: Icon(
                                                Icons.play_arrow_rounded,
                                                color: context.textColor,
                                                size: 36,
                                              ),
                                            ),
                                          ],
                                        )
                                      else
                                        Container(
                                          height: 120,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1E1B4B),
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                  top: Radius.circular(20),
                                                ),
                                          ),
                                          child: Center(
                                            child: Icon(
                                              Icons.videocam_rounded,
                                              color: context.textColor54.withOpacity(0.4),
                                              size: 60,
                                            ),
                                          ),
                                        ),
                                      // Info
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              t['title'] ?? '',
                                              style: TextStyle(color: context.textColor, fontSize: 17,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            if ((t['description'] ?? '')
                                                .isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                t['description'],
                                                style: TextStyle(color: context.textColor60, fontSize: 13,
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 10),
                                            Row(
                                              children: [
                                                if ((t['chapter'] ?? '')
                                                    .isNotEmpty)
                                                  _buildTag(
                                                    t['chapter'],
                                                    const Color(0xFF8B5CF6),
                                                    Icons.menu_book_rounded,
                                                  ),
                                                if ((t['sessionDate'] ?? '')
                                                    .isNotEmpty) ...[
                                                  const SizedBox(width: 8),
                                                  _buildTag(
                                                    t['sessionDate'],
                                                    const Color(0xFF10B981),
                                                    Icons
                                                        .calendar_today_rounded,
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: IconButton(
                                                style: IconButton.styleFrom(
                                                  backgroundColor: Colors
                                                      .redAccent
                                                      .withOpacity(0.1),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                ),
                                                icon: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  color: Colors.redAccent,
                                                ),
                                                onPressed: () =>
                                                    _deleteTutorial(
                                                      t['_id'] ?? t['id'],
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
                            )
                            .animate()
                            .fade(duration: 400.ms, delay: delay.ms)
                            .slideY(begin: 0.15, end: 0),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildTag(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
