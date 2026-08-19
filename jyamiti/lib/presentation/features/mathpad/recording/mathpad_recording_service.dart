import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum MathPadRecordingState { idle, recording, waitingForEncodeChoice, encoding }

class MathPadRecordingException implements Exception {
  final String message;
  MathPadRecordingException(this.message);
  @override
  String toString() => message;
}

/// Records the Math Pad canvas (not the whole screen/window) plus
/// microphone narration into one .mp4 -- Windows only.
///
/// Optionally also a small webcam picture-in-picture box, baked into the
/// exported video only (never shown live on the canvas while drawing) --
/// see `start`'s `includeCamera` and the "Camera capture" section below.
/// That webcam side runs as its own completely independent `ffmpeg`
/// process capturing straight from the DirectShow device to its own file
/// for the whole session, and is only ever combined with the canvas video
/// as a SEPARATE overlay pass after the normal (unchanged) canvas encode
/// below has already finished and produced a complete, valid video on its
/// own. That ordering is deliberate: the canvas capture/encode path here
/// is never touched or made conditional on the camera in any way, so a
/// plain recording (`includeCamera: false`, the default) behaves
/// identically to before this existed, and a camera failure of any kind
/// (no webcam, permission denied, overlay pass errors out) can only ever
/// cost the camera video-in-video, never the underlying recording.
///
/// The "video" side is repeated `RenderRepaintBoundary.toImage()` snapshots
/// of the canvas (the same technique `ThemeReveal` already uses for its
/// transition screenshot), since Flutter has no built-in screen/window
/// capture or video encoder. A snapshot only gets written to disk as a new
/// PNG frame when it's actually different from the last one written --
/// otherwise the stretch of time it covers (the board sitting idle while
/// the tutor talks, or a slow capture falling behind) is just added as
/// extra hold-duration on that existing frame, tracked in `_concatEntries`.
/// This keeps both disk I/O during a long recording and ffmpeg's work at
/// `stop()` proportional to how much actually changed on the board, not to
/// how long the recording ran. [stop] hands that frame set (as a concat
/// manifest -- see `stop()`) + the recorded WAV audio to a bundled
/// `ffmpeg.exe` (installed next to the app exe by the Windows build, see
/// `windows/CMakeLists.txt`) to mux/encode into the final video.
class MathPadRecordingService extends ChangeNotifier {
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
  // `_frameCount` is the *timeline* position in 1/fps slots (used to keep
  // the video's length truthful to real elapsed time, same as before).
  // It's no longer 1:1 with the number of PNG files actually written --
  // see `_lastFrameBytes` below.
  int _frameCount = 0;
  DateTime? _startedAt;
  GlobalKey? _canvasKey;

  // How much later than `_startedAt` (the video timeline's own zero point)
  // each OTHER capture stream actually started, in seconds -- measured,
  // not assumed, so `encode()`/`_overlayCamera` can shift each stream
  // later by exactly this much via ffmpeg's `-itsoffset` and keep
  // everything genuinely aligned instead of just hoping the streams
  // happened to start close enough together. See their measurement sites
  // in `start()` for what each one actually bounds.
  double _audioStartOffsetSeconds = 0.0;
  double _cameraStartOffsetSeconds = 0.0;

  // Intermediate state for delayed encode choice
  List<_ConcatEntry>? _capturedConcatEntries;
  Directory? _capturedSessionDir;
  bool _capturedCameraWasEnabled = false;
  String? _capturedAudioPath;
  double _capturedAudioStartOffsetSeconds = 0.0;
  double _capturedCameraStartOffsetSeconds = 0.0;

  // Byte-for-byte content of the most recently *written* frame, so an
  // unchanged board (the tutor pausing to talk, or a slow capture falling
  // behind on a static frame) doesn't get re-encoded and rewritten to disk
  // on every single 1/fps tick. A long recording spends most of its time
  // with nothing actually changing on screen, so skipping those repeats
  // is what keeps both disk I/O during capture and ffmpeg's decode work
  // at `stop()` proportional to how much the board actually changed, not
  // to how long the recording ran.
  Uint8List? _lastFrameBytes;
  int _writtenFrameIndex = 0;
  final List<_ConcatEntry> _concatEntries = [];

  // ─── Camera capture (optional, additive -- see the class doc above) ────
  // Entirely separate from everything above: its own ffmpeg process
  // writing its own file, started/stopped alongside the canvas
  // capture/mic but never read from or written into by any of it.
  Process? _cameraProcess;
  bool _cameraEnabled = false;

