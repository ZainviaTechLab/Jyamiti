import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:jyamiti/services/api_service.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoId;
  final String title;
  /// Pass the assignment ID to enable the 80% watch completion feature.
  /// When null, the screen behaves as a regular video viewer.
  final String? assignmentId;
  /// Called when the student marks the assignment as completed.
  final VoidCallback? onCompleted;

  const VideoPlayerScreen({
    super.key,
    required this.videoId,
    required this.title,
    this.assignmentId,
    this.onCompleted,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late YoutubePlayerController _controller;
  bool _showCompletionButton = false;
  bool _isCompleting = false;
  bool _alreadyCompleted = false;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        mute: false,
        showFullscreenButton: true,
      ),
    );

    // Poll for position updates to detect 80% watch threshold
    if (widget.assignmentId != null) {
      _progressTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _checkWatchProgress();
      });
    }
  }

  Future<void> _checkWatchProgress() async {
    if (_alreadyCompleted || _showCompletionButton) {
      _progressTimer?.cancel();
      return;
    }
    try {
      // Both currentTime and duration are async in youtube_player_flutter v10.
      // Using _controller.metadata.duration returns Duration.zero until metadata
      // loads, so we must use the Future-based _controller.duration instead.
      final positionSeconds = await _controller.currentTime;
      final durationSeconds = await _controller.duration;
      if (durationSeconds > 0 && positionSeconds > 0) {
        final progress = positionSeconds / durationSeconds;
        if (progress >= 0.8) {
          if (mounted) {
            setState(() => _showCompletionButton = true);
          }
          _progressTimer?.cancel();
        }
      }
    } catch (_) {
      // Controller may not be ready yet; ignore and retry on next tick
    }
  }

  Future<void> _markAsCompleted() async {
    if (_isCompleting || _alreadyCompleted) return;
    setState(() => _isCompleting = true);

    try {
      final res = await ApiService.completeAssignment(widget.assignmentId!);
      if (res.statusCode == 200) {
        setState(() {
          _alreadyCompleted = true;
          _isCompleting = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Assignment marked as completed!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          widget.onCompleted?.call();
          Navigator.pop(context);
        }
      } else {
        setState(() => _isCompleting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to mark as completed. Please try again.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isCompleting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title, style: TextStyle(color: context.textColor, fontSize: 16)),
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        iconTheme: IconThemeData(color: context.textColor),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 850),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 80),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                YoutubePlayer(
                  controller: _controller,
                ),
                // 80% completion button (only for assignments)
                if (widget.assignmentId != null) ...[
                  const SizedBox(height: 32),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: _showCompletionButton && !_alreadyCompleted
                        ? Padding(
                            key: const ValueKey('completion_btn'),
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withOpacity(0.4),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _isCompleting ? null : _markAsCompleted,
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        if (_isCompleting)
                                          const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                          )
                                        else
                                          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 24),
                                        const SizedBox(width: 12),
                                        Text(
                                          _isCompleting ? 'Marking as completed...' : 'I have completed watching',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : !_showCompletionButton
                            ? Padding(
                                key: const ValueKey('watch_more'),
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.info_outline_rounded, color: Colors.white38, size: 16),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Watch 80% of the video to mark as completed',
                                      style: TextStyle(color: Colors.white38, fontSize: 13),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
