import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/api_service.dart';
import '../../academic/screens/Worksheet_submissions_screen.dart';
import '../../academic/screens/file_viewer_screen.dart';

class BatchWorksheetsScreen extends StatefulWidget {
  final Map<String, dynamic> batch;
  final bool isInline;
  final VoidCallback? onBack;
  const BatchWorksheetsScreen({super.key, required this.batch, this.isInline = false, this.onBack});

  @override
  State<BatchWorksheetsScreen> createState() => _BatchWorksheetsScreenState();
}

class _BatchWorksheetsScreenState extends State<BatchWorksheetsScreen> {
  List<dynamic> _Worksheets = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchWorksheets();
  }

  Future<void> _fetchWorksheets() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.get(
        '/Worksheets/batch/${widget.batch['id'] ?? widget.batch['_id']}',
      );
      if (res.statusCode == 200) {
        setState(() {
          _Worksheets = jsonDecode(res.body);
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showCreateWorksheetDialog() async {
    // Show a loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: JyamitiLoader(color: Color(0xFF6366F1)),
      ),
    );

    // Fetch past schedules
    List<DateTime> pastSessionDates = [];
    try {
      final res = await ApiService.get(
        '/schedules/batch/${widget.batch['id'] ?? widget.batch['_id']}/past',
      );
      if (res.statusCode == 200) {
        final List<dynamic> schedules = jsonDecode(res.body);
        for (var s in schedules) {
          if (s['date'] != null) {
            final dt = DateTime.parse(s['date']).toLocal();
            pastSessionDates.add(DateTime(dt.year, dt.month, dt.day));
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching past schedules: $e');
    }

    if (context.mounted) {
      Navigator.pop(context); // close loading
    }

    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final maxScoreCtrl = TextEditingController();
    DateTime? selectedDate; // Due Date
    DateTime? selectedSessionDate;
    String? selectedFileName;
    List<int>? selectedFileBytes;
    bool isDownloadable = false;

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              title: Text(
                'Create Worksheet',
                style: TextStyle(color: context.textColor),
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: titleCtrl,
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Title',
                          labelStyle: TextStyle(color: context.textColor70),
                        ),
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      TextFormField(
                        controller: descCtrl,
                        maxLines: 4,
                        keyboardType: TextInputType.multiline,
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Worksheet Content / Instructions',
                          hintText:
                              'Type or paste worksheet questions/content directly here...',
                          labelStyle: TextStyle(color: context.textColor70),
                          alignLabelWithHint: true,
                        ),
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () async {
                            final data =
                                await Clipboard.getData(Clipboard.kTextPlain);
                            if (data != null &&
                                data.text != null &&
                                data.text!.isNotEmpty) {
                              descCtrl.text = descCtrl.text.isEmpty
                                  ? data.text!
                                  : '${descCtrl.text}\n${data.text!}';
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Pasted worksheet text from clipboard!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.paste_rounded, size: 14),
                          label: const Text(
                            '📋 Paste Text from Clipboard',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      TextFormField(
                        controller: maxScoreCtrl,
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Total Max Score',
                          labelStyle: TextStyle(color: context.textColor70),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedSessionDate == null
                                  ? 'No session date selected'
                                  : 'Session: ${selectedSessionDate!.toLocal().toString().split(' ')[0]}',
                              style: TextStyle(color: context.textColor70),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              if (pastSessionDates.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'No past sessions available.',
                                      style: TextStyle(color: context.textColor),
                                    ),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                return;
                              }
                              final d = await showDatePicker(
                                context: context,
                                initialDate: pastSessionDates.first,
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                                selectableDayPredicate: (DateTime day) {
                                  final cleanDay = DateTime(
                                    day.year,
                                    day.month,
                                    day.day,
                                  );
                                  return pastSessionDates.contains(cleanDay);
                                },
                              );
                              if (d != null) {
                                setDialogState(() => selectedSessionDate = d);
                              }
                            },
                            child: const Text(
                              'Pick Session Date',
                              style: TextStyle(color: Color(0xFF818CF8)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedDate == null
                                  ? 'No due date selected'
                                  : 'Due: ${selectedDate!.toLocal().toString().split(' ')[0]}',
                              style: TextStyle(color: context.textColor70),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now().add(
                                  const Duration(days: 1),
                                ),
                                firstDate: DateTime.now(),
                                lastDate: DateTime(2030),
                              );
                              if (d != null) {
                                setDialogState(() => selectedDate = d);
                              }
                            },
                            child: const Text(
                              'Pick Due Date',
                              style: TextStyle(color: Color(0xFF818CF8)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedFileName == null
                                  ? 'No file selected'
                                  : selectedFileName!,
                              style: TextStyle(color: context.textColor70),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              FilePickerResult? result =
                                  await FilePicker.pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: [
                                      'pdf',
                                      'jpg',
                                      'jpeg',
                                      'png',
                                    ],
                                    withData: true,
                                  );
                              if (result != null &&
                                  result.files.single.bytes != null) {
                                setDialogState(() {
                                  selectedFileName = result.files.single.name;
                                  selectedFileBytes = result.files.single.bytes;
                                });
                              }
                            },
                            child: const Text(
                              'Pick File',
                              style: TextStyle(color: Color(0xFF818CF8)),
                            ),
                          ),
                        ],
                      ),
                      CheckboxListTile(
                        title: Text(
                          'Downloadable by Students',
                          style: TextStyle(color: context.textColor70),
                        ),
                        value: isDownloadable,
                        onChanged: (val) {
                          setDialogState(() {
                            isDownloadable = val ?? false;
                          });
                        },
                        activeColor: const Color(0xFF6366F1),
                        checkColor: Colors.white,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: context.textColor60),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                  ),
                  onPressed: () async {
                    if (formKey.currentState!.validate() &&
                        selectedDate != null &&
                        selectedSessionDate != null) {
                      if (selectedFileBytes == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'A file attachment is required.',
                              style: TextStyle(color: context.textColor),
                            ),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }

                      showDialog(
                        context: context,
                        builder: (_) => const Center(
                          child: JyamitiLoader(
                            color: Color(0xFF6366F1),
                          ),
                        ),
                      );

                      final Map<String, String> fields = {
                        'title': titleCtrl.text,
                        'description': descCtrl.text,
                        'batchId': widget.batch['id'] ?? widget.batch['_id'],
                        'maxScore': maxScoreCtrl.text,
                        'dueDate': selectedDate!.toIso8601String(),
                        'sessionDate': selectedSessionDate!.toIso8601String(),
                        'isDownloadable': isDownloadable.toString(),
                      };

                      final res = await ApiService.uploadWorksheet(
                        '/Worksheets',
                        fields,
                        selectedFileBytes,
                        selectedFileName,
                      );
                      Navigator.pop(context); // close loading

                      if (res.statusCode == 201) {
                        Navigator.pop(ctx); // close dialog
                        _fetchWorksheets();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to create')),
                        );
                      }
                    } else if (selectedDate == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'A due date is required.',
                            style: TextStyle(color: context.textColor),
                          ),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    } else if (selectedSessionDate == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'A session date is required.',
                            style: TextStyle(color: context.textColor),
                          ),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  },
                  child: Text(
                    'Create',
                    style: TextStyle(color: context.textColor),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditWorksheetDialog(Map<String, dynamic> Worksheet) async {
    // Show a loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: JyamitiLoader(color: Color(0xFF6366F1)),
      ),
    );

    // Fetch past schedules
    List<DateTime> pastSessionDates = [];
    try {
      final res = await ApiService.get(
        '/schedules/batch/${widget.batch['id'] ?? widget.batch['_id']}/past',
      );
      if (res.statusCode == 200) {
        final List<dynamic> schedules = jsonDecode(res.body);
        for (var s in schedules) {
          if (s['date'] != null) {
            final dt = DateTime.parse(s['date']).toLocal();
            pastSessionDates.add(DateTime(dt.year, dt.month, dt.day));
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching past schedules: $e');
    }

    if (context.mounted) {
      Navigator.pop(context); // close loading
    }

    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController(text: Worksheet['title']);
    final descCtrl = TextEditingController(text: Worksheet['description']);
    final maxScoreCtrl = TextEditingController(
      text: Worksheet['maxScore']?.toString() ?? '',
    );
    DateTime? selectedDate = DateTime.tryParse(Worksheet['dueDate'] ?? '');
    DateTime? selectedSessionDate = Worksheet['sessionDate'] != null
        ? DateTime.tryParse(Worksheet['sessionDate'])
        : null;
    String? selectedFileName;
    List<int>? selectedFileBytes;
    bool isDownloadable = Worksheet['isDownloadable'] ?? false;

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              title: Text(
                'Edit Worksheet',
                style: TextStyle(color: context.textColor),
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: titleCtrl,
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Title',
                          labelStyle: TextStyle(color: context.textColor70),
                        ),
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      TextFormField(
                        controller: descCtrl,
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Description',
                          labelStyle: TextStyle(color: context.textColor70),
                        ),
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      TextFormField(
                        controller: maxScoreCtrl,
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Max Score',
                          labelStyle: TextStyle(color: context.textColor70),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedSessionDate == null
                                  ? 'No session date selected'
                                  : 'Session: ${selectedSessionDate!.toLocal().toString().split(' ')[0]}',
                              style: TextStyle(color: context.textColor70),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              if (pastSessionDates.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'No past sessions available.',
                                      style: TextStyle(color: context.textColor),
                                    ),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                return;
                              }
                              final d = await showDatePicker(
                                context: context,
                                initialDate:
                                    selectedSessionDate ??
                                    pastSessionDates.first,
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                                selectableDayPredicate: (DateTime day) {
                                  final cleanDay = DateTime(
                                    day.year,
                                    day.month,
                                    day.day,
                                  );
                                  return pastSessionDates.contains(cleanDay);
                                },
                              );
                              if (d != null) {
                                setDialogState(() => selectedSessionDate = d);
                              }
                            },
                            child: const Text(
                              'Pick Session Date',
                              style: TextStyle(color: Color(0xFF818CF8)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedDate == null
                                  ? 'No due date'
                                  : 'Due: ${selectedDate!.toLocal().toString().split(' ')[0]}',
                              style: TextStyle(color: context.textColor70),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: selectedDate ?? DateTime.now(),
                                firstDate: DateTime.now(),
                                lastDate: DateTime(2030),
                              );
                              if (d != null) {
                                setDialogState(() => selectedDate = d);
                              }
                            },
                            child: const Text(
                              'Pick Date',
                              style: TextStyle(color: Color(0xFF818CF8)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedFileName == null
                                  ? 'Keep existing file'
                                  : selectedFileName!,
                              style: TextStyle(color: context.textColor70),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              FilePickerResult? result =
                                  await FilePicker.pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: [
                                      'pdf',
                                      'jpg',
                                      'jpeg',
                                      'png',
                                    ],
                                    withData: true,
                                  );
                              if (result != null &&
                                  result.files.single.bytes != null) {
                                setDialogState(() {
                                  selectedFileName = result.files.single.name;
                                  selectedFileBytes = result.files.single.bytes;
                                });
                              }
                            },
                            child: const Text(
                              'Change File',
                              style: TextStyle(color: Color(0xFF818CF8)),
                            ),
                          ),
                        ],
                      ),
                      CheckboxListTile(
                        title: Text(
                          'Downloadable by Students',
                          style: TextStyle(color: context.textColor70),
                        ),
                        value: isDownloadable,
                        onChanged: (val) {
                          setDialogState(() {
                            isDownloadable = val ?? false;
                          });
                        },
                        activeColor: const Color(0xFF6366F1),
                        checkColor: Colors.white,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: context.textColor60),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                  ),
                  onPressed: () async {
                    if (formKey.currentState!.validate() &&
                        selectedDate != null) {
                      showDialog(
                        context: context,
                        builder: (_) => const Center(
                          child: JyamitiLoader(
                            color: Color(0xFF6366F1),
                          ),
                        ),
                      );

                      final Map<String, String> fields = {
                        'title': titleCtrl.text,
                        'description': descCtrl.text,
                        'maxScore': maxScoreCtrl.text,
                        'dueDate': selectedDate!.toIso8601String(),
                        'isDownloadable': isDownloadable.toString(),
                      };

                      if (selectedSessionDate != null) {
                        fields['sessionDate'] = selectedSessionDate!
                            .toIso8601String();
                      }

                      final res = await ApiService.uploadWorksheet(
                        '/Worksheets/${Worksheet['_id']}',
                        fields,
                        selectedFileBytes,
                        selectedFileName,
                        method: 'PUT',
                      );
                      Navigator.pop(context); // close loading

                      if (res.statusCode == 200) {
                        Navigator.pop(ctx); // close dialog
                        _fetchWorksheets();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to update')),
                        );
                      }
                    } else if (selectedDate == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'A due date is required.',
                            style: TextStyle(color: context.textColor),
                          ),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  },
                  child: Text(
                    'Save',
                    style: TextStyle(color: context.textColor),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleStudentWorksheetTap(Map<String, dynamic> Worksheet) async {
    showDialog(
      context: context,
      builder: (_) => const Center(child: JyamitiLoader()),
    );
    final res = await ApiService.get(
      '/Worksheets/${Worksheet['_id']}/my-submission',
    );
    Navigator.pop(context);

    if (res.statusCode == 200) {
      final submission = (res.body.isNotEmpty && res.body != 'null')
          ? jsonDecode(res.body)
          : null;
      _showStudentSubmissionDialog(Worksheet, submission);
    }
  }

  void _showStudentSubmissionDialog(
    Map<String, dynamic> Worksheet,
    Map<String, dynamic>? submission,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Text(
            Worksheet['title'],
            style: TextStyle(color: context.textColor),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Worksheet['description'],
                style: TextStyle(color: context.textColor70),
              ),
              if (Worksheet['fileUrl'] != null) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    final url =
                        '${ApiService.baseUrl.replaceAll('/api', '')}/${Worksheet['fileUrl']}';
                    final filename = Worksheet['fileUrl'].split('/').last;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FileViewerScreen(
                          url: url,
                          filename: filename,
                          isDownloadable: Worksheet['isDownloadable'] ?? false,
                        ),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.insert_drive_file_rounded,
                        color: Colors.blueAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'View Attachment',
                        style: TextStyle(
                          color: Colors.blueAccent,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (submission != null) ...[
                if (submission['fileUrl'] != null) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () {
                      final url =
                          '${ApiService.baseUrl.replaceAll('/api', '')}/${submission['fileUrl']}';
                      final filename = submission['fileUrl'].split('/').last;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              FileViewerScreen(url: url, filename: filename),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.upload_file_rounded,
                          color: Colors.blueAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'View Your Submission',
                          style: TextStyle(
                            color: Colors.blueAccent,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (submission['annotatedFileUrl'] != null) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () {
                      final url =
                          '${ApiService.baseUrl.replaceAll('/api', '')}/${submission['annotatedFileUrl']}';
                      final filename = submission['annotatedFileUrl']
                          .split('/')
                          .last;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              FileViewerScreen(url: url, filename: filename),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.feedback,
                          color: Colors.greenAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'View Tutor Feedback',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              if (submission == null) ...[
                const Text(
                  'No submission yet.',
                  style: TextStyle(color: Colors.orangeAccent),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                  ),
                  icon:  Icon(Icons.upload_file, color: context.textColor),
                  label:  Text(
                    'Upload PDF',
                    style: TextStyle(color: context.textColor),
                  ),
                  onPressed: () async {
                    FilePickerResult? result = await FilePicker.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['pdf'],
                      withData: true,
                    );
                    if (result != null && result.files.single.bytes != null) {
                      Navigator.pop(ctx);
                      _uploadSubmission(
                        Worksheet['_id'],
                        result.files.single.bytes!,
                        result.files.single.name,
                      );
                    }
                  },
                ),
              ] else ...[
                Text(
                  'Status: ${submission['status']}',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (submission['status'] == 'GRADED') ...[
                  Divider(color: context.textColor54.withOpacity(0.4)),
                  Text(
                    'Total Score: ${submission['totalScore']}',
                    style: TextStyle(color: context.textColor, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Remark: ${submission['remark']}',
                    style: TextStyle(color: context.textColor70),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    'Waiting for grading...',
                    style: TextStyle(color: context.textColor60),
                  ),
                ],
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close', style: TextStyle(color: context.textColor)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _uploadSubmission(
    String WorksheetId,
    List<int> bytes,
    String filename,
  ) async {
    showDialog(
      context: context,
      builder: (_) => const Center(child: JyamitiLoader()),
    );
    try {
      final res = await ApiService.uploadFile(
        '/Worksheets/$WorksheetId/submit',
        bytes,
        filename,
      );
      Navigator.pop(context);
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Upload failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
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
        title: Text(
          'Worksheets: ${widget.batch['name']}',
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
            ? const Center(
                child: JyamitiLoader(color: Color(0xFF6366F1)),
              )
            : _Worksheets.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.book_rounded,
                      color: context.textColor54.withOpacity(0.4),
                      size: 80,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Worksheets found',
                      style: TextStyle(color: context.textColor70, fontSize: 18),
                    ),
                  ],
                ).animate().fade(duration: 600.ms),
              )
            : ListView.builder(
                padding: EdgeInsets.only(
                  top: widget.isInline ? kToolbarHeight + 24 : 100,
                  left: 16,
                  right: 16,
                  bottom: 100,
                ),
                itemCount: _Worksheets.length,
                itemBuilder: (ctx, i) {
                  final a = _Worksheets[i];
                  final delay = (i % 10) * 60;
                  return Container(
                        margin: const EdgeInsets.only(bottom: 16),
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
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () {
                                if (role == 'STUDENT') {
                                  _handleStudentWorksheetTap(a);
                                } else {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          WorksheetSubmissionsScreen(
                                            Worksheet: a,
                                          ),
                                    ),
                                  );
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF6366F1,
                                            ).withOpacity(0.2),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.book_rounded,
                                            color: Color(0xFF818CF8),
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                a['title'],
                                                style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Due: ${DateTime.parse(a['dueDate']).toLocal().toString().split(' ')[0]}',
                                                style: const TextStyle(
                                                  color: Color(0xFF818CF8),
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (role == 'TUTOR')
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (a['fileUrl'] != null)
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.visibility,
                                                    color: Color(0xFF818CF8),
                                                  ),
                                                  onPressed: () {
                                                    final url =
                                                        '${ApiService.baseUrl.replaceAll('/api', '')}/${a['fileUrl']}';
                                                    final filename =
                                                        a['fileUrl']
                                                            .split('/')
                                                            .last;
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            FileViewerScreen(
                                                              url: url,
                                                              filename:
                                                                  filename,
                                                            ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              IconButton(
                                                icon: Icon(
                                                  Icons.edit_rounded,
                                                  color: context.textColor60,
                                                ),
                                                onPressed: () =>
                                                    _showEditWorksheetDialog(a),
                                              ),
                                            ],
                                          )
                                        else
                                          Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            size: 16,
                                            color: context.textColor54.withOpacity(0.5),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                      .animate()
                      .fade(duration: 400.ms, delay: delay.ms)
                      .slideY(begin: 0.1, end: 0);
                },
              ),
      ),
      floatingActionButton: role == 'TUTOR'
          ? FloatingActionButton.extended(
              onPressed: _showCreateWorksheetDialog,
              backgroundColor: const Color(0xFF6366F1),
              icon:  Icon(Icons.add_rounded, color: context.textColor),
              label:  Text(
                'Add Worksheet',
                style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold,
                ),
              ),
            ).animate().scale(delay: 400.ms)
          : null,
    );
  }
}
