import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum MathPadRecordingState { idle, recording, encoding }

class MathPadRecordingException implements Exception {
  final String message;
  MathPadRecordingException(this.message);
  @override
  String toString() => message;
}

/// Records the Math Pad canvas (not the whole screen/window) plus
/// microphone narration into one .mp4 -- Windows only.
///
/// The "video" side is just repeated `RenderRepaintBoundary.toImage()`
/// snapshots of the canvas (the same technique `ThemeReveal` already uses
/// for its transition screenshot) written out as numbered PNG frames,
/// since Flutter has no built-in screen/window capture or video encoder.
/// [stop] hands those frames + the recorded WAV audio to a bundled
/// `ffmpeg.exe` (installed next to the app exe by the Windows build, see
/// `windows/CMakeLists.txt`) to mux/encode into the final video.
class MathPadRecordingService {
  MathPadRecordingService();

  // 60fps to match how fluid the live drawing itself already feels (the
  // canvas's own live-stroke overlay repaints at up to 120fps). The
  // frame-catch-up path below keeps the recording truthful to real
  // elapsed time even on hardware that can't quite sustain a genuine
  // 60 unique captures/sec on a particularly busy board -- worst case it
  // holds a frame for an extra tick rather than falling behind or
  // desyncing from the audio track.
  static const int fps = 60;
  // Never capture at a higher resolution than this on the long edge --
  // recording at the full raw devicePixelRatio (2x-3x+ on many modern
  // Windows displays) roughly quadruples PNG-encode/disk-write time per
  // frame for detail a whiteboard recording doesn't need, which is exactly
  // what makes capture more likely to fall behind and fall back to
  // duplicate/"held" frames (visible as stutter) in the first place.
  static const double _maxCapturePixelRatio = 1.5;

  final AudioRecorder _audioRecorder = AudioRecorder();
  Timer? _frameTimer;
  bool _frameCallbackRegistered = false;
  bool _captureInFlight = false;
  Directory? _sessionDir;
  int _frameCount = 0;
  DateTime? _startedAt;
  GlobalKey? _canvasKey;

  MathPadRecordingState _state = MathPadRecordingState.idle;
  MathPadRecordingState get state => _state;
  Duration elapsed = Duration.zero;

  /// Called on every state change and roughly once a second while
  /// recording (to update the elapsed-time badge).
  void Function(MathPadRecordingState state, Duration elapsed)? onUpdate;

  /// Windows-only feature -- no bundled ffmpeg exists for other platforms,
  /// and mobile/web would need an entirely different capture mechanism.
  static bool get isSupportedPlatform => Platform.isWindows;