  MathPadRecordingState _state = MathPadRecordingState.idle;
  MathPadRecordingState get state => _state;
  Duration elapsed = Duration.zero;

  /// 0..1 once encoding starts producing real output -- parsed from
  /// ffmpeg's own `-progress` stream in `stop()`, not estimated.
  double encodingProgress = 0.0;

  /// Called on every state change and roughly once a second while
  /// recording (to update the elapsed-time badge).
  void Function(MathPadRecordingState state, Duration elapsed)? onUpdate;

  /// Called (throttled to a few times a second) with `encodingProgress`
  /// while `state == encoding`, so the UI can show a real percentage
  /// instead of an indeterminate spinner.
  void Function(double progress)? onEncodingProgress;

  /// Fired if a `start(includeCamera: true)` recording's camera couldn't
  /// be captured or added to the final video, for any reason (no webcam,
  /// permission denied, the overlay pass itself failing) -- purely
  /// informational, never thrown, since none of those should ever cost
  /// the tutor the actual recording (which is already saved by the time
  /// any camera-overlay failure could happen).
  void Function(String message)? onCameraWarning;

  /// Fired only during a camera-enabled recording's `stop()`, right as
  /// encoding moves from the normal canvas pass into the second
  /// camera-overlay pass -- lets the UI swap "Encoding…" for something
  /// like "Adding camera…" instead of the progress bar silently
  /// restarting from 0% with no explanation. Never fired at all for a
  /// plain recording, so existing (no-camera) UI text is unaffected.
  void Function(String label)? onEncodingPhaseChanged;

  /// Windows-only feature -- no bundled ffmpeg exists for other platforms,
  /// and mobile/web would need an entirely different capture mechanism.
  static bool get isSupportedPlatform => Platform.isWindows || Platform.isMacOS;

  /// Best-effort probe for a usable webcam, so the UI can grey out/hide
  /// the camera toggle up front instead of the tutor only finding out
  /// "no camera" after already hitting Record.
  Future<bool> hasCamera() async => (await _detectCameraDeviceName()) != null;

  /// Parses ffmpeg's own `-f dshow -list_devices true` output (it prints
  /// the device list to stderr as a side effect of intentionally failing
  /// to open the fake "dummy" device) to find the first available video
  /// capture device's exact name, e.g. `"Integrated Camera"` -- the form
  /// `-f dshow -i video="<name>"` needs. Returns null (never throws) on
  /// anything going wrong, from "ffmpeg missing" to "no camera plugged
  /// in" to "ffmpeg's output format changed" -- every caller treats null
  /// as just "no camera available" and degrades gracefully.
  Future<String?> _detectCameraDeviceName() async {
    final String ffmpegPath = _resolveFfmpegPath();
    if (!await File(ffmpegPath).exists()) return null;
    ProcessResult result;
    try {
      if (Platform.isMacOS) {
        result = await Process.run(ffmpegPath, [
          '-hide_banner',
          '-f', 'avfoundation',
          '-list_devices', 'true',
          '-i', '""',
        ]);
      } else {
        result = await Process.run(ffmpegPath, [
          '-hide_banner',
          '-f', 'dshow',
          '-list_devices', 'true',
          '-i', 'dummy',
        ]);
      }
    } catch (_) {
      return null;
    }
    final String output = result.stderr is String
        ? result.stderr as String
        : result.stderr.toString();
        
    if (Platform.isMacOS) {
      bool inVideoSection = false;
      for (final rawLine in output.split('\n')) {
        final String line = rawLine.trim();
        if (line.contains('AVFoundation video devices:')) {
          inVideoSection = true;
          continue;
        }
        if (line.contains('AVFoundation audio devices:')) {
          inVideoSection = false;
          continue;
        }
        if (inVideoSection) {
          final match = RegExp(r'\[(\d+)\]').firstMatch(line);
          if (match != null) return match.group(1);
        }
      }
      return null;
    }

    bool inVideoSection = false;
    for (final rawLine in output.split('\n')) {
      final String line = rawLine.trim();
      
      // Modern ffmpeg output includes "(video)" inline.
      if (line.contains('(video)')) {
        final match = RegExp(r'"([^"]+)"').firstMatch(line);
        if (match != null) return match.group(1);
      }

      if (line.contains('DirectShow video devices')) {
        inVideoSection = true;
        continue;
      }
      if (line.contains('DirectShow audio devices')) {
        inVideoSection = false;
        continue;
      }
      // Skip a device's "Alternative name" sub-line -- only the primary
      // friendly name (what `-i video="..."` expects) is wanted.
      if (inVideoSection && !line.contains('Alternative name')) {
        final match = RegExp(r'"([^"]+)"').firstMatch(line);
        if (match != null) return match.group(1);
      }
    }
    return null;
  }

