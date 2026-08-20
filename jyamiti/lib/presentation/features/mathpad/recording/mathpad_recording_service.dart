import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart' as ffi2;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win32/win32.dart' as win32;

enum MathPadRecordingState { idle, recording, waitingForEncodeChoice, encoding }

/// How `_evaluateSegmentSeal` decides when to fold captured frames into a
/// background-encoded segment during a recording -- see the "Real-time
/// (background) segment encoding" section's doc comment below for what
/// sealing actually does. The tutor's choice is persisted locally (see
/// [MathPadRecordingService.loadSegmentSealMode]/`setSegmentSealMode`) so
/// it survives across sessions.
enum SegmentSealMode {
  /// Seals on a fixed timer only, every `_kSegmentSealInterval`, no matter
  /// what's happening on the board -- simple and predictable, but the
  /// background encode can land in the middle of an actively busy/fast-
  /// changing board and compete with capture for CPU right when that
  /// matters most.
  fixedInterval,

  /// Seals only during a natural pause -- the board hasn't produced a new
  /// distinct frame for `_kIdleSealThreshold` (the tutor is talking, not
  /// drawing) -- so the background encode never competes with an actively
  /// busy board. The tradeoff: a recording with no pauses at all
  /// (continuous, uninterrupted drawing) never seals until it stops, so a
  /// long uninterrupted stretch gets none of this feature's benefit.
  idleOnly,

  /// Seals on whichever comes first: a natural idle pause, or the fixed
  /// timer ceiling. Gets [idleOnly]'s CPU-contention win for the common
  /// "draw a bit, talk, draw a bit" pattern, with no regression for
  /// continuous drawing -- that case just falls back to behaving like
  /// [fixedInterval]. The recommended default.
  hybrid,
}

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
///
/// For a recording longer than one `_kSegmentSealInterval`, most of that
/// final encode has actually already happened WHILE recording was still
/// running: `_maybeSealSegment` periodically folds everything captured so
/// far into a small, already-finished video segment in the background (see
/// its own doc comment), so `encode()` only has real encoding work left to
/// do for the last short leftover tail -- everything sealed before that
/// gets joined in with a fast stream-copy concat instead of being decoded
/// and re-encoded from scratch. A short recording (under one seal
/// interval) never has anything sealed, and transparently falls back to
/// the original single full-encode pass with no behaviour change.
// ─── Windows Job Object: kill-on-close safety net for spawned ffmpeg
// processes ──────────────────────────────────────────────────────────────
// `Process.start` on Windows does not tie a child process's lifetime to
// this app's -- if `jyamiti.exe` is hard-killed (Task Manager "End Task",
// a crash, a forced restart) instead of exiting normally, any ffmpeg child
// still running keeps right on running as an orphan. That matters most for
// `_cameraProcess`: it holds an exclusive DirectShow handle on the webcam
// for as long as it's alive, so an orphaned copy leaves the webcam locked
// system-wide -- unusable in any other app -- until it's manually killed
// in Task Manager or the machine reboots.
//
// A Windows Job Object created with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`
// fixes this at the OS level: every process assigned to it is
// automatically terminated the instant the job's last handle closes --
// which Windows itself does when this process exits, for ANY reason,
// crash included, with no Dart code needing to run for it to take effect.
// `package:win32` wraps the handful of plain functions this needs
// (`CreateJobObject`/`SetInformationJobObject`/`AssignProcessToJobObject`)
// but not the specific limit-information struct or constant, so those are
// defined here directly via `dart:ffi`, matching the real Win32 struct
// layout (`JOBOBJECT_EXTENDED_LIMIT_INFORMATION`) field-for-field.

const int _kJobObjectExtendedLimitInformation = 9;
const int _kJobObjectLimitKillOnJobClose = 0x00002000;
const int _kProcessSetQuota = 0x0100;
const int _kProcessTerminate = 0x0001;

base class _IoCounters extends ffi.Struct {
  @ffi.Uint64()
  external int readOperationCount;
  @ffi.Uint64()
  external int writeOperationCount;
  @ffi.Uint64()
  external int otherOperationCount;
  @ffi.Uint64()
  external int readTransferCount;
  @ffi.Uint64()
  external int writeTransferCount;
  @ffi.Uint64()
  external int otherTransferCount;
}

base class _JobObjectBasicLimitInformation extends ffi.Struct {
  @ffi.Int64()
  external int perProcessUserTimeLimit;
  @ffi.Int64()
  external int perJobUserTimeLimit;
  @ffi.Uint32()
  external int limitFlags;
  @ffi.Uint64()
  external int minimumWorkingSetSize;
  @ffi.Uint64()
  external int maximumWorkingSetSize;
  @ffi.Uint32()
  external int activeProcessLimit;
  @ffi.Uint64()
  external int affinity;
  @ffi.Uint32()
  external int priorityClass;
  @ffi.Uint32()
  external int schedulingClass;
}

