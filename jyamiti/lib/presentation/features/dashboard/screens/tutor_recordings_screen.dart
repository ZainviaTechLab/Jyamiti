import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../providers/theme_provider.dart';
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
        trailing: FilledButton.icon(
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
      ),
    );
  }
}
