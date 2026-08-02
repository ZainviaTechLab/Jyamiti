import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/api_service.dart';
import 'file_viewer_screen.dart';

class SessionNotesScreen extends StatefulWidget {
  final String batchId;
  final String batchName;
  final String sessionDate;
  final List<dynamic> teacherNotes;
  final List<dynamic> studentSubmissions;
  final VoidCallback onRefresh;

  const SessionNotesScreen({
    super.key,
    required this.batchId,
    required this.batchName,
    required this.sessionDate,
    required this.teacherNotes,
    required this.studentSubmissions,
    required this.onRefresh,
  });

  @override
  State<SessionNotesScreen> createState() => _SessionNotesScreenState();
}

class _SessionNotesScreenState extends State<SessionNotesScreen> {
  Future<void> _takePhotosAndConvertToPdf(
    Function(String, List<int>) onComplete,
  ) async {
    final ImagePicker picker = ImagePicker();
    List<XFile> capturedPhotos = [];
    bool takeMore = true;

    while (takeMore) {
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        capturedPhotos.add(photo);
        if (!mounted) return;
        takeMore =
            await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                title: Text(
                  'Add Another Page?',
                  style: TextStyle(color: context.textColor),
                ),
                content: Text(
                  'You have captured ${capturedPhotos.length} page(s). Do you want to take another photo?',
                  style: TextStyle(color: context.textColor70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(
                      'No, I\'m done',
                      style: TextStyle(color: context.textColor60),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(
                      'Yes, capture another',
                      style: TextStyle(color: context.textColor),
                    ),
                  ),
                ],
              ),
            ) ??
            false;
      } else {
        takeMore = false;
      }
    }

    if (capturedPhotos.isNotEmpty && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: JyamitiLoader(color: Color(0xFF6366F1)),
        ),
      );

      try {
        final PdfDocument document = PdfDocument();
        document.pageSettings.margins.all = 0; // Remove white borders
        
        for (var photo in capturedPhotos) {
          final bytes = await photo.readAsBytes();
          final PdfBitmap image = PdfBitmap(bytes);
          
          // Set the page size to match the image size exactly
          document.pageSettings.size = Size(image.width.toDouble(), image.height.toDouble());
          
          final PdfPage page = document.pages.add();
          
          // Draw the image to fill the exact size of the newly created page
          page.graphics.drawImage(
            image, 
            Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble())
          );
        }

        final List<int> pdfBytes = await document.save();
        document.dispose();

        if (mounted) Navigator.pop(context); // close loading
        onComplete('scanned_notes.pdf', pdfBytes);
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // close loading
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to generate PDF: $e')));
        }
      }
    }
  }

  void _showUploadDialog(String role) {
    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String? selectedFileName;
    List<int>? selectedFileBytes;
    bool isDownloadable = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              title: Text(
                'Upload Note',
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
                          labelText: 'Session Notes / Content',
                          hintText:
                              'Type or paste session notes directly here...',
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
                                      'Pasted notes text from clipboard!'),
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
                          IconButton(
                            icon: const Icon(
                              Icons.camera_alt,
                              color: Color(0xFF818CF8),
                            ),
                            tooltip: 'Take Photo',
                            onPressed: () {
                              _takePhotosAndConvertToPdf((name, bytes) {
                                setDialogState(() {
                                  selectedFileName = name;
                                  selectedFileBytes = bytes;
                                });
                              });
                            },
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
                      if (role != 'STUDENT')
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
                        selectedFileBytes != null) {
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
                        'batchId': widget.batchId,
                        'sessionDate': widget
                            .sessionDate, // Use the current session date directly
                        if (role != 'STUDENT')
                          'isDownloadable': isDownloadable.toString(),
                      };

                      final endpoint = role == 'STUDENT'
                          ? '/notes/student-upload'
                          : '/notes';
                      final res = await ApiService.uploadWorksheet(
                        endpoint,
                        fields,
                        selectedFileBytes,
                        selectedFileName,
                      );
                      Navigator.pop(context); // close loading

                      if (res.statusCode == 201 || res.statusCode == 200) {
                        Navigator.pop(ctx); // close dialog
                        widget
                            .onRefresh(); // trigger refresh on BatchNotesScreen
                        Navigator.pop(
                          context,
                        ); // Also pop SessionNotesScreen to see the refreshed list
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to upload')),
                        );
                      }
                    } else if (selectedFileBytes == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please select a file')),
                      );
                    }
                  },
                  child: Text(
                    'Upload',
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

  void _showEditDialog(
    Map<String, dynamic> note,
    String role,
    bool isStudentNote,
  ) {
    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController(text: note['title'] ?? '');
    final descCtrl = TextEditingController(text: note['description'] ?? '');
    String? selectedFileName = note['fileUrl']?.split('/').last;
    List<int>? selectedFileBytes;
    bool isDownloadable = note['isDownloadable'] ?? false;
    final noteId = note['_id'] ?? note['id'];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              title: Text(
                'Edit Note',
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
                              'Change File',
                              style: TextStyle(color: Color(0xFF818CF8)),
                            ),
                          ),
                        ],
                      ),
                      if (role != 'STUDENT')
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
                    if (formKey.currentState!.validate()) {
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
                        if (role != 'STUDENT')
                          'isDownloadable': isDownloadable.toString(),
                      };

                      final endpoint = isStudentNote
                          ? '/notes/submissions/$noteId'
                          : '/notes/$noteId';
                      final res = await ApiService.uploadWorksheet(
                        endpoint,
                        fields,
                        selectedFileBytes,
                        selectedFileBytes != null ? selectedFileName : null,
                        method: 'PUT',
                      );
                      Navigator.pop(context); // close loading

                      if (res.statusCode == 200) {
                        Navigator.pop(ctx); // close dialog
                        widget
                            .onRefresh(); // trigger refresh on BatchNotesScreen
                        Navigator.pop(
                          context,
                        ); // Also pop SessionNotesScreen to see the refreshed list
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to update note'),
                          ),
                        );
                      }
                    }
                  },
                  child: Text(
                    'Save Changes',
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

  void _showReviewDialog(Map<String, dynamic> submission) {
    // Determine criteria: from teacher note or default
    List<String> criteria = [
      'Completed on time',
      'Missing content',
      'Neatness',
      'No correction',
    ];
    if (widget.teacherNotes.isNotEmpty &&
        widget.teacherNotes.first['criteria'] != null) {
      criteria = List<String>.from(widget.teacherNotes.first['criteria']);
    }

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
              title: Text(
                'Review: ${submission['student']['name']}',
                style: TextStyle(color: context.textColor),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                      child: Text(
                        'File: ${submission['fileUrl'].split('/').last}',
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Criteria Review (Y/N):',
                      style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...criteria.map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                c,
                                style: TextStyle(color: context.textColor70),
                              ),
                            ),
                            DropdownButton<String>(
                              value: criteriaSelections[c],
                              dropdownColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                              style: TextStyle(color: context.textColor),
                              items: const [
                                DropdownMenuItem(
                                  value: 'Y',
                                  child: Text(
                                    'Yes (Y)',
                                    style: TextStyle(color: Colors.greenAccent),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'N',
                                  child: Text(
                                    'No (N)',
                                    style: TextStyle(color: Colors.redAccent),
                                  ),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setDialogState(() {
                                    criteriaSelections[c] = val;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
                    final res = await ApiService.put(
                      '/notes/submissions/${submission['_id']}/review',
                      {'criteriaValues': criteriaSelections},
                    );

                    if (res.statusCode == 200) {
                      Navigator.pop(ctx);
                      widget.onRefresh();
                      Navigator.pop(context); // close screen to reload
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to save review')),
                      );
                    }
                  },
                  child: Text(
                    'Save Review',
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

  void _showStudentSubmissionDetailsDialog(Map<String, dynamic> submission) {
    // Determine criteria: from teacher note or default
    List<String> criteria = [
      'Completed on time',
      'Missing content',
      'Neatness',
      'No correction',
    ];
    if (widget.teacherNotes.isNotEmpty &&
        widget.teacherNotes.first['criteria'] != null) {
      criteria = List<String>.from(widget.teacherNotes.first['criteria']);
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Text(
            'My Note Submission',
            style: TextStyle(color: context.textColor),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Title: ${submission['title']}',
                style: TextStyle(color: context.textColor70),
              ),
              Text(
                'Description: ${submission['description']}',
                style: TextStyle(color: context.textColor70),
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 16),
              Text(
                'Status: ${submission['status']}',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (submission['status'] == 'REVIEWED') ...[
                Divider(color: context.textColor54.withOpacity(0.4)),
                Text(
                  'Criteria Review:',
                  style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...criteria.map((c) {
                  final val = submission['criteriaValues']?[c] ?? 'N/A';
                  final color = val == 'Y'
                      ? Colors.greenAccent
                      : (val == 'N' ? Colors.redAccent : Colors.white70);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Row(
                      children: [
                        Icon(
                          val == 'Y'
                              ? Icons.check_circle
                              : (val == 'N'
                                    ? Icons.cancel
                                    : Icons.help_outline),
                          color: color,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            c,
                            style: TextStyle(color: context.textColor70),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  'Waiting for review...',
                  style: TextStyle(color: context.textColor60),
                ),
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

  void _showNoteDetailsDialog(Map<String, dynamic> note) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Text(
            note['title'],
            style: TextStyle(color: context.textColor),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                note['description'] ?? 'No description',
                style: TextStyle(color: context.textColor70),
              ),
              if (note['fileUrl'] != null) ...[
                const SizedBox(height: 16),
                InkWell(
                  onTap: () {
                    final url =
                        '${ApiService.baseUrl.replaceAll('/api', '')}/${note['fileUrl']}';
                    final filename = note['fileUrl'].split('/').last;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FileViewerScreen(
                          url: url,
                          filename: filename,
                          isDownloadable: note['isDownloadable'] ?? false,
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

  @override
  Widget build(BuildContext context) {
    final role = Provider.of<AuthProvider>(context, listen: false).userRole;

    bool shouldShowUploadButton = true;
    if (role == 'STUDENT' && widget.studentSubmissions.isNotEmpty) {
      shouldShowUploadButton = false;
    } else if (role != 'STUDENT' && widget.teacherNotes.isNotEmpty) {
      shouldShowUploadButton = false;
    }

    return Scaffold(
      backgroundColor: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(
          '${widget.batchName} - ${widget.sessionDate}',
          style: TextStyle(color: context.textColor, fontSize: 16),
        ),
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        iconTheme: IconThemeData(color: context.textColor),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Teacher Notes',
              style: TextStyle(color: context.textColor, fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.teacherNotes.isEmpty)
              Text(
                'No teacher notes uploaded for this session.',
                style: TextStyle(color: context.textColor54),
              )
            else
              ...widget.teacherNotes.map(
                (n) => Card(
                  color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                  child: ListTile(
                    title: Text(
                      n['title'],
                      style: TextStyle(color: context.textColor),
                    ),
                    subtitle: Text(
                      n['description'] ?? '',
                      style: TextStyle(color: context.textColor70),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (role != 'STUDENT')
                          IconButton(
                            icon: const Icon(
                              Icons.edit,
                              color: Colors.orangeAccent,
                            ),
                            onPressed: () =>
                                _showEditDialog(n, role ?? 'STUDENT', false),
                          ),
                        const Icon(
                          Icons.remove_red_eye,
                          color: Color(0xFF6366F1),
                        ),
                      ],
                    ),
                    onTap: () => _showNoteDetailsDialog(n),
                  ),
                ),
              ),

            const SizedBox(height: 32),

           Text(
              'Student Notes',
              style: TextStyle(color: context.textColor, fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.studentSubmissions.isEmpty)
               Text(
                'No student notes uploaded for this session.',
                style: TextStyle(color: context.textColor54),
              )
            else
              ...widget.studentSubmissions.map((s) {
                final isReviewed = s['status'] == 'REVIEWED';
                final isOwnSubmission = role == 'STUDENT';

                return Card(
                  color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                  child: ListTile(
                    title: Text(
                      isOwnSubmission ? s['title'] : s['student']['name'],
                      style: TextStyle(color: context.textColor),
                    ),
                    subtitle: Text(
                      isOwnSubmission ? s['description'] : s['title'],
                      style: TextStyle(color: context.textColor70),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isOwnSubmission)
                          IconButton(
                            icon: const Icon(
                              Icons.edit,
                              color: Colors.orangeAccent,
                            ),
                            onPressed: () =>
                                _showEditDialog(s, role ?? 'STUDENT', true),
                          ),
                        isOwnSubmission
                            ? Icon(
                                isReviewed ? Icons.check_circle : Icons.pending,
                                color: isReviewed
                                    ? Colors.greenAccent
                                    : Colors.orangeAccent,
                              )
                            : const Icon(
                                Icons.grading,
                                color: Color(0xFF6366F1),
                              ),
                      ],
                    ),
                    onTap: () {
                      if (role == 'STUDENT') {
                        _showStudentSubmissionDetailsDialog(s);
                      } else {
                        _showReviewDialog(s);
                      }
                    },
                  ),
                );
              }),
          ],
        ),
      ),
      floatingActionButton: shouldShowUploadButton
          ? FloatingActionButton.extended(
              onPressed: () => _showUploadDialog(role ?? 'STUDENT'),
              backgroundColor: const Color(0xFF6366F1),
              icon:Icon(Icons.upload_file, color: context.textColor),
              label:Text(
                'Upload Note',
                style: TextStyle(color: context.textColor),
              ),
            )
          : null,
    );
  }
}