base class _JobObjectExtendedLimitInformation extends ffi.Struct {
  external _JobObjectBasicLimitInformation basicLimitInformation;
  external _IoCounters ioInfo;
  @ffi.Uint64()
  external int processMemoryLimit;
  @ffi.Uint64()
  external int jobMemoryLimit;
  @ffi.Uint64()
  external int peakProcessMemoryUsed;
  @ffi.Uint64()
  external int peakJobMemoryUsed;
}

/// Created lazily, once per app run -- every process ever assigned to it
/// (see `_tieProcessLifetimeToApp`) dies the moment this handle closes,
/// which Windows does automatically on process exit for any reason.
int? _killOnCloseJobHandle;

/// Best-effort and silent on any failure (never throws) -- a spawned
/// ffmpeg process working normally matters far more than this safety net
/// existing at all, so nothing here is allowed to affect the actual
/// recording if the OS call fails for some unexpected reason.
int? _ensureKillOnCloseJob() {
  if (_killOnCloseJobHandle != null) return _killOnCloseJobHandle;
  if (!Platform.isWindows) return null;
  try {
    final int job = win32.CreateJobObject(ffi.nullptr, ffi.nullptr);
    if (job == 0) return null;

    final ffi.Pointer<_JobObjectExtendedLimitInformation> info =
        ffi2.calloc<_JobObjectExtendedLimitInformation>();
    try {
      info.ref.basicLimitInformation.limitFlags =
          _kJobObjectLimitKillOnJobClose;
      final int ok = win32.SetInformationJobObject(
        job,
        _kJobObjectExtendedLimitInformation,
        info.cast(),
        ffi.sizeOf<_JobObjectExtendedLimitInformation>(),
      );
      if (ok == 0) {
        win32.CloseHandle(job);
        return null;
      }
    } finally {
      ffi2.calloc.free(info);
    }

    _killOnCloseJobHandle = job;
    return job;
  } catch (_) {
    return null;
  }
}

/// Assigns the OS process with [pid] to the kill-on-close job so it's
/// terminated automatically if this app's process ever is, gracefully or
/// not -- called right after every ffmpeg `Process.start` in this file.
void _tieProcessLifetimeToApp(int pid) {
  if (!Platform.isWindows) return;
  try {
    final int? job = _ensureKillOnCloseJob();
    if (job == null) return;
    final int handle = win32.OpenProcess(
      _kProcessSetQuota | _kProcessTerminate,
      0,
      pid,
    );
    if (handle == 0) return;
    win32.AssignProcessToJobObject(job, handle);
    win32.CloseHandle(handle);
  } catch (_) {
    // Un-assigned just falls back to today's behaviour (graceful stop /
    // `dispose()`'s hard kill on a clean exit) -- never worth surfacing.
  }
}

class MathPadRecordingService extends ChangeNotifier {
  MathPadRecordingService() {
    // Best-effort, fire-and-forget: the very first recording of a fresh
    // app launch could in theory start before this resolves (a plain
    // local-disk read, normally fast), in which case it just uses the
    // `hybrid` default for that one recording -- never worth blocking
    // construction over.
    unawaited(loadSegmentSealMode());
  }

