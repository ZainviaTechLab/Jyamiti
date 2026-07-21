import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'video_player_screen.dart';
import '../../../../services/api_service.dart';

class StudentTutorialsScreen extends StatefulWidget {
  final Map<String, dynamic> batch;
  final bool isInline;
  final VoidCallback? onBack;

  const StudentTutorialsScreen({super.key, required this.batch, this.isInline = false, this.onBack});

  @override
  State<StudentTutorialsScreen> createState() => _StudentTutorialsScreenState();
}

class _StudentTutorialsScreenState extends State<StudentTutorialsScreen> {
  bool _isLoading = true;
  List<dynamic> _tutorials = [];
  List<dynamic> _filtered = [];

  // Filter state
  String? _selectedSession;
  String? _selectedChapter;

  List<String> _sessionDates = [];
  List<String> _chapters = [];

  @override
  void initState() {
    super.initState();
    _fetchTutorials();
  }

  Future<void> _fetchTutorials() async {
    setState(() => _isLoading = true);
    try {
      final batchId = widget.batch['id'] ?? widget.batch['_id'];
      final res = await ApiService.get('/tutorials/batch/$batchId');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        // Build unique filter lists from the data itself
        final sessionSet = <String>{};
        final chapterSet = <String>{};
        for (final t in data) {
          if ((t['sessionDate'] ?? '').isNotEmpty) sessionSet.add(t['sessionDate']);
          if ((t['chapter'] ?? '').isNotEmpty) chapterSet.add(t['chapter']);
        }
        setState(() {
          _tutorials = data;
          _sessionDates = sessionSet.toList()..sort();
          _chapters = chapterSet.toList()..sort();
          _applyFilters();
        });
      }
    } catch (e) {
      debugPrint('Error fetching tutorials: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    _filtered = _tutorials.where((t) {
      final matchSession = _selectedSession == null || t['sessionDate'] == _selectedSession;
      final matchChapter = _selectedChapter == null || t['chapter'] == _selectedChapter;
      return matchSession && matchChapter;
    }).toList();
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
        automaticallyImplyLeading: !widget.isInline,
        leading: widget.isInline && widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onBack,
              )
            : null,
        title: Text('Tutorials — ${widget.batch['name']}', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold)),
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white.withOpacity(0.85),
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(color: Colors.transparent)),
        ),
        iconTheme: IconThemeData(color: context.textColor),
      ),
      body: Container(
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
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
            : Column(
                children: [
                  // Filter bar
                  SizedBox(height: kToolbarHeight + MediaQuery.of(context).padding.top + 8),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: context.glassBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.glassBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: _buildFilterDropdown(
                          hint: 'All Sessions',
                          value: _selectedSession,
                          items: _sessionDates,
                          icon: Icons.calendar_today_rounded,
                          color: const Color(0xFF10B981),
                          onChanged: (v) {
                            setState(() {
                              _selectedSession = v;
                              _applyFilters();
                            });
                          },
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _buildFilterDropdown(
                          hint: 'All Chapters',
                          value: _selectedChapter,
                          items: _chapters,
                          icon: Icons.menu_book_rounded,
                          color: const Color(0xFF8B5CF6),
                          onChanged: (v) {
                            setState(() {
                              _selectedChapter = v;
                              _applyFilters();
                            });
                          },
                        )),
                        if (_selectedSession != null || _selectedChapter != null) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedSession = null;
                                _selectedChapter = null;
                                _applyFilters();
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ).animate().fade(duration: 400.ms).slideY(begin: -0.2),
                  const SizedBox(height: 12),

                  // Results count
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Text(
                          '${_filtered.length} video${_filtered.length == 1 ? '' : 's'}',
                          style: TextStyle(color: context.textColor54, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Video list
                  Expanded(
                    child: _filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.video_library_rounded, color: context.textColor54.withOpacity(0.4), size: 80),
                                const SizedBox(height: 16),
                                Text(
                                  _tutorials.isEmpty ? 'No tutorials uploaded yet.' : 'No results for selected filters.',
                                  style: TextStyle(color: context.textColor54, fontSize: 16),
                                ),
                              ],
                            ).animate().fade(duration: 600.ms),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 32),
                            itemCount: _filtered.length,
                            itemBuilder: (ctx, idx) {
                              final t = _filtered[idx];
                              final videoId = _extractYoutubeId(t['videoUrl'] ?? '');
                              final delay = (idx % 10) * 60;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                decoration: BoxDecoration(
                                  color: context.glassBg,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.25)),
                                  boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.06), blurRadius: 12)],
                                ),
                                child: ClipRRect(
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
                                          final uri = Uri.tryParse(t['videoUrl'] ?? '');
                                          if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                                        }
                                      },
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Thumbnail
                                          if (videoId != null)
                                            Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                ClipRRect(
                                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                                                  child: Image.network(
                                                    'https://img.youtube.com/vi/$videoId/mqdefault.jpg',
                                                    width: double.infinity,
                                                    height: 185,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) => Container(
                                                      height: 185,
                                                      color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                                                      child: Icon(Icons.video_library_rounded, color: context.textColor54.withOpacity(0.4), size: 60),
                                                    ),
                                                  ),
                                                ),
                                                // Play overlay
                                                Container(
                                                  width: 60, height: 60,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: Colors.black.withOpacity(0.55),
                                                    border: Border.all(color: context.textColor54.withOpacity(0.4), width: 2),
                                                  ),
                                                  child: Icon(Icons.play_arrow_rounded, color: context.textColor, size: 40),
                                                ),
                                                // Duration badge area top right
                                                Positioned(
                                                  top: 10, right: 12,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black.withOpacity(0.6),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.play_circle_outline_rounded, color: context.textColor70, size: 12),
                                                        SizedBox(width: 4),
                                                        Text('Watch', style: TextStyle(color: context.textColor70, fontSize: 11)),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            )
                                          else
                                            Container(
                                              height: 120,
                                              decoration: BoxDecoration(
                                                color: context.isDark ? const Color(0xFF1E1B4B) : const Color(0xFFCBD5E1),
                                                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                                              ),
                                              child: Center(
                                                child: Icon(Icons.videocam_rounded, color: context.textColor54.withOpacity(0.4), size: 60),
                                              ),
                                            ),

                                          Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(t['title'] ?? '', style: TextStyle(color: context.textColor, fontSize: 17, fontWeight: FontWeight.bold)),
                                                if ((t['description'] ?? '').isNotEmpty) ...[
                                                  const SizedBox(height: 4),
                                                  Text(t['description'], style: TextStyle(color: context.textColor60, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                                                ],
                                                const SizedBox(height: 10),
                                                Row(
                                                  children: [
                                                    if ((t['chapter'] ?? '').isNotEmpty) _buildTag(t['chapter'], const Color(0xFF8B5CF6), Icons.menu_book_rounded),
                                                    if ((t['sessionDate'] ?? '').isNotEmpty) ...[
                                                      const SizedBox(width: 8),
                                                      _buildTag(t['sessionDate'], const Color(0xFF10B981), Icons.calendar_today_rounded),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                if ((t['tutor']?['name'] ?? '').isNotEmpty)
                                                  Row(
                                                    children: [
                                                      Icon(Icons.person_rounded, size: 14, color: context.textColor54.withOpacity(0.5)),
                                                      const SizedBox(width: 4),
                                                      Text('by ${t['tutor']['name']}', style: TextStyle(color: context.textColor54, fontSize: 12)),
                                                    ],
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ).animate().fade(duration: 400.ms, delay: delay.ms).slideY(begin: 0.1, end: 0);
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String hint,
    required String? value,
    required List<String> items,
    required IconData icon,
    required Color color,
    required void Function(String?) onChanged,
  }) {
    return DropdownButton<String>(
      value: value,
      isExpanded: true,
      underline: const SizedBox(),
      dropdownColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
      icon: Icon(Icons.expand_more_rounded, color: color, size: 20),
      hint: Row(
        children: [
          Icon(icon, size: 14, color: color.withOpacity(0.7)),
          const SizedBox(width: 6),
          Text(hint, style: TextStyle(color: color.withOpacity(0.7), fontSize: 13)),
        ],
      ),
      items: items.map((item) {
        return DropdownMenuItem<String>(
          value: item,
          child: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(item, style: TextStyle(color: context.textColor, fontSize: 13), overflow: TextOverflow.ellipsis)),
            ],
          ),
        );
      }).toList(),
      onChanged: onChanged,
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
          Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