  /// Gracefully finishes the camera ffmpeg process (if one was started)
  /// by writing 'q' to its stdin -- the standard way to tell an
  /// interactive ffmpeg process to finish and flush its output cleanly;
  /// just killing it can leave `camera.mp4` without a valid trailer.
  /// Falls back to a hard kill if it doesn't exit promptly, so callers
  /// (`stop()`/`cancel()`) can never hang waiting on this.
  Future<void> _stopCameraCapture() async {
    final Process? process = _cameraProcess;
    _cameraProcess = null;
    if (process == null) return;
    try {
      process.stdin.writeln('q');
      await process.stdin.flush();
    } catch (_) {}
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
    }
  }

  /// [canvasKey] must point at a `RepaintBoundary` that already paints a
  /// fully opaque background itself (Math Pad's capture area does) --
  /// this service just snapshots it as-is, no post-capture compositing.
  ///
  /// [includeCamera] (default false, so every existing call site behaves
  /// exactly as before) additionally starts an independent webcam capture
  /// alongside the canvas/mic -- see the class doc comment. Any camera
  /// failure (no device, permission denied) only ever disables the
  /// camera for this recording (reported via [onCameraWarning]); it never
  /// prevents or aborts the recording itself the way a mic failure does.
  Future<void> start(GlobalKey canvasKey, {bool includeCamera = false}) async {
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
      p.join(tempRoot.path, 'mathpad_recording_$sessionId'),
    );
    await sessionDir.create(recursive: true);

    // The video timeline's zero point -- set as the very first thing in
    // this function's real capture-triggering work, immediately before
    // asking the mic to start, rather than after (the old ordering set
    // this only once audio.start() had already resolved, so the WAV file
    // always began recording measurably before the video's own t=0,
    // permanently offsetting the audio ahead of the picture). Every
    // capture stream's actual start latency is measured relative to THIS
    // instant and compensated for at mux time in `encode()`/
    // `_overlayCamera` via ffmpeg's `-itsoffset`, rather than assumed away.
    _startedAt = DateTime.now();
    elapsed = Duration.zero;

    try {
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          // Matches the sample rate Windows' own WASAPI shared-mode audio
          // engine mixes at by default (48kHz) -- capturing at the
          // historical default of 44.1kHz instead forces an extra
          // resample step in the OS audio pipeline before it ever reaches
          // this app, a real (if subtle) source of quality loss for no
          // benefit. This is what "the natural Windows setting" actually
          // means at the API level: matching the engine's own native
          // format instead of a value that predates it.
          sampleRate: 48000,
          // A single presenter's narration is a mono source -- recording
          // stereo just duplicates that one mic channel into both L/R
          // (bigger file, zero real quality gain) and risks an audible
          // channel imbalance on drivers that don't upmix cleanly.
          numChannels: 1,
          // Device-level noise suppression/auto-gain (where the input
          // device actually supports it) -- complements, rather than
          // replaces, the `loudnorm` normalization already applied at
          // encode time below. `echoCancel` deliberately left off: it
          // exists for two-way calls with a live speaker output feeding
          // back into the mic, not a solo narration recording, and
          // enabling it with nothing to cancel can only cost fidelity.
          autoGain: true,
          noiseSuppress: true,
        ),
        path: p.join(sessionDir.path, 'audio.wav'),
      );
    } catch (e) {
      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
      }
      throw MathPadRecordingException('Could not start audio recording: $e');
    }
    // `_audioRecorder.start()` resolving is the earliest confirmation the
    // mic is actually capturing -- the true start happened SOMEWHERE in
    // the interval between `_startedAt` and now, but "now" is the
    // soonest-available, safe upper-bound estimate (assuming it started
    // any later would risk clipping real narration off the front of the
    // muxed track). Zero, not negative, since a `-itsoffset` compensating
    // for audio starting AFTER the video's t=0 needs the audio pushed
    // later in the output timeline -- see its use in `encode()`.
    _audioStartOffsetSeconds = max(
      0.0,
      DateTime.now().difference(_startedAt!).inMicroseconds / 1e6,
    );

    _sessionDir = sessionDir;
    _canvasKey = canvasKey;
    _frameCount = 0;
    _lastFrameBytes = null;
    _writtenFrameIndex = 0;
    _concatEntries.clear();
    encodingProgress = 0.0;

    // Camera is best-effort and starts AFTER the canvas/mic side is
    // already fully committed above -- so any trouble here (no webcam,
    // permission denied, ffmpeg failing to spawn) only ever disables the
    // camera for this recording, never the recording itself.
    _cameraEnabled = false;
    if (includeCamera) {
      try {
        final String? device = await _detectCameraDeviceName();
        final String ffmpegPath = _resolveFfmpegPath();
        if (device == null) {
          onCameraWarning?.call('No camera was found -- recording without one.');
        } else {
          final List<String> cameraArgs = Platform.isMacOS 
              ? [
                  '-y',
                  '-f', 'avfoundation',
                  '-i', device,
                  '-c:v', 'libx264',
                  '-preset', 'veryfast',
                  '-pix_fmt', 'yuv420p',
                  p.join(sessionDir.path, 'camera.mp4'),
                ]
              : [
                  '-y',
                  '-f', 'dshow',
                  '-i', 'video=$device',
                  '-c:v', 'libx264',
                  '-preset', 'veryfast',
                  '-pix_fmt', 'yuv420p',
                  p.join(sessionDir.path, 'camera.mp4'),
                ];
          _cameraProcess = await Process.start(ffmpegPath, cameraArgs);
          // Best-effort start-offset estimate, same idea as
          // `_audioStartOffsetSeconds` -- a LOWER bound, not exact: this
          // only measures how long spawning the OS process itself took,
          // not how much longer ffmpeg then spent actually opening the
          // DirectShow device inside it (camera device open latency is
          // typically the slowest of the three capture streams to
          // actually start, and isn't observable from here without
          // fragile stderr-message parsing). Still meaningfully better
          // than the previous behaviour of assuming zero offset.
          _cameraStartOffsetSeconds = max(
            0.0,
            DateTime.now().difference(_startedAt!).inMicroseconds / 1e6,
          );
          // IMPORTANT: We must consume stdout and stderr, otherwise the OS
          // pipe buffer fills up with ffmpeg's continuous status output and
          // causes ffmpeg to freeze permanently.
          _cameraProcess!.stdout.listen((_) {});
          _cameraProcess!.stderr.listen((_) {});

          _cameraEnabled = true;
        }
      } catch (e) {
        _cameraProcess = null;
        _cameraEnabled = false;
        onCameraWarning?.call('Could not start the camera -- recording without it.');
      }
    }

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
          // one frame interval on a big/complex board, so more than one
          // frame-slot may be due by the time it finishes -- `fillTo` is
          // however many 1/fps slots have now elapsed. The video's length
          // must stay truthful to that regardless (otherwise it drifts
          // short of the real-time-length audio track, chopping the tail
          // off the narration when `stop()` muxes with `-shortest`), but
          // that no longer means writing this frame to disk once per slot:
          // if it's byte-identical to the last frame we actually wrote
          // (the board didn't change -- e.g. the tutor paused to talk),
          // every one of those slots is just added as extra duration on
          // the existing concat entry instead of a fresh file. Only a
          // genuinely different frame gets written and starts a new entry.
          final int fillTo = max(_targetFrameCountNow(), _frameCount + 1);
          final int slotsElapsed = fillTo - _frameCount;
          final double durationSeconds = slotsElapsed / fps;

          final bool sameAsLast =
              _lastFrameBytes != null && _bytesEqual(_lastFrameBytes!, pngBytes);
          if (sameAsLast && _concatEntries.isNotEmpty) {
            _concatEntries.last.durationSeconds += durationSeconds;
          } else {
            _writtenFrameIndex++;
            final String fileName =
                'frame_${_writtenFrameIndex.toString().padLeft(6, '0')}.png';
            final File file = File(p.join(_sessionDir!.path, fileName));
            await file.writeAsBytes(pngBytes);
            _concatEntries.add(_ConcatEntry(fileName, durationSeconds));
            _lastFrameBytes = pngBytes;
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

  /// Stops capturing, halts all inputs, and moves to a waiting state.
  /// Call `encode()` immediately after to process the captured data.
  void updateCanvasKey(GlobalKey canvasKey) {
    _canvasKey = canvasKey;
  }

  Future<void> stopCapture() async {
    if (_state != MathPadRecordingState.recording) {
      throw MathPadRecordingException('Not currently recording.');
    }
    _frameTimer?.cancel();
    _frameTimer = null;
    
    // Let any in-flight frame capture finish before we freeze state
    while (_captureInFlight) {
      await Future.delayed(const Duration(milliseconds: 20));
    }

    String? audioPath;
    try {
      audioPath = await _audioRecorder.stop();
    } catch (e) {
      audioPath = null;
    }

    await _stopCameraCapture();

    _capturedConcatEntries = List.of(_concatEntries);
    _capturedSessionDir = _sessionDir;
    _capturedCameraWasEnabled = _cameraEnabled;
    _capturedAudioPath = audioPath;
    _capturedAudioStartOffsetSeconds = _audioStartOffsetSeconds;
    _capturedCameraStartOffsetSeconds = _cameraStartOffsetSeconds;

    _canvasKey = null;
    _sessionDir = null;
    _startedAt = null;
    _cameraProcess = null;
    _cameraEnabled = false;
    _frameCount = 0;
    _writtenFrameIndex = 0;
    _lastFrameBytes = null;
    _concatEntries.clear();
    _audioStartOffsetSeconds = 0.0;
    _cameraStartOffsetSeconds = 0.0;

    _state = MathPadRecordingState.waitingForEncodeChoice;
    _emit();
  }

  /// Encodes the captured frames and audio into an .mp4 via the bundled ffmpeg.
  /// If [fastEncode] is true, uses much faster compression presets.
  Future<String> encode({bool fastEncode = false}) async {
    if (_state != MathPadRecordingState.waitingForEncodeChoice) {
      throw MathPadRecordingException('Not waiting for encode.');
    }

    final List<_ConcatEntry> concatEntries = _capturedConcatEntries ?? [];
    final Directory sessionDir = _capturedSessionDir!;
    final bool cameraWasEnabled = _capturedCameraWasEnabled;
    final String? audioPath = _capturedAudioPath;
    final double audioStartOffsetSeconds = _capturedAudioStartOffsetSeconds;
    final double cameraStartOffsetSeconds = _capturedCameraStartOffsetSeconds;

    _state = MathPadRecordingState.encoding;
    _emit();

    Future<void> cleanup() async {
      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
      }
    }

    if (concatEntries.isEmpty) {
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

      final Directory outDir = await getRecordingsDir();
      final String outPath =
          p.join(outDir.path, 'MathPad_${DateTime.now().millisecondsSinceEpoch}.mp4');

      // A concat-demuxer manifest instead of a plain numbered-frame glob:
      // each entry says how long (in seconds) to hold one physical PNG,
      // so a long static stretch (nothing drawn -- see `_captureFrame`'s
      // dedup above) costs ffmpeg one small `duration` line instead of
      // thousands of identical files to open, decode and re-encode. The
      // concat demuxer only applies a `duration` line to the file that
      // immediately precedes it, and ignores one trailing a final file
      // with nothing after it -- so the last file is deliberately
      // repeated once more with no duration line to make its hold time
      // stick (a documented quirk of the format, not a bug here).
      final StringBuffer manifest = StringBuffer('ffconcat version 1.0\n');
      for (final entry in concatEntries) {
        manifest.writeln("file '${entry.fileName}'");
        manifest.writeln('duration ${entry.durationSeconds.toStringAsFixed(6)}');
      }
      manifest.writeln("file '${concatEntries.last.fileName}'");
      final File manifestFile = File(p.join(sessionDir.path, 'frames.ffconcat'));
      await manifestFile.writeAsString(manifest.toString());

      // Total captured timeline length -- the denominator for turning
      // ffmpeg's `-progress` output (which reports elapsed *output* time,
      // not a percentage) into the 0..1 fraction the UI's progress bar
      // wants. Same value the concat entries' durations were built from,
      // so it lines up with what ffmpeg will actually encode.
      final double totalDurationSeconds = concatEntries.fold(
        0.0,
        (sum, e) => sum + e.durationSeconds,
      );

      // The board is mostly flat colour/line art with long static
      // stretches (talking, thinking) rather than the high-motion,
      // fine-grain-detail video `medium`/low-crf is tuned for -- `veryfast`
      // plus a slightly relaxed crf trades a little bitrate efficiency for
      // dramatically less CPU time per frame, which matters much more once
      // a real lecture-length recording is feeding it thousands of frames.
      final List<String> args = [
        '-y',
        // Machine-readable `key=value` progress lines on stdout (ending
        // each block with `progress=continue`/`end`) instead of guessing
        // at completion from an indeterminate spinner -- paired with
        // `-nostats` so ffmpeg's normal human-readable stats lines don't
        // also clutter stderr redundantly.
        '-progress', 'pipe:1',
        '-nostats',
        '-f', 'concat',
        '-safe', '0',
        '-i', manifestFile.path,
        if (audioPath != null) ...[
          // Shifts the audio input later in the output timeline by
          // however much it actually started after the video's own t=0
          // (measured in `start()`, see `_audioStartOffsetSeconds`'s doc
          // comment) -- without this, the mic's recorded WAV -- which
          // always began capturing at least a little later than the
          // video's zero point once the mic was genuinely ready -- gets
          // muxed as if it started at the exact same instant, permanently
          // offsetting narration relative to the picture by that amount
          // for the whole recording.
          if (audioStartOffsetSeconds > 0.0005)
            ...['-itsoffset', audioStartOffsetSeconds.toStringAsFixed(6)],
          '-i', audioPath,
        ],
        // Normalizes the concat demuxer's variable-duration input frames
        // into a proper constant-frame-rate output stream -- cheap for
        // ffmpeg to do internally (it's just frame duplication at encode
        // time), unlike materializing those same duplicate frames as
        // files up front the way this used to work.
        '-r', '$fps',
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
        '-preset', fastEncode ? 'ultrafast' : 'veryfast',
        '-crf', fastEncode ? '28' : '20',
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

      final Process process;
      try {
        process = await Process.start(ffmpegPath, args);
      } on ProcessException catch (e) {
        throw MathPadRecordingException('Could not run ffmpeg: ${e.message}');
      }

      final StringBuffer stderrBuffer = StringBuffer();
      DateTime lastProgressEmit = DateTime.fromMillisecondsSinceEpoch(0);

      final StreamSubscription<String> stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            // Each `-progress` block repeats several `key=value` lines --
            // `out_time_us` (microseconds of output encoded so far) is the
            // only one this needs. Throttled to a few updates/sec so a
            // fast encode can't flood `setState` calls on the UI side.
            if (line.startsWith('out_time_us=') && totalDurationSeconds > 0) {
              final int? outTimeUs = int.tryParse(
                line.substring('out_time_us='.length),
              );
              if (outTimeUs != null) {
                encodingProgress = ((outTimeUs / 1000000) / totalDurationSeconds)
                    .clamp(0.0, 1.0);
                final DateTime now = DateTime.now();
                if (now.difference(lastProgressEmit) >
                    const Duration(milliseconds: 150)) {
                  lastProgressEmit = now;
                  onEncodingProgress?.call(encodingProgress);
                  notifyListeners();
                }
              }
            } else if (line == 'progress=end') {
              encodingProgress = 1.0;
              onEncodingProgress?.call(1.0);
              notifyListeners();
            }
          });
      final StreamSubscription<List<int>> stderrSub = process.stderr.listen(
        (chunk) => stderrBuffer.write(utf8.decode(chunk, allowMalformed: true)),
      );

      final int exitCode = await process.exitCode;
      await stdoutSub.cancel();
      await stderrSub.cancel();

      if (exitCode != 0) {
        // Surface ffmpeg's own stderr (its actual reason) instead of just
        // the exit code, so a failure like this is diagnosable from the
        // error message alone next time instead of needing to reproduce it.
        final String stderrText = stderrBuffer.toString();
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
          'Encoding failed (ffmpeg exit $exitCode):\n$tail',
        );
      }

      // The canvas-only video above is already complete and saved at
      // `outPath` regardless of what happens from here -- everything
      // below is a strictly additive second pass that can only ever
      // improve on that, never take it away.
      if (!cameraWasEnabled) {
        await _generateThumbnail(outPath);
        return outPath;
      }

      final File cameraFile = File(p.join(sessionDir.path, 'camera.mp4'));
      if (!await cameraFile.exists()) {
        onCameraWarning?.call(
          'Camera capture produced no video -- saved without it.',
        );
        await _generateThumbnail(outPath);
        return outPath;
      }
      try {
        onEncodingPhaseChanged?.call('Adding camera…');
        encodingProgress = 0.0;
        onEncodingProgress?.call(0.0);
        notifyListeners();
        final String finalVideoPath = await _overlayCamera(
          ffmpegPath: ffmpegPath,
          canvasVideoPath: outPath,
          cameraVideoPath: cameraFile.path,
          outDir: outDir,
          totalDurationSeconds: totalDurationSeconds,
          fastEncode: fastEncode,
          cameraStartOffsetSeconds: cameraStartOffsetSeconds,
        );
        await _generateThumbnail(finalVideoPath);
        return finalVideoPath;
      } catch (e) {
        onCameraWarning?.call(
          'Camera couldn\'t be added to the video -- saved without it.',
        );
        await _generateThumbnail(outPath);
        return outPath;
      }
    } finally {
      encodingProgress = 0.0;
      await cleanup();
      _state = MathPadRecordingState.idle;
      _emit();
    }
  }

  /// Second, independent ffmpeg pass: overlays `cameraVideoPath` (scaled
  /// small, top-right corner, thin white border) onto the already-fully-
  /// encoded `canvasVideoPath`, re-using the same `-progress`-parsing
  /// technique as the main encode above so the UI's progress bar keeps
  /// reporting real numbers through this phase too. On success, the
  /// superseded plain video is deleted so the tutor isn't left with two
  /// near-duplicate files per recording; on failure, the caller falls
  /// back to keeping the plain video (see `stop()`).
  Future<String> _overlayCamera({
    required String ffmpegPath,
    required String canvasVideoPath,
    required String cameraVideoPath,
    required Directory outDir,
    required double totalDurationSeconds,
    required bool fastEncode,
    double cameraStartOffsetSeconds = 0.0,
  }) async {
    final String finalPath =
        p.join(outDir.path, 'MathPad_${DateTime.now().millisecondsSinceEpoch}_cam.mp4');
    final List<String> args = [
      '-y',
      '-progress', 'pipe:1',
      '-nostats',
      '-i', canvasVideoPath,
      // Shifts the camera stream later to match how much after the canvas
      // video's own t=0 it actually started (measured in `start()`, see
      // `_cameraStartOffsetSeconds`'s doc comment) -- the DirectShow
      // device is typically the slowest of the three capture streams to
      // actually come online, so without this the picture-in-picture box
      // visibly leads the canvas/audio by that same amount for the whole
      // recording.
      if (cameraStartOffsetSeconds > 0.0005)
        ...['-itsoffset', cameraStartOffsetSeconds.toStringAsFixed(6)],
      '-i', cameraVideoPath,
      // Camera box: cropped to a square and scaled to 240x240 for a significantly
      // larger PIP presence. Placed in the top-right corner with a small
      // margin and a thin white border so it stays legible over any
      // background colour. `overlay`'s default `eof_action` (repeat)
      // freezes the box on its last frame if the camera feed happens to
      // be a touch shorter than the canvas video, rather than cutting
      // the output short -- so this deliberately does NOT pass
      // `-shortest`, which would risk truncating the real recording to
      // match a slightly-shorter camera capture instead.
      '-filter_complex',
      '[1:v]crop=ih:ih,scale=w=240:h=240,'
          'drawbox=x=0:y=0:w=iw:h=ih:color=white@0.9:t=4[cam];'
          '[0:v][cam]overlay=x=main_w-overlay_w-24:y=24[outv]',
      '-map', '[outv]',
      '-map', '0:a?',
      '-c:v', 'libx264',
      '-preset', fastEncode ? 'ultrafast' : 'veryfast',
      '-crf', fastEncode ? '28' : '20',
      '-c:a', 'copy',
      finalPath,
    ];

    final Process process;
    try {
      process = await Process.start(ffmpegPath, args);
    } on ProcessException catch (e) {
      throw MathPadRecordingException('Could not run ffmpeg: ${e.message}');
    }

    final StringBuffer stderrBuffer = StringBuffer();
    DateTime lastProgressEmit = DateTime.fromMillisecondsSinceEpoch(0);
    final StreamSubscription<String> stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.startsWith('out_time_us=') && totalDurationSeconds > 0) {
            final int? outTimeUs = int.tryParse(
              line.substring('out_time_us='.length),
            );
            if (outTimeUs != null) {
              encodingProgress = ((outTimeUs / 1000000) / totalDurationSeconds)
                  .clamp(0.0, 1.0);
              final DateTime now = DateTime.now();
              if (now.difference(lastProgressEmit) >
                  const Duration(milliseconds: 150)) {
                lastProgressEmit = now;
                onEncodingProgress?.call(encodingProgress);
                notifyListeners();
              }
            }
          } else if (line == 'progress=end') {
            encodingProgress = 1.0;
            onEncodingProgress?.call(1.0);
            notifyListeners();
          }
        });
    final StreamSubscription<List<int>> stderrSub = process.stderr.listen(
      (chunk) => stderrBuffer.write(utf8.decode(chunk, allowMalformed: true)),
    );

    final int exitCode = await process.exitCode;
    await stdoutSub.cancel();
    await stderrSub.cancel();

    if (exitCode != 0) {
      final String stderrText = stderrBuffer.toString();
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
        'Camera overlay failed (ffmpeg exit $exitCode):\n$tail',
      );
    }

    // Superseded by `finalPath` -- delete so the tutor doesn't end up
    // with two near-duplicate files for one recording.
    try {
      await File(canvasVideoPath).delete();
    } catch (_) {}
    return finalPath;
  }

  /// Discards an in-progress recording without encoding anything.
  Future<void> cancel() async {
    if (_state != MathPadRecordingState.recording) return;
    _frameTimer?.cancel();
    _frameTimer = null;
    await _audioRecorder.stop();
    await _stopCameraCapture();
    _cameraEnabled = false;
    final Directory? sessionDir = _sessionDir;
    _sessionDir = null;
    _canvasKey = null;
    _lastFrameBytes = null;
    _concatEntries.clear();
    if (sessionDir != null && await sessionDir.exists()) {
      await sessionDir.delete(recursive: true);
    }
    _state = MathPadRecordingState.idle;
    _emit();
  }

  Future<void> _generateThumbnail(String videoPath) async {
    final String ffmpegPath = _resolveFfmpegPath();
    final String baseName = p.basenameWithoutExtension(videoPath);
    final String parentDir = File(videoPath).parent.path;
    
    final Directory thumbnailDir = Directory(p.join(parentDir, '.thumbnails'));
    if (!await thumbnailDir.exists()) {
      await thumbnailDir.create();
    }
    
    final String thumbnailPath = p.join(thumbnailDir.path, '$baseName.png');
    
    try {
      await Process.run(ffmpegPath, [
        '-y',
        '-i', videoPath,
        '-ss', '00:00:00.500',
        '-vframes', '1',
        '-q:v', '2',
        thumbnailPath,
      ]);
    } catch (_) {}
  }

  String _resolveFfmpegPath() {
    final String exeDir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isMacOS) {
      return p.join(exeDir, 'ffmpeg');
    }
    return p.join(exeDir, 'ffmpeg.exe');
  }

  Future<Directory> getRecordingsDir() async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory recordings = Directory(p.join(docs.path, 'Jyamiti Recordings'));
    if (!await recordings.exists()) {
      await recordings.create(recursive: true);
    }
    return recordings;
  }

  Future<List<File>> getRecordings() async {
    final Directory dir = await getRecordingsDir();
    final List<FileSystemEntity> entities = await dir.list().toList();
    final List<File> mp4Files = entities
        .whereType<File>()
        .where((f) => f.path.endsWith('.mp4'))
        .toList();
    // Sort by modified date descending (newest first)
    mp4Files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return mp4Files;
  }

  final Map<String, String> _durationCache = {};

  Future<String> getVideoDuration(String path) async {
    if (_durationCache.containsKey(path)) return _durationCache[path]!;
    
    final String ffmpegPath = _resolveFfmpegPath();
    if (!await File(ffmpegPath).exists()) return '';
    
    try {
      final result = await Process.run(ffmpegPath, ['-i', path]);
      final String output = result.stderr.toString();
      final match = RegExp(r'Duration: (\d{2}:\d{2}:\d{2})').firstMatch(output);
      if (match != null) {
        final durationStr = match.group(1)!;
        String display = durationStr;
        if (display.startsWith('00:')) {
          display = display.substring(3);
        }
        _durationCache[path] = display;
        return display;
      }
    } catch (_) {}
    
    return '';
  }

  void _emit() {
    onUpdate?.call(_state, elapsed);
    notifyListeners();
  }

  Future<void> dispose() async {
    _frameTimer?.cancel();
    await _audioRecorder.dispose();
    _cameraProcess?.kill(ProcessSignal.sigkill);
  }
}

/// One physical frame file in the `stop()` concat manifest, plus how many
/// seconds it should be held for (accumulated across every duplicate 1/fps
/// slot it stood in for -- see the dedup check in `_captureFrame`).
class _ConcatEntry {
  final String fileName;
  double durationSeconds;
  _ConcatEntry(this.fileName, this.durationSeconds);
}

/// Manual length-then-contents comparison (early-exits on the first
/// mismatch) -- cheap relative to the PNG encode that produced `a`/`b` in
/// the first place, and avoids pulling in `package:collection` just for
/// this one check.
bool _bytesEqual(Uint8List a, Uint8List b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