  /// Loads the tutor's saved [segmentSealMode] from local storage, if any
  /// was ever saved -- falls back to (and leaves unchanged) whatever
  /// [segmentSealMode] already is on any error or missing value.
  Future<void> loadSegmentSealMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_kSegmentSealModePrefKey);
      if (saved == null) return;
      segmentSealMode = SegmentSealMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => segmentSealMode,
      );
      notifyListeners();
    } catch (_) {
      // Keep whatever `segmentSealMode` already was.
    }
  }

  /// Changes [segmentSealMode] and persists the choice locally so it's
  /// still in effect the next time the app opens. Safe to call mid-
  /// recording -- `_evaluateSegmentSeal` reads `segmentSealMode` fresh on
  /// every tick, so a change takes effect on its very next check.
  Future<void> setSegmentSealMode(SegmentSealMode mode) async {
    segmentSealMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSegmentSealModePrefKey, mode.name);
    } catch (_) {
      // Setting still applies for the rest of this session even if saving
      // it for next time happened to fail.
    }
  }

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
  // not assumed, so `encode()` can shift each stream later by exactly this
  // much via ffmpeg's `-itsoffset` and keep
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

  // ─── Real-time (background) segment encoding ───────────────────────────
  // Periodically folds the frames captured so far into a small, already-
  // finished video segment WHILE recording is still running, so `encode()`
  // at the end only has real encoding work left to do for the last
  // (usually short) leftover tail -- everything sealed before that gets
  // joined in with a fast stream-copy concat instead of being decoded and
  // re-encoded from scratch. Each sealed segment is also a real,
  // independently valid file the moment it's written (unlike one
  // continuous live-piped encode into a single growing file), so a crash
  // mid-recording only ever loses the current unsealed tail's PNGs, never
  // any already-sealed portion.
  static const Duration _kSegmentSealInterval = Duration(seconds: 20);
  // How long the board must sit unchanged before [SegmentSealMode.idleOnly]
  // / [SegmentSealMode.hybrid] treat it as "a natural pause" worth sealing
  // on -- long enough that a normal beat between strokes doesn't trigger
  // it, short enough that a tutor pausing to talk gets sealed promptly.
  static const Duration _kIdleSealThreshold = Duration(seconds: 4);
  // How often `_evaluateSegmentSeal` actually checks the two thresholds
  // above -- just a polling granularity, not a seal trigger itself.
  static const Duration _kSegmentSealCheckInterval = Duration(seconds: 2);
  static const String _kSegmentSealModePrefKey = 'mathpad_segment_seal_mode';

  /// The tutor's chosen sealing strategy -- defaults to [SegmentSealMode.hybrid]
  /// until [loadSegmentSealMode] (fired from the constructor, best-effort)
  /// resolves whatever was actually saved locally.
  SegmentSealMode segmentSealMode = SegmentSealMode.hybrid;

  Timer? _segmentSealTimer;
  bool _segmentSealInFlight = false;
  // When the fixed-interval ceiling was last reset -- either at recording
  // start, or the moment a seal (of EITHER kind) was last attempted, so
  // "every `_kSegmentSealInterval`" means "since the last seal", not "on
  // this wall-clock cadence regardless of what already happened".
  DateTime? _lastSealCheckpoint;
  // When the most recent genuinely NEW (non-duplicate) frame was written --
  // updated in `_captureFrame`'s new-entry branch, never its dedup-extend
  // branch. `null` means nothing's been captured yet this recording.
  DateTime? _lastDistinctFrameAt;
  final List<String> _sealedSegmentPaths = [];
  // How many of `_concatEntries` (from the front) have already been folded
  // into a sealed segment -- entries from this index onward are still
  // pending/unsealed. Deliberately never includes the very LAST entry in
  // `_concatEntries` at seal time: the frame-dedup logic in `_captureFrame`
  // keeps extending that entry's `durationSeconds` for as long as the
  // board stays unchanged, so sealing it while it might still be growing
  // would permanently drop whatever hold-time arrives after the seal.
  int _sealedConcatEntryCount = 0;
  List<String>? _capturedSealedSegmentPaths;
  int _capturedSealedConcatEntryCount = 0;

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

  /// Current human-readable encoding status (e.g. "Encoding…", "Adding camera…")
  String encodingPhaseLabel = 'Encoding…';

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
    // instant and compensated for at mux time in `encode()` via ffmpeg's
    // `-itsoffset`, rather than assumed away.
    _startedAt = DateTime.now();
    elapsed = Duration.zero;
    _lastEmittedElapsed = Duration.zero;

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
          // autoGain and noiseSuppress deliberately off: on Windows these
          // activate the OS APO (Audio Processing Objects) pipeline which
          // applies heavy-handed noise suppression/AGC that distorts clean
          // mic narration into artifacts/muffled noise when there is
          // nothing real for it to cancel. Volume normalisation is handled
          // cleanly at encode time via dynaudnorm (see below) without any
          // signal quality cost. echoCancel also left off for the same
          // reason -- it exists for two-way call scenarios with live
          // speaker feedback, not a solo narration recording.
          autoGain: false,
          noiseSuppress: false,
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
    _sealedSegmentPaths.clear();
    _sealedConcatEntryCount = 0;
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
          // See the "Windows Job Object" section above this class -- ties
          // this process's lifetime to the app's so a hard-kill can't
          // orphan it holding the webcam locked.
          _tieProcessLifetimeToApp(_cameraProcess!.pid);
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

    // Real-time background segment encoding -- see the "Real-time
    // (background) segment encoding" fields' doc comment above, and
    // `_evaluateSegmentSeal` for how `segmentSealMode` picks when to
    // actually trigger one.
    _lastSealCheckpoint = _startedAt;
    _lastDistinctFrameAt = null;
    _segmentSealTimer = Timer.periodic(
      _kSegmentSealCheckInterval,
      (_) => _evaluateSegmentSeal(),
    );
  }

  int _targetFrameCountNow() {
    if (_startedAt == null) return 0;
    return (DateTime.now().difference(_startedAt!).inMilliseconds * fps / 1000)
        .floor();
  }

  Future<void> _captureFrame() async {
    if (_sessionDir == null || _startedAt == null) return;
    
    // Always keep elapsed time updated
    elapsed = DateTime.now().difference(_startedAt!);

    if (_captureInFlight) {
      _emitElapsedTick();
      return;
    }
    
    // Nothing new due yet -- capturing again right now would just be a
    // needless duplicate of the last frame, but we still emitted the latest elapsed time.
    if (_targetFrameCountNow() <= _frameCount) {
      _emitElapsedTick();
      return;
    }

    _captureInFlight = true;
    try {
      final RenderObject? renderObject = _canvasKey
          ?.currentContext
          ?.findRenderObject();
      if (renderObject is RenderRepaintBoundary &&
          renderObject.attached &&
          !renderObject.debugNeedsPaint) {
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
            // A genuinely new frame -- resets the idle clock
            // `_evaluateSegmentSeal` watches for `idleOnly`/`hybrid`.
            _lastDistinctFrameAt = DateTime.now();
          }
          _frameCount = fillTo;
        }
      } else if (_concatEntries.isNotEmpty) {
        // While switching pages or transitioning between routes, the canvas
        // may be briefly unmounted or rebuilding. Keep the timeline advancing
        // and hold the last valid frame so video frames, recording timer,
        // and audio narration remain continuously in sync without stalling.
        final int fillTo = max(_targetFrameCountNow(), _frameCount + 1);
        final int slotsElapsed = fillTo - _frameCount;
        if (slotsElapsed > 0) {
          final double durationSeconds = slotsElapsed / fps;
          _concatEntries.last.durationSeconds += durationSeconds;
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
    _emitElapsedTick();
  }

  /// Builds a concat-demuxer manifest for exactly [entries] and encodes it
  /// with the bundled ffmpeg into one MPEG-TS segment at [outPath] --
  /// shared by the periodic background seal below and by `encode()`'s
  /// final leftover-tail segment, so both produce segments in exactly the
  /// same format (required for the fast `-c copy` concat that joins them
  /// all together afterward). Returns false (never throws) on any
  /// failure, so a failed segment just means more work happens at the
  /// final encode instead -- never worth losing the recording over.
  Future<bool> _encodeSegment({
    required Directory sessionDir,
    required List<_ConcatEntry> entries,
    required String outPath,
    required String preset,
    required String crf,
  }) async {
    if (entries.isEmpty) return false;
    try {
      final String ffmpegPath = _resolveFfmpegPath();
      if (!await File(ffmpegPath).exists()) return false;

      final StringBuffer manifest = StringBuffer('ffconcat version 1.0\n');
      for (final entry in entries) {
        manifest.writeln("file '${entry.fileName}'");
        manifest.writeln('duration ${entry.durationSeconds.toStringAsFixed(6)}');
      }
      manifest.writeln("file '${entries.last.fileName}'");
      final File manifestFile = File(
        p.join(sessionDir.path, '${p.basenameWithoutExtension(outPath)}.ffconcat'),
      );
      await manifestFile.writeAsString(manifest.toString());

      final ProcessResult result = await Process.run(ffmpegPath, [
        '-y',
        '-f', 'concat',
        '-safe', '0',
        '-i', manifestFile.path,
        '-r', '$fps',
        '-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2',
        '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p',
        '-preset', preset,
        '-crf', crf,
        '-f', 'mpegts',
        outPath,
      ]);
      try {
        await manifestFile.delete();
      } catch (_) {}
      return result.exitCode == 0 && await File(outPath).exists();
    } catch (_) {
      return false;
    }
  }

  /// Runs on every `_segmentSealTimer` tick (a short, fixed poll interval,
  /// `_kSegmentSealCheckInterval` -- not a seal trigger itself) and decides,
  /// based on `segmentSealMode`, whether NOW is actually a moment to seal:
  ///
  /// - [SegmentSealMode.fixedInterval]: only once `_kSegmentSealInterval`
  ///   has passed since the last seal attempt, regardless of activity.
  /// - [SegmentSealMode.idleOnly]: only once the board has sat unchanged
  ///   for `_kIdleSealThreshold` (a natural pause).
  /// - [SegmentSealMode.hybrid]: whichever of the above comes first.
  ///
  /// `_maybeSealSegment` itself is a no-op if there's nothing new to seal,
  /// so triggering it here is safe even if this fires more often than
  /// there's actually new content.
  void _evaluateSegmentSeal() {
    final DateTime now = DateTime.now();
    final bool fixedDue =
        _lastSealCheckpoint != null &&
        now.difference(_lastSealCheckpoint!) >= _kSegmentSealInterval;
    final bool idleDue =
        _lastDistinctFrameAt != null &&
        now.difference(_lastDistinctFrameAt!) >= _kIdleSealThreshold;

    final bool shouldSeal = switch (segmentSealMode) {
      SegmentSealMode.fixedInterval => fixedDue,
      SegmentSealMode.idleOnly => idleDue,
      SegmentSealMode.hybrid => fixedDue || idleDue,
    };
    if (!shouldSeal) return;

    _lastSealCheckpoint = now;
    unawaited(_maybeSealSegment());
  }

  /// Folds every not-yet-sealed frame (except the very last entry -- see
  /// `_sealedConcatEntryCount`'s doc comment) into one more sealed segment,
  /// in the background, while recording continues uninterrupted. Triggered
  /// by `_evaluateSegmentSeal` above; guarded by `_segmentSealInFlight` so
  /// a slow seal can never overlap with the next one.
  Future<void> _maybeSealSegment() async {
    if (_segmentSealInFlight || _sessionDir == null) return;
    final int sealableCount =
        _concatEntries.length - 1 - _sealedConcatEntryCount;
    if (sealableCount <= 0) return;

    _segmentSealInFlight = true;
    try {
      final Directory dir = _sessionDir!;
      final List<_ConcatEntry> toSeal = _concatEntries.sublist(
        _sealedConcatEntryCount,
        _concatEntries.length - 1,
      );
      final String segmentPath = p.join(
        dir.path,
        'segment_${_sealedSegmentPaths.length}.ts',
      );
      // Same fixed "normal quality" preset the tail segment and the
      // single-pass path both use -- every segment in a recording (sealed
      // in the background or the leftover tail encoded once stopped) is
      // encoded identically, so there's nothing to reconcile at `encode()`
      // time.
      final bool ok = await _encodeSegment(
        sessionDir: dir,
        entries: toSeal,
        outPath: segmentPath,
        preset: 'veryfast',
        crf: '20',
      );
      if (ok) {
        _sealedSegmentPaths.add(segmentPath);
        _sealedConcatEntryCount += toSeal.length;
        // Already fully baked into `segmentPath` -- delete the source
        // PNGs to reclaim disk space, same spirit as the frame dedup in
        // `_captureFrame`.
        for (final entry in toSeal) {
          try {
            await File(p.join(dir.path, entry.fileName)).delete();
          } catch (_) {}
        }
      }
    } catch (_) {
      // A failed seal just means more work happens at the final encode.
    } finally {
      _segmentSealInFlight = false;
    }
  }

  /// Updates the canvas capture key (e.g. when switching pages in MathPad).
  void updateCanvasKey(GlobalKey canvasKey) {
    _canvasKey = canvasKey;
    _lastFrameBytes = null;
    notifyListeners();
  }

  Future<void> stopCapture() async {
    if (_state != MathPadRecordingState.recording) {
      throw MathPadRecordingException('Not currently recording.');
    }
    _frameTimer?.cancel();
    _frameTimer = null;
    _segmentSealTimer?.cancel();
    _segmentSealTimer = null;

    // Stopped here, immediately alongside the video timers above, rather
    // than after the "wait for in-flight work" block below -- that wait
    // can genuinely take a while (a segment seal in flight spawns a real
    // ffmpeg encode of up to `_kSegmentSealInterval` worth of frames), and
    // the video's own cumulative duration is effectively frozen the
    // instant `_frameTimer` above is cancelled (no more frame slots get
    // timed after this). If the mic kept recording through that wait
    // before being told to stop, the audio file would end up measurably
    // longer than the video, and `encode()`'s `-shortest` mux flag would
    // then silently truncate that extra tail off the *audio* to match the
    // now-shorter video -- clipping exactly the last moment of narration
    // right as the tutor says whatever they were saying when they hit
    // stop. Stopping both here, back to back, keeps them ending at
    // essentially the same real-world instant instead.
    String? audioPath;
    try {
      audioPath = await _audioRecorder.stop();
    } catch (e) {
      audioPath = null;
    }

    // Let any in-flight frame capture -- and any in-flight background
    // segment seal -- finish before we freeze state, so `encode()` always
    // sees a fully consistent `_sealedSegmentPaths`/`_sealedConcatEntryCount`
    // pair (a seal that's still mid-flight when this runs could otherwise
    // finish afterward and mutate state nobody's looking at anymore).
    while (_captureInFlight || _segmentSealInFlight) {
      await Future.delayed(const Duration(milliseconds: 20));
    }

    await _stopCameraCapture();

    _capturedConcatEntries = List.of(_concatEntries);
    _capturedSessionDir = _sessionDir;
    _capturedCameraWasEnabled = _cameraEnabled;
    _capturedAudioPath = audioPath;
    _capturedAudioStartOffsetSeconds = _audioStartOffsetSeconds;
    _capturedCameraStartOffsetSeconds = _cameraStartOffsetSeconds;
    _capturedSealedSegmentPaths = List.of(_sealedSegmentPaths);
    _capturedSealedConcatEntryCount = _sealedConcatEntryCount;

    _canvasKey = null;
    _sessionDir = null;
    _startedAt = null;
    _cameraProcess = null;
    _cameraEnabled = false;
    _frameCount = 0;
    _writtenFrameIndex = 0;
    _lastFrameBytes = null;
    _concatEntries.clear();
    _sealedSegmentPaths.clear();
    _sealedConcatEntryCount = 0;
    _lastSealCheckpoint = null;
    _lastDistinctFrameAt = null;
    _audioStartOffsetSeconds = 0.0;
    _cameraStartOffsetSeconds = 0.0;

    _state = MathPadRecordingState.waitingForEncodeChoice;
    _emit();
  }

  /// Runs ffmpeg with [args], parsing its `-progress pipe:1` stdout stream
  /// to keep `encodingProgress`/`onEncodingProgress` reporting real numbers
  /// (against [totalDurationSeconds], the output timeline length this run
  /// is expected to produce) instead of an indeterminate spinner. Shared by
  /// all of `encode()`'s ffmpeg invocations -- they only differ in `args`.
  /// Throws on a non-zero exit, surfacing ffmpeg's own stderr tail so a
  /// failure is diagnosable from the error message alone.
  Future<void> _runFfmpegWithProgress(
    String ffmpegPath,
    List<String> args,
    double totalDurationSeconds,
  ) async {
    final Process process;
    try {
      process = await Process.start(ffmpegPath, args);
    } on ProcessException catch (e) {
      throw MathPadRecordingException('Could not run ffmpeg: ${e.message}');
    }
    // See the "Windows Job Object" section above this class.
    _tieProcessLifetimeToApp(process.pid);

    final StringBuffer stderrBuffer = StringBuffer();
    DateTime lastProgressEmit = DateTime.fromMillisecondsSinceEpoch(0);

    final StreamSubscription<String> stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          // Each `-progress` block repeats several `key=value` lines --
          // `out_time_us` (microseconds of output encoded so far) is the
          // only one this needs. Throttled to a few updates/sec so a fast
          // encode can't flood `setState` calls on the UI side.
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
  }

  /// Encodes the captured frames and audio into an .mp4 via the bundled
  /// ffmpeg. If a camera was recorded, it's overlaid as part of this same
  /// ffmpeg pass (one `filter_complex` graph) rather than as a second,
  /// separate re-encode of an already-finished canvas video -- overlaying
  /// requires decoding either way (a filter graph can't run on a `-c:v
  /// copy` compressed stream), so doing it in one pass here means paying
  /// that decode+encode cost exactly once, instead of once for a
  /// camera-less canvas video and then again to decode that back and stamp
  /// the camera on top of it. If the combined pass fails for any reason,
  /// this falls back to a plain camera-less encode so the tutor still gets
  /// a usable recording (see the `catch` around `encodeCanvasWithCamera`
  /// below).
  Future<String> encode() async {
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

      // A camera stream only counts if it actually produced a file -- a
      // camera that failed mid-recording (see the `onCameraWarning` call
      // sites in `start()`) still leaves `cameraWasEnabled` true, so this
      // is the real gate for whether to bother with the overlay branch.
      final File cameraFile = File(p.join(sessionDir.path, 'camera.mp4'));
      bool hasCamera = false;
      if (cameraWasEnabled) {
        if (await cameraFile.exists()) {
          hasCamera = true;
        } else {
          onCameraWarning?.call(
            'Camera capture produced no video -- saved without it.',
          );
        }
      }

      // Total captured timeline length -- the denominator for turning
      // ffmpeg's `-progress` output (which reports elapsed *output* time,
      // not a percentage) into the 0..1 fraction the UI's progress bar
      // wants. Same value the concat entries' durations were built from,
      // so it lines up with what ffmpeg will actually encode.
      final double totalDurationSeconds = concatEntries.fold(
        0.0,
        (sum, e) => sum + e.durationSeconds,
      );

      final List<String> sealedSegments = _capturedSealedSegmentPaths ?? const [];
      // The unsealed leftover tail -- everything captured after the last
      // background seal (see `_sealedConcatEntryCount`'s doc comment). When
      // nothing was ever sealed (a short recording, under one seal
      // interval), this is simply every captured entry, and the raw-stills
      // branch below handles it exactly as it always has.
      final List<_ConcatEntry> tailEntries =
          concatEntries.length > _capturedSealedConcatEntryCount
          ? concatEntries.sublist(_capturedSealedConcatEntryCount)
          : const [];

      // The canvas source, as an ffmpeg concat-demuxer manifest -- either
      // the already-encoded background-sealed segments (+ a freshly
      // encoded tail), or the raw captured stills. `canvasPreEncoded`
      // tracks which, since only the sealed-segments case is eligible for
      // a cheap `-c:v copy` when there's no camera to overlay.
      final String canvasManifestPath;
      final bool canvasPreEncoded;
      if (sealedSegments.isNotEmpty) {
        // ─── Sealed segments + tail ────────────────────────────────────
        // Most of the video is already encoded (sealed periodically in
        // the background throughout the recording -- see
        // `_maybeSealSegment`). Only the small leftover tail needs a real
        // encode here.
        final List<String> allSegments = List.of(sealedSegments);
        if (tailEntries.isNotEmpty) {
          final String tailPath = p.join(sessionDir.path, 'segment_tail.ts');
          final bool tailOk = await _encodeSegment(
            sessionDir: sessionDir,
            entries: tailEntries,
            outPath: tailPath,
            preset: 'veryfast',
            crf: '20',
          );
          if (tailOk) allSegments.add(tailPath);
        }

        final StringBuffer segManifest = StringBuffer('ffconcat version 1.0\n');
        for (final seg in allSegments) {
          final String safeSeg = seg.replaceAll(r'\', '/').replaceAll("'", r"\'");
          segManifest.writeln("file '$safeSeg'");
        }
        final File segManifestFile = File(
          p.join(sessionDir.path, 'segments.ffconcat'),
        );
        await segManifestFile.writeAsString(segManifest.toString());
        canvasManifestPath = segManifestFile.path;
        canvasPreEncoded = true;
      } else {
        // ─── Raw captured stills ───────────────────────────────────────
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
        canvasManifestPath = manifestFile.path;
        canvasPreEncoded = false;
      }

      // ─── Plain canvas-only encode -- used when there's no camera, and
      // as the camera-merged pass's fallback if that fails below ───────
      Future<void> encodeCanvasOnly() async {
        await _runFfmpegWithProgress(ffmpegPath, [
          '-y',
          '-progress', 'pipe:1',
          '-nostats',
          '-f', 'concat',
          '-safe', '0',
          '-i', canvasManifestPath,
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
          if (canvasPreEncoded)
            // Every sealed segment (and the tail) is already correctly
            // encoded H.264/yuv420p at the target framerate -- just
            // container-copy them together instead of re-encoding a
            // second time, which is the entire point of sealing in the
            // background.
            ...['-c:v', 'copy']
          else ...[
            // Normalizes the concat demuxer's variable-duration input
            // frames into a proper constant-frame-rate output stream --
            // cheap for ffmpeg to do internally (it's just frame
            // duplication at encode time), unlike materializing those
            // same duplicate frames as files up front the way this used
            // to work.
            '-r', '$fps',
            // yuv420p (4:2:0 chroma subsampling) requires both dimensions
            // to be even -- the captured canvas size is whatever the
            // window happens to be, which is very often NOT even in both
            // directions, and libx264 flatly refuses (rather than
            // rounding) an odd width/height. Trimming at most 1px off the
            // right/bottom is imperceptible; the alternative (padding)
            // would add a visible border instead.
            '-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2',
            '-c:v', 'libx264',
            '-pix_fmt', 'yuv420p',
            '-preset', 'veryfast',
            '-crf', '20',
          ],
          if (audioPath != null) ...[
            // dynaudnorm smoothly normalises the mic volume without the
            // heavy two-pass EBU analysis that loudnorm runs -- it adapts
            // frame-by-frame so quiet narration is brought up and loud
            // passages are gently levelled without the pumping/distortion
            // artefacts loudnorm can introduce on a signal that was
            // already slightly noisy coming off the mic. framelen=500ms
            // keeps the adaptation smooth for natural-paced speech.
            '-af', 'dynaudnorm=framelen=500:gausssize=31:peak=0.95',
            '-c:a', 'aac',
            '-b:a', '192k',
            '-shortest',
          ],
          outPath,
        ], totalDurationSeconds);
      }

      // ─── Camera-merged encode: canvas + camera overlay + audio, all in
      // one ffmpeg pass ───────────────────────────────────────────────
      Future<void> encodeCanvasWithCamera() async {
        final List<String> inputArgs = [
          '-f', 'concat',
          '-safe', '0',
          '-i', canvasManifestPath,
        ];
        int nextInputIndex = 1;
        int? audioInputIndex;
        if (audioPath != null) {
          if (audioStartOffsetSeconds > 0.0005) {
            inputArgs.addAll([
              '-itsoffset',
              audioStartOffsetSeconds.toStringAsFixed(6),
            ]);
          }
          inputArgs.addAll(['-i', audioPath]);
          audioInputIndex = nextInputIndex++;
        }
        // Shifts the camera stream later to match how much after the
        // canvas video's own t=0 it actually started (measured in
        // `start()`, see `_cameraStartOffsetSeconds`'s doc comment) -- the
        // DirectShow device is typically the slowest of the three capture
        // streams to actually come online, so without this the
        // picture-in-picture box visibly leads the canvas/audio by that
        // same amount for the whole recording.
        if (cameraStartOffsetSeconds > 0.0005) {
          inputArgs.addAll([
            '-itsoffset',
            cameraStartOffsetSeconds.toStringAsFixed(6),
          ]);
        }
        inputArgs.addAll(['-i', cameraFile.path]);
        final int cameraInputIndex = nextInputIndex++;

        // `fps`+`scale` here do the same job `-r`/`-vf` did for the
        // camera-less path above, just expressed inside the filter graph
        // instead of as separate output options -- `-vf` can't be mixed
        // with an explicit `-filter_complex`/`-map`. Camera box: cropped
        // to a square and scaled to 240x240, top-right corner, thin white
        // border so it stays legible over any background colour.
        // `overlay`'s default `eof_action` (repeat) freezes the box on
        // its last frame if the camera feed happens to be a touch shorter
        // than the canvas video, rather than cutting the output short.
        final String filterComplex =
            '[0:v]fps=$fps,scale=trunc(iw/2)*2:trunc(ih/2)*2[base];'
            '[$cameraInputIndex:v]crop=ih:ih,scale=w=240:h=240,'
            'drawbox=x=0:y=0:w=iw:h=ih:color=white@0.9:t=4[cam];'
            '[base][cam]overlay=x=main_w-overlay_w-24:y=24[outv]';

        await _runFfmpegWithProgress(ffmpegPath, [
          '-y',
          '-progress', 'pipe:1',
          '-nostats',
          ...inputArgs,
          '-filter_complex', filterComplex,
          '-map', '[outv]',
          if (audioInputIndex != null) ...['-map', '$audioInputIndex:a'],
          '-c:v', 'libx264',
          '-pix_fmt', 'yuv420p',
          '-preset', 'veryfast',
          '-crf', '20',
          if (audioInputIndex != null) ...[
            '-af', 'dynaudnorm=framelen=500:gausssize=31:peak=0.95',
            '-c:a', 'aac',
            '-b:a', '192k',
            // Only the mapped outputs ([outv] + audio) factor into
            // `-shortest` -- the camera input is consumed inside the
            // filter graph, not mapped as its own stream, so a
            // shorter/longer camera capture never affects when the
            // output ends; only canvas-vs-audio length does, matching
            // the camera-less path above exactly.
            '-shortest',
          ],
          outPath,
        ], totalDurationSeconds);
      }

      if (hasCamera) {
        try {
          await encodeCanvasWithCamera();
        } catch (e) {
          onCameraWarning?.call(
            'Camera couldn\'t be added to the video -- saved without it.',
          );
          encodingProgress = 0.0;
          onEncodingProgress?.call(0.0);
          notifyListeners();
          await encodeCanvasOnly();
        }
      } else {
        await encodeCanvasOnly();
      }

      await _generateThumbnail(outPath);
      return outPath;
    } finally {
      encodingProgress = 0.0;
      await cleanup();
      _state = MathPadRecordingState.idle;
      _emit();
    }
  }

  /// Discards an in-progress recording without encoding anything.
  Future<void> cancel() async {
    if (_state != MathPadRecordingState.recording &&
        _state != MathPadRecordingState.waitingForEncodeChoice) {
      return;
    }
    _frameTimer?.cancel();
    _frameTimer = null;
    _segmentSealTimer?.cancel();
    _segmentSealTimer = null;
    // A sealed-segment encode may still be running in the background --
    // let it finish before deleting `sessionDir` out from under it, rather
    // than risk it failing loudly (harmlessly) partway through a delete.
    while (_segmentSealInFlight) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    await _audioRecorder.stop();
    await _stopCameraCapture();
    _cameraEnabled = false;
    final Directory? sessionDir = _sessionDir;
    final Directory? capturedSessionDir = _capturedSessionDir;
    _sessionDir = null;
    _capturedSessionDir = null;
    _capturedConcatEntries = null;
    _capturedSealedSegmentPaths = null;
    _canvasKey = null;
    _lastFrameBytes = null;
    _concatEntries.clear();
    // Sealed `.ts` segments live inside `sessionDir` too, so deleting it
    // recursively already covers them -- just reset the tracking state.
    _sealedSegmentPaths.clear();
    _sealedConcatEntryCount = 0;
    _lastSealCheckpoint = null;
    _lastDistinctFrameAt = null;
    if (sessionDir != null && await sessionDir.exists()) {
      await sessionDir.delete(recursive: true);
    }
    if (capturedSessionDir != null && await capturedSessionDir.exists()) {
      await capturedSessionDir.delete(recursive: true);
    }
    _state = MathPadRecordingState.idle;
    _emit();
  }

  /// Purely cosmetic and strictly best-effort -- by the time this runs, the
  /// actual recording is already safely saved at [videoPath], so nothing in
  /// here is allowed to throw back out to `encode()`'s caller. A missing
  /// thumbnail just means the library falls back to a placeholder icon; it
  /// must never turn an otherwise-successful "recording saved" result into
  /// a reported failure.
  Future<void> _generateThumbnail(String videoPath) async {
    try {
      final String ffmpegPath = _resolveFfmpegPath();
      final String baseName = p.basenameWithoutExtension(videoPath);
      final String parentDir = File(videoPath).parent.path;

      final Directory thumbnailDir = Directory(p.join(parentDir, '.thumbnails'));
      if (!await thumbnailDir.exists()) {
        // `recursive: true` even though `parentDir` (the recordings dir)
        // is already guaranteed to exist by `getRecordingsDir()` at this
        // point -- cheap insurance against ever throwing here if that
        // ever stops being true, since the try/catch around this whole
        // method exists precisely so a thumbnail problem can never fail
        // the recording save itself.
        await thumbnailDir.create(recursive: true);
      }

      final String thumbnailPath = p.join(thumbnailDir.path, '$baseName.png');

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

  // The last `elapsed` value actually broadcast by `_emitElapsedTick`,
  // compared at whole-second resolution -- see that method's doc comment.
  Duration _lastEmittedElapsed = Duration.zero;

  /// `_captureFrame` calls this (not `_emit`) on every tick -- up to `fps`
  /// (60) times/sec, from both the persistent-frame-callback and the
  /// `Timer.periodic` backstop -- purely to keep `elapsed` bookkeeping
  /// current. Broadcasting a `notifyListeners()` on every one of those
  /// ticks forces `mathpad.dart`'s listener to `setState()` the entire
  /// page (canvas, toolbar, every overlay) up to 60-140+ times/sec just to
  /// update a "REC 00:15" badge that only ever displays whole seconds --
  /// that full-tree rebuild storm competing with pointer/stylus event
  /// handling on the same UI isolate is what actually caused the drawing
  /// stutter while recording, not the capture work itself. Only notifying
  /// when the displayed second actually changes cuts that from ~60-140/sec
  /// down to 1/sec, with zero visible difference to the badge.
  void _emitElapsedTick() {
    onUpdate?.call(_state, elapsed);
    if (elapsed.inSeconds != _lastEmittedElapsed.inSeconds) {
      _lastEmittedElapsed = elapsed;
      notifyListeners();
    }
  }

  Future<void> dispose() async {
    _frameTimer?.cancel();
    _segmentSealTimer?.cancel();
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
