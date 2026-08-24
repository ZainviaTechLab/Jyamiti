import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../providers/auth_provider.dart';
import '../../../../providers/theme_provider.dart';
import '../../../../services/api_service.dart';
import '../../../../services/upload_service.dart';
import '../../mathpad/recording/web_recordings_storage_service.dart';
import 'web_video_player/web_video_player_view.dart';

/// Web recordings list -- with full feature parity to `TutorRecordingsScreen`:
/// - Interactive Play button with in-app HTML5 video player modal
/// - List View & Grid View toggling
/// - Save to Google Drive
/// - Upload to YouTube with tutorial linkage
/// - Share via WhatsApp / Web Share
/// - Download and Delete
class WebRecordingsScreen extends StatefulWidget {
  final bool isInline;
  const WebRecordingsScreen({super.key, this.isInline = false});

  @override
  State<WebRecordingsScreen> createState() => _WebRecordingsScreenState();
}

class _WebRecordingsScreenState extends State<WebRecordingsScreen> {
  final MathPadWebRecordingsStorageService _storage =
      MathPadWebRecordingsStorageService();
  Future<List<WebRecordingMeta>>? _recordingsFuture;
  final Set<String> _busyIds = {};
  bool _isGridView = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _recordingsFuture = _storage.listRecordings();
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    int i = 0;
    double size = bytes.toDouble();
    while (size > 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _playRecording(WebRecordingMeta meta, bool isDark) async {
    setState(() => _busyIds.add(meta.id));
    final String? blobUrl = await _storage.getRecordingBlobUrl(meta.id);
    if (!mounted) return;
    setState(() => _busyIds.remove(meta.id));

    if (blobUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load recording data for playback.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final String viewId = 'web-video-${meta.id}-${DateTime.now().millisecondsSinceEpoch}';

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            width: 820,
            constraints: const BoxConstraints(maxHeight: 640),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.play_circle_filled_rounded,
                        color: Color(0xFF6366F1),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            meta.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${_formatDate(meta.createdAt)} • ${_formatBytes(meta.sizeBytes)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.open_in_new_rounded,
                        color: isDark ? Colors.white70 : Colors.black54,
                        size: 20,
                      ),
                      tooltip: 'Open in new tab',
                      onPressed: () => openInNewTab(blobUrl),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      color: Colors.black,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: buildWebVideoPlayerWidget(
                          blobUrl: blobUrl,
                          viewId: viewId,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _download(meta),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Download'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    _storage.revokeBlobUrl(blobUrl);
  }

  Future<void> _download(WebRecordingMeta meta) async {
    setState(() => _busyIds.add(meta.id));
    final bool ok = await _storage.downloadRecording(meta.id, meta.name);
    if (!mounted) return;
    setState(() => _busyIds.remove(meta.id));
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not find this recording -- it may have been deleted.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      _refresh();
    }
  }

  Future<void> _delete(WebRecordingMeta meta) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Recording'),
        content: Text('Are you sure you want to delete "${meta.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _storage.deleteRecording(meta.id);
    if (!mounted) return;
    _refresh();
  }

  Future<void> _shareViaWhatsApp(WebRecordingMeta meta) async {
    setState(() => _busyIds.add(meta.id));
    final bytes = await _storage.loadRecordingBytes(meta.id);
    if (!mounted) return;
    setState(() => _busyIds.remove(meta.id));

    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load recording for sharing.')),
      );
      return;
    }

    try {
      final result = await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            name: meta.name,
            mimeType: meta.mimeType,
          ),
        ],
        text: 'Check out my MathPad recording: ${meta.name}',
      );
      if (result.status == ShareResultStatus.unavailable) {
        final whatsappUrl = Uri.parse(
          'https://wa.me/?text=${Uri.encodeComponent('Check out my MathPad recording: ${meta.name}')}',
        );
        if (await canLaunchUrl(whatsappUrl)) {
          await launchUrl(whatsappUrl);
        }
      }
    } catch (_) {
      final whatsappUrl = Uri.parse(
        'https://wa.me/?text=${Uri.encodeComponent('Check out my MathPad recording: ${meta.name}')}',
      );
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl);
      }
    }
  }

  void _showDriveUploadDialog(WebRecordingMeta meta, bool isDark) {
    final nameController = TextEditingController(text: meta.name);
    String? selectedFolderId;
    String selectedFolderName = 'Tutor Uploads (Root Directory)';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              child: Container(
                width: 500,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          'assets/image/drive_icon.png',
                          width: 24,
                          height: 24,
                          errorBuilder: (c, e, s) => const Icon(
                            Icons.add_to_drive,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Save to Google Drive',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_done,
                              size: 20,
                              color: Colors.blue.shade600,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Jyamiti Central Drive',
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'File Name',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Destination',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.02)
                            : Colors.grey.shade50,
                        border: Border.all(
                          color: isDark ? Colors.white24 : Colors.black12,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.folder,
                            color: isDark ? Colors.white54 : Colors.black54,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              selectedFolderName,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (c) => _FolderSelectionDialog(
                                  isDark: isDark,
                                  onSelected: (id, name) {
                                    setModalState(() {
                                      selectedFolderId =
                                          id == 'root' ? null : id;
                                      selectedFolderName = name;
                                    });
                                  },
                                ),
                              );
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1E293B),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            child: const Text('Select folder'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Video ready to save',
                              style: TextStyle(color: Colors.green),
                            ),
                          ],
                        ),
                        FilledButton(
                          onPressed: () async {
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (c) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );

                            try {
                              final bytes = await _storage
                                  .loadRecordingBytes(meta.id);
                              if (bytes == null) {
                                throw Exception('Could not load recording data');
                              }

                              await UploadService().uploadBytesToDrive(
                                bytes,
                                nameController.text.trim().isEmpty
                                    ? meta.name
                                    : nameController.text.trim(),
                                folderId: selectedFolderId,
                              );

                              if (context.mounted) {
                                Navigator.pop(context); // pop loading
                                Navigator.pop(context); // pop dialog
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Successfully uploaded to Google Drive!',
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                Navigator.pop(context); // pop loading
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Upload failed: $e'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('Save to Drive'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showYouTubeUploadDialog(WebRecordingMeta meta, bool isDark) {
    final titleController = TextEditingController(text: meta.name);
    final descController = TextEditingController(
      text: 'This video was made with Jyamiti MathPad',
    );
    final keywordsController = TextEditingController(
      text: 'Jyamiti, Math, Education',
    );
    String privacy = 'Unlisted';
    String category = 'Education';
    bool isForKids = false;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final List batches = authProvider.profile?['batches'] as List? ?? [];
    String? selectedBatchId;
    String? selectedSession;
    String? selectedChapter;
    List<String> sessionDates = [];
    List<String> chapters = [];
    bool isLoadingData = false;

    Future<void> fetchBatchDetails(
      String batchId,
      StateSetter setModalState,
    ) async {
      setModalState(() => isLoadingData = true);
      try {
        final batch = batches.firstWhere(
          (b) => (b['id'] ?? b['_id']) == batchId,
          orElse: () => null,
        );

        final courseId = batch?['course']?['id'] ?? batch?['course']?['_id'];
        if (courseId != null) {
          final res = await ApiService.get('/courses');
          if (res.statusCode == 200) {
            final List courses = jsonDecode(res.body);
            final course = courses.firstWhere(
              (c) => c['id'] == courseId || c['_id'] == courseId,
              orElse: () => null,
            );
            if (course != null && course['syllabus'] != null) {
              chapters = (course['syllabus'] as List)
                  .map((s) => s['title'].toString())
                  .toList();
            } else {
              chapters = [];
            }
          }
        }

        final res2 = await ApiService.get('/schedules/my-schedules');
        if (res2.statusCode == 200) {
          final data = jsonDecode(res2.body);
          final List schedules = data['schedules'] ?? [];
          final filtered = schedules.where((s) {
            final schedBatchId = s['batch']?['_id'] ?? s['batch'];
            return schedBatchId == batchId;
          }).toList();
          sessionDates = filtered
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
        debugPrint('Error fetching batch details: $e');
      }
      setModalState(() {
        isLoadingData = false;
        selectedSession = null;
        selectedChapter = null;
      });
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              child: Container(
                width: 650,
                padding: const EdgeInsets.all(32),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.play_circle_filled_rounded,
                            color: Colors.red,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Upload to YouTube',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.video_camera_front,
                                size: 20,
                                color: Colors.red.shade600,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Jyamiti Official Channel',
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Title',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: titleController,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: Color(0xFF6366F1),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: Color(0xFF6366F1),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Description',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: descController,
                        maxLines: 4,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      Text(
                        'Link as Tutorial (Optional)',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Select a batch to automatically submit this YouTube video as a tutorial.',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Batch / Branch',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: selectedBatchId,
                        dropdownColor:
                            isDark ? const Color(0xFF1E293B) : Colors.white,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: batches.map((b) {
                          return DropdownMenuItem<String>(
                            value: b['id'] ?? b['_id'],
                            child: Text(b['name'] ?? 'Unnamed Batch'),
                          );
                        }).toList(),
                        onChanged: (v) {
                          setModalState(() => selectedBatchId = v);
                          if (v != null) {
                            fetchBatchDetails(v, setModalState);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      if (isLoadingData)
                        const Center(child: CircularProgressIndicator())
                      else if (selectedBatchId != null) ...[
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Session Date',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    initialValue: selectedSession,
                                    dropdownColor: isDark
                                        ? const Color(0xFF1E293B)
                                        : Colors.white,
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                    ),
                                    items: sessionDates.map((e) {
                                      return DropdownMenuItem(
                                        value: e,
                                        child: Text(e),
                                      );
                                    }).toList(),
                                    onChanged: (v) => setModalState(
                                        () => selectedSession = v),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Chapter',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    initialValue: selectedChapter,
                                    dropdownColor: isDark
                                        ? const Color(0xFF1E293B)
                                        : Colors.white,
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                    ),
                                    items: chapters.map((e) {
                                      return DropdownMenuItem(
                                        value: e,
                                        child: Text(e),
                                      );
                                    }).toList(),
                                    onChanged: (v) => setModalState(
                                        () => selectedChapter = v),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Video Privacy',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black87,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  initialValue: privacy,
                                  dropdownColor: isDark
                                      ? const Color(0xFF1E293B)
                                      : Colors.white,
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                  items: ['Public', 'Unlisted', 'Private']
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(e),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) =>
                                      setModalState(() => privacy = v!),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Category',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black87,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  initialValue: category,
                                  dropdownColor: isDark
                                      ? const Color(0xFF1E293B)
                                      : Colors.white,
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                  items: [
                                    'Education',
                                    'Entertainment',
                                    'People & Blogs',
                                  ]
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(e),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) =>
                                      setModalState(() => category = v!),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Keywords',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: keywordsController,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Is this video made for kids?',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'In accordance with COPPA and other laws, we require you to tell us whether your video is made for kids.',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Theme(
                        data: Theme.of(context).copyWith(
                          unselectedWidgetColor:
                              isDark ? Colors.white54 : Colors.black54,
                        ),
                        child: RadioGroup<bool>(
                          groupValue: isForKids,
                          onChanged: (v) =>
                              setModalState(() => isForKids = v ?? false),
                          child: Column(
                            children: [
                              RadioListTile<bool>(
                                title: Text(
                                  "Yes, it's made for kids",
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    fontSize: 14,
                                  ),
                                ),
                                value: true,
                                contentPadding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                activeColor: const Color(0xFF6366F1),
                              ),
                              RadioListTile<bool>(
                                title: Text(
                                  "No, it's not made for kids",
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    fontSize: 14,
                                  ),
                                ),
                                value: false,
                                contentPadding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                activeColor: const Color(0xFF6366F1),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () async {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (c) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );

                          try {
                            final bytes =
                                await _storage.loadRecordingBytes(meta.id);
                            if (bytes == null) {
                              throw Exception('Could not load recording data');
                            }

                            final videoId =
                                await UploadService().uploadBytesToYouTube(
                              bytes: bytes,
                              title: titleController.text.trim().isEmpty
                                  ? meta.name
                                  : titleController.text.trim(),
                              description: descController.text.trim(),
                              privacyStatus: privacy,
                              categoryId: '27',
                              tags: keywordsController.text
                                  .split(',')
                                  .map((e) => e.trim())
                                  .where((e) => e.isNotEmpty)
                                  .toList(),
                              madeForKids: isForKids,
                            );

                            if (selectedBatchId != null &&
                                videoId.isNotEmpty) {
                              final ytUrl =
                                  'https://www.youtube.com/watch?v=$videoId';
                              final res = await ApiService.post('/tutorials', {
                                'batchId': selectedBatchId,
                                'title': titleController.text.trim().isEmpty
                                    ? meta.name
                                    : titleController.text.trim(),
                                'videoUrl': ytUrl,
                                'sessionDate': selectedSession ?? '',
                                'chapter': selectedChapter ?? '',
                                'description': descController.text.trim(),
                              });
                              if (res.statusCode != 201) {
                                final body = jsonDecode(res.body);
                                debugPrint(
                                  'Tutorial link failed: ${body['message']}',
                                );
                              }
                            }

                            if (context.mounted) {
                              Navigator.pop(context); // pop loading
                              Navigator.pop(context); // pop dialog
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    selectedBatchId != null
                                        ? 'Successfully uploaded to YouTube & linked to Tutorial!'
                                        : 'Successfully uploaded to YouTube!',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              Navigator.pop(context); // pop loading
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Upload failed: $e'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        child: const Text('Upload to YouTube'),
                      ),
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

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'My Recordings',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _isGridView = !_isGridView;
                        });
                      },
                      icon: Icon(
                        _isGridView
                            ? Icons.view_list_rounded
                            : Icons.grid_view_rounded,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      tooltip: _isGridView ? 'List View' : 'Grid View',
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _refresh,
                      icon: Icon(
                        Icons.refresh_rounded,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      tooltip: 'Refresh List',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Recordings made on the web version are stored in this browser '
              'only -- clearing site data or switching browsers will lose them.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: FutureBuilder<List<WebRecordingMeta>>(
                future: _recordingsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error loading recordings: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    );
                  }

                  final List<WebRecordingMeta> recordings =
                      snapshot.data ?? [];
                  if (recordings.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.video_library_outlined,
                            size: 64,
                            color: isDark ? Colors.white24 : Colors.black26,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No recordings yet.',
                            style: TextStyle(
                              fontSize: 16,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  if (_isGridView) {
                    return GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 240,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: recordings.length,
                      itemBuilder: (context, index) =>
                          _buildItem(context, recordings[index], isDark, true),
                    );
                  }

                  return ListView.separated(
                    itemCount: recordings.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) =>
                        _buildItem(context, recordings[index], isDark, false),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    WebRecordingMeta meta,
    bool isDark,
    bool isGrid,
  ) {
    final bool busy = _busyIds.contains(meta.id);
    final sizeStr = _formatBytes(meta.sizeBytes);
    final dateStr = _formatDate(meta.createdAt);

    Widget buildThumbnail({double? width, double? height}) {
      return Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Icon(
            Icons.movie_creation_rounded,
            color: Color(0xFF6366F1),
            size: 24,
          ),
        ),
      );
    }

    List<PopupMenuEntry<String>> buildMenuItems() => [
          PopupMenuItem(
            value: 'drive',
            child: Row(
              children: [
                const Icon(
                  Icons.add_to_drive_rounded,
                  color: Colors.blue,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  'Save to Drive',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'youtube',
            child: Row(
              children: [
                const Icon(
                  Icons.play_circle_filled_rounded,
                  color: Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  'Upload to YouTube',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'whatsapp',
            child: Row(
              children: [
                const Icon(
                  Icons.share_rounded,
                  color: Colors.green,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  'Share via WhatsApp',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'download',
            child: Row(
              children: [
                const Icon(
                  Icons.download_rounded,
                  color: Color(0xFF6366F1),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  'Download File',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  'Delete',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ];

    void handleMenuSelect(String value) {
      if (value == 'drive') {
        _showDriveUploadDialog(meta, isDark);
      } else if (value == 'youtube') {
        _showYouTubeUploadDialog(meta, isDark);
      } else if (value == 'whatsapp') {
        _shareViaWhatsApp(meta);
      } else if (value == 'download') {
        _download(meta);
      } else if (value == 'delete') {
        _delete(meta);
      }
    }

    if (isGrid) {
      return InkWell(
        onTap: busy ? null : () => _playRecording(meta, isDark),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black12,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: buildThumbnail(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$dateStr\n$sizeStr',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        FilledButton.icon(
                          onPressed:
                              busy ? null : () => _playRecording(meta, isDark),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            minimumSize: const Size(64, 32),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          icon: busy
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 16,
                                ),
                          label: const Text(
                            'Play',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert_rounded,
                            size: 20,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          tooltip: 'Options',
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          onSelected: handleMenuSelect,
                          itemBuilder: (context) => buildMenuItems(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black12,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: buildThumbnail(width: 44, height: 44),
        title: Text(
          meta.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Text(
            'Status: Saved • $dateStr • $sizeStr',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : () => _playRecording(meta, isDark),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Play'),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert_rounded,
                size: 20,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              tooltip: 'Options',
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              onSelected: handleMenuSelect,
              itemBuilder: (context) => buildMenuItems(),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderSelectionDialog extends StatefulWidget {
  final bool isDark;
  final void Function(String id, String name) onSelected;

  const _FolderSelectionDialog({
    required this.isDark,
    required this.onSelected,
  });

  @override
  State<_FolderSelectionDialog> createState() => _FolderSelectionDialogState();
}

class _FolderSelectionDialogState extends State<_FolderSelectionDialog> {
  bool _isLoading = true;
  List<Map<String, String>> _folders = [];

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() => _isLoading = true);
    try {
      final folders = await UploadService().listDriveFolders();
      if (mounted) {
        setState(() {
          _folders = folders;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load folders: $e')));
      }
    }
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text(
          'New Folder',
          style: TextStyle(
            color: widget.isDark ? Colors.white : Colors.black87,
          ),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(
            color: widget.isDark ? Colors.white : Colors.black87,
          ),
          decoration: const InputDecoration(hintText: 'Folder Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null && name.trim().isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        final id = await UploadService().createDriveFolder(name.trim());
        if (mounted) {
          widget.onSelected(id, name.trim());
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create folder: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Container(
        width: 400,
        height: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select Folder',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: widget.isDark ? Colors.white : Colors.black87,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: widget.isDark ? Colors.white54 : Colors.black54,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _folders.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return ListTile(
                            leading: Icon(
                              Icons.folder_shared,
                              color: Colors.blue.shade600,
                            ),
                            title: Text(
                              'Tutor Uploads (Root Directory)',
                              style: TextStyle(
                                color: widget.isDark
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onTap: () {
                              widget.onSelected(
                                'root',
                                'Tutor Uploads (Root Directory)',
                              );
                              Navigator.pop(context);
                            },
                          );
                        }
                        final folder = _folders[index - 1];
                        return ListTile(
                          leading: Icon(
                            Icons.folder,
                            color: widget.isDark
                                ? Colors.white54
                                : Colors.black54,
                          ),
                          title: Text(
                            folder['name'] ?? '',
                            style: TextStyle(
                              color: widget.isDark
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                          onTap: () {
                            widget.onSelected(
                              folder['id'] ?? '',
                              folder['name'] ?? '',
                            );
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _createFolder,
                  icon: const Icon(Icons.create_new_folder),
                  label: const Text('New Folder'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
