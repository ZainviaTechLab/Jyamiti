import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:jyamiti/services/api_service.dart';
import '../bloc/course/course_bloc.dart';
import '../bloc/course/course_event.dart';
import '../bloc/course/course_state.dart';
import '../../exams/screens/assessment_question_form_screen.dart';
import '../../academic/screens/video_player_screen.dart';
import '../../../../domain/models/slide_deck_models.dart';
import '../../../../services/slide_cache_service.dart';
import '../../slides/screens/admin_slide_cms_screen.dart' deferred as cms_screen;
import '../../slides/screens/admin_slide_analytics_screen.dart' deferred as analytics_screen;
import '../../slides/screens/student_slide_viewer_screen.dart' deferred as student_viewer_screen;

class CourseSyllabusScreen extends StatefulWidget {
  final String courseId;
  final String courseName;
  final VoidCallback? onBack;

  const CourseSyllabusScreen({
    super.key,
    required this.courseId,
    required this.courseName,
    this.onBack,
  });

  @override
  State<CourseSyllabusScreen> createState() => _CourseSyllabusScreenState();
}

class _CourseSyllabusScreenState extends State<CourseSyllabusScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  List<dynamic> _syllabus = [];
  bool _hasChanges = false;
  final Set<String> _expandedKeys = {};

  @override
  void initState() {
    super.initState();
    _fetchCourse();
  }

  Future<bool> _handleBackPress() async {
    if (_hasChanges) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Text('Unsaved Changes', style: TextStyle(color: context.textColor)),
          content: Text('You have unsaved changes. Do you want to discard them?', style: TextStyle(color: context.textColor70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: context.textColor60))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      return confirm == true;
    }
    return true;
  }

  void _fetchCourse() {
    final state = context.read<CourseBloc>().state;
    if (state is CourseLoaded) {
      final course = state.courses.firstWhere((c) => (c['id'] ?? c['_id']) == widget.courseId, orElse: () => null);
      if (course != null && course['syllabus'] != null) {
        setState(() {
          _syllabus = List<dynamic>.from(course['syllabus']);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _saveSyllabus() {
    setState(() => _isSaving = true);
    context.read<CourseBloc>().add(UpdateCourseSyllabus(id: widget.courseId, syllabus: _syllabus));
  }

  Future<String?> _showInputDialog(String title, {String initialValue = ''}) async {
    final ctrl = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text(title, style: TextStyle(color: context.textColor)),
        content: TextField(
          controller: ctrl,
          style: TextStyle(color: context.textColor),
          decoration: InputDecoration(
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: context.textColor54.withOpacity(0.4))),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: const Color(0xFF6366F1))),
          ),
          autofocus: true,
          onSubmitted: (val) {
            final text = val.trim();
            if (text.isNotEmpty) {
              Navigator.pop(ctx, text);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: context.textColor60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _addChapter() async {
    final title = await _showInputDialog('Add Chapter / Unit');
    if (title != null && title.isNotEmpty) {
      final newIndex = _syllabus.length;
      setState(() {
        _syllabus.add({'title': title, 'topics': []});
        _hasChanges = true;
        _expandedKeys.add('c_$newIndex');
      });
      _saveSyllabus();
    }
  }

  void _addTopic(int chapterIndex) async {
    final title = await _showInputDialog('Add Topic');
    if (title != null && title.isNotEmpty) {
      setState(() {
        if (_syllabus[chapterIndex]['topics'] == null) {
          _syllabus[chapterIndex]['topics'] = [];
        }
        final topics = _syllabus[chapterIndex]['topics'] as List;
        final newTopicIndex = topics.length;
        topics.add({'title': title, 'subTopics': []});
        _hasChanges = true;
        _expandedKeys.add('c_$chapterIndex');
        _expandedKeys.add('c_${chapterIndex}_t_$newTopicIndex');
      });
      _saveSyllabus();
    }
  }

  void _addSubTopic(int chapterIndex, int topicIndex) async {
    final title = await _showInputDialog('Add Sub-topic');
    if (title != null && title.isNotEmpty) {
      setState(() {
        if (_syllabus[chapterIndex]['topics'][topicIndex]['subTopics'] == null) {
          _syllabus[chapterIndex]['topics'][topicIndex]['subTopics'] = [];
        }
        _syllabus[chapterIndex]['topics'][topicIndex]['subTopics'].add({'title': title});
        _hasChanges = true;
        _expandedKeys.add('c_$chapterIndex');
        _expandedKeys.add('c_${chapterIndex}_t_$topicIndex');
      });
      _saveSyllabus();
    }
  }

  void _editTitle(dynamic node, String type) async {
    final title = await _showInputDialog('Edit $type', initialValue: node['title'] ?? '');
    if (title != null && title.isNotEmpty) {
      setState(() {
        node['title'] = title;
        _hasChanges = true;
      });
      _saveSyllabus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final shouldPop = await _handleBackPress();
        if (shouldPop && widget.onBack != null) {
          widget.onBack!();
          return false;
        }
        return shouldPop;
      },
      child: BlocListener<CourseBloc, CourseState>(
        listener: (context, state) {
          if (state is CourseOperationSuccess) {
            setState(() {
              _isSaving = false;
              _hasChanges = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          } else if (state is CourseOperationFailure) {
            setState(() => _isSaving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message), backgroundColor: Colors.redAccent),
            );
          } else if (state is CourseLoaded) {
            if (!_hasChanges && !_isSaving) {
              final course = state.courses.firstWhere((c) => (c['id'] ?? c['_id']) == widget.courseId, orElse: () => null);
              if (course != null && course['syllabus'] != null) {
                setState(() {
                  _syllabus = List<dynamic>.from(course['syllabus']);
                });
              }
            }
          }
        },
        child: Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () async {
                final shouldPop = await _handleBackPress();
                if (shouldPop) {
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else {
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  }
                }
              },
            ),
            title: Text('Syllabus: ${widget.courseName}', style: TextStyle(color: context.textColor, fontSize: 18, fontWeight: FontWeight.bold)),
            backgroundColor: context.isDark ? const Color(0xFF0F172A).withOpacity(0.8) : Colors.white.withOpacity(0.7),
            elevation: 0,
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: Colors.transparent),
              ),
            ),
            iconTheme: IconThemeData(color: context.textColor),
            bottom: _isSaving
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(3),
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.transparent,
                      color: Color(0xFF6366F1),
                      minHeight: 3,
                    ),
                  )
                : null,
            actions: [
              if (_hasChanges)
                IconButton(
                  icon: const Icon(Icons.save, color: Color(0xFF10B981)),
                  onPressed: _saveSyllabus,
                  tooltip: 'Save Changes',
                ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
              : _syllabus.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('No syllabus defined yet.', style: TextStyle(color: context.textColor54, fontSize: 16)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                            onPressed: _addChapter,
                            icon: const Icon(Icons.add, color: Colors.white),
                            label: const Text('Add Chapter', style: TextStyle(color: Colors.white)),
                          )
                        ],
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: context.isDark ? const [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)] : const [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                      ),
                      child: ListView.builder(
                        padding: const EdgeInsets.only(top: 100, left: 16, right: 16, bottom: 100),
                        itemCount: _syllabus.length,
                        itemBuilder: (context, cIndex) {
                          final chapter = _syllabus[cIndex];
                          final topics = chapter['topics'] ?? [];
                          final chapterKey = 'c_$cIndex';
                          final isChapterExpanded = _expandedKeys.contains(chapterKey);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: context.isDark 
                                    ? const Color(0xFF8B5CF6).withOpacity(0.3)
                                    : const Color(0xFF8B5CF6).withOpacity(0.15),
                              ),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFF8B5CF6).withOpacity(0.05), blurRadius: 10, spreadRadius: 0),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                child: ExpansionTile(
                                  key: Key('chapter_${cIndex}_$isChapterExpanded'),
                                  initiallyExpanded: isChapterExpanded,
                                  onExpansionChanged: (expanded) {
                                    setState(() {
                                      if (expanded) {
                                        _expandedKeys.add(chapterKey);
                                      } else {
                                        _expandedKeys.remove(chapterKey);
                                      }
                                    });
                                  },
                                  iconColor: context.textColor,
                                  collapsedIconColor: context.textColor70,
                                  title: Row(
                                    children: [
                                      const Icon(Icons.menu_book, color: Color(0xFF8B5CF6), size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(chapter['title'] ?? '', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold))),
                                      IconButton(
                                        icon: const Icon(Icons.folder_special_rounded, color: Color(0xFF8B5CF6), size: 18),
                                        onPressed: () => _manageResources(chapter),
                                        tooltip: 'Manage Resources',
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.edit, size: 16, color: context.textColor54),
                                        onPressed: () => _editTitle(chapter, 'Chapter'),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, size: 16, color: Colors.redAccent),
                                        onPressed: () {
                                          setState(() { _syllabus.removeAt(cIndex); _hasChanges = true; });
                                          _saveSyllabus();
                                        },
                                      ),
                                    ],
                                  ),
                                  children: [
                                    for (int tIndex = 0; tIndex < topics.length; tIndex++) ...[
                                      Builder(
                                        builder: (context) {
                                          final topic = topics[tIndex];
                                          final topicKey = 'c_${cIndex}_t_$tIndex';
                                          final isTopicExpanded = _expandedKeys.contains(topicKey);
                                          final subTopics = topic['subTopics'] ?? [];

                                          return Padding(
                                            padding: const EdgeInsets.only(left: 16.0),
                                            child: ExpansionTile(
                                              key: Key('topic_${cIndex}_${tIndex}_$isTopicExpanded'),
                                              initiallyExpanded: isTopicExpanded,
                                              onExpansionChanged: (expanded) {
                                                setState(() {
                                                  if (expanded) {
                                                    _expandedKeys.add(topicKey);
                                                  } else {
                                                    _expandedKeys.remove(topicKey);
                                                  }
                                                });
                                              },
                                              iconColor: context.textColor70,
                                              collapsedIconColor: context.textColor60,
                                              title: Row(
                                                children: [
                                                  const Icon(Icons.topic, color: Color(0xFF3B82F6), size: 18),
                                                  const SizedBox(width: 8),
                                                  Expanded(child: Text(topic['title'] ?? '', style: TextStyle(color: context.textColor))),
                                                  IconButton(
                                                    icon: const Icon(Icons.folder_special_rounded, color: Color(0xFF8B5CF6), size: 18),
                                                    onPressed: () => _manageResources(topic),
                                                    tooltip: 'Manage Resources',
                                                  ),
                                                  IconButton(
                                                    icon: Icon(Icons.edit, size: 16, color: context.textColor54),
                                                    onPressed: () => _editTitle(topic, 'Topic'),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.delete, size: 16, color: Colors.redAccent),
                                                    onPressed: () {
                                                      setState(() { topics.removeAt(tIndex); _hasChanges = true; });
                                                      _saveSyllabus();
                                                    },
                                                  ),
                                                ],
                                              ),
                                              children: [
                                                for (int sIndex = 0; sIndex < subTopics.length; sIndex++)
                                                  ListTile(
                                                    contentPadding: const EdgeInsets.only(left: 64, right: 16),
                                                    leading: Icon(Icons.subdirectory_arrow_right, color: context.textColor54.withOpacity(0.5), size: 16),
                                                    title: Text(subTopics[sIndex]['title'] ?? '', style: TextStyle(color: context.textColor70, fontSize: 14)),
                                                    trailing: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        IconButton(
                                                          icon: const Icon(Icons.folder_special_rounded, color: Color(0xFF8B5CF6), size: 14),
                                                          onPressed: () => _manageResources(subTopics[sIndex]),
                                                          tooltip: 'Manage Resources',
                                                        ),
                                                        IconButton(
                                                          icon: Icon(Icons.edit, size: 14, color: context.textColor54),
                                                          onPressed: () => _editTitle(subTopics[sIndex], 'Sub-topic'),
                                                        ),
                                                        IconButton(
                                                          icon: const Icon(Icons.delete, size: 14, color: Colors.redAccent),
                                                          onPressed: () {
                                                            setState(() { subTopics.removeAt(sIndex); _hasChanges = true; });
                                                            _saveSyllabus();
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ListTile(
                                                  contentPadding: const EdgeInsets.only(left: 64),
                                                  title: TextButton.icon(
                                                    onPressed: () => _addSubTopic(cIndex, tIndex),
                                                    icon: const Icon(Icons.add, size: 16, color: Color(0xFF10B981)),
                                                    label: const Text('Add Sub-topic', style: TextStyle(color: Color(0xFF10B981))),
                                                    style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                                                  ),
                                                )
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton.icon(
                                          onPressed: () => _addTopic(cIndex),
                                          icon: const Icon(Icons.add, size: 16, color: Color(0xFF6366F1)),
                                          label: const Text('Add Topic', style: TextStyle(color: Color(0xFF6366F1))),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ).animate().fade(duration: 400.ms),
          floatingActionButton: _syllabus.isNotEmpty
              ? FloatingActionButton.extended(
                  backgroundColor: const Color(0xFF6366F1),
                  onPressed: _addChapter,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('Add Chapter', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ).animate().scale(delay: 500.ms)
              : null,
        ),
      ),
    );
  }

  void _manageResources(Map<String, dynamic> node) async {
    final state = context.read<CourseBloc>().state;
    int grade = 10;
    if (state is CourseLoaded) {
      final course = state.courses.firstWhere((c) => c['id'] == widget.courseId, orElse: () => null);
      if (course != null) {
        final gradeStr = course['grade']?.toString() ?? '';
        final match = RegExp(r'\d+').firstMatch(gradeStr);
        grade = match != null ? int.tryParse(match.group(0)!) ?? 10 : 10;
      }
    }

    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SyllabusResourceEditor(item: node, grade: grade),
    );

    if (updated != null) {
      setState(() {
        node['videos'] = updated['videos'];
        node['slides'] = updated['slides'];
        node['practiceQuestions'] = updated['practiceQuestions'];
        _hasChanges = true;
      });
      _saveSyllabus();
    }
  }
}

class SyllabusResourceEditor extends StatefulWidget {
  final Map<String, dynamic> item;
  final int grade;

  const SyllabusResourceEditor({
    super.key,
    required this.item,
    required this.grade,
  });

  @override
  State<SyllabusResourceEditor> createState() => _SyllabusResourceEditorState();
}

class _SyllabusResourceEditorState extends State<SyllabusResourceEditor> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _videos = [];
  List<dynamic> _slides = [];
  List<dynamic> _practiceQuestions = [];

  bool _loadingQuestions = true;
  List<dynamic> _allGradeQuestions = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _videos = List.from(widget.item['videos'] ?? []);
    _slides = List.from(widget.item['slides'] ?? []);
    _practiceQuestions = List.from(widget.item['practiceQuestions'] ?? []);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String? _extractYoutubeId(String url) {
    final regExp = RegExp(
      r'^.*(youtu.be\/|v\/|u\/\w\/|embed\/|watch\?v=|\&v=)([^#\&\?]*).*',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(url);
    if (match != null && match.group(2)!.length == 11) {
      return match.group(2);
    }
    return null;
  }

  void _editVideoDialog({Map<String, dynamic>? initialVideo, int? index}) async {
    final titleCtrl = TextEditingController(text: initialVideo?['title'] ?? '');
    final urlCtrl = TextEditingController(text: initialVideo?['url'] ?? '');

    void submit() {
      final title = titleCtrl.text.trim();
      final url = urlCtrl.text.trim();
      if (title.isEmpty || url.isEmpty) return;
      Navigator.pop(context);
      setState(() {
        final videoData = {'title': title, 'url': url};
        if (index != null) {
          _videos[index] = videoData;
        } else {
          _videos.add(videoData);
        }
      });
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text(initialVideo == null ? 'Add Video' : 'Edit Video', style: TextStyle(color: context.textColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(
                labelText: 'Video Title',
                labelStyle: TextStyle(color: context.textColor60),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: context.textColor54.withOpacity(0.3))),
              ),
              style: TextStyle(color: context.textColor),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              decoration: InputDecoration(
                labelText: 'Video URL',
                labelStyle: TextStyle(color: context.textColor60),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: context.textColor54.withOpacity(0.3))),
              ),
              style: TextStyle(color: context.textColor),
              onSubmitted: (_) => submit(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: context.textColor60))),
          ElevatedButton(
            onPressed: submit,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _editSlideDialog({Map<String, dynamic>? initialSlide, int? index}) async {
    final titleCtrl = TextEditingController(text: initialSlide?['title'] ?? '');
    final contentCtrl = TextEditingController(text: initialSlide?['content'] ?? '');
    String imageUrl = initialSlide?['image'] ?? '';
    bool isUploading = false;

    void submitSlide() {
      final title = titleCtrl.text.trim();
      if (title.isEmpty) return;
      Navigator.pop(context);
      setState(() {
        final slideData = {
          'title': title,
          'content': contentCtrl.text.trim(),
          'image': imageUrl,
        };
        if (index != null) {
          _slides[index] = slideData;
        } else {
          _slides.add(slideData);
        }
      });
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> _pickAndUploadImage() async {
              setDialogState(() => isUploading = true);
              try {
                final result = await FilePicker.pickFiles(type: FileType.image);
                if (result != null && result.files.single.bytes != null) {
                  final bytes = result.files.single.bytes!;
                  final filename = result.files.single.name;
                  final res = await ApiService.uploadFile('/assessment-questions/upload', bytes, filename, fieldName: 'file');
                  if (res.statusCode == 200) {
                    final response = await http.Response.fromStream(res);
                    final data = jsonDecode(response.body);
                    setDialogState(() {
                      imageUrl = data['fileUrl'];
                    });
                  }
                }
              } catch (e) {
                debugPrint('Upload error: $e');
              } finally {
                setDialogState(() => isUploading = false);
              }
            }

            return AlertDialog(
              backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              title: Text(initialSlide == null ? 'Add Slide' : 'Edit Slide', style: TextStyle(color: context.textColor)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: InputDecoration(
                        labelText: 'Slide Title',
                        labelStyle: TextStyle(color: context.textColor60),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: context.textColor54.withOpacity(0.3))),
                      ),
                      style: TextStyle(color: context.textColor),
                      onSubmitted: (_) => submitSlide(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: contentCtrl,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Slide Content',
                        labelStyle: TextStyle(color: context.textColor60),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: context.textColor54.withOpacity(0.3))),
                      ),
                      style: TextStyle(color: context.textColor),
                    ),
                    const SizedBox(height: 20),
                    if (imageUrl.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          'https://api.jyamitimath.com/$imageUrl',
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 50),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    ElevatedButton.icon(
                      onPressed: isUploading ? null : _pickAndUploadImage,
                      icon: isUploading 
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.image, size: 18),
                      label: Text(imageUrl.isEmpty ? 'Upload Image' : 'Change Image'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: context.textColor60))),
                ElevatedButton(
                  onPressed: submitSlide,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Resources: ${widget.item['title']}',
                    style: TextStyle(color: context.textColor, fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: context.textColor60),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF6366F1),
              unselectedLabelColor: context.textColor60,
              indicatorColor: const Color(0xFF6366F1),
              tabs: const [
                Tab(icon: Icon(Icons.video_library), text: 'Videos'),
                Tab(icon: Icon(Icons.slideshow), text: 'Slides'),
                Tab(icon: Icon(Icons.assignment), text: 'Practice'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildVideosTab(),
                  _buildSlidesTab(),
                  _buildQuestionsTab(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: context.textColor60)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, {
                      'videos': _videos,
                      'slides': _slides,
                      'practiceQuestions': _practiceQuestions,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save Resources', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildVideosTab() {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _editVideoDialog(),
            icon: const Icon(Icons.add, size: 16, color: Color(0xFF6366F1)),
            label: const Text('Add Video', style: TextStyle(color: Color(0xFF6366F1))),
          ),
        ),
        Expanded(
          child: _videos.isEmpty
              ? Center(child: Text('No videos added.', style: TextStyle(color: context.textColor60)))
              : ListView.builder(
                  itemCount: _videos.length,
                  itemBuilder: (context, index) {
                    final video = _videos[index];
                    return ListTile(
                      leading: const Icon(Icons.play_circle_fill, color: Colors.red, size: 30),
                      title: Text(video['title'] ?? '', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold)),
                      subtitle: Text(video['url'] ?? '', style: TextStyle(color: context.textColor60, fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.red, size: 22),
                            tooltip: 'Watch Video',
                            onPressed: () {
                              final videoId = _extractYoutubeId(video['url'] ?? '');
                              if (videoId == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Invalid YouTube URL')),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VideoPlayerScreen(
                                    videoId: videoId,
                                    title: video['title'] ?? 'Video Preview',
                                  ),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () => _editVideoDialog(initialVideo: video, index: index),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
                            onPressed: () => setState(() => _videos.removeAt(index)),
                          )
                        ],
                      ),
                    );
                  },
                ),
        )
      ],
    );
  }

  Widget _buildSlidesTab() {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: () async {
              final topicTitle = widget.item['title'] ?? 'Topic Slide Deck';
              final initialDeck = SlideDeck(
                id: 'deck_${DateTime.now().millisecondsSinceEpoch}',
                courseId: 'course_${widget.grade}',
                courseName: 'Grade ${widget.grade} Mathematics',
                title: '$topicTitle - Learning Slides',
                description: 'Interactive slide deck for $topicTitle.',
                slides: [
                  SlideItem(
                    id: 's1',
                    slideIndex: 0,
                    title: 'Welcome to $topicTitle',
                    theme: 'darkGlass',
                    blocks: [
                      SlideBlock(
                        id: 'b1',
                        type: SlideBlockType.heading,
                        content: topicTitle,
                      ),
                      SlideBlock(
                        id: 'b2',
                        type: SlideBlockType.paragraph,
                        content: 'Enter main lesson notes and explanations here.',
                      ),
                    ],
                  ),
                ],
                createdAt: DateTime.now(),
              );

              await cms_screen.loadLibrary();
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => cms_screen.AdminSlideCmsScreen(initialDeck: initialDeck),
                ),
              );

              setState(() {
                _slides.add(initialDeck.toMap());
              });
            },
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Create Slide Deck in CMS'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _slides.isEmpty
              ? Center(child: Text('No slide decks added yet.', style: TextStyle(color: context.textColor60)))
              : ListView.builder(
                  itemCount: _slides.length,
                  itemBuilder: (context, index) {
                    final slideData = _slides[index];
                    final SlideDeck deck = slideData is Map<String, dynamic> && slideData.containsKey('slides')
                        ? SlideDeck.fromMap(slideData)
                        : SlideDeck(
                            id: 'deck_$index',
                            courseId: 'c101',
                            courseName: 'Mathematics',
                            title: slideData['title'] ?? 'Slide Deck ${index + 1}',
                            description: slideData['content'] ?? 'Topic slide deck',
                            createdAt: DateTime.now(),
                            slides: [
                              SlideItem(
                                id: 's_$index',
                                slideIndex: 0,
                                title: slideData['title'] ?? 'Slide 1',
                                blocks: [
                                  SlideBlock(
                                    id: 'b1',
                                    type: SlideBlockType.heading,
                                    content: slideData['title'] ?? '',
                                  ),
                                  SlideBlock(
                                    id: 'b2',
                                    type: SlideBlockType.paragraph,
                                    content: slideData['content'] ?? '',
                                  ),
                                ],
                              ),
                            ],
                          );

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFF6366F1),
                          child: Icon(Icons.slideshow_rounded, color: Colors.white, size: 20),
                        ),
                        title: Text(deck.title, style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold)),
                        subtitle: Text('${deck.slides.length} slides • ${deck.courseName}', style: TextStyle(color: context.textColor60, fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF10B981), size: 22),
                              tooltip: 'Live Student Preview',
                              onPressed: () async {
                                await student_viewer_screen.loadLibrary();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => student_viewer_screen.StudentSlideViewerScreen(deck: deck),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF6366F1), size: 22),
                              tooltip: 'Open CMS Editor',
                              onPressed: () async {
                                await cms_screen.loadLibrary();
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => cms_screen.AdminSlideCmsScreen(initialDeck: deck),
                                  ),
                                );
                                setState(() {
                                  _slides[index] = deck.toMap();
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.analytics_outlined, color: Color(0xFF0EA5E9), size: 20),
                              tooltip: 'View Analytics',
                              onPressed: () async {
                                await analytics_screen.loadLibrary();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => analytics_screen.AdminSlideAnalyticsScreen(deck: deck),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                              tooltip: 'Delete Deck',
                              onPressed: () => setState(() => _slides.removeAt(index)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        )
      ],
    );
  }

  Widget _buildQuestionsTab() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Practice Questions (${_practiceQuestions.length}):',
              style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            TextButton.icon(
              onPressed: () async {
                final created = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AssessmentQuestionFormScreen(
                      initialGrade: widget.grade,
                      isPracticeMode: true,
                    ),
                  ),
                );
                if (created != null) {
                  setState(() {
                    if (created is List) {
                      _practiceQuestions.addAll(List<Map<String, dynamic>>.from(created));
                    } else if (created is Map) {
                      _practiceQuestions.add(Map<String, dynamic>.from(created));
                    }
                  });
                }
              },
              icon: const Icon(Icons.add, size: 16, color: Color(0xFF6366F1)),
              label: const Text('Create Question', style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _practiceQuestions.isEmpty
              ? Center(child: Text('No practice questions added for this topic yet.', style: TextStyle(color: context.textColor60), textAlign: TextAlign.center))
              : ListView.builder(
                  itemCount: _practiceQuestions.length,
                  itemBuilder: (context, index) {
                    final q = _practiceQuestions[index] as Map<String, dynamic>;
                    final bool isClasswork = q['isClasswork'] == true || q['category'] == 'classwork';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: context.isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.01),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.textColor.withOpacity(0.05)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (isClasswork) ...[
                                        Container(
                                          margin: const EdgeInsets.only(right: 6),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.amber.withOpacity(0.5)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [
                                              Icon(Icons.lock_rounded, size: 10, color: Colors.amber),
                                              SizedBox(width: 3),
                                              Text(
                                                'Classwork (Teacher Only)',
                                                style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      Expanded(
                                        child: Text(
                                          q['text'] ?? '',
                                          style: TextStyle(color: context.textColor, fontSize: 13, fontWeight: FontWeight.w600),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Type: ${q['type']} | Marks: ${q['marks'] ?? 1}${isClasswork ? ' • Reserved for Classwork' : ''}',
                                    style: TextStyle(color: context.textColor60, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.edit, size: 18, color: context.textColor60),
                              onPressed: () async {
                                final updated = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AssessmentQuestionFormScreen(
                                      initialGrade: widget.grade,
                                      existingQuestion: q,
                                      isPracticeMode: true,
                                    ),
                                  ),
                                );
                                if (updated != null) {
                                  setState(() {
                                    if (updated is List) {
                                      if (updated.isNotEmpty) {
                                        _practiceQuestions[index] = updated[0];
                                        if (updated.length > 1) {
                                          _practiceQuestions.insertAll(index + 1, List<Map<String, dynamic>>.from(updated.sublist(1)));
                                        }
                                      }
                                    } else if (updated is Map) {
                                      _practiceQuestions[index] = Map<String, dynamic>.from(updated);
                                    }
                                  });
                                }
                              },
                              tooltip: 'Edit Question',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                                    title: Text('Delete Question', style: TextStyle(color: context.textColor)),
                                    content: Text('Are you sure you want to delete this practice question?', style: TextStyle(color: context.textColor70)),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: Text('Cancel', style: TextStyle(color: context.textColor60)),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                setState(() {
                                  _practiceQuestions.removeAt(index);
                                });
                              }
                            },
                            tooltip: 'Delete Question',
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    ],
  );
}
}
