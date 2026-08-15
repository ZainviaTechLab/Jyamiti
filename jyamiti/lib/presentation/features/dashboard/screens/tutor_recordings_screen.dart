import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../providers/theme_provider.dart';
import '../../../../services/upload_service.dart';
import '../../mathpad/recording/mathpad_recording_service.dart';

class TutorRecordingsScreen extends StatefulWidget {
  final bool isInline;
  const TutorRecordingsScreen({super.key, this.isInline = false});

  @override
  State<TutorRecordingsScreen> createState() => _TutorRecordingsScreenState();
}

class _TutorRecordingsScreenState extends State<TutorRecordingsScreen> {
  Future<List<File>>? _recordingsFuture;
  bool _isGridView = false;

  @override
  void initState() {
    super.initState();
    _refreshRecordings();
  }

  void _refreshRecordings() {
    setState(() {
      _recordingsFuture = Provider.of<MathPadRecordingService>(context, listen: false).getRecordings();
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size > 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future<void> _shareViaWhatsApp(File file) async {
    try {
      final result = await Share.shareXFiles([XFile(file.path)], text: 'Check out my MathPad recording!');
      if (result.status == ShareResultStatus.success) {
        // Shared successfully
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to share: $e')));
      }
    }
  }

  void _showDriveUploadDialog(File file, bool isDark) {
    final baseName = p.basenameWithoutExtension(file.path);
    final nameController = TextEditingController(text: baseName);
    
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    Image.asset('assets/image/drive_icon.png', width: 24, height: 24, errorBuilder: (c, e, s) => const Icon(Icons.add_to_drive, color: Colors.blue)),
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
                      child: const Icon(Icons.check, color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.close, color: isDark ? Colors.white54 : Colors.black54),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.account_circle, size: 20, color: Colors.green.shade600),
                        const SizedBox(width: 8),
                        Text('learn@jyamitimath.com', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                        const SizedBox(width: 16),
                        TextButton(
                          onPressed: () {},
                          style: TextButton.styleFrom(
                            foregroundColor: isDark ? Colors.white70 : Colors.black87,
                            backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          child: const Text('Disconnect'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('File Name', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Destination', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.02) : Colors.grey.shade50,
                    border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Text('All files', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                      const Spacer(),
                      FilledButton(
                        onPressed: () {},
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
                          child: const Icon(Icons.check, color: Colors.white, size: 12),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Video will be saved after export',
                          style: TextStyle(color: Colors.green),
                        ),
                      ],
                    ),
                    FilledButton(
                      onPressed: () async {
                        showDialog(
                          context: context, 
                          barrierDismissible: false,
                          builder: (c) => const Center(child: CircularProgressIndicator()),
                        );
                        
                        try {
                          await UploadService().uploadToDrive(file, nameController.text);
                          if (context.mounted) {
                            Navigator.pop(context); // pop loading
                            Navigator.pop(context); // pop dialog
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Successfully uploaded to Google Drive!')));
                          }
                        } catch (e) {
                          if (context.mounted) {
                            Navigator.pop(context); // pop loading
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
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
  }

  void _showYouTubeUploadDialog(File file, bool isDark) {
    final baseName = p.basenameWithoutExtension(file.path);
    final titleController = TextEditingController(text: baseName);
    final descController = TextEditingController(text: 'This video was made with Jyamiti MathPad');
    final keywordsController = TextEditingController(text: 'Jyamiti, Math, Education');
    String privacy = 'Unlisted';
    String category = 'Education';
    bool isForKids = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              child: Container(
                width: 650,
                padding: const EdgeInsets.all(32),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.account_circle, size: 20, color: Colors.green.shade600),
                              const SizedBox(width: 8),
                              Text('learn@jyamitimath.com', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                              const SizedBox(width: 16),
                              TextButton(
                                onPressed: () {},
                                style: TextButton.styleFrom(
                                  foregroundColor: isDark ? Colors.white70 : Colors.black87,
                                  backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                ),
                                child: const Text('Disconnect'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Title', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: titleController,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF6366F1))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF6366F1))),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Description', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: descController,
                        maxLines: 4,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Video Privacy', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13)),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  value: privacy,
                                  dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  ),
                                  items: ['Public', 'Unlisted', 'Private'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                  onChanged: (v) => setState(() => privacy = v!),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Category', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13)),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  value: category,
                                  dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  ),
                                  items: ['Education', 'Entertainment', 'People & Blogs'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                  onChanged: (v) => setState(() => category = v!),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Keywords', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: keywordsController,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text('Is this video made for kids?', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      Text(
                        'In accordance with the Children\'s Online Privacy Protection Act (COPPA) and other laws, we require you to tell us whether your video is made for kids.',
                        style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      Theme(
                        data: Theme.of(context).copyWith(
                          unselectedWidgetColor: isDark ? Colors.white54 : Colors.black54,
                        ),
                        child: Column(
                          children: [
                            RadioListTile<bool>(
                              title: Text('Yes, it\'s made for kids', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14)),
                              value: true,
                              groupValue: isForKids,
                              onChanged: (v) => setState(() => isForKids = v!),
                              contentPadding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              activeColor: const Color(0xFF6366F1),
                            ),
                            RadioListTile<bool>(
                              title: Text('No, it\'s not made for kids', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14)),
                              value: false,
                              groupValue: isForKids,
                              onChanged: (v) => setState(() => isForKids = v!),
                              contentPadding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              activeColor: const Color(0xFF6366F1),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text.rich(
                        TextSpan(
                          text: 'By clicking "Upload", you certify that the content you are uploading complies with the YouTube Terms of Service (including the YouTube Community Guidelines) at ',
                          children: [
                            TextSpan(text: 'https://www.youtube.com/t/terms', style: TextStyle(color: const Color(0xFF6366F1), decoration: TextDecoration.underline)),
                            TextSpan(text: '. Please be sure not to violate the copyright or privacy rights of others.'),
                          ],
                        ),
                        style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Text.rich(
                        TextSpan(
                          text: 'For more information on how YouTube in Jyamiti functions, please refer to the following ',
                          children: [
                            TextSpan(text: 'article', style: TextStyle(color: const Color(0xFF6366F1), decoration: TextDecoration.underline)),
                            TextSpan(text: '.'),
                          ],
                        ),
                        style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 12),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () async {
                          showDialog(
                            context: context, 
                            barrierDismissible: false,
                            builder: (c) => const Center(child: CircularProgressIndicator()),
                          );
                          
                          try {
                            await UploadService().uploadToYouTube(
                              video: file,
                              title: titleController.text,
                              description: descController.text,
                              privacyStatus: privacy,
                              categoryId: '27', // Education category ID for YouTube
                              tags: keywordsController.text.split(',').map((e) => e.trim()).toList(),
                              madeForKids: isForKids,
                            );
                            if (context.mounted) {
                              Navigator.pop(context); // pop loading
                              Navigator.pop(context); // pop dialog
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Successfully uploaded to YouTube!')));
                            }
                          } catch (e) {
                            if (context.mounted) {
                              Navigator.pop(context); // pop loading
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
                            }
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF38B2AC), // Teal color from screenshot
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: const Text('Upload', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

  Widget _buildActiveEncodingCard(BuildContext context, MathPadRecordingService service) {
    final bool isDark = context.isDark;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF43F5E).withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF43F5E).withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF43F5E).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.sync_rounded,
                  color: Color(0xFFF43F5E),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Video is currently encoding...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Please wait while the final MP4 is being generated. This may take a few minutes.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: service.encodingProgress > 0 ? service.encodingProgress : null,
              minHeight: 8,
              backgroundColor: const Color(0xFFF43F5E).withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF43F5E)),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${(service.encodingProgress * 100).clamp(0, 100).toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFF43F5E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;

    return Consumer<MathPadRecordingService>(
      builder: (context, recordingService, _) {
        final bool isEncoding = recordingService.state == MathPadRecordingState.encoding;
        
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
                            _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          tooltip: _isGridView ? 'List View' : 'Grid View',
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _refreshRecordings,
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
                const SizedBox(height: 32),
                
                if (isEncoding)
                  _buildActiveEncodingCard(context, recordingService),
                  
                Expanded(
                  child: FutureBuilder<List<File>>(
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
                      
                      final files = snapshot.data ?? [];
                      
                      if (files.isEmpty && !isEncoding) {
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
                                'No recordings found.',
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
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 240,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.85,
                          ),
                          itemCount: files.length,
                          itemBuilder: (context, index) => _buildItem(context, files[index], isDark, true),
                        );
                      }

                      return ListView.separated(
                        itemCount: files.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => _buildItem(context, files[index], isDark, false),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildItem(BuildContext context, File file, bool isDark, bool isGrid) {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final baseName = p.basenameWithoutExtension(file.path);
    final parentDir = file.parent.path;
    final thumbnailFile = File(p.join(parentDir, '.thumbnails', '$baseName.png'));

    int fileSize = 0;
    DateTime? date;
    try {
      if (file.existsSync()) {
        fileSize = file.lengthSync();
        date = file.lastModifiedSync();
      }
    } catch (_) {}

    final sizeStr = _formatBytes(fileSize);
    final dateStr = date != null
        ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
        : 'Unknown Date';

    Widget buildThumbnail({double? width, double? height}) {
      return thumbnailFile.existsSync()
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                thumbnailFile,
                width: width,
                height: height,
                fit: BoxFit.cover,
              ),
            )
          : Container(
              width: width,
              height: height,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.movie_creation_rounded,
                color: Color(0xFF6366F1),
              ),
            );
    }

    if (isGrid) {
      return InkWell(
        onTap: () async {
          final uri = Uri.file(file.path);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black12,
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
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FutureBuilder<String>(
                      future: context.read<MathPadRecordingService>().getVideoDuration(file.path),
                      builder: (context, durationSnapshot) {
                        final durationStr = durationSnapshot.data ?? '';
                        final durationPart = durationStr.isNotEmpty ? '$durationStr • ' : '';
                        return Text(
                          '$durationPart$dateStr\n$sizeStr',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert_rounded, size: 20, color: isDark ? Colors.white70 : Colors.black54),
                          tooltip: 'Options',
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          onSelected: (value) {
                            if (value == 'drive') {
                              _showDriveUploadDialog(file, isDark);
                            } else if (value == 'youtube') {
                              _showYouTubeUploadDialog(file, isDark);
                            } else if (value == 'whatsapp') {
                              _shareViaWhatsApp(file);
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'drive',
                              child: Row(
                                children: [
                                  const Icon(Icons.add_to_drive_rounded, color: Colors.blue, size: 20),
                                  const SizedBox(width: 12),
                                  Text('Save to Drive', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'youtube',
                              child: Row(
                                children: [
                                  const Icon(Icons.play_circle_filled_rounded, color: Colors.red, size: 20),
                                  const SizedBox(width: 12),
                                  Text('Upload to YouTube', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'whatsapp',
                              child: Row(
                                children: [
                                  const Icon(Icons.share_rounded, color: Colors.green, size: 20),
                                  const SizedBox(width: 12),
                                  Text('Share via WhatsApp', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                                ],
                              ),
                            ),
                          ],
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
          fileName,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: FutureBuilder<String>(
            future: context.read<MathPadRecordingService>().getVideoDuration(file.path),
            builder: (context, durationSnapshot) {
              final durationStr = durationSnapshot.data ?? '';
              final durationPart = durationStr.isNotEmpty ? ' • $durationStr' : '';
              return Text(
                'Status: Saved$durationPart • $dateStr • $sizeStr',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              );
            },
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, size: 20, color: isDark ? Colors.white70 : Colors.black54),
              tooltip: 'Options',
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onSelected: (value) {
                if (value == 'drive') {
                  _showDriveUploadDialog(file, isDark);
                } else if (value == 'youtube') {
                  _showYouTubeUploadDialog(file, isDark);
                } else if (value == 'whatsapp') {
                  _shareViaWhatsApp(file);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'drive',
                  child: Row(
                    children: [
                      const Icon(Icons.add_to_drive_rounded, color: Colors.blue, size: 20),
                      const SizedBox(width: 12),
                      Text('Save to Drive', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'youtube',
                  child: Row(
                    children: [
                      const Icon(Icons.play_circle_filled_rounded, color: Colors.red, size: 20),
                      const SizedBox(width: 12),
                      Text('Upload to YouTube', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'whatsapp',
                  child: Row(
                    children: [
                      const Icon(Icons.share_rounded, color: Colors.green, size: 20),
                      const SizedBox(width: 12),
                      Text('Share via WhatsApp', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () async {
                final uri = Uri.file(file.path);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Play'),
            ),
          ],
        ),
      ),
    );
  }
}