  /// [canvasKey] must point at a `RepaintBoundary` that already paints a
  /// fully opaque background itself (Math Pad's capture area does) --
  /// this service just snapshots it as-is, no post-capture compositing.
  Future<void> start(GlobalKey canvasKey) async {
    if (_state != MathPadRecordingState.idle) return;
    if (!Platform.isWindows) {
      throw MathPadRecordingException(
        'Recording is only available on Windows right now.',
      );
    }

    bool hasMicPermission;
    try {
      hasMicPermission = await _audioRecorder.hasPermission();
    } catch (e) {
      throw MathPadRecordingException('Could not access the microphone: $e');
    }
    if (!hasMicPermission) {
      throw MathPadRecordingException(
        'Microphone permission was denied -- allow it in Windows Settings '
        '> Privacy > Microphone to record narration.',
      );
    }

    final Directory tempRoot = await getTemporaryDirectory();
    final String sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final Directory sessionDir = Directory(
      '${tempRoot.path}\\mathpad_recording_$sessionId',
    );
    await sessionDir.create(recursive: true);

    try {
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: '${sessionDir.path}\\audio.wav',
      );
    } catch (e) {
      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
      }
      throw MathPadRecordingException('Could not start audio recording: $e');
    }

    _sessionDir = sessionDir;
    _canvasKey = canvasKey;
    _frameCount = 0;
    _startedAt = DateTime.now();
    elapsed = Duration.zero;
    _state = MathPadRecordingState.recording;
    _emit();

    // Primary capture trigger: a callback tied to Flutter's own vsync-synced
    // frame scheduling, so a capture attempt happens right when the engine
    // actually renders a new frame -- not on a guessed wall-clock interval.
    // `Timer.periodic` alone can jitter a few ms early/late at a 60fps
    // (16.7ms) period on Windows, since Dart timers aren't held to a higher
    // resolution than the OS default (~15.6ms) unless something raises it;
    // that uneven pacing is visible as stutter even when every captured
    // frame is genuinely unique. `_captureFrame` already self-throttles to
    // `fps` via `_targetFrameCountNow`, so firing this on every real repaint
    // (which can be more frequent than `fps` on a high-refresh-rate display)
    // is safe -- most calls are a no-op check.
    //
    // A `PersistentFrameCallback` can't be unregistered once added, so it's
    // registered once for this service's lifetime rather than per
    // recording, and gates its own work on `_state`.
    if (!_frameCallbackRegistered) {
      _frameCallbackRegistered = true;
      SchedulerBinding.instance.addPersistentFrameCallback((_) {
        if (_state == MathPadRecordingState.recording) {
          unawaited(_captureFrame());
        }
      });
    }

    // Backstop: guarantees frames keep getting produced even during a
    // stretch where nothing on the board is changing and Flutter isn't
    // scheduling any new frames on its own (e.g. the tutor pauses drawing
    // to talk) -- otherwise the frame callback above would simply never
    // fire during that stretch, and the video would desync from the
    // real-time-length audio track.
    _frameTimer = Timer.periodic(
      const Duration(milliseconds: 1000 ~/ fps),
      (_) => _captureFrame(),
    );
  }

  int _targetFrameCountNow() {
    if (_startedAt == null) return 0;
    return (DateTime.now().difference(_startedAt!).inMilliseconds * fps / 1000)
        .floor();
  }

  Future<void> _captureFrame() async {
    if (_captureInFlight || _sessionDir == null || _startedAt == null) return;
    // Nothing new due yet -- capturing again right now would just be a
    // needless duplicate of the last frame.
    if (_targetFrameCountNow() <= _frameCount) return;

    _captureInFlight = true;
    try {
      final RenderObject? renderObject = _canvasKey
          ?.currentContext
          ?.findRenderObject();
      if (renderObject is RenderRepaintBoundary) {
        final double pixelRatio = min(
          ui.PlatformDispatcher.instance.views.first.devicePixelRatio,
          _maxCapturePixelRatio,
        );
        // A single capture straight to PNG -- the capture area itself now
        // paints a guaranteed-opaque backdrop as its bottom layer (see
        // `_buildCanvasCaptureArea` in mathpad.dart), so there's no need to
        // re-rasterize a second composited image over a background colour
        // here like before. That extra PictureRecorder+Canvas+toImage()
        // round trip was roughly doubling the cost of every captured frame
        // -- cutting it out is what actually lets capture keep up with a
        // high fps target instead of falling behind and holding/duplicating
        // frames (the real cause of visible stutter, not the fps number
        // itself).
        final ui.Image image = await renderObject.toImage(
          pixelRatio: pixelRatio,
        );

        final ByteData? bytes = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        image.dispose();
        if (bytes != null && _sessionDir != null) {
          final Uint8List pngBytes = bytes.buffer.asUint8List();
          // The capture above (toImage + PNG-encode) can take longer than
          // one frame interval on a big/complex board, so more
          // than one frame-slot may be due by the time it finishes.
          // Writing this same just-captured frame into every due slot
          // keeps the final video's length truthful to how long the
          // recording actually ran -- otherwise a slow capture would
          // quietly make the video shorter than the on-screen timer, and
          // since `stop()` mixes it with a real-time-length audio track
          // using `-shortest`, that would also chop the tail off the
          // narration to match.
          final int fillTo = max(_targetFrameCountNow(), _frameCount + 1);
          for (int n = _frameCount + 1; n <= fillTo; n++) {
            final File file = File(
              '${_sessionDir!.path}\\frame_${n.toString().padLeft(6, '0')}.png',
            );
            await file.writeAsBytes(pngBytes);
          }
          _frameCount = fillTo;
        }
      }
    } catch (_) {
      // One missed frame isn't worth aborting the whole recording over.
    } finally {
      _captureInFlight = false;
    }
    if (_startedAt != null) {
      elapsed = DateTime.now().difference(_startedAt!);
    }
    _emit();
  }

  /// Stops capturing, encodes what was captured into an .mp4 via the
  /// bundled ffmpeg, saves it under Documents\Jyamiti Recordings, and
  /// returns the final file path. Throws [MathPadRecordingException] on
  /// failure (nothing captured, ffmpeg missing/failed, etc.) -- always
  /// clears the temp session first either way.
  Future<String> stop() async {
    if (_state != MathPadRecordingState.recording) {
      throw MathPadRecordingException('Not currently recording.');
    }
    _frameTimer?.cancel();
    _frameTimer = null;
    // Let any in-flight frame capture finish before we start reading
    // `_frameCount`/muxing, instead of racing it.
    while (_captureInFlight) {
      await Future.delayed(const Duration(milliseconds: 20));
    }

    String? audioPath;
    try {
      audioPath = await _audioRecorder.stop();
    } catch (e) {
      // The mic recorder failing to stop cleanly shouldn't leave this
      // service stuck thinking it's still "recording" forever (with no
      // way for the UI to retry) -- fall through with no audio track
      // rather than aborting the whole capture.
      audioPath = null;
    }
    final Directory sessionDir = _sessionDir!;
    final int frameCount = _frameCount;
    _sessionDir = null;
    _canvasKey = null;

    _state = MathPadRecordingState.encoding;
    _emit();

    Future<void> cleanup() async {
      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
      }
    }

    if (frameCount == 0) {
      await cleanup();
      _state = MathPadRecordingState.idle;
      _emit();
      throw MathPadRecordingException(
        'Nothing was captured -- the recording was too short.',
      );
    }

    try {
      final String ffmpegPath = _resolveFfmpegPath();
      if (!await File(ffmpegPath).exists()) {
        throw MathPadRecordingException(
          'ffmpeg.exe wasn\'t found next to the app -- recording can\'t be '
          'encoded.',
        );
      }

      final Directory outDir = await _ensureRecordingsDir();
      final String outPath =
          '${outDir.path}\\MathPad_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final List<String> args = [
        '-y',
        '-framerate', '$fps',
        // Frames are written starting at frame_000001.png (index 1), but
        // ffmpeg's image2 demuxer defaults to looking for index 0 first --
        // without this it never finds frame_000000.png and fails outright
        // before encoding anything.
        '-start_number', '1',
        '-i', '${sessionDir.path}\\frame_%06d.png',
        if (audioPath != null) ...['-i', audioPath],
        // yuv420p (4:2:0 chroma subsampling) requires both dimensions to
        // be even -- the captured canvas size is whatever the window
        // happens to be, which is very often NOT even in both directions,
        // and libx264 flatly refuses (rather than rounding) an odd
        // width/height. Trimming at most 1px off the right/bottom is
        // imperceptible; the alternative (padding) would add a visible
        // border instead.
        '-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2',
        '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p',
        '-preset', 'medium',
        '-crf', '18',
        if (audioPath != null) ...[
          // Raw mic input volume varies a lot by device/distance/OS input
          // gain -- loudnorm brings it up to a consistent, clearly audible
          // loudness (EBU R128 standard target for spoken content) instead
          // of just passing through whatever level the mic happened to
          // capture, without a fixed gain multiplier risking clipping on
          // recordings that were already loud enough.
          '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11',
          '-c:a', 'aac',
          '-b:a', '192k',
          '-shortest',
        ],
        outPath,
      ];

      final ProcessResult result;
      try {
        result = await Process.run(ffmpegPath, args);
      } on ProcessException catch (e) {
        throw MathPadRecordingException('Could not run ffmpeg: ${e.message}');
      }
      if (result.exitCode != 0) {
        // Surface ffmpeg's own stderr (its actual reason) instead of just
        // the exit code, so a failure like this is diagnosable from the
        // error message alone next time instead of needing to reproduce it.
        final String stderrText = result.stderr is String
            ? result.stderr as String
            : result.stderr.toString();
        final String tail = stderrText.trim().isEmpty
            ? '(no stderr output)'
            : stderrText
                  .trim()
                  .split('\n')
                  .reversed
                  .take(5)
                  .toList()
                  .reversed
                  .join('\n');
        throw MathPadRecordingException(
          'Encoding failed (ffmpeg exit ${result.exitCode}):\n$tail',
        );
      }
      return outPath;
    } finally {
      await cleanup();
      _state = MathPadRecordingState.idle;
      _emit();
    }
  }

  /// Discards an in-progress recording without encoding anything.
  Future<void> cancel() async {
    if (_state != MathPadRecordingState.recording) return;
    _frameTimer?.cancel();
    _frameTimer = null;
    await _audioRecorder.stop();
    final Directory? sessionDir = _sessionDir;
    _sessionDir = null;
    _canvasKey = null;
    if (sessionDir != null && await sessionDir.exists()) {
      await sessionDir.delete(recursive: true);
    }
    _state = MathPadRecordingState.idle;
    _emit();
  }

  String _resolveFfmpegPath() {
    final String exeDir = File(Platform.resolvedExecutable).parent.path;
    return '$exeDir\\ffmpeg.exe';
  }

  Future<Directory> _ensureRecordingsDir() async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory recordings = Directory('${docs.path}\\Jyamiti Recordings');
    if (!await recordings.exists()) {
      await recordings.create(recursive: true);
    }
    return recordings;
  }

  void _emit() => onUpdate?.call(_state, elapsed);

  Future<void> dispose() async {
    _frameTimer?.cancel();
    await _audioRecorder.dispose();
  }
}
