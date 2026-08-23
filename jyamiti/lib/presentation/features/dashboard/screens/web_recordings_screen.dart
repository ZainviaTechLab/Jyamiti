import 'package:flutter/material.dart';

import '../../../../providers/theme_provider.dart';
import '../../mathpad/recording/web_recordings_storage_service.dart';

/// Web's own recordings list -- the equivalent of `TutorRecordingsScreen`
/// for `MathPadWebRecordingService`'s output. Deliberately much simpler
/// than that screen (no Drive/YouTube/WhatsApp sharing, no "Play" via a
/// native file path -- none of which map onto web's IndexedDB-backed
/// storage the same way, and weren't worth forcing): just a list, a
/// Download button per recording (the only thing actually asked for), and
/// Delete. Recordings land here via `MathPadWebRecordingService.stop()` ->
/// `mathpad.dart`'s `_stopWebRecording` -> `saveRecording` -- never an
/// automatic download.
class WebRecordingsScreen extends StatefulWidget {
  final bool isInline;
  const WebRecordingsScreen({super.key, this.isInline = false});

  @override
  State<WebRecordingsScreen> createState() => _WebRecordingsScreenState();
}

class _WebRecordingsScreenState extends State<WebRecordingsScreen> {
  final MathPadWebRecordingsStorageService _storage = MathPadWebRecordingsStorageService();
  Future<List<WebRecordingMeta>>? _recordingsFuture;
  final Set<String> _busyIds = {};

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
    await _storage.deleteRecording(meta.id);
    if (!mounted) return;
    _refresh();
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

                  final List<WebRecordingMeta> recordings = snapshot.data ?? [];
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

                  return ListView.separated(
                    itemCount: recordings.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) =>
                        _buildItem(context, recordings[index], isDark),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, WebRecordingMeta meta, bool isDark) {
    final bool busy = _busyIds.contains(meta.id);
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
        leading: Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.movie_creation_rounded, color: Color(0xFF6366F1)),
        ),
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
            '${_formatDate(meta.createdAt)} • ${_formatBytes(meta.sizeBytes)}',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: busy ? null : () => _delete(meta),
              icon: Icon(
                Icons.delete_outline_rounded,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
              tooltip: 'Delete',
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: busy ? null : () => _download(meta),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download'),
            ),
          ],
        ),
      ),
    );
  }
}
